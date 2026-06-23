import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows;

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
    return WebViewWidget(
      controller: (controller as WebViewFlutterGakujoWebViewController)._inner,
    );
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

    if (kDebugMode) {
      developer.log(
        'Using ${inner.platform.runtimeType} via webview_flutter',
        name: 'MoreBetterGakujo',
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

class WebViewFlutterGakujoWebViewController implements GakujoWebViewController {
  WebViewFlutterGakujoWebViewController(this._inner);

  final WebViewController _inner;

  @override
  Future<void> setJavaScriptModeUnrestricted() async {
    _inner.setJavaScriptMode(JavaScriptMode.unrestricted);
  }

  @override
  Future<void> addJavaScriptChannel(
    String name, {
    required FutureOr<void> Function(String message) onMessageReceived,
  }) async {
    _inner.addJavaScriptChannel(
      name,
      onMessageReceived: (message) => onMessageReceived(message.message),
    );
  }

  @override
  Future<void> setNavigationDelegate(GakujoNavigationDelegate delegate) async {
    _inner.setNavigationDelegate(
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
  Future<void> dispose() async {}
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
    return ValueListenableBuilder<windows.WebviewValue>(
      valueListenable: windowsController._inner,
      builder: (context, value, child) {
        if (!value.isInitialized) {
          return const Center(child: Text('WebViewを準備中...'));
        }
        return windows.Webview(windowsController._inner);
      },
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
  }
}

class WindowsGakujoWebViewController implements GakujoWebViewController {
  WindowsGakujoWebViewController(this._inner) {
    _ready = _inner.initialize();
    _subscriptions.add(_inner.url.listen(_handleUrlChanged));
    _subscriptions.add(_inner.title.listen((value) {
      _title = value;
    }));
    _subscriptions.add(_inner.historyChanged.listen((value) {
      _canGoBack = value.canGoBack;
      _canGoForward = value.canGoForward;
    }));
    _subscriptions.add(_inner.loadingState.listen((state) async {
      if (state == windows.LoadingState.navigationCompleted) {
        final url = _currentUrl;
        if (url != null) {
          await _delegate?.onPageFinished?.call(url);
        }
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
    return result?.toString();
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
    _javaScriptHandlers[channel]?.call(message);
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
