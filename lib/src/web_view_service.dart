import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as windows;

import 'allowed_web_origins.dart';

enum GakujoNavigationDecision {
  navigate,
  prevent,
}

class GakujoNavigationRequest {
  const GakujoNavigationRequest({
    required this.url,
  });

  final String url;
}

class GakujoWebResourceError {
  const GakujoWebResourceError({
    required this.description,
  });

  final String description;
}

class GakujoNavigationDelegate {
  const GakujoNavigationDelegate({
    this.onNavigationRequest,
    this.onPageStarted,
    this.onPageFinished,
    this.onWebResourceError,
  });

  final FutureOr<GakujoNavigationDecision> Function(GakujoNavigationRequest)?
      onNavigationRequest;
  final void Function(String url)? onPageStarted;
  final FutureOr<void> Function(String url)? onPageFinished;
  final void Function(GakujoWebResourceError error)? onWebResourceError;
}

abstract class GakujoWebViewController {
  Future<void> setJavaScriptModeUnrestricted();

  Future<void> addJavaScriptChannel(
    String name, {
    required FutureOr<void> Function(String message) onMessageReceived,
  });

  Future<void> setNavigationDelegate(GakujoNavigationDelegate delegate);

  Future<void> reload();

  Future<void> loadUrl(String url);

  Future<String?> getTitle();

  Future<void> runJavaScript(String script);

  Future<Object?> runJavaScriptReturningResult(String script);

  Future<bool> canGoBack();

  Future<bool> canGoForward();

  Future<void> goBack();

  Future<void> goForward();

  Future<String?> currentUrl();

  Future<String?> cookieHeaderForUrl(String url);

  Future<void> dispose();
}

abstract class GakujoWebViewService {
  const GakujoWebViewService();

  GakujoWebViewController createController();

  Widget buildWidget(GakujoWebViewController controller);

  Future<void> configureController(
    GakujoWebViewController controller, {
    required bool debugAllowed,
  });
}

class WebViewFlutterGakujoWebViewService extends GakujoWebViewService {
  const WebViewFlutterGakujoWebViewService();

  @override
  GakujoWebViewController createController() {
    return WebViewFlutterGakujoWebViewController(WebViewController());
  }

  @override
  Widget buildWidget(GakujoWebViewController controller) {
    final inner = (controller as WebViewFlutterGakujoWebViewController)._inner;
    final webView = WebViewWidget(controller: inner);
    if (!needsFlutterJavaScriptDialogs(defaultTargetPlatform)) {
      return webView;
    }
    return _JavaScriptDialogHost(controller: inner, child: webView);
  }

  @override
  Future<void> configureController(
    GakujoWebViewController controller, {
    required bool debugAllowed,
  }) async {
    final inner = (controller as WebViewFlutterGakujoWebViewController)._inner;
    await _configureAndroidController(
      inner,
      debugAllowed: debugAllowed,
    );
    await _configureAppleHistoryNavigationGestures(inner);

    if (kDebugMode) {
      developer.log(
        'Using ${inner.platform.runtimeType} via webview_flutter',
        name: 'MoreBetterGakujo',
      );
    }
  }

