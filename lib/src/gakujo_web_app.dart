import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'allowed_web_origins.dart';
import 'download_destination_settings.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_course_name_estimator.dart';
import 'gakujo_download_capture_script.dart';
import 'gakujo_download_request.dart';
import 'gakujo_download_service.dart';
import 'gakujo_download_url_policy.dart';
import 'gakujo_last_page_store.dart';
import 'platform/platform_service.dart';
import 'gakujo_start_url_resolver.dart';
import 'login_autofill_assist_script.dart';
import 'totp_generator.dart';
import 'two_factor_autofill_script.dart';
import 'two_factor_secret_store.dart';
import 'web_view_service.dart';

class GakujoWebApp extends StatefulWidget {
  const GakujoWebApp({
    super.key,
    TwoFactorSecretStore? secretStore,
    TotpGenerator? totpGenerator,
    GakujoLastPageStore? lastPageStore,
    GakujoAppSettingsStore? appSettingsStore,
    String? startUrl,
    String? initialTwoFactorSecret,
    bool? debugAllowed,
  })  : _secretStore = secretStore,
        _totpGenerator = totpGenerator,
        _lastPageStore = lastPageStore,
        _appSettingsStore = appSettingsStore,
        _startUrl = startUrl,
        _initialTwoFactorSecret = initialTwoFactorSecret,
        _debugAllowed = debugAllowed;

  final TwoFactorSecretStore? _secretStore;
  final TotpGenerator? _totpGenerator;
  final GakujoLastPageStore? _lastPageStore;
  final GakujoAppSettingsStore? _appSettingsStore;
  final String? _startUrl;
  final String? _initialTwoFactorSecret;
  final bool? _debugAllowed;

  @override
  State<GakujoWebApp> createState() => _GakujoWebAppState();
}

