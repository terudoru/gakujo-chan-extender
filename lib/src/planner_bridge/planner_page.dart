import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

import '../star_sync/star_sync_google_auth.dart';
import '../web_view_service.dart';
import 'planner_broker.dart';
import 'planner_drive.dart';

/// One dedicated controller for the lifetime of this route; platform's normal
/// persistent website profile (cookies/localStorage/IndexedDB), never incognito.
class HostedPlannerPage extends StatefulWidget {
  const HostedPlannerPage({
    super.key,
    required this.service,
    required this.auth,
    required this.student,
    required this.signIn,
    required this.signOut,
    required this.onExternalLink,
    this.onAuthorized,
  });
  final GakujoWebViewService service;
  final StarSyncGoogleAuth auth;
  final String? Function() student;
  final Future<void> Function() signIn;
  final Future<void> Function() signOut;
  final ValueChanged<Uri> onExternalLink;
  final VoidCallback? onAuthorized;
  @override
  State<HostedPlannerPage> createState() => _HostedPlannerPageState();
}

class _HostedPlannerPageState extends State<HostedPlannerPage> {
  GakujoWebViewController? _controller;
  late final NativePlannerDrive _drive;
  late final PlannerBroker _broker;
  Timer? _poll;
  int _document = 0;
  String? _capability;
  Uri? _bridgeDocumentUrl;
  String? _error;
  int _authReplies = 0;
  final _deferredSessions = <(Map<String, dynamic>, int)>[];
  final _channel = 'MbgPlannerNative${_random()}';
  static String _random() => List.generate(
    32,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();

  @override
  void initState() {
    super.initState();
    _drive = NativePlannerDrive(widget.auth);
    _broker = PlannerBroker(
      auth: widget.auth,
      drive: _drive,
      student: widget.student,
      signIn: widget.signIn,
      signOut: widget.signOut,
      onAuthorized: widget.onAuthorized,
      onSession: (event) {
        if (_authReplies > 0) {
          _deferredSessions.add((event, _document));
        } else {
          unawaited(_emit(event, _document));
        }
      },
    );
    _poll = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_refreshSession()),
    );
    unawaited(_open());
  }

  Future<void> _refreshSession() async {
    try {
      await _broker.refreshSession();
    } on Object {
      // Request replies report errors; background polling retries next time.
    }
  }

  void _invalidate() {
    _document++;
    _capability = null;
    _bridgeDocumentUrl = null;
    _deferredSessions.clear();
    _broker.invalidate();
  }

  void _navigationStarted(String url) {
    // Windows also reports SourceChanged for pushState/replaceState and hashes.
    // Those retain the installed JS bridge; ContentLoading still invalidates
    // real documents (including a reload of the very same URL).
    final uri = Uri.tryParse(url);
    if (_bridgeDocumentUrl != null &&
        uri != null &&
        uri.removeFragment() == _bridgeDocumentUrl) {
      return;
    }
    _invalidate();
  }

  Future<void> _emit(Map<String, dynamic> value, int document) async {
    try {
      final controller = _controller;
      if (!mounted ||
          controller == null ||
          document != _document ||
          _capability == null) {
        return;
      }
      final capability = _capability;
      final url = await controller.currentUrl();
      if (!mounted ||
          document != _document ||
          url == null ||
          !isHostedPlanner(Uri.parse(url))) {
        return;
      }
      await controller.runJavaScript(
        'if(window === window.top && location.origin === "https://gakujo.terudoru.com" && location.pathname.startsWith("/syllabus/")) window.__mbgPlannerDeliver?.(${jsonEncode(capability)}, ${jsonEncode(value)});',
      );
    } on Object {
      /* A disappearing document has no reply target. */
    }
  }

  Future<void> _receive(String message) async {
    final document = _document;
    try {
      if (message.length > 26 * 1024 * 1024 || _capability == null) return;
      final envelope = jsonDecode(message);
      if (envelope is! List ||
          envelope.length != 2 ||
          envelope[0] != _capability) {
        return;
      }
      final controller = _controller!;
      final url = await controller.currentUrl();
      if (url == null || document != _document) return;
      final request = jsonDecode(envelope[1] as String);
      final auth =
          request is Map &&
          (request['op'] == 'signIn' || request['op'] == 'signOut');
      if (auth) _authReplies++;
      try {
        final reply = await _broker.handle(
          request,
          document: Uri.parse(url),
          topFrame: true,
        );
        await _emit(reply, document);
      } finally {
        if (auth) _authReplies--;
        if (_authReplies == 0) {
          final events = _deferredSessions.toList();
          _deferredSessions.clear();
          for (final (event, target) in events) {
            await _emit(event, target);
          }
        }
      }
    } on Object {
      /* Malformed, unauthenticated messages are ignored. */
    }
  }

  Future<void> _open() async {
    try {
      final native = widget.service is WindowsGakujoWebViewService
          ? windows.WebviewController()
          : null;
      final controller = _controller = native == null
          ? widget.service.createController()
          : WindowsGakujoWebViewController(native);
      await controller.setJavaScriptModeUnrestricted();
      if (!mounted) return;
      if (native != null) {
        await native.setPopupWindowPolicy(
          windows.WebviewPopupWindowPolicy.sameWindow,
        );
        // The native host guard runs before requests; path guard also runs in Dart.
        await native.setNavigationAllowlist(
          hosts: ['gakujo.terudoru.com'],
          hostSuffixes: [],
          pathPrefixes: ['/syllabus/'],
        );
      }
      await controller.addJavaScriptChannel(
        _channel,
        onMessageReceived: _receive,
      );
      await controller.setNavigationDelegate(
        GakujoNavigationDelegate(
          onNavigationStarting: _navigationStarted,
          onDocumentStarted: _invalidate,
          onPageStarted: _navigationStarted,
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (request.isMainFrame && uri != null && isHostedPlanner(uri)) {
              return GakujoNavigationDecision.navigate;
            }
            if (request.isMainFrame &&
                uri != null &&
                const {'http', 'https'}.contains(uri.scheme)) {
              widget.onExternalLink(uri);
            }
            return GakujoNavigationDecision.prevent;
          },
          onPageFinished: (url) async {
            if (!mounted ||
                !isHostedPlanner(Uri.parse(url)) ||
                await controller.currentUrl() != url) {
              return;
            }
            // WebView2 also completes same-document hash navigations. Keep the
            // existing capability and bridge object until a real document starts.
            if (_bridgeDocumentUrl == Uri.parse(url).removeFragment()) return;
            if (controller is WebViewFlutterGakujoWebViewController) {
              await controller.installTrustedChannels();
            }
            final capability = _capability = _random();
            _bridgeDocumentUrl = Uri.parse(url).removeFragment();
            await controller.runJavaScript('''
            (() => {
              if(window !== window.top || location.origin !== 'https://gakujo.terudoru.com' || !location.pathname.startsWith('/syllabus/')) return;
              const channel = window[${jsonEncode(_channel)}];
              const capability = ${jsonEncode(capability)};
              Object.defineProperty(window, 'MbgPlannerBridge', {configurable:true, value:Object.freeze({postMessage(message) {
                channel.postMessage(JSON.stringify([capability,String(message)]));
              }})});
              Object.defineProperty(window, '__mbgPlannerDeliver', {configurable:true, value:(key, detail) => {
                if(key === capability) window.dispatchEvent(new CustomEvent('mbg:planner-bridge', {detail}));
              }});
              document.documentElement.dataset.plannerHost = 'app';
              document.addEventListener('click', e => { const a=e.target.closest?.('a[target="_blank"]'); if(a) a.target='_self'; }, true);
              window.dispatchEvent(new Event('mbg:planner-host'));
            })();
          ''');
            await _refreshSession();
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = '履修手帖を読み込めませんでした。');
            }
          },
        ),
      );
      if (!mounted) return;
      setState(() {});
      await controller.loadUrl('https://gakujo.terudoru.com/syllabus/');
    } on Object {
      if (mounted) setState(() => _error = '履修手帖を開けませんでした。');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _invalidate();
    _broker.dispose();
    _drive.close();
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('履修手帖')),
    body: _error != null
        ? Center(child: Text(_error!))
        : _controller == null
        ? const Center(child: CircularProgressIndicator())
        : widget.service.buildWidget(_controller!),
  );
}