  Future<void> _configureAppleHistoryNavigationGestures(
    WebViewController controller,
  ) async {
    if (!supportsNativeGakujoHistoryGestures(defaultTargetPlatform)) {
      return;
    }
    try {
      await (controller.platform as dynamic)
          .setAllowsBackForwardNavigationGestures(true);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to enable native WebView history gestures',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _configureAndroidController(
    WebViewController controller, {
    required bool debugAllowed,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final platformController = controller.platform;
    try {
      await (platformController as dynamic).setAllowFileAccess(debugAllowed);
      await (platformController as dynamic).setAllowContentAccess(false);
      await (platformController as dynamic).enableZoom(true);
      await (platformController as dynamic).setUseWideViewPort(true);
      await (platformController as dynamic).setLoadWithOverviewMode(true);
      await (platformController as dynamic).setBuiltInZoomControls(true);
      await (platformController as dynamic).setDisplayZoomControls(false);
      // Without this callback Android WebView ignores <input type="file">, so
      // assignment attachments cannot be chosen.
      await (platformController as dynamic)
          .setOnShowFileSelector(_pickAndroidUploadFiles);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to configure Android WebView platform controller',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// Receives webview_flutter_android's `FileSelectorParams`. The parameter is
/// dynamic, like the other Android-only calls above, so this file does not
/// depend on the Android implementation package directly.
Future<List<String>> _pickAndroidUploadFiles(dynamic params) async {
  try {
    final acceptTypes = [
      for (final value in params.acceptTypes as List<Object?>)
        if (value != null) value.toString(),
    ];
    final typeGroups = androidUploadTypeGroups(acceptTypes);
    final allowsMultiple = (params.mode as Enum).name == 'openMultiple';
    final files = allowsMultiple
        ? await openFiles(acceptedTypeGroups: typeGroups)
        : [
            if (await openFile(acceptedTypeGroups: typeGroups)
                case final file?)
              file,
          ];
    return [
      for (final file in files)
        if (file.path.isNotEmpty) Uri.file(file.path).toString(),
    ];
  } on Object catch (error, stackTrace) {
    developer.log(
      'Android WebView file selection failed',
      name: 'MoreBetterGakujo',
      error: error,
      stackTrace: stackTrace,
    );
    // An empty result cancels the chooser so the page can be used again.
    return const [];
  }
}

/// Converts an HTML `accept` list such as `.pdf,image/*` into file_selector
/// type groups. Unsupported or empty filters allow any file.
@visibleForTesting
List<XTypeGroup> androidUploadTypeGroups(List<String> acceptTypes) {
  final extensions = <String>{};
  final mimeTypes = <String>{};
  for (final rawGroup in acceptTypes) {
    for (final raw in rawGroup.split(',')) {
      final value = raw.trim().toLowerCase();
      if (value.isEmpty || value == '*/*') {
        // Any explicit wildcard makes the whole filter permissive.
        return const [];
      }
      if (value.startsWith('.') && value.length > 1) {
        extensions.add(value.substring(1));
      } else if (value.contains('/')) {
        mimeTypes.add(value);
      }
    }
  }
  if (extensions.isEmpty && mimeTypes.isEmpty) {
    return const [];
  }
  return [
    XTypeGroup(
      label: 'accepted',
      extensions: extensions.isEmpty ? null : extensions.toList(),
      mimeTypes: mimeTypes.isEmpty ? null : mimeTypes.toList(),
    ),
  ];
}

class WebViewFlutterGakujoWebViewController implements GakujoWebViewController {
  WebViewFlutterGakujoWebViewController(this._inner);

  final WebViewController _inner;

  @override
  Future<void> setJavaScriptModeUnrestricted() async {
    await _inner.setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  @override
  Future<void> addJavaScriptChannel(
    String name, {
    required FutureOr<void> Function(String message) onMessageReceived,
  }) async {
    await _inner.addJavaScriptChannel(
      name,
      onMessageReceived: (message) {
        unawaited(
          Future.sync(() => onMessageReceived(message.message)).catchError(
            (Object error, StackTrace stackTrace) {
              developer.log(
                'WebView JavaScript channel handler failed',
                name: 'MoreBetterGakujo',
                error: error,
                stackTrace: stackTrace,
              );
            },
          ),
        );
      },
    );
  }

  @override
  Future<void> setNavigationDelegate(GakujoNavigationDelegate delegate) async {
    await _inner.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) async {
          final decision = await delegate.onNavigationRequest?.call(
            GakujoNavigationRequest(url: request.url),
          );
          return decision == GakujoNavigationDecision.prevent
              ? NavigationDecision.prevent
              : NavigationDecision.navigate;
        },
        onPageStarted: delegate.onPageStarted,
        onPageFinished: (url) async {
          await delegate.onPageFinished?.call(url);
        },
        onWebResourceError: (error) {
          delegate.onWebResourceError?.call(
            GakujoWebResourceError(description: error.description),
          );
        },
      ),
    );
  }

  @override
  Future<void> reload() => _inner.reload();

  @override
  Future<void> loadUrl(String url) {
    return _inner.loadRequest(Uri.parse(url));
  }

  @override
  Future<String?> getTitle() => _inner.getTitle();

  @override
  Future<void> runJavaScript(String script) => _inner.runJavaScript(script);

  @override
  Future<Object?> runJavaScriptReturningResult(String script) {
    return _inner.runJavaScriptReturningResult(script);
  }

  @override
  Future<bool> canGoBack() => _inner.canGoBack();

  @override
  Future<bool> canGoForward() => _inner.canGoForward();

  @override
  Future<void> goBack() => _inner.goBack();

  @override
  Future<void> goForward() => _inner.goForward();

  @override
  Future<String?> currentUrl() => _inner.currentUrl();

  @override
  Future<String?> cookieHeaderForUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }

    try {
      final cookies = await WebViewCookieManager().getCookies(
        domain: Uri(scheme: uri.scheme, host: uri.host),
      );
      final requestPath = uri.path.isEmpty ? '/' : uri.path;
      final pairs = <String>[];
      for (final cookie in cookies) {
        final name = cookie.name.trim();
        if (name.isEmpty || !cookiePathMatches(requestPath, cookie.path)) {
          continue;
        }
        pairs.add('$name=${cookie.value}');
      }
      return pairs.isEmpty ? null : pairs.join('; ');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to read WebView cookie store',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  Future<void> dispose() async {}
}

bool supportsNativeGakujoHistoryGestures(TargetPlatform platform) {
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

/// webview_flutter_wkwebview drops `alert()` and makes `confirm()` return
/// false unless Flutter handles the panels, which silently cancels confirmed
/// actions such as submissions. Android and Windows show native dialogs.
@visibleForTesting
bool needsFlutterJavaScriptDialogs(TargetPlatform platform) {
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

class _JavaScriptDialogHost extends StatefulWidget {
  const _JavaScriptDialogHost({
    required this.controller,
    required this.child,
  });

  final WebViewController controller;
  final Widget child;

  @override
  State<_JavaScriptDialogHost> createState() => _JavaScriptDialogHostState();
}

class _JavaScriptDialogHostState extends State<_JavaScriptDialogHost> {
  @override
  void initState() {
    super.initState();
    unawaited(_register(widget.controller));
  }

  @override
  void didUpdateWidget(_JavaScriptDialogHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      unawaited(_register(widget.controller));
    }
  }

  Future<void> _register(WebViewController controller) async {
    try {
      await controller.setOnJavaScriptAlertDialog((request) async {
        await _show<void>(request.message, cancellable: false);
      });
      await controller.setOnJavaScriptConfirmDialog((request) async {
        return await _show<bool>(request.message, cancellable: true) ?? false;
      });
      await controller.setOnJavaScriptTextInputDialog((request) async {
        return await _showTextInput(request.message, request.defaultText) ??
            '';
      });
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to register WebView JavaScript dialogs',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<T?> _show<T>(String message, {required bool cancellable}) async {
    if (!mounted) {
      return null;
    }
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          if (cancellable)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showTextInput(String message, String? defaultText) async {
    if (!mounted) {
      return null;
    }
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _JavaScriptTextInputDialog(
        message: message,
        defaultText: defaultText ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Owns its text controller so the field is not disposed while the dialog's
/// closing animation still renders it.
class _JavaScriptTextInputDialog extends StatefulWidget {
  const _JavaScriptTextInputDialog({
    required this.message,
    required this.defaultText,
  });

  final String message;
  final String defaultText;

  @override
  State<_JavaScriptTextInputDialog> createState() =>
      _JavaScriptTextInputDialogState();
}

class _JavaScriptTextInputDialogState
    extends State<_JavaScriptTextInputDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.defaultText);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          TextField(controller: _text, autofocus: true),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

@visibleForTesting
bool cookiePathMatches(String requestPath, String cookiePath) {
  final normalizedRequestPath =
      requestPath.isEmpty || !requestPath.startsWith('/') ? '/' : requestPath;
  final normalizedCookiePath =
      cookiePath.isEmpty || !cookiePath.startsWith('/') ? '/' : cookiePath;
  if (normalizedRequestPath == normalizedCookiePath) {
    return true;
  }
  if (!normalizedRequestPath.startsWith(normalizedCookiePath)) {
    return false;
  }
  if (normalizedCookiePath.endsWith('/')) {
    return true;
  }
  return normalizedRequestPath.length > normalizedCookiePath.length &&
      normalizedRequestPath.codeUnitAt(normalizedCookiePath.length) == 0x2f;
}

enum MouseHistoryNavigation { back, forward }

@visibleForTesting
MouseHistoryNavigation? mouseHistoryNavigation(PointerDownEvent event) {
  if (event.kind != PointerDeviceKind.mouse) {
    return null;
  }
  if (event.buttons == kBackMouseButton) {
    return MouseHistoryNavigation.back;
  }
  if (event.buttons == kForwardMouseButton) {
    return MouseHistoryNavigation.forward;
  }
  return null;
}

class WindowsGakujoWebViewService extends GakujoWebViewService {
  const WindowsGakujoWebViewService();

  @override
  GakujoWebViewController createController() {
    return WindowsGakujoWebViewController(windows.WebviewController());
  }

  @override
  Widget buildWidget(GakujoWebViewController controller) {
    final windowsController = controller as WindowsGakujoWebViewController;
    // The WebView2 texture only forwards primary, secondary and middle
    // buttons, so mouse back/forward buttons would otherwise do nothing.
    return Listener(
      onPointerDown: (event) {
        switch (mouseHistoryNavigation(event)) {
          case MouseHistoryNavigation.back:
            unawaited(windowsController.goBack());
          case MouseHistoryNavigation.forward:
            unawaited(windowsController.goForward());
          case null:
            break;
        }
      },
      child: ValueListenableBuilder<windows.WebviewValue>(
        valueListenable: windowsController._inner,
        builder: (context, value, child) {
          if (!value.isInitialized) {
            return const Center(child: Text('WebViewを準備中...'));
          }
          return windows.Webview(windowsController._inner);
        },
      ),
    );
  }

  @override
  Future<void> configureController(
    GakujoWebViewController controller, {
    required bool debugAllowed,
  }) async {
    final windowsController = controller as WindowsGakujoWebViewController;
    await windowsController._ready;
    await windowsController._inner.setPopupWindowPolicy(
      windows.WebviewPopupWindowPolicy.sameWindow,
    );
    // The plugin turns WebView2's context menu off, which left Windows users
    // without right-click copy while other platforms keep their native menus.
    await windowsController._inner.setDefaultContextMenusEnabled(true);
  }
}

class WindowsGakujoWebViewController implements GakujoWebViewController {
  WindowsGakujoWebViewController(this._inner) {
    _ready = _inner.initialize();
    _subscriptions.add(_inner.url.listen((url) {
      unawaited(
        _handleUrlChanged(url).catchError(
          (Object error, StackTrace stackTrace) {
            developer.log(
              'Windows WebView URL handler failed',
              name: 'MoreBetterGakujo',
              error: error,
              stackTrace: stackTrace,
            );
          },
        ),
      );
    }));
    _subscriptions.add(_inner.title.listen((value) {
      _title = value;
    }));
    _subscriptions.add(_inner.historyChanged.listen((value) {
      _canGoBack = value.canGoBack;
      _canGoForward = value.canGoForward;
    }));
    _subscriptions.add(_inner.loadingState.listen((state) {
      if (state == windows.LoadingState.navigationCompleted) {
        unawaited(_notifyPageFinished());
      }
    }));
    _subscriptions.add(_inner.onLoadError.listen((error) {
      _delegate?.onWebResourceError?.call(
        GakujoWebResourceError(description: error.name),
      );
    }));
    _subscriptions.add(_inner.webMessage.listen(_handleWebMessage));
  }

  final windows.WebviewController _inner;
  final Map<String, FutureOr<void> Function(String)> _javaScriptHandlers = {};
  final List<StreamSubscription<Object?>> _subscriptions = [];
  late final Future<void> _ready;
  GakujoNavigationDelegate? _delegate;
  String? _currentUrl;
  String? _title;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _handlingPreventedNavigation = false;

  @override
  Future<void> setJavaScriptModeUnrestricted() async {
    await _ready;
  }

  @override
  Future<void> addJavaScriptChannel(
    String name, {
    required FutureOr<void> Function(String message) onMessageReceived,
  }) async {
    _javaScriptHandlers[name] = onMessageReceived;
    await _ready;
    final bridgeScript = _channelBridgeScript(name);
    await _inner.addScriptToExecuteOnDocumentCreated(bridgeScript);
    await _tryExecuteScript(bridgeScript);
  }

  @override
  Future<void> setNavigationDelegate(GakujoNavigationDelegate delegate) async {
    _delegate = delegate;
  }

  @override
  Future<void> reload() async {
    await _ready;
    await _inner.reload();
  }

  @override
  Future<void> loadUrl(String url) async {
    await _ready;
    await _inner.loadUrl(url);
  }

  @override
  Future<String?> getTitle() async {
    await _ready;
    if (_title != null && _title!.isNotEmpty) {
      return _title;
    }
    final result = await _inner.executeScript('document.title');
    return WindowsJavaScriptResult.decodeString(result);
  }

  @override
  Future<void> runJavaScript(String script) async {
    await _ready;
    await _inner.executeScript(script);
  }

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async {
    await _ready;
    return _inner.executeScript(script);
  }

  @override
  Future<bool> canGoBack() async {
    await _ready;
    return _canGoBack;
  }

  @override
  Future<bool> canGoForward() async {
    await _ready;
    return _canGoForward;
  }

  @override
  Future<void> goBack() async {
    await _ready;
    if (_canGoBack) {
      await _inner.goBack();
    }
  }

  @override
  Future<void> goForward() async {
    await _ready;
    if (_canGoForward) {
      await _inner.goForward();
    }
  }

  @override
  Future<String?> currentUrl() async {
    await _ready;
    return _currentUrl;
  }

  @override
  Future<String?> cookieHeaderForUrl(String url) async {
    return null;
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _inner.dispose();
  }

  Future<void> _handleUrlChanged(String url) async {
    if (_handlingPreventedNavigation) {
      return;
    }

    final decision = await _delegate?.onNavigationRequest?.call(
      GakujoNavigationRequest(url: url),
    );
    if (decision != GakujoNavigationDecision.prevent) {
      _currentUrl = url;
      _delegate?.onPageStarted?.call(url);
      return;
    }

    _handlingPreventedNavigation = true;
    try {
      await _inner.stop();
      if (_canGoBack) {
        await _inner.goBack();
      } else if (_currentUrl != null && _currentUrl != url) {
        await _inner.loadUrl(_currentUrl!);
      } else {
        await _inner.loadUrl(AllowedWebOrigins.gakujoUrl);
      }
    } finally {
      _handlingPreventedNavigation = false;
    }
  }

  void _handleWebMessage(Object? raw) {
    final decoded = WindowsWebMessageBridge.decode(raw);
    if (decoded == null) {
      return;
    }
    final channel = decoded.channel;
    final message = decoded.message;
    if (channel == null || message == null) {
      return;
    }
    final handler = _javaScriptHandlers[channel];
    if (handler == null) {
      return;
    }
    unawaited(
      Future.sync(() => handler(message)).catchError(
        (Object error, StackTrace stackTrace) {
          developer.log(
            'Windows WebView JavaScript channel handler failed',
            name: 'MoreBetterGakujo',
            error: error,
            stackTrace: stackTrace,
          );
        },
      ),
    );
  }

  Future<void> _notifyPageFinished() async {
    final url = _currentUrl;
    if (url == null) {
      return;
    }
    try {
      await _delegate?.onPageFinished?.call(url);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Windows WebView page-finished handler failed',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _tryExecuteScript(String script) async {
    try {
      await _inner.executeScript(script);
    } on Object {
      // There may be no document yet. The document-created script handles
      // future pages.
    }
  }

  static String _channelBridgeScript(String name) {
    final encodedName = jsonEncode(name);
    return '''
(function() {
  var channelName = $encodedName;
  window[channelName] = {
    postMessage: function(message) {
      window.chrome.webview.postMessage(JSON.stringify({
        channel: channelName,
        message: String(message)
      }));
    }
  };
})()
''';
  }
}

@visibleForTesting
class WindowsWebMessage {
  const WindowsWebMessage({
    required this.channel,
    required this.message,
  });

  final String? channel;
  final String? message;
}

@visibleForTesting
class WindowsWebMessageBridge {
  const WindowsWebMessageBridge._();

  static WindowsWebMessage? decode(Object? raw) {
    final map = switch (raw) {
      final Map<dynamic, dynamic> value => value,
      final String value => _decodeJsonMap(value),
      _ => null,
    };
    if (map == null) {
      return null;
    }
    return WindowsWebMessage(
      channel: map['channel']?.toString(),
      message: map['message']?.toString(),
    );
  }

  static Map<dynamic, dynamic>? _decodeJsonMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<dynamic, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

@visibleForTesting
class WindowsJavaScriptResult {
  const WindowsJavaScriptResult._();

  static String? decodeString(Object? raw) {
    final value = raw?.toString();
    if (value == null) {
      return null;
    }
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is String) {
          return decoded;
        }
      } on FormatException {
        return value;
      }
    }
    return value;
  }
}