class _GakujoWebAppState extends State<GakujoWebApp>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  late final TwoFactorSecretStore _secretStore;
  late final TotpGenerator _totpGenerator;
  late final GakujoWebViewService _webViewService;
  late final GakujoDownloadService _downloadService;
  late final GakujoLastPageStore _lastPageStore;
  late final GakujoAppSettingsStore _appSettingsStore;
  late final bool _debugAllowed;
  String? _currentPageUrl;
  String _status = '準備中';
  bool _canGoBack = false;
  bool _canGoForward = false;
  DownloadDestinationSettings _downloadRoot =
      const DownloadDestinationSettings(isConfigured: false);
  GakujoAppSettings _appSettings = const GakujoAppSettings();
  String? _currentCourseName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _secretStore = widget._secretStore ?? TwoFactorSecretStore();
    _totpGenerator = widget._totpGenerator ?? const TotpGenerator();
    final platformService = GakujoPlatformService.current();
    _webViewService = platformService.createWebViewService();
    _downloadService = platformService.createDownloadService();
    _lastPageStore = widget._lastPageStore ?? GakujoLastPageStore();
    _appSettingsStore = widget._appSettingsStore ?? GakujoAppSettingsStore();
    _debugAllowed = widget._debugAllowed ?? kDebugMode;

    _controller = _webViewService.createController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        GakujoDownloadCaptureScript.channelName,
        onMessageReceived: _handleDownloadMessage,
      )
      ..addJavaScriptChannel(
        LoginAutofillAssistScript.channelName,
        onMessageReceived: _handleLoginAutofillMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigationRequest,
          onPageStarted: (url) {
            _currentPageUrl = url;
            unawaited(_refreshNavigationState());
            _setStatus('読込中: ${_displayUrl(url)}');
          },
          onPageFinished: (url) async {
            _currentPageUrl = url;
            _setStatus('表示中: ${_displayUrl(url)}');
            await _saveLastPageUrl(url);
            await _refreshNavigationState();
            await _injectLoginAutofillAssistIfAllowed();
            await _injectTwoFactorAutofillIfAllowed();
            await _injectDownloadCaptureIfAllowed();
            await _refreshEstimatedCourseName();
          },
          onWebResourceError: (error) {
            _setStatus('読込エラー: ${error.description}');
          },
        ),
      );

    _loadDownloadRoot();
    unawaited(_loadInitialPage());
  }

  @override
  void dispose() {
    unawaited(_saveCurrentPageUrl());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_saveCurrentPageUrl());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleSystemBack());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('More Better Gakujo'),
          actions: [
            GakujoNavigationActions(
              canGoBack: _canGoBack,
              canGoForward: _canGoForward,
              onBack: () => unawaited(_goBack()),
              onForward: () => unawaited(_goForward()),
            ),
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
              child: _webViewService.buildWidget(_controller),
            ),
          ],
        ),
      ),
    );
  }

  Future<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) async {
    final canLoad = AllowedWebOrigins.canLoad(
      request.url,
      debugAllowed: _debugAllowed,
    );
    if (!canLoad) {
      _setStatus('ブロック: ${_displayUrl(request.url)}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gakujo以外のページをブロックしました')),
      );
      return NavigationDecision.prevent;
    }

    if (GakujoDownloadUrlPolicy.shouldDownload(request.url)) {
      final title = await _controller.getTitle();
      final courseName = await _estimateCourseNameFromPage(title);
      await _handleDownloadRequest(
        GakujoDownloadRequest(
          url: request.url,
          method: 'GET',
          courseName: courseName,
          fileName: '',
          formFields: const {},
        ),
      );
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  Future<String> _estimateCourseNameFromPage(String? fallbackTitle) async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        '(window.__MBG_ESTIMATE_COURSE_NAME && '
        'window.__MBG_ESTIMATE_COURSE_NAME()) || ""',
      );
      final estimated = _stringFromJavaScriptResult(result).trim();
      debugPrint('MoreBetterGakujo course estimate script="$estimated"');
      if (_isUsefulCourseName(estimated)) {
        return estimated;
      }
    } catch (error, stackTrace) {
      developer.log(
        'Failed to estimate course name from page',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final tableEstimate = await _estimateCourseNameFromTables();
    if (_isUsefulCourseName(tableEstimate)) {
      return tableEstimate;
    }

    final bodyEstimate = await _estimateCourseNameFromBodyText();
    if (_isUsefulCourseName(bodyEstimate)) {
      return bodyEstimate;
    }

    final fallback = fallbackTitle?.trim() ?? '';
    if (_isUsefulCourseName(fallback)) {
      return fallback;
    }
    return '未分類';
  }

  Future<void> _refreshEstimatedCourseName() async {
    final estimated = await _estimateCourseNameFromPage(
      await _controller.getTitle(),
    );
    if (!_isUsefulCourseName(estimated)) {
      return;
    }
    _currentCourseName = estimated;
    debugPrint('MoreBetterGakujo current course="$estimated"');
  }

  Future<void> _showSettingsDialog() async {
    var secretInput = '';
    var loginIdInput = '';
    var loginPasswordInput = '';
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canSaveSecret = secretInput.trim().isNotEmpty;
            final canSaveLoginCredentials =
                loginIdInput.trim().isNotEmpty && loginPasswordInput.isNotEmpty;

            Future<void> refreshDownloadRoot(
              Future<DownloadDestinationSettings> Function() action,
            ) async {
              try {
                final next = await action();
                if (!mounted) {
                  return;
                }
                setState(() {
                  _downloadRoot = next;
                });
                setDialogState(() {});
              } on PlatformException catch (error) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'ダウンロード保存先を設定できませんでした: ${error.message ?? error.code}',
                      ),
                    ),
                  );
                }
              }
            }

            final rootLabel = _downloadRoot.isConfigured
                ? (_downloadRoot.displayName ?? '設定済み')
                : '未設定';
            final selectedDownloadSaveMode = _appSettings.downloadSaveMode;
            final selectedPageMode = _appSettings.pageMode;

            return AlertDialog(
              title: const Text('設定'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TwoFactorSecretSection(
                      canSave: canSaveSecret,
                      onChanged: (value) {
                        secretInput = value;
                        setDialogState(() {});
                      },
                      onClear: () async {
                        await _secretStore.clear();
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('2FA秘密鍵を削除しました')),
                          );
                        }
                      },
                      onSave: () async {
                        try {
                          await _secretStore.save(secretInput);
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('2FA秘密鍵を保存しました')),
                            );
                          }
                          await _injectTwoFactorAutofillIfAllowed();
                        } on FormatException {
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('長いBase32秘密鍵を確認してください'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const Divider(height: 32),
                    LoginCredentialsSection(
                      isConfigured: _appSettings.hasLoginCredentials,
                      canSave: canSaveLoginCredentials,
                      onLoginIdChanged: (value) {
                        loginIdInput = value;
                        setDialogState(() {});
                      },
                      onPasswordChanged: (value) {
                        loginPasswordInput = value;
                        setDialogState(() {});
                      },
                      onClear: () async {
                        await _appSettingsStore.clearLoginCredentials();
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _appSettings =
                              _appSettings.copyWith(loginCredentials: null);
                        });
                        setDialogState(() {});
                        messenger.showSnackBar(
                          const SnackBar(content: Text('ログイン情報を削除しました')),
                        );
                      },
                      onSave: () async {
                        await _appSettingsStore.saveLoginCredentials(
                          loginId: loginIdInput,
                          password: loginPasswordInput,
                        );
                        if (!mounted) {
                          return;
                        }
                        final credentials = GakujoLoginCredentials(
                          loginId: loginIdInput.trim(),
                          password: loginPasswordInput,
                        );
                        setState(() {
                          _appSettings = _appSettings.copyWith(
                            loginCredentials: credentials,
                          );
                        });
                        setDialogState(() {});
                        messenger.showSnackBar(
                          const SnackBar(content: Text('ログイン情報を保存しました')),
                        );
                        await _injectLoginAutofillAssistIfAllowed();
                      },
                    ),
                    const Divider(height: 32),
                    DownloadDestinationSection(
                      rootLabel: rootLabel,
                      isConfigured: _downloadRoot.isConfigured,
                      saveMode: selectedDownloadSaveMode,
                      onSaveModeChanged: (mode) async {
                        if (mode == null) {
                          return;
                        }
                        await _appSettingsStore.saveDownloadSaveMode(mode);
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _appSettings =
                              _appSettings.copyWith(downloadSaveMode: mode);
                        });
                        setDialogState(() {});
                      },
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
                    const Divider(height: 32),
                    GakujoPageModeSection(
                      pageMode: selectedPageMode,
                      onChanged: (mode) async {
                        if (mode == null) {
                          return;
                        }
                        await _appSettingsStore.savePageMode(mode);
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _appSettings = _appSettings.copyWith(pageMode: mode);
                        });
                        setDialogState(() {});
                        await _controller.loadRequest(Uri.parse(mode.startUrl));
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('閉じる'),
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
      debugPrint(
        'MoreBetterGakujo download candidate ${request.method} '
        '${_displayUrl(request.url)} as "${request.fileName}" '
        'course="${request.courseName}"',
      );
    } on FormatException {
      _setStatus('保存エラー: ダウンロード情報を読めませんでした');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ダウンロード情報を読めませんでした')),
        );
      }
      return;
    }

    await _handleDownloadRequest(request);
  }

  void _handleLoginAutofillMessage(JavaScriptMessage message) {
    debugPrint('MoreBetterGakujo login autofill ${message.message}');
    developer.log(
      'Login autofill ${message.message}',
      name: 'MoreBetterGakujo',
    );
  }

  Future<void> _handleDownloadRequest(GakujoDownloadRequest request) async {
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

    var effectiveRequest = request;
    if (!_isUsefulCourseName(request.courseName)) {
      final pageCourseName =
          await _estimateCourseNameFromPage(await _controller.getTitle());
      final cachedCourseName = _currentCourseName;
      final courseName = _isUsefulCourseName(pageCourseName)
          ? pageCourseName
          : _isUsefulCourseName(cachedCourseName ?? '')
              ? cachedCourseName!
              : null;
      if (courseName != null) {
        effectiveRequest = GakujoDownloadRequest(
          url: request.url,
          method: request.method,
          courseName: courseName,
          fileName: request.fileName,
          formFields: request.formFields,
        );
      }
    }
    debugPrint(
      'Download request course="${effectiveRequest.courseName}" '
      'file="${effectiveRequest.fileName}"',
    );

    var root = _downloadRoot;
    if (_appSettings.downloadSaveMode.needsConfiguredRoot &&
        !root.isConfigured) {
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
      _setStatus('ダウンロード中: ${effectiveRequest.fileName}');
      final result = await _downloadService.download(
        effectiveRequest,
        userAgent: await _userAgent(),
        cookieHeader: await _cookieHeader(),
        saveMode: _appSettings.downloadSaveMode,
      );
      final savedPath = result.courseName.isEmpty
          ? result.fileName
          : '${result.courseName}/${result.fileName}';
      _setStatus('保存しました: $savedPath');
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
    return _stringFromJavaScriptResult(result);
  }

  Future<String?> _cookieHeader() async {
    if (!AllowedWebOrigins.canLoad(
      _currentPageUrl,
      debugAllowed: _debugAllowed,
    )) {
      return null;
    }

    try {
      final result = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      return _stringFromJavaScriptResult(result);
    } catch (error, stackTrace) {
      developer.log(
        'Failed to read WebView cookie header',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
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

  Future<void> _injectLoginAutofillAssistIfAllowed() async {
    if (!AllowedWebOrigins.canLoad(
      _currentPageUrl,
      debugAllowed: _debugAllowed,
    )) {
      return;
    }

    try {
      final credentials = _appSettings.loginCredentials;
      debugPrint(
        'MoreBetterGakujo inject login autofill '
        'hasCredentials=${credentials?.isComplete ?? false}',
      );
      developer.log(
        'Inject login autofill url=${_displayUrl(_currentPageUrl)} '
        'hasCredentials=${credentials?.isComplete ?? false}',
        name: 'MoreBetterGakujo',
      );
      await _controller.runJavaScript(
        LoginAutofillAssistScript.build(
          credentials: credentials == null
              ? null
              : GakujoLoginAutofillCredentials(
                  loginId: credentials.loginId,
                  password: credentials.password,
                ),
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to inject login autofill assist script',
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
    await _webViewService.configureController(
      _controller,
      debugAllowed: _debugAllowed,
    );
    await _saveInitialTwoFactorSecretIfAllowed();
    await _loadAppSettings();
    final savedUrl = _appSettings.hasLoginCredentials
        ? null
        : await _lastPageStore.load(debugAllowed: _debugAllowed);
    await _controller.loadRequest(Uri.parse(_resolveStartUrl(savedUrl)));
  }

  Future<void> _loadAppSettings() async {
    final settings = await _appSettingsStore.load();
    if (!mounted) {
      return;
    }

    setState(() {
      _appSettings = settings;
    });
  }

  Future<void> _saveInitialTwoFactorSecretIfAllowed() async {
    final secret = widget._initialTwoFactorSecret;
    if (!_debugAllowed || secret == null || secret.isEmpty) {
      return;
    }

    await _secretStore.save(secret);
  }

  String _resolveStartUrl(String? savedUrl) {
    return GakujoStartUrlResolver.resolve(
      debugAllowed: _debugAllowed,
      debugStartUrl: widget._startUrl,
      savedUrl: savedUrl,
      fallbackUrl: _appSettings.pageMode.startUrl,
    );
  }

  Future<void> _handleSystemBack() async {
    if (await _goBackIfPossible()) {
      return;
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('前のページはありません')),
    );
  }

  Future<void> _goBack() async {
    if (!await _goBackIfPossible() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('前のページはありません')),
      );
    }
  }

  Future<bool> _goBackIfPossible() async {
    if (!await _controller.canGoBack()) {
      await _refreshNavigationState();
      return false;
    }

    await _controller.goBack();
    await _refreshNavigationState();
    return true;
  }

  Future<void> _goForward() async {
    if (await _controller.canGoForward()) {
      await _controller.goForward();
    }
    await _refreshNavigationState();
  }

  Future<void> _refreshNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    if (!mounted) {
      return;
    }

    if (_canGoBack == canGoBack && _canGoForward == canGoForward) {
      return;
    }

    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  Future<void> _saveCurrentPageUrl() async {
    String? url;
    try {
      url = await _controller.currentUrl();
    } catch (error, stackTrace) {
      developer.log(
        'Failed to read current WebView URL',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }

    await _saveLastPageUrl(url ?? _currentPageUrl);
  }

  Future<void> _saveLastPageUrl(String? url) async {
    try {
      await _lastPageStore.saveIfAllowed(url, debugAllowed: _debugAllowed);
    } catch (error, stackTrace) {
      developer.log(
        'Failed to save last page URL',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
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

  String _stringFromJavaScriptResult(Object? result) {
    final raw = result?.toString() ?? '';
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is String) {
          return decoded;
        }
      } on FormatException {
        return raw;
      }
    }
    return raw;
  }

  Future<String> _estimateCourseNameFromBodyText() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        r'''
(function() {
  var texts = [];
  function collect(win) {
    try {
      if (win.document && win.document.body) {
        texts.push(win.document.body.innerText || '');
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        collect(win.frames[i]);
      }
    } catch (e) {}
  }
  collect(window);
  return texts.join('\n\n');
})()
''',
      );
      final bodyText = _stringFromJavaScriptResult(result);
      final candidates = _courseNameCandidatesFromBodyText(bodyText);
      final estimated = GakujoCourseNameEstimator.estimateFromCandidates(
        candidates,
      );
      debugPrint(
        'MoreBetterGakujo course estimate body="$estimated" '
        'candidates="${candidates.take(3).join(' / ')}"',
      );
      return estimated;
    } catch (error, stackTrace) {
      developer.log(
        'Failed to estimate course name from body text',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return '未分類';
    }
  }

  Future<String> _estimateCourseNameFromTables() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        r'''
(function() {
  function textOf(element) {
    return ((element && (element.innerText || element.textContent)) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }
  function collectDocuments() {
    var documents = [];
    function collect(win) {
      try {
        if (win.document) {
          documents.push(win.document);
        }
        for (var i = 0; i < win.frames.length; i += 1) {
          collect(win.frames[i]);
        }
      } catch (e) {}
    }
    collect(window);
    return documents;
  }
  var documents = collectDocuments();
  for (var d = 0; d < documents.length; d += 1) {
    var tables = documents[d].querySelectorAll('table');
    for (var t = 0; t < tables.length; t += 1) {
      var rows = tables[t].querySelectorAll('tr');
      for (var r = 0; r < rows.length; r += 1) {
        var cells = rows[r].querySelectorAll('th,td');
        var courseIndex = -1;
        for (var c = 0; c < cells.length; c += 1) {
          if (textOf(cells[c]) === '科目名') {
            courseIndex = c;
            break;
          }
        }
        if (courseIndex < 0) {
          continue;
        }
        for (var same = courseIndex + 1; same < cells.length; same += 1) {
          var sameRowValue = textOf(cells[same]);
          if (sameRowValue) {
            return sameRowValue;
          }
        }
        for (var next = r + 1; next < rows.length; next += 1) {
          var nextCells = rows[next].querySelectorAll('th,td');
          if (nextCells.length <= courseIndex) {
            continue;
          }
          var value = textOf(nextCells[courseIndex]);
          if (value) {
            return value;
          }
        }
      }
    }
  }
  return '';
})()
''',
      );
      final rawEstimate = _stringFromJavaScriptResult(result).trim();
      final estimated = GakujoCourseNameEstimator.estimateFromCandidates([
        rawEstimate,
      ]);
      debugPrint(
        'MoreBetterGakujo course estimate table="$estimated" '
        'raw="$rawEstimate"',
      );
      return estimated;
    } catch (error) {
      debugPrint('MoreBetterGakujo course estimate table failed: $error');
      return '未分類';
    }
  }

  List<String> _courseNameCandidatesFromBodyText(String bodyText) {
    final lines = bodyText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final labeledLines = lines
        .where(
          (line) => RegExp(
            r'授業科目名|授業科目|科目名|授業名|講義名|科目\s*[:：]',
          ).hasMatch(line),
        )
        .toList();
    final compactBody = bodyText.replaceAll(RegExp(r'\s+'), ' ').trim();
    return [
      ...labeledLines,
      compactBody,
    ];
  }

  bool _isUsefulCourseName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '未分類') {
      return false;
    }

    const genericPageLabels = {
      '開設一覧',
      '連絡通知',
      '掲示一覧',
      '授業ポートフォリオ',
      'レポート・小テスト・アンケート提出',
      'レポート提出',
      '小テスト',
      'アンケート',
      '年度 開講所属 開講番号 科目名',
      'タイトル',
    };
    if (genericPageLabels.contains(normalized)) {
      return false;
    }

    final lower = normalized.toLowerCase();
    return !lower.contains('campussquare') &&
        !lower.contains('more better gakujo') &&
        !normalized.contains('学務情報システム');
  }
}

