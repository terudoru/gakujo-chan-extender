import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'allowed_web_origins.dart';
import 'download_destination_settings.dart';
import 'gakujo_download_capture_script.dart';
import 'gakujo_download_request.dart';
import 'gakujo_download_service.dart';
import 'totp_generator.dart';
import 'two_factor_autofill_script.dart';
import 'two_factor_secret_store.dart';

class GakujoWebApp extends StatefulWidget {
  const GakujoWebApp({
    super.key,
    TwoFactorSecretStore? secretStore,
    TotpGenerator? totpGenerator,
    String? startUrl,
    String? initialTwoFactorSecret,
    bool? debugAllowed,
  })  : _secretStore = secretStore,
        _totpGenerator = totpGenerator,
        _startUrl = startUrl,
        _initialTwoFactorSecret = initialTwoFactorSecret,
        _debugAllowed = debugAllowed;

  final TwoFactorSecretStore? _secretStore;
  final TotpGenerator? _totpGenerator;
  final String? _startUrl;
  final String? _initialTwoFactorSecret;
  final bool? _debugAllowed;

  @override
  State<GakujoWebApp> createState() => _GakujoWebAppState();
}

class _GakujoWebAppState extends State<GakujoWebApp> {
  late final WebViewController _controller;
  late final TwoFactorSecretStore _secretStore;
  late final TotpGenerator _totpGenerator;
  late final GakujoDownloadService _downloadService;
  late final bool _debugAllowed;
  String? _currentPageUrl;
  String _status = '準備中';
  DownloadDestinationSettings _downloadRoot =
      const DownloadDestinationSettings(isConfigured: false);

  @override
  void initState() {
    super.initState();
    _secretStore = widget._secretStore ?? TwoFactorSecretStore();
    _totpGenerator = widget._totpGenerator ?? const TotpGenerator();
    _downloadService = const GakujoDownloadService();
    _debugAllowed = widget._debugAllowed ?? kDebugMode;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        GakujoDownloadCaptureScript.channelName,
        onMessageReceived: _handleDownloadMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigationRequest,
          onPageStarted: (url) {
            _currentPageUrl = url;
            _setStatus('読込中: ${_displayUrl(url)}');
          },
          onPageFinished: (url) async {
            _currentPageUrl = url;
            _setStatus('表示中: ${_displayUrl(url)}');
            await _injectTwoFactorAutofillIfAllowed();
            await _injectDownloadCaptureIfAllowed();
          },
          onWebResourceError: (error) {
            _setStatus('読込エラー: ${error.description}');
          },
        ),
      );

    _configureAndroidWebView();
    _loadDownloadRoot();
    _loadInitialPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('More Better Gakujo'),
        actions: [
          IconButton(
            tooltip: '設定',
            onPressed: _showSettingsDialog,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: '再読込',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }

  NavigationDecision _handleNavigationRequest(NavigationRequest request) {
    if (AllowedWebOrigins.canLoad(
      request.url,
      debugAllowed: _debugAllowed,
    )) {
      return NavigationDecision.navigate;
    }

    _setStatus('ブロック: ${_displayUrl(request.url)}');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gakujo以外のページをブロックしました')),
    );
    return NavigationDecision.prevent;
  }

  Future<void> _showSettingsDialog() async {
    var secretInput = '';
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> refreshDownloadRoot(
              Future<DownloadDestinationSettings> Function() action,
            ) async {
              final next = await action();
              if (!mounted) {
                return;
              }
              setState(() {
                _downloadRoot = next;
              });
              setDialogState(() {});
            }

            final rootLabel = _downloadRoot.isConfigured
                ? (_downloadRoot.displayName ?? '設定済み')
                : '未設定';

            return AlertDialog(
              title: const Text('設定'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'QRコード横の長いBase32 2FA秘密鍵を保存します。6桁コードではありません。保存済みの秘密鍵は表示しません。',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: '長いBase32 2FA秘密鍵',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        secretInput = value;
                      },
                    ),
                    const Divider(height: 32),
                    DownloadDestinationSection(
                      rootLabel: rootLabel,
                      isConfigured: _downloadRoot.isConfigured,
                      onPick: () async {
                        await refreshDownloadRoot(
                          _downloadService.pickDownloadRoot,
                        );
                      },
                      onClear: () async {
                        await refreshDownloadRoot(
                          _downloadService.clearDownloadRoot,
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await _secretStore.clear();
                    if (mounted) {
                      navigator.pop();
                      messenger.showSnackBar(
                        const SnackBar(content: Text('2FA秘密鍵を削除しました')),
                      );
                    }
                  },
                  child: const Text('削除'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('閉じる'),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      await _secretStore.save(secretInput);
                      if (mounted) {
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(content: Text('2FA秘密鍵を保存しました')),
                        );
                      }
                      await _injectTwoFactorAutofillIfAllowed();
                    } on FormatException {
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('長いBase32秘密鍵を確認してください')),
                        );
                      }
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadDownloadRoot() async {
    final root = await _downloadService.getDownloadRoot();
    if (!mounted) {
      return;
    }

    setState(() {
      _downloadRoot = root;
    });
  }

  Future<void> _handleDownloadMessage(JavaScriptMessage message) async {
    late final GakujoDownloadRequest request;
    try {
      request = GakujoDownloadRequest.fromJsonText(message.message);
    } on FormatException {
      _setStatus('保存エラー: ダウンロード情報を読めませんでした');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ダウンロード情報を読めませんでした')),
        );
      }
      return;
    }

    if (!AllowedWebOrigins.canLoad(
      request.url,
      debugAllowed: _debugAllowed,
    )) {
      _setStatus('ブロック: ${_displayUrl(request.url)}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gakujo以外のダウンロードをブロックしました')),
      );
      return;
    }

    var root = _downloadRoot;
    if (!root.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ダウンロード保存先を選択してください')),
      );
      root = await _downloadService.pickDownloadRoot();
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadRoot = root;
      });
      if (!root.isConfigured) {
        return;
      }
    }

    try {
      _setStatus('ダウンロード中: ${request.fileName}');
      final result = await _downloadService.download(
        request,
        userAgent: await _userAgent(),
      );
      _setStatus('保存しました: ${result.courseName}/${result.fileName}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存しました: ${result.fileName}')),
        );
      }
    } on PlatformException catch (error) {
      _setStatus('保存エラー: ${error.message ?? error.code}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存できませんでした: ${error.message ?? error.code}')),
        );
      }
    }
  }

  Future<String?> _userAgent() async {
    final result = await _controller.runJavaScriptReturningResult(
      'navigator.userAgent',
    );
    return result.toString();
  }

  Future<void> _injectDownloadCaptureIfAllowed() async {
    if (!AllowedWebOrigins.canLoad(
      _currentPageUrl,
      debugAllowed: _debugAllowed,
    )) {
      return;
    }

    try {
      await _controller.runJavaScript(GakujoDownloadCaptureScript.build());
    } catch (error, stackTrace) {
      developer.log(
        'Failed to inject download capture script',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _injectTwoFactorAutofillIfAllowed() async {
    if (!AllowedWebOrigins.canAutofill(
      _currentPageUrl,
      debugAllowed: _debugAllowed,
    )) {
      return;
    }

    final secret = await _secretStore.load();
    if (secret == null) {
      return;
    }

    final token = _totpGenerator.currentToken(secret);
    final script = TwoFactorAutofillScript.build(token: token);
    await _controller.runJavaScript(script);
  }

  Future<void> _loadInitialPage() async {
    await _saveInitialTwoFactorSecretIfAllowed();
    await _controller.loadRequest(Uri.parse(_resolveStartUrl()));
  }

  void _configureAndroidWebView() {
    final platformController = _controller.platform;
    if (platformController is! AndroidWebViewController) {
      return;
    }

    platformController.setAllowFileAccess(_debugAllowed);
    platformController.setAllowContentAccess(false);
    platformController.setMixedContentMode(MixedContentMode.neverAllow);
    platformController.setOnConsoleMessage((message) {
      developer.log(
        'WebViewConsole: ${message.message}',
        name: 'MoreBetterGakujo',
      );
    });
  }

  Future<void> _saveInitialTwoFactorSecretIfAllowed() async {
    final secret = widget._initialTwoFactorSecret;
    if (!_debugAllowed || secret == null || secret.isEmpty) {
      return;
    }

    await _secretStore.save(secret);
  }

  String _resolveStartUrl() {
    final startUrl = widget._startUrl;
    if (startUrl != null &&
        AllowedWebOrigins.canLoad(startUrl, debugAllowed: _debugAllowed)) {
      return startUrl;
    }

    return AllowedWebOrigins.gakujoUrl;
  }

  void _setStatus(String status) {
    if (!mounted) {
      return;
    }

    setState(() {
      _status = status;
    });
  }

  String _displayUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return '(unknown)';
    }

    return url.replaceAll(
      RegExp(r';jsessionid=[^?#]+', caseSensitive: false),
      ';jsessionid=<redacted>',
    );
  }
}

class DownloadDestinationSection extends StatelessWidget {
  const DownloadDestinationSection({
    super.key,
    required this.rootLabel,
    required this.isConfigured,
    required this.onPick,
    required this.onClear,
  });

  final String rootLabel;
  final bool isConfigured;
  final Future<void> Function() onPick;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ダウンロード保存先',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(rootLabel),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: onPick,
              child: const Text('フォルダを選択'),
            ),
            TextButton(
              onPressed: isConfigured ? onClear : null,
              child: const Text('解除'),
            ),
          ],
        ),
      ],
    );
  }
}