class GakujoNavigationActions extends StatelessWidget {
  const GakujoNavigationActions({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '前のページ',
          onPressed: canGoBack ? onBack : null,
          icon: const Icon(Icons.arrow_back),
        ),
        IconButton(
          tooltip: '次のページ',
          onPressed: canGoForward ? onForward : null,
          icon: const Icon(Icons.arrow_forward),
        ),
      ],
    );
  }
}

class TwoFactorSecretSection extends StatelessWidget {
  const TwoFactorSecretSection({
    super.key,
    required this.canSave,
    required this.onChanged,
    required this.onClear,
    required this.onSave,
  });

  final bool canSave;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onClear;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '2FA秘密鍵',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'QRコード横の長いBase32文字列を保存します。6桁コードではありません。保存済みの秘密鍵は表示しません。\n取得方法: https://github.com/koji-genba/gakujo-chan-extender#2段階認証自動入力',
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
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: canSave ? () => unawaited(onSave()) : null,
              icon: const Icon(Icons.key),
              label: const Text('秘密鍵を保存'),
            ),
            TextButton.icon(
              onPressed: () => unawaited(onClear()),
              icon: const Icon(Icons.delete_outline),
              label: const Text('秘密鍵を削除'),
            ),
          ],
        ),
      ],
    );
  }
}

class LoginCredentialsSection extends StatelessWidget {
  const LoginCredentialsSection({
    super.key,
    required this.isConfigured,
    required this.canSave,
    required this.onLoginIdChanged,
    required this.onPasswordChanged,
    required this.onClear,
    required this.onSave,
  });

  final bool isConfigured;
  final bool canSave;
  final ValueChanged<String> onLoginIdChanged;
  final ValueChanged<String> onPasswordChanged;
  final Future<void> Function() onClear;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    final status = isConfigured ? '保存済み' : '未設定';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ログイン自動入力',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'ログインIDとパスワードを端末内に保存します。保存済みの場合、起動直後のログイン画面で入力とログイン操作を自動で行います。現在の状態: $status',
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'ログインID',
            border: OutlineInputBorder(),
          ),
          enableSuggestions: false,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          onChanged: onLoginIdChanged,
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            labelText: 'パスワード',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onChanged: onPasswordChanged,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: canSave ? () => unawaited(onSave()) : null,
              icon: const Icon(Icons.login),
              label: const Text('ログイン情報を保存'),
            ),
            TextButton.icon(
              onPressed: isConfigured ? () => unawaited(onClear()) : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('ログイン情報を削除'),
            ),
          ],
        ),
      ],
    );
  }
}

class DownloadDestinationSection extends StatelessWidget {
  const DownloadDestinationSection({
    super.key,
    required this.rootLabel,
    required this.isConfigured,
    required this.saveMode,
    required this.onSaveModeChanged,
    required this.onPick,
    required this.onClear,
  });

  final String rootLabel;
  final bool isConfigured;
  final DownloadSaveMode saveMode;
  final ValueChanged<DownloadSaveMode?> onSaveModeChanged;
  final Future<void> Function() onPick;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ダウンロード設定',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'ファイル保存モード',
            border: OutlineInputBorder(),
          ),
          child: RadioGroup<DownloadSaveMode>(
            groupValue: saveMode,
            onChanged: onSaveModeChanged,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in DownloadSaveMode.values)
                  RadioListTile<DownloadSaveMode>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: mode,
                    title: Text(mode.label),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: '保存先フォルダ',
            border: OutlineInputBorder(),
          ),
          child: Text(rootLabel),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open),
              label: const Text('フォルダを選択'),
            ),
            TextButton.icon(
              onPressed: isConfigured ? onClear : null,
              icon: const Icon(Icons.link_off),
              label: const Text('解除'),
            ),
          ],
        ),
      ],
    );
  }
}

class GakujoPageModeSection extends StatelessWidget {
  const GakujoPageModeSection({
    super.key,
    required this.pageMode,
    required this.onChanged,
  });

  final GakujoPageMode pageMode;
  final ValueChanged<GakujoPageMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '表示版',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: '開く画面',
            border: OutlineInputBorder(),
          ),
          child: RadioGroup<GakujoPageMode>(
            groupValue: pageMode,
            onChanged: onChanged,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in GakujoPageMode.values)
                  RadioListTile<GakujoPageMode>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: mode,
                    title: Text(mode.label),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
