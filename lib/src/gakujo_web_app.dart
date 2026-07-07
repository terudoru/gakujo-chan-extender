import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'allowed_web_origins.dart';
import 'app_update_service.dart';
import 'desktop_page_zoom_script.dart';
import 'download_destination_settings.dart';
import 'download_file_name_policy.dart';
import 'gakujo_activity_store.dart';
import 'gakujo_activity_classifier.dart';
import 'gakujo_academic_calendar.dart';
import 'gakujo_academic_calendar_resolver.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_calendar_export.dart';
import 'gakujo_calendar_service.dart';
import 'gakujo_course_name_estimator.dart';
import 'gakujo_dated_activity.dart';
import 'gakujo_download_capture_script.dart';
import 'gakujo_download_history_store.dart';
import 'gakujo_download_request.dart';
import 'gakujo_download_service.dart';
import 'gakujo_download_url_policy.dart';
import 'file_system_gakujo_download_service.dart';
import 'gakujo_gpa_display_script.dart';
import 'gakujo_last_page_store.dart';
import 'gakujo_message_filter_script.dart';
import 'gakujo_message_reader_script.dart';
import 'gakujo_notification_service.dart';
import 'gakujo_report_draft_script.dart';
import 'gakujo_report_sorter_script.dart';
import 'gakujo_session_extender_script.dart';
import 'platform/platform_service.dart';
import 'secure_storage_factory.dart';
import 'gakujo_start_url_resolver.dart';
import 'login_autofill_assist_script.dart';
import 'totp_generator.dart';
import 'two_factor_autofill_script.dart';
import 'two_factor_secret_store.dart';
import 'web_view_service.dart';

enum _ToolbarAction {
  addFavorite,
  copyUrl,
  openExternal,
  reload,
}

enum _CalendarValidationAction { add, delete }

enum _SecureStorageRecoveryAction { retry, reset, continueWithoutStorage }

enum _ScheduleIntegrationAction {
  syncCalendar,
  deleteDeviceCalendar,
  validation,
}

const _calendarValidationTitle = 'More Better Gakujo 検証';
const _calendarValidationUidNamespace = 'calendar-validation';
const _schedulePortalUrl =
    'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=sch';
const _compactToolbarHeight = 40.0;
const _toolbarButtonExtent = 40.0;
const _toolbarIconSize = 20.0;
const _zoomResetButtonWidth = 56.0;

@visibleForTesting
String downloadRootLabel(
  DownloadDestinationSettings root, {
  required bool includePath,
}) {
  if (!root.isConfigured) {
    return '未設定';
  }

  final displayName = root.displayName?.trim();
  final path = root.path?.trim();
  if (!includePath) {
    return displayName?.isNotEmpty == true ? displayName! : '設定済み';
  }

  if (path == null || path.isEmpty || path == displayName) {
    return displayName?.isNotEmpty == true ? displayName! : '設定済み';
  }

  if (displayName == null || displayName.isEmpty) {
    return path;
  }
  return '$displayName\n$path';
}

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

@visibleForTesting
Uri savedDownloadLocationUri(String location) {
  final trimmed = location.trim();
  if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed) ||
      trimmed.startsWith(r'\\')) {
    return Uri.file(trimmed, windows: true);
  }

  final schemeMatch = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(
    trimmed,
  );
  if (schemeMatch != null) {
    final scheme = schemeMatch.group(1)?.toLowerCase();
    if (scheme == 'content' || scheme == 'file') {
      return Uri.parse(trimmed);
    }
  }

  return Uri.file(File(trimmed).absolute.path);
}

@visibleForTesting
bool javaScriptResultAsBool(Object? result) {
  if (result is bool) {
    return result;
  }
  if (result is num) {
    return result != 0;
  }
  final raw = result?.toString().trim() ?? '';
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is bool) {
        return decoded;
      }
      return decoded.toString().toLowerCase() == 'true';
    } on FormatException {
      return false;
    }
  }
  // Some WebView platforms surface a JS boolean as the numeric string 1/0.
  return raw.toLowerCase() == 'true' || raw == '1';
}

@visibleForTesting
bool isCancelledDownloadError(PlatformException error) {
  return error.code == 'cancelled';
}

@visibleForTesting
bool shouldReadPageForActivityFeatures(GakujoAppSettings settings) {
  return settings.isFeatureEnabled(GakujoFeatureFlag.activityScan) ||
      settings.isFeatureEnabled(GakujoFeatureFlag.deadlineScan) ||
      settings.isFeatureEnabled(GakujoFeatureFlag.reportListCache);
}

@visibleForTesting
bool get activityBellToolbarButtonEnabled => false;

class _GakujoWebAppState extends State<GakujoWebApp>
    with WidgetsBindingObserver {
  late final GakujoWebViewController _controller;
  late final Future<void> _webViewReady;
  late final TwoFactorSecretStore _secretStore;
  late final TotpGenerator _totpGenerator;
  late final GakujoWebViewService _webViewService;
  late final GakujoDownloadService _downloadService;
  late final GakujoCalendarService _calendarService;
  late final GakujoDownloadHistoryStore _downloadHistoryStore;
  late final GakujoActivityStore _activityStore;
  late final GakujoNotificationService _notificationService;
  late final AppUpdateService _updateService;
  late final GakujoAcademicCalendarResolver _academicCalendarResolver;
  late final GakujoLastPageStore _lastPageStore;
  late final GakujoAppSettingsStore _appSettingsStore;
  late final bool _debugAllowed;
  String? _currentPageUrl;
  String? _lastAllowedPageUrl;
  String _status = '準備中';
  bool _canGoBack = false;
  bool _canGoForward = false;
  DownloadDestinationSettings _downloadRoot =
      const DownloadDestinationSettings(isConfigured: false);
  GakujoAppSettings _appSettings = const GakujoAppSettings();
  String? _currentCourseName;
  String? _pendingLoginRestoreUrl;
  String? _sessionRecoveryUrl;
  String? _lastSessionRecoveryNoticeUrl;
  bool _loginRestoreAttempted = false;
  bool _isSettingsDialogOpen = false;
  bool _appSettingsLoaded = false;
  bool _secureStorageAccessAllowed = !Platform.isMacOS;
  bool _loginAutofillStorageLoadAttempted = false;
  bool _secureStorageRecoveryDialogVisible = false;
  int _deadlineCount = 0;
  double _desktopZoom = 1.0;
  double _desktopPanZoomStartZoom = 1.0;
  bool _desktopPanZoomIsPinching = false;
  double _desktopHistorySwipeDistance = 0;
  bool _desktopHistorySwipeTriggered = false;
  int _desktopZoomApplyRevision = 0;
  Offset? _desktopZoomOrigin;
  Timer? _desktopHistorySwipeResetTimer;
  Timer? _autoBackupTimer;
  Completer<String>? _nextPageFinishedCompleter;
  Future<void> _desktopZoomApplyQueue = Future<void>.value();

  static const double _minimumDesktopZoom = 0.5;
  static const double _maximumDesktopZoom = 2.0;
  static const double _desktopZoomStep = 0.1;
  static const double _desktopHistorySwipeThreshold = 120;
  static const double _desktopHorizontalSwipeDominance = 1.35;
  static const double _desktopPinchZoomDeadZone = 0.01;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _secretStore = widget._secretStore ?? TwoFactorSecretStore();
    _totpGenerator = widget._totpGenerator ?? const TotpGenerator();
    final platformService = GakujoPlatformService.current();
    _webViewService = platformService.createWebViewService();
    _calendarService = platformService.createCalendarService();
    _downloadHistoryStore = GakujoDownloadHistoryStore();
    _activityStore = GakujoActivityStore();
    _notificationService = const GakujoNotificationService();
    _updateService = const AppUpdateService();
    _academicCalendarResolver = const GakujoAcademicCalendarResolver();
    _lastPageStore = widget._lastPageStore ?? GakujoLastPageStore();
    _appSettingsStore = widget._appSettingsStore ?? GakujoAppSettingsStore();
    _debugAllowed = widget._debugAllowed ?? kDebugMode;

    _controller = _webViewService.createController();
    _downloadService = Platform.isWindows
        ? FileSystemGakujoDownloadService(
            authenticatedBytesLoader: _downloadBytesWithWebViewSession,
          )
        : platformService.createDownloadService();
    _webViewReady = _configureWebViewController();

    if (_secureStorageAccessAllowed) {
      _loadDownloadRoot();
      unawaited(_compactStoredData());
    }
    if (activityBellToolbarButtonEnabled) {
      _refreshActivityCounts();
    }
    unawaited(_loadInitialPage());
  }

  @override
  void dispose() {
    unawaited(_saveCurrentPageUrl());
    unawaited(_controller.dispose());
    _desktopHistorySwipeResetTimer?.cancel();
    _autoBackupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_saveCurrentPageUrl());
      if (_appSettingsLoaded &&
          _appSettings.isFeatureEnabled(GakujoFeatureFlag.autoBackup)) {
        unawaited(_writeAutomaticBackup());
      }
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
          toolbarHeight: _compactToolbarHeight,
          titleSpacing: 0,
          title: const SizedBox.shrink(),
          actions: [
            GakujoNavigationActions(
              canGoBack: _canGoBack,
              canGoForward: _canGoForward,
              onBack: () => unawaited(_goBack()),
              onForward: () => unawaited(_goForward()),
            ),
            if (activityBellToolbarButtonEnabled)
              IconButton(
                tooltip: '新着情報・期限・予定',
                onPressed: () => unawaited(_showActivityDialog()),
                icon: Badge.count(
                  count: _deadlineCount,
                  isLabelVisible: _deadlineCount > 0,
                  child: const Icon(Icons.notifications_outlined),
                ),
                iconSize: _toolbarIconSize,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: _toolbarButtonExtent,
                  height: _toolbarButtonExtent,
                ),
              ),
            if (_supportsDesktopZoom)
              GakujoZoomActions(
                zoomPercent: (_desktopZoom * 100).round(),
                canZoomOut: _desktopZoom > _minimumDesktopZoom,
                canZoomIn: _desktopZoom < _maximumDesktopZoom,
                onZoomOut: () => unawaited(_changeDesktopZoomBy(
                  -_desktopZoomStep,
                )),
                onReset: () => unawaited(_setDesktopZoom(1.0)),
                onZoomIn: () => unawaited(_changeDesktopZoomBy(
                  _desktopZoomStep,
                )),
              ),
            IconButton(
              tooltip: '設定',
              onPressed: _isSettingsDialogOpen
                  ? null
                  : () => unawaited(_showSettingsDialog()),
              icon: const Icon(Icons.settings),
              iconSize: _toolbarIconSize,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(
                width: _toolbarButtonExtent,
                height: _toolbarButtonExtent,
              ),
            ),
            SizedBox.square(
              dimension: _toolbarButtonExtent,
              child: PopupMenuButton<_ToolbarAction>(
                tooltip: 'メニュー',
                padding: EdgeInsets.zero,
                iconSize: _toolbarIconSize,
                icon: const Icon(Icons.more_vert),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _ToolbarAction.addFavorite,
                    child: Text('お気に入りに追加'),
                  ),
                  PopupMenuItem(
                    value: _ToolbarAction.copyUrl,
                    child: Text('URLをコピー'),
                  ),
                  PopupMenuItem(
                    value: _ToolbarAction.openExternal,
                    child: Text('外部ブラウザで開く'),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: _ToolbarAction.reload,
                    child: Text('再読込'),
                  ),
                ],
                onSelected: (action) => unawaited(_handleToolbarAction(action)),
              ),
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
                    vertical: 4,
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
              child: _isSettingsDialogOpen
                  ? const SizedBox.expand()
                  : _buildWebViewArea(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebViewArea() {
    final content = _webViewService.buildWidget(_controller);

    if (!_supportsDesktopZoom) {
      return content;
    }

    return Focus(
      autofocus: true,
      onKeyEvent: _handleDesktopZoomKeyEvent,
      child: Listener(
        onPointerHover: _handleDesktopPointerHover,
        onPointerDown: _handleDesktopPointerDown,
        onPointerSignal: _handleDesktopZoomPointerSignal,
        onPointerPanZoomStart: _handleDesktopPanZoomStart,
        onPointerPanZoomUpdate: _handleDesktopPanZoomUpdate,
        onPointerPanZoomEnd: _handleDesktopPanZoomEnd,
        child: content,
      ),
    );
  }

  void _handleDesktopPointerHover(PointerHoverEvent event) {
    _desktopZoomOrigin = event.localPosition;
  }

  void _handleDesktopPointerDown(PointerDownEvent event) {
    _desktopZoomOrigin = event.localPosition;
  }

  bool get _supportsDesktopZoom {
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  KeyEventResult _handleDesktopZoomKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      unawaited(_changeDesktopZoomBy(_desktopZoomStep));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      unawaited(_changeDesktopZoomBy(-_desktopZoomStep));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      unawaited(_setDesktopZoom(1.0));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _handleDesktopZoomPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (!HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed) {
      _handleDesktopHistorySwipeDelta(event.scrollDelta);
      return;
    }

    final delta =
        event.scrollDelta.dy < 0 ? _desktopZoomStep : -_desktopZoomStep;
    _desktopZoomOrigin = event.localPosition;
    unawaited(_changeDesktopZoomBy(delta));
  }

  void _handleDesktopPanZoomStart(PointerPanZoomStartEvent event) {
    _desktopPanZoomStartZoom = _desktopZoom;
    _desktopPanZoomIsPinching = false;
    _desktopZoomOrigin = event.localPosition;
    _resetDesktopHistorySwipe();
  }

  void _handleDesktopPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _desktopZoomOrigin = event.localPosition;
    if ((event.scale - 1).abs() > _desktopPinchZoomDeadZone) {
      _desktopPanZoomIsPinching = true;
      unawaited(_setDesktopZoomSmooth(_desktopPanZoomStartZoom * event.scale));
      return;
    }

    if (_desktopPanZoomIsPinching) {
      return;
    }

    _handleDesktopHistorySwipeDelta(event.panDelta);
  }

  void _handleDesktopPanZoomEnd(PointerPanZoomEndEvent event) {
    _desktopPanZoomIsPinching = false;
    _scheduleDesktopHistorySwipeReset();
  }

  void _handleDesktopHistorySwipeDelta(Offset delta) {
    if (!_supportsDesktopZoom || _desktopHistorySwipeTriggered) {
      return;
    }

    final horizontal = delta.dx.abs();
    final vertical = delta.dy.abs();
    if (horizontal <= vertical * _desktopHorizontalSwipeDominance) {
      if (vertical > horizontal) {
        _scheduleDesktopHistorySwipeReset();
      }
      return;
    }

    _desktopHistorySwipeDistance += delta.dx;
    _scheduleDesktopHistorySwipeReset();

    if (_desktopHistorySwipeDistance.abs() < _desktopHistorySwipeThreshold) {
      return;
    }

    _desktopHistorySwipeTriggered = true;
    if (_desktopHistorySwipeDistance < 0) {
      unawaited(_goBackIfPossible());
    } else {
      unawaited(_goForwardIfPossible());
    }
  }

  void _scheduleDesktopHistorySwipeReset() {
    _desktopHistorySwipeResetTimer?.cancel();
    _desktopHistorySwipeResetTimer = Timer(
      const Duration(milliseconds: 250),
      _resetDesktopHistorySwipe,
    );
  }

  void _resetDesktopHistorySwipe() {
    _desktopHistorySwipeResetTimer?.cancel();
    _desktopHistorySwipeResetTimer = null;
    _desktopHistorySwipeDistance = 0;
    _desktopHistorySwipeTriggered = false;
  }

  Future<void> _changeDesktopZoomBy(double delta) {
    return _setDesktopZoom(_desktopZoom + delta);
  }

  Future<void> _setDesktopZoom(double zoom) async {
    final nextZoom = (zoom / _desktopZoomStep).round() * _desktopZoomStep;
    return _setDesktopZoomValue(nextZoom);
  }

  Future<void> _setDesktopZoomSmooth(double zoom) {
    return _setDesktopZoomValue(zoom);
  }

  Future<void> _setDesktopZoomValue(double zoom) async {
    final clampedZoom = zoom
        .clamp(
          _minimumDesktopZoom,
          _maximumDesktopZoom,
        )
        .toDouble();
    if ((_desktopZoom - clampedZoom).abs() < 0.001) {
      await _applyDesktopZoomIfAllowed();
      return;
    }

    if (mounted) {
      setState(() {
        _desktopZoom = clampedZoom;
      });
    } else {
      _desktopZoom = clampedZoom;
    }
    await _applyDesktopZoomIfAllowed();
  }

  Future<void> _applyDesktopZoomIfAllowed() async {
    final revision = ++_desktopZoomApplyRevision;
    _desktopZoomApplyQueue = _desktopZoomApplyQueue.catchError((_) {}).then(
      (_) async {
        if (revision != _desktopZoomApplyRevision ||
            !mounted ||
            !_supportsDesktopZoom ||
            !_canRunPageScripts) {
          return;
        }

        try {
          await _controller.runJavaScript(
            DesktopPageZoomScript.build(
              _desktopZoom,
              originX: _desktopZoomOrigin?.dx,
              originY: _desktopZoomOrigin?.dy,
            ),
          );
        } catch (error, stackTrace) {
          developer.log(
            'Failed to apply desktop page zoom',
            name: 'MoreBetterGakujo',
            error: error,
            stackTrace: stackTrace,
          );
        }
      },
    );
    await _desktopZoomApplyQueue;
  }

  Future<GakujoNavigationDecision> _handleNavigationRequest(
    GakujoNavigationRequest request,
  ) async {
    if (_isInternalBlankUrl(request.url)) {
      return GakujoNavigationDecision.navigate;
    }

    final canNavigate = AllowedWebOrigins.canNavigate(
      request.url,
      debugAllowed: _debugAllowed,
    );
    if (!canNavigate) {
      _setStatus('ブロック: ${_displayUrl(request.url)}');
      _showSnackBar('許可されていない外部サイトをブロックしました');
      return GakujoNavigationDecision.prevent;
    }

    if (AllowedWebOrigins.canLoad(
          request.url,
          debugAllowed: _debugAllowed,
        ) &&
        _appSettings.isFeatureEnabled(GakujoFeatureFlag.downloadCapture) &&
        GakujoDownloadUrlPolicy.shouldDownload(request.url)) {
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
      return GakujoNavigationDecision.prevent;
    }

    return GakujoNavigationDecision.navigate;
  }

  Future<String> _estimateCourseNameFromPage(String? fallbackTitle) async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        '(window.__MBG_ESTIMATE_COURSE_NAME && '
        'window.__MBG_ESTIMATE_COURSE_NAME()) || ""',
      );
      final estimated = _stringFromJavaScriptResult(result).trim();
      if (kDebugMode) {
        debugPrint('MoreBetterGakujo course estimate script="$estimated"');
      }
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
    if (kDebugMode) {
      debugPrint('MoreBetterGakujo current course="$estimated"');
    }
  }

  Future<void> _showSettingsDialog() async {
    var secretInput = '';
    var loginIdInput = '';
    var loginPasswordInput = '';
    var messageExcludeKeywordInput = '';
    final messageExcludeKeywordController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isSettingsDialogOpen = true;
    });
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final canSaveSecret = secretInput.trim().isNotEmpty;
              final canSaveLoginCredentials = loginIdInput.trim().isNotEmpty &&
                  loginPasswordInput.isNotEmpty;
              final canAddMessageExcludeKeyword =
                  messageExcludeKeywordInput.trim().isNotEmpty;

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
                  if (!dialogContext.mounted) {
                    return;
                  }
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

              final rootLabel = _downloadRootLabel(_downloadRoot);
              final selectedDownloadSaveMode = _appSettings.downloadSaveMode;
              final selectedPageMode = _appSettings.pageMode;

              final sections = [
                SettingsExpansionSection(
                  title: 'ログイン',
                  icon: Icons.account_circle_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                          TextInput.finishAutofillContext(shouldSave: false);
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _appSettings =
                                _appSettings.copyWith(loginCredentials: null);
                          });
                          if (!dialogContext.mounted) {
                            return;
                          }
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
                          TextInput.finishAutofillContext(shouldSave: true);
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
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {});
                          messenger.showSnackBar(
                            const SnackBar(content: Text('ログイン情報を保存しました')),
                          );
                          await _injectLoginAutofillAssistIfAllowed();
                        },
                      ),
                      const Divider(height: 32),
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
                    ],
                  ),
                ),
                SettingsExpansionSection(
                  title: '保存設定',
                  icon: Icons.folder_outlined,
                  child: DownloadDestinationSection(
                    rootLabel: rootLabel,
                    isConfigured: _downloadRoot.isConfigured,
                    saveMode: selectedDownloadSaveMode,
                    helperText: _downloadDestinationHelperText,
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
                      if (!dialogContext.mounted) {
                        return;
                      }
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
                ),
                SettingsExpansionSection(
                  title: '表示設定',
                  icon: Icons.web_asset_outlined,
                  child: GakujoPageModeSection(
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
                      if (!dialogContext.mounted) {
                        return;
                      }
                      setDialogState(() {});
                      await _controller.loadUrl(mode.startUrl);
                    },
                  ),
                ),
                SettingsExpansionSection(
                  title: '機能設定',
                  icon: Icons.tune,
                  child: FeatureFlagsSection(
                    settings: _appSettings,
                    onChanged: (flag, enabled) async {
                      await _appSettingsStore.saveFeatureEnabled(
                        flag,
                        enabled: enabled,
                      );
                      final disabled = {
                        ..._appSettings.disabledFeatureFlags,
                      };
                      if (enabled) {
                        disabled.remove(flag);
                      } else {
                        disabled.add(flag);
                      }
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _appSettings = _appSettings.copyWith(
                          disabledFeatureFlags: disabled,
                        );
                      });
                      if (flag == GakujoFeatureFlag.autoBackup) {
                        _scheduleAutoBackup();
                      }
                      if (!dialogContext.mounted) {
                        return;
                      }
                      setDialogState(() {});
                    },
                  ),
                ),
                SettingsExpansionSection(
                  title: '連絡通知フィルタ',
                  icon: Icons.filter_alt_outlined,
                  child: MessageExcludeKeywordsSection(
                    keywords: _appSettings.messageExcludeKeywords,
                    controller: messageExcludeKeywordController,
                    canAdd: canAddMessageExcludeKeyword,
                    onChanged: (value) {
                      messageExcludeKeywordInput = value;
                      setDialogState(() {});
                    },
                    onAdd: () async {
                      final next = normalizeMessageExcludeKeywords([
                        ..._appSettings.messageExcludeKeywords,
                        messageExcludeKeywordInput,
                      ]);
                      await _saveMessageExcludeKeywords(next);
                      messageExcludeKeywordInput = '';
                      messageExcludeKeywordController.clear();
                      if (!dialogContext.mounted) {
                        return;
                      }
                      setDialogState(() {});
                    },
                    onRemove: (keyword) async {
                      final next = _appSettings.messageExcludeKeywords
                          .where((value) => value != keyword)
                          .toList();
                      await _saveMessageExcludeKeywords(next);
                      if (!dialogContext.mounted) {
                        return;
                      }
                      setDialogState(() {});
                    },
                  ),
                ),
                SettingsExpansionSection(
                  title: 'データ/履歴',
                  icon: Icons.storage_outlined,
                  child: AppDataShortcutsSection(
                    onShowDownloadHistory: _showDownloadHistoryDialog,
                    onShowFailedDownloads: _showFailedDownloadsDialog,
                    onShowCourseMaterials: _showCourseMaterialsDialog,
                    onShowCachedReports: _showCachedReportsDialog,
                    onShowChangeHistory: _showChangeHistoryDialog,
                    onShowFavorites: _showFavoritesDialog,
                    onShowDataManagement: _showDataManagementDialog,
                  ),
                ),
                SettingsExpansionSection(
                  title: '連携',
                  icon: Icons.event_available_outlined,
                  child: AppIntegrationSection(
                    onScheduleIntegration: _showScheduleIntegrationDialog,
                  ),
                ),
                SettingsExpansionSection(
                  title: 'バックアップ/診断',
                  icon: Icons.health_and_safety_outlined,
                  child: AppMaintenanceSection(
                    onCheckUpdates: _checkForUpdates,
                    onCreateBackup: _createManualBackup,
                    onCreateErrorReport: _createErrorReportPackage,
                    onExportSettings: _exportSettingsToClipboard,
                    onImportSettings: () async {
                      await _importSettingsFromClipboard();
                      if (!dialogContext.mounted) {
                        return;
                      }
                      setDialogState(() {});
                    },
                    onCheckDownloadDestination: _checkDownloadDestinationHealth,
                    onCopyDiagnostics: _copyDiagnosticInfo,
                  ),
                ),
              ];

              return Dialog.fullscreen(
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('設定'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('閉じる'),
                      ),
                    ],
                  ),
                  body: SafeArea(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                      itemCount: sections.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => sections[index],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSettingsDialogOpen = false;
        });
      }
      messageExcludeKeywordController.dispose();
    }
  }

  Future<void> _showInitialSetupWizard() async {
    if (_isSettingsDialogOpen) {
      return;
    }

    var selectedDownloadSaveMode = _appSettings.downloadSaveMode;
    var selectedPageMode = _appSettings.pageMode;
    final disabledFeatureFlags = {..._appSettings.disabledFeatureFlags};
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final wizardSettings = _appSettings.copyWith(
              downloadSaveMode: selectedDownloadSaveMode,
              pageMode: selectedPageMode,
              disabledFeatureFlags: disabledFeatureFlags,
              setupCompleted: true,
            );

            Future<void> complete() async {
              Object? saveError;
              StackTrace? saveStackTrace;
              try {
                await Future.wait([
                  _appSettingsStore.saveDownloadSaveMode(
                    selectedDownloadSaveMode,
                  ),
                  _appSettingsStore.savePageMode(selectedPageMode),
                  _appSettingsStore.saveDisabledFeatureFlags(
                    disabledFeatureFlags,
                  ),
                  _appSettingsStore.saveSetupCompleted(true),
                ]);
              } on Object catch (error, stackTrace) {
                saveError = error;
                saveStackTrace = stackTrace;
              }
              if (!mounted) {
                return;
              }
              setState(() {
                _appSettings = wizardSettings;
              });
              _scheduleAutoBackup();
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.of(dialogContext).pop();
              if (saveError != null) {
                developer.log(
                  'Failed to persist initial setup settings',
                  name: 'MoreBetterGakujo',
                  error: saveError,
                  stackTrace: saveStackTrace,
                );
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('初回セットアップを保存できませんでした。キーチェーン設定を確認してください。'),
                  ),
                );
              }
              await _controller.loadUrl(selectedPageMode.startUrl);
            }

            return AlertDialog(
              title: const Text('初回セットアップ'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GakujoPageModeSection(
                      pageMode: selectedPageMode,
                      onChanged: (mode) {
                        if (mode == null) {
                          return;
                        }
                        selectedPageMode = mode;
                        setDialogState(() {});
                      },
                    ),
                    const Divider(height: 32),
                    DownloadDestinationSection(
                      rootLabel: _downloadRootLabel(_downloadRoot),
                      isConfigured: _downloadRoot.isConfigured,
                      saveMode: selectedDownloadSaveMode,
                      helperText: _downloadDestinationHelperText,
                      onSaveModeChanged: (mode) {
                        if (mode == null) {
                          return;
                        }
                        selectedDownloadSaveMode = mode;
                        setDialogState(() {});
                      },
                      onPick: () async {
                        try {
                          final root =
                              await _downloadService.pickDownloadRoot();
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _downloadRoot = root;
                          });
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {});
                        } on PlatformException catch (error) {
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                '保存先を設定できませんでした: ${error.message ?? error.code}',
                              ),
                            ),
                          );
                        }
                      },
                      onClear: () async {
                        final root = await _downloadService.clearDownloadRoot();
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _downloadRoot = root;
                        });
                        if (!dialogContext.mounted) {
                          return;
                        }
                        setDialogState(() {});
                      },
                    ),
                    const Divider(height: 32),
                    FeatureFlagsSection(
                      settings: wizardSettings,
                      onChanged: (flag, enabled) {
                        if (enabled) {
                          disabledFeatureFlags.remove(flag);
                        } else {
                          disabledFeatureFlags.add(flag);
                        }
                        setDialogState(() {});
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Object? saveError;
                    StackTrace? saveStackTrace;
                    try {
                      await _appSettingsStore.saveSetupCompleted(true);
                    } on Object catch (error, stackTrace) {
                      saveError = error;
                      saveStackTrace = stackTrace;
                    }
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _appSettings = _appSettings.copyWith(
                        setupCompleted: true,
                      );
                    });
                    if (!dialogContext.mounted) {
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    if (saveError != null) {
                      developer.log(
                        'Failed to persist initial setup skip',
                        name: 'MoreBetterGakujo',
                        error: saveError,
                        stackTrace: saveStackTrace,
                      );
                      messenger.showSnackBar(
                        const SnackBar(
                          content:
                              Text('初回セットアップ状態を保存できませんでした。キーチェーン設定を確認してください。'),
                        ),
                      );
                    }
                  },
                  child: const Text('あとで'),
                ),
                FilledButton(
                  onPressed: () => unawaited(complete()),
                  child: const Text('完了'),
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

  Future<void> _compactStoredData() async {
    try {
      await Future.wait([
        _downloadHistoryStore.compact(),
        _activityStore.compact(),
      ]);
      await _refreshActivityCounts();
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to compact stored data',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _checkDownloadDestinationHealth() async {
    try {
      final root = await _downloadService.getDownloadRoot();
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadRoot = root;
      });
      final needsRoot = _appSettings.downloadSaveMode.needsConfiguredRoot;
      if (!needsRoot) {
        _showSnackBar('現在の保存方式では固定保存先は不要です');
      } else if (root.isConfigured) {
        _showSnackBar('保存先は利用できます: ${root.displayName ?? root.path ?? '設定済み'}');
      } else {
        _showSnackBar('保存先を再設定してください');
      }
    } on PlatformException catch (error) {
      _showSnackBar('保存先を確認できませんでした: ${error.message ?? error.code}');
    }
  }

  Future<void> _showDownloadHistoryDialog() async {
    var entries = await _downloadHistoryStore.load();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('ダウンロード履歴'),
              content: SizedBox(
                width: 520,
                child: entries.isEmpty
                    ? const Text('まだ保存したファイルはありません。')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return ListTile(
                            dense: true,
                            title: Text(entry.fileName),
                            subtitle: Text(
                              '${entry.displayCourseName}\n'
                              '${_formatDateTime(entry.savedAt)}'
                              '${entry.location == null ? '' : '\n${entry.location}'}',
                            ),
                            isThreeLine: entry.location != null,
                            trailing: entry.location == null
                                ? null
                                : IconButton(
                                    tooltip: '保存場所をコピー',
                                    icon: const Icon(Icons.copy),
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: entry.location!),
                                      );
                                      Navigator.of(dialogContext).pop();
                                      _showSnackBar('保存場所をコピーしました');
                                    },
                                  ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: entries.isEmpty
                      ? null
                      : () async {
                          await _downloadHistoryStore.clear();
                          entries = const [];
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {});
                        },
                  child: const Text('履歴を削除'),
                ),
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

  Future<void> _showFailedDownloadsDialog() async {
    var entries = await _downloadHistoryStore.loadFailedDownloads();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('失敗したダウンロード'),
              content: SizedBox(
                width: 560,
                child: entries.isEmpty
                    ? const Text('再試行待ちのダウンロードはありません。')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              entry.request.fileName.trim().isEmpty
                                  ? _displayUrl(entry.request.url)
                                  : entry.request.fileName,
                            ),
                            subtitle: Text(
                              '${entry.request.courseName.trim().isEmpty ? '未分類' : entry.request.courseName}\n'
                              '${_formatDateTime(entry.failedAt)}\n'
                              '${entry.errorMessage}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              tooltip: '再試行',
                              icon: const Icon(Icons.refresh),
                              onPressed: () async {
                                Navigator.of(dialogContext).pop();
                                await _handleDownloadRequest(
                                  entry.request,
                                  retryEntryId: entry.id,
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: entries.isEmpty
                      ? null
                      : () async {
                          await _downloadHistoryStore.clearFailedDownloads();
                          entries = const [];
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {});
                        },
                  child: const Text('キューを削除'),
                ),
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

  Future<void> _showCourseMaterialsDialog() async {
    final entries = await _downloadHistoryStore.load();
    if (!mounted) {
      return;
    }

    final grouped = <String, List<GakujoDownloadHistoryEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.displayCourseName, () => []).add(entry);
    }
    final courses = grouped.keys.toList()..sort();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('授業ごとの資料'),
          content: SizedBox(
            width: 560,
            child: courses.isEmpty
                ? const Text('ダウンロード履歴から授業ごとの資料一覧を作ります。')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: courses.length,
                    itemBuilder: (context, index) {
                      final course = courses[index];
                      final files = grouped[course]!;
                      return ExpansionTile(
                        title: Text(course),
                        subtitle: Text('${files.length}件'),
                        children: [
                          for (final file in files)
                            ListTile(
                              dense: true,
                              title: Text(file.fileName),
                              subtitle: Text(_formatDateTime(file.savedAt)),
                              trailing: file.location == null
                                  ? null
                                  : IconButton(
                                      tooltip: '保存場所をコピー',
                                      icon: const Icon(Icons.copy),
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(text: file.location!),
                                        );
                                        Navigator.of(dialogContext).pop();
                                        _showSnackBar('保存場所をコピーしました');
                                      },
                                    ),
                            ),
                        ],
                      );
                    },
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
  }

  Future<void> _showCachedReportsDialog() async {
    final reportLists = await _activityStore.loadReportLists();
    if (!mounted) {
      return;
    }

    final sorted = [...reportLists]
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('保存済み課題一覧'),
          content: SizedBox(
            width: 620,
            child: sorted.isEmpty
                ? const Text('レポート・小テスト画面を開くと、課題一覧を保存します。')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final reportList = sorted[index];
                      return ExpansionTile(
                        title: Text(reportList.title),
                        subtitle: Text(_formatDateTime(reportList.capturedAt)),
                        children: [
                          for (final item in reportList.items)
                            ListTile(
                              dense: true,
                              title: Text(item),
                            ),
                          OverflowBar(
                            alignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  unawaited(
                                    _loadAllowedPageUrl(reportList.url),
                                  );
                                },
                                icon: const Icon(Icons.open_in_browser),
                                label: const Text('開く'),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: sorted.isEmpty
                  ? null
                  : () async {
                      await _activityStore.clearReportLists();
                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                        _showSnackBar('保存済み課題一覧を削除しました');
                      }
                    },
              child: const Text('削除'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showChangeHistoryDialog() async {
    final changes = await _activityStore.loadChanges();
    if (!mounted) {
      return;
    }

    final sorted = [...changes]
      ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('変更履歴'),
          content: SizedBox(
            width: 560,
            child: sorted.isEmpty
                ? const Text('まだ変更履歴はありません。')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final change = sorted[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.history),
                        title: Text(change.category),
                        subtitle: Text(
                          '${change.title}\n${_formatDateTime(change.changedAt)}',
                        ),
                        isThreeLine: true,
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          unawaited(_loadAllowedPageUrl(change.url));
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: sorted.isEmpty
                  ? null
                  : () async {
                      await _activityStore.clearChanges();
                      if (mounted) {
                        Navigator.of(dialogContext).pop();
                        _showSnackBar('変更履歴を削除しました');
                      }
                    },
              child: const Text('削除'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showActivityDialog() async {
    var deadlines = await _activityStore.loadDeadlines();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var isScanning = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final datedItems = [...deadlines]
              ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

            Future<void> rescan() async {
              if (isScanning) {
                return;
              }
              setDialogState(() {
                isScanning = true;
              });
              String message;
              try {
                final result = await _rescanActivityForBell();
                deadlines = await _activityStore.loadDeadlines();
                await _refreshActivityCounts();
                message = result == null
                    ? 'このページでは再検出できませんでした'
                    : '再検出しました: ${result.deadlineCount}件';
              } on Object catch (error, stackTrace) {
                developer.log(
                  'Failed to rescan activity from dialog',
                  name: 'MoreBetterGakujo',
                  error: error,
                  stackTrace: stackTrace,
                );
                message = '再検出に失敗しました';
              }
              if (!mounted || !dialogContext.mounted) {
                return;
              }
              setDialogState(() {
                isScanning = false;
              });
              _showSnackBar(message);
            }

            return AlertDialog(
              title: const Text('新着情報・期限・予定'),
              content: SizedBox(
                width: 560,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      '新着情報・期限・予定',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (datedItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('表示する新着情報・期限・予定はありません。'),
                      )
                    else
                      for (final item in datedItems)
                        ListTile(
                          dense: true,
                          leading: Icon(_datedActivityIcon(item.kind)),
                          title: Text(item.title),
                          subtitle: _datedActivitySubtitle(item),
                          isThreeLine: true,
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            unawaited(_openDatedActivityEntry(item));
                          },
                        ),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: isScanning ? null : () => unawaited(rescan()),
                  icon: isScanning
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(isScanning ? '再検出中' : '再検出'),
                ),
                TextButton(
                  onPressed: () async {
                    await Future.wait([
                      _activityStore.markSnapshotsSeen(),
                      _activityStore.clearDeadlines(),
                    ]);
                    if (!mounted) {
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    await _refreshActivityCounts();
                  },
                  child: const Text('すべて確認済みにする'),
                ),
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

  IconData _datedActivityIcon(String kind) {
    switch (kind) {
      case 'deadline':
        return Icons.event_note;
      case 'schedule':
        return Icons.event_available_outlined;
      case 'notice':
        return Icons.campaign_outlined;
      default:
        return Icons.info_outline;
    }
  }

  String _datedActivityKindLabel(String kind) {
    switch (kind) {
      case 'deadline':
        return '期限';
      case 'schedule':
        return '予定';
      case 'notice':
        return '新着情報';
      default:
        return '情報';
    }
  }

  Widget _datedActivitySubtitle(GakujoDeadlineEntry item) {
    return Text(
      '${_datedActivityKindLabel(item.kind)}\n${item.dueText}',
    );
  }

  Future<void> _openDatedActivityEntry(GakujoDeadlineEntry entry) async {
    await _loadAllowedPageUrl(entry.url);
    if (entry.isDeadline) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (entry.title.trim().isNotEmpty) {
      await _quickJumpTo(entry.title);
    }
  }

  Future<void> _showDataManagementDialog() async {
    final history = await _downloadHistoryStore.load();
    final failedDownloads = await _downloadHistoryStore.loadFailedDownloads();
    final favorites = await _activityStore.loadFavorites();
    final deadlines = await _activityStore.loadDeadlines();
    final changes = await _activityStore.loadChanges();
    final reportLists = await _activityStore.loadReportLists();
    if (!mounted) {
      return;
    }

    Future<void> clearAll() async {
      await Future.wait([
        _downloadHistoryStore.clear(),
        _downloadHistoryStore.clearFailedDownloads(),
        _activityStore.clearSnapshots(),
        _activityStore.clearDeadlines(),
        _activityStore.clearChanges(),
        _activityStore.clearReportLists(),
        _activityStore.replaceFavorites(const []),
      ]);
      await _refreshActivityCounts();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('データ管理'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [
                _DataCountTile(label: 'ダウンロード履歴', count: history.length),
                _DataCountTile(
                    label: '失敗したダウンロード', count: failedDownloads.length),
                _DataCountTile(label: 'お気に入り', count: favorites.length),
                _DataCountTile(label: '新着情報・期限・予定', count: deadlines.length),
                _DataCountTile(label: '変更履歴', count: changes.length),
                _DataCountTile(label: '保存済み課題一覧', count: reportLists.length),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await clearAll();
                if (mounted) {
                  Navigator.of(dialogContext).pop();
                  _showSnackBar('保存データを削除しました');
                }
              },
              child: const Text('全て削除'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkForUpdates() async {
    _setStatus('更新を確認しています');
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final info = await _updateService.checkLatestRelease(
        currentVersion: packageInfo.version,
      );
      if (!mounted) {
        return;
      }
      if (!info.hasUpdate) {
        _showSnackBar('最新版です: ${info.currentVersion}');
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('新しいバージョンがあります: ${info.latestVersion}'),
          action: SnackBarAction(
            label: '開く',
            onPressed: () => unawaited(
              launchUrl(
                Uri.parse(info.releaseUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        ),
      );
    } on Object catch (error) {
      _showSnackBar('更新を確認できませんでした: $error');
    }
  }

  Future<void> _createManualBackup() async {
    try {
      final file = await _writeBackupFile(prefix: 'manual');
      _showSnackBar('バックアップを作成しました: ${file.path}');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to write manual backup',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnackBar('バックアップを作成できませんでした: $error');
    }
  }

  Future<void> _createErrorReportPackage() async {
    final includeStoredData = await _confirmDetailedErrorReport();
    if (includeStoredData == null) {
      return;
    }
    try {
      final payload = await _diagnosticPayload(
        includeStoredData: includeStoredData,
      );
      final file = await _writeJsonFile(
        directoryName: 'MoreBetterGakujoReports',
        fileName: 'error-report-${DateTime.now().microsecondsSinceEpoch}.json',
        payload: payload,
      );
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(payload),
        ),
      );
      _showSnackBar('エラー報告パッケージを作成してコピーしました: ${file.path}');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to create error report package',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnackBar('エラー報告パッケージを作成できませんでした: $error');
    }
  }

  Future<bool?> _confirmDetailedErrorReport() {
    if (!mounted) {
      return Future.value(null);
    }
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('エラー報告パッケージ'),
          content: const Text(
            '軽量版は件数と設定状態だけを含みます。詳細版は履歴、URL、失敗ダウンロード、課題キャッシュも含みます。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('軽量版'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('詳細版'),
            ),
          ],
        );
      },
    );
  }

  void _scheduleAutoBackup() {
    _autoBackupTimer?.cancel();
    if (!_appSettings.isFeatureEnabled(GakujoFeatureFlag.autoBackup)) {
      return;
    }
    _autoBackupTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(_writeAutomaticBackup()),
    );
    unawaited(_writeAutomaticBackup());
  }

  Future<File?> _writeAutomaticBackup() async {
    try {
      return await _writeBackupFile(prefix: 'auto');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to write automatic backup',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<File> _writeBackupFile({required String prefix}) async {
    return _writeJsonFile(
      directoryName: 'MoreBetterGakujoBackups',
      fileName: '$prefix-backup-${DateTime.now().microsecondsSinceEpoch}.json',
      payload: await _backupPayload(),
    );
  }

  Future<File> _writeJsonFile({
    required String directoryName,
    required String fileName,
    required Map<String, Object?> payload,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(_joinLocalPath(documents.path, directoryName));
    await directory.create(recursive: true);
    final file = File(_joinLocalPath(directory.path, fileName));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    await _pruneJsonFiles(directory, keep: 10);
    return file;
  }

  Future<void> _pruneJsonFiles(Directory directory, {required int keep}) async {
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final file in files.skip(keep)) {
      try {
        await file.delete();
      } on FileSystemException {
        // Best-effort cleanup only.
      }
    }
  }

  String _joinLocalPath(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) {
      return '$parent$child';
    }
    return '$parent${Platform.pathSeparator}$child';
  }

  Future<void> _showFavoritesDialog() async {
    var favorites = await _activityStore.loadFavorites();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('お気に入り'),
              content: SizedBox(
                width: 520,
                child: favorites.isEmpty
                    ? const Text('ページ操作から現在のページを追加できます。')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: favorites.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final favorite = favorites[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.star),
                            title: Text(favorite.title),
                            subtitle: Text(favorite.url),
                            trailing: IconButton(
                              tooltip: '削除',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await _activityStore.removeFavorite(
                                  favorite.url,
                                );
                                favorites =
                                    await _activityStore.loadFavorites();
                                if (!dialogContext.mounted) {
                                  return;
                                }
                                setDialogState(() {});
                              },
                            ),
                            onTap: () {
                              Navigator.of(dialogContext).pop();
                              unawaited(_loadAllowedPageUrl(favorite.url));
                            },
                          );
                        },
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

  Future<void> _handleToolbarAction(_ToolbarAction action) async {
    switch (action) {
      case _ToolbarAction.reload:
        await _controller.reload();
        return;
      case _ToolbarAction.addFavorite:
      case _ToolbarAction.copyUrl:
      case _ToolbarAction.openExternal:
        break;
    }

    final url = await _currentActionableUrl();
    if (url == null) {
      _showSnackBar('現在のページURLを取得できませんでした');
      return;
    }

    switch (action) {
      case _ToolbarAction.addFavorite:
        final title = await _controller.getTitle();
        await _activityStore.addFavorite(
          GakujoFavoritePage(
            title: _favoriteTitle(title, url),
            url: url,
            addedAt: DateTime.now(),
          ),
        );
        _showSnackBar('お気に入りに追加しました');
        return;
      case _ToolbarAction.copyUrl:
        await Clipboard.setData(ClipboardData(text: url));
        _showSnackBar('URLをコピーしました');
        return;
      case _ToolbarAction.openExternal:
        final launched = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          _showSnackBar('外部ブラウザで開けませんでした');
        }
        return;
      case _ToolbarAction.reload:
        return;
    }
  }

  Future<String?> _currentActionableUrl() async {
    final currentUrl = await _controller.currentUrl();
    if (AllowedWebOrigins.canNavigate(
      currentUrl,
      debugAllowed: _debugAllowed,
    )) {
      return currentUrl;
    }
    if (!AllowedWebOrigins.canNavigate(
      _currentPageUrl,
      debugAllowed: _debugAllowed,
    )) {
      return null;
    }
    return _currentPageUrl;
  }

  Future<void> _exportCurrentScheduleToCalendar({
    GakujoCalendarImportSettings? importSettings,
  }) async {
    // #region DEBUG
    _appendCalendarDebugLog('[DEBUG H0] exportCurrentSchedule enter');
    // #endregion DEBUG
    if (!_canRunPageScripts) {
      // #region DEBUG
      _appendCalendarDebugLog('[DEBUG H0] exportCurrentSchedule noPageScripts');
      // #endregion DEBUG
      _showSnackBar('スケジュールページを読み込んでから使ってください');
      return;
    }

    final rawSettings = importSettings ?? _appSettings.calendarImportSettings;
    final settings = _effectiveCalendarImportSettings(rawSettings);
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H0] exportCurrentSchedule method=${settings.method.name} '
      'rawMethod=${rawSettings.method.name} '
      'termSource=${settings.termSource.name} '
      'termTarget=${settings.termTarget.name} '
      'directSupported=${_calendarService.supportsDirectSync}',
    );
    // #endregion DEBUG
    if (settings.method == GakujoCalendarImportMethod.officialGoogle) {
      await _ensureSchedulePageForCalendarImport();
      await _openOfficialGoogleScheduleIntegration(
        showMissingMessage: true,
        successMessage: '本家Googleスケジュール連携を開きました',
      );
      return;
    }

    List<GakujoCalendarCourse>? fallbackCourses;
    GakujoCalendarTermRange? fallbackTermRange;
    String? fallbackUidNamespace;
    String? fallbackTermLabel;

    try {
      final preferredTerm = settings.termSource ==
              GakujoCalendarTermSource.officialAcademicCalendar
          ? await _resolveCalendarTerm(settings: settings)
          : null;
      final extraction = await _readCalendarScheduleForImport(
        preferredTermRange: preferredTerm?.termRange,
      );
      final extractedCourses = extraction.courses;
      if (extractedCourses.isEmpty) {
        _showSnackBar('本家Google連携から取り込める授業が見つかりませんでした。スケジュールページで再実行してください');
        return;
      }

      final resolvedTerm = preferredTerm ??
          await _resolveCalendarTerm(
            extraction: extraction,
            settings: settings,
          );
      if (resolvedTerm == null) {
        return;
      }
      final termRange = resolvedTerm.termRange;
      final uidNamespace = resolvedTerm.uidNamespace;
      final termLabel = resolvedTerm.label;
      final coursesWithResolvedAmbiguousTerms =
          await _resolveAmbiguousCalendarCourseTerms(
        extractedCourses,
        selectedTermName: resolvedTerm.termName,
      );
      if (coursesWithResolvedAmbiguousTerms == null) {
        return;
      }
      final courses = GakujoCalendarExport.filterCoursesForTerm(
        courses: coursesWithResolvedAmbiguousTerms,
        termRange: termRange,
        termName: resolvedTerm.termName ?? '',
      );
      // #region DEBUG
      _appendCalendarDebugLog(
        '[DEBUG H10] termFilter term=${resolvedTerm.termName ?? termLabel} '
        'before=${extractedCourses.length} after=${courses.length}',
      );
      // #endregion DEBUG
      if (courses.isEmpty) {
        _showSnackBar(
            '${resolvedTerm.termName ?? '選択した期間'}に追加できる授業が見つかりませんでした');
        return;
      }
      fallbackCourses = courses;
      fallbackTermRange = termRange;
      fallbackUidNamespace = uidNamespace;
      fallbackTermLabel = termLabel;
      final shouldUseDirect =
          settings.method == GakujoCalendarImportMethod.deviceCalendar ||
              (settings.method == GakujoCalendarImportMethod.automatic &&
                  _calendarService.supportsDirectSync);
      if (shouldUseDirect && _calendarService.supportsDirectSync) {
        final events = GakujoCalendarEventBuilder.buildEvents(
          courses: courses,
          rangeStart: termRange.start,
          rangeEnd: termRange.end,
          noClassDates: termRange.noClassDates,
          uidNamespace: uidNamespace,
          termLabel: termLabel,
        );
        final result = await _calendarService.syncEvents(
          events: events,
          rangeStart: termRange.start,
          rangeEnd: termRange.end,
          calendarTitle: settings.effectiveCalendarTitle,
        );
        _showSnackBar(_calendarSyncMessage(result, resolvedTerm.termName));
        return;
      }
      if (settings.method == GakujoCalendarImportMethod.icsFile ||
          settings.method == GakujoCalendarImportMethod.deviceCalendar) {
        await _writeCalendarFallbackFile(
          courses: courses,
          termRange: termRange,
          uidNamespace: uidNamespace,
          termLabel: termLabel,
          reason: settings.method == GakujoCalendarImportMethod.deviceCalendar
              ? 'この環境ではOSカレンダー直接追加に未対応のため'
              : null,
        );
        return;
      }
      final openedOfficial = await _openOfficialGoogleScheduleIntegration(
        showMissingMessage: false,
        successMessage: 'この環境ではOSカレンダー直接追加に未対応のため、本家Googleスケジュール連携を開きました',
      );
      if (openedOfficial) {
        return;
      }
      await _writeCalendarFallbackFile(
        courses: courses,
        termRange: termRange,
        uidNamespace: uidNamespace,
        termLabel: termLabel,
        reason: null,
      );
    } on PlatformException catch (error) {
      if (isCancelledDownloadError(error)) {
        return;
      }
      if (_calendarService.supportsDirectSync &&
          (error.code == 'calendar_permission_denied' ||
              error.code == 'calendar_sync_failed')) {
        developer.log(
          'Falling back to iCalendar file after direct calendar sync failed',
          name: 'MoreBetterGakujo',
          error: error,
        );
        final courses = fallbackCourses;
        final termRange = fallbackTermRange;
        final uidNamespace = fallbackUidNamespace;
        final termLabel = fallbackTermLabel;
        if (termRange == null ||
            courses == null ||
            courses.isEmpty ||
            uidNamespace == null ||
            termLabel == null) {
          _showSnackBar('OSカレンダーに追加できませんでした: ${error.message ?? error.code}');
          return;
        }
        final reason = error.code == 'calendar_permission_denied'
            ? 'カレンダーへのアクセスが許可されていないため'
                '（システム設定＞プライバシーとセキュリティ＞カレンダーで許可できます）'
            : 'OSカレンダーに追加できなかったため';
        // The fallback runs inside this catch block, so its own exceptions
        // (notably the user cancelling the save dialog) would otherwise escape
        // unhandled. Swallow cancellation and report only real failures.
        try {
          await _writeCalendarFallbackFile(
            courses: courses,
            termRange: termRange,
            uidNamespace: uidNamespace,
            termLabel: termLabel,
            reason: reason,
          );
        } on PlatformException catch (fallbackError) {
          if (!isCancelledDownloadError(fallbackError)) {
            _showSnackBar('カレンダー用ファイルを作成できませんでした: '
                '${fallbackError.message ?? fallbackError.code}');
          }
        }
        return;
      }
      developer.log(
        'Failed to export calendar file',
        name: 'MoreBetterGakujo',
        error: error,
      );
      _showSnackBar('カレンダー用ファイルを作成できませんでした: ${error.message ?? error.code}');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to export calendar file',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnackBar('カレンダー用ファイルを作成できませんでした: $error');
    }
  }

  GakujoCalendarImportSettings _effectiveCalendarImportSettings(
    GakujoCalendarImportSettings settings,
  ) {
    if (!_calendarService.supportsDirectSync &&
        settings.method == GakujoCalendarImportMethod.deviceCalendar) {
      return settings.copyWith(method: GakujoCalendarImportMethod.icsFile);
    }
    if (_calendarService.supportsDirectSync &&
        settings.method == GakujoCalendarImportMethod.officialGoogle) {
      return settings.copyWith(
          method: GakujoCalendarImportMethod.deviceCalendar);
    }
    return settings;
  }

  List<GakujoCalendarImportMethod> _calendarImportMethodChoices() {
    if (!_calendarService.supportsDirectSync) {
      return GakujoCalendarImportMethod.values
          .where(
              (method) => method != GakujoCalendarImportMethod.deviceCalendar)
          .toList(growable: false);
    }
    return GakujoCalendarImportMethod.values
        .where((method) => method != GakujoCalendarImportMethod.officialGoogle)
        .toList(growable: false);
  }

  Future<_ResolvedCalendarTerm?> _resolveCalendarTerm({
    required GakujoCalendarImportSettings settings,
    GakujoCalendarExtraction? extraction,
    String manualTitle = 'ターム期間を入力',
    String manualDescription = 'ページからターム期間を読み取れませんでした。書き出す授業期間を入力してください。',
    String manualActionLabel = '書き出し',
  }) async {
    if (settings.termSource ==
        GakujoCalendarTermSource.officialAcademicCalendar) {
      final officialTerm = await _officialAcademicTermFor(
        DateTime.now(),
        target: settings.termTarget,
      );
      if (officialTerm != null) {
        final termRange = _calendarTermRangeForOfficial(
          officialTerm,
          includeNoClassDates: settings.includeNoClassDates,
        );
        return _ResolvedCalendarTerm(
          termRange: termRange,
          uidNamespace:
              'niigata-${officialTerm.academicYear}-${officialTerm.name}',
          label: '${officialTerm.academicYear}年度 ${officialTerm.name}',
          termName: officialTerm.name,
        );
      }
    }

    final pageRange = extraction?.termRange;
    final termRange = pageRange ??
        await _askCalendarTermRange(
          title: manualTitle,
          description: manualDescription,
          actionLabel: manualActionLabel,
        );
    if (termRange == null) {
      return null;
    }
    final effectiveRange = settings.includeNoClassDates
        ? termRange
        : GakujoCalendarTermRange(
            start: termRange.start,
            end: termRange.end,
            sourceText: termRange.sourceText,
          );
    return _ResolvedCalendarTerm(
      termRange: effectiveRange,
      uidNamespace:
          'manual-${_dateFileStamp(termRange.start)}-${_dateFileStamp(termRange.end)}',
      label: _calendarRangeLabel(termRange),
      termName: null,
    );
  }

  GakujoCalendarTermRange _calendarTermRangeForOfficial(
    GakujoAcademicTerm officialTerm, {
    required bool includeNoClassDates,
  }) {
    return GakujoCalendarTermRange(
      start: officialTerm.start,
      end: officialTerm.end,
      sourceText:
          '${officialTerm.academicYear}年度 ${officialTerm.name} 公式授業暦 ${officialTerm.sourceUrl}',
      noClassDates: includeNoClassDates ? officialTerm.noClassDates : const [],
    );
  }

  Future<List<GakujoCalendarCourse>?> _resolveAmbiguousCalendarCourseTerms(
    List<GakujoCalendarCourse> courses, {
    required String? selectedTermName,
  }) async {
    final uniqueAmbiguous = <String, GakujoCalendarCourse>{};
    for (final course in courses) {
      if (GakujoCalendarExport.hasAmbiguousTermCode(course)) {
        uniqueAmbiguous.putIfAbsent(
          GakujoCalendarExport.courseIdentityKey(course),
          () => course,
        );
      }
    }
    if (uniqueAmbiguous.isEmpty) {
      return courses;
    }

    final selections = await _askAmbiguousCalendarCourseTerms(
      uniqueAmbiguous.values.toList(growable: false),
      selectedTermName: selectedTermName,
    );
    if (selections == null) {
      return null;
    }
    if (selections.isEmpty) {
      return courses;
    }

    return [
      for (final course in courses)
        if (GakujoCalendarExport.hasAmbiguousTermCode(course))
          course.copyWith(
            termHint: [
              course.termHint,
              ...?selections[GakujoCalendarExport.courseIdentityKey(course)]
                  ?.map(_calendarTermNameForCode),
            ].where((value) => value.trim().isNotEmpty).join(' '),
          )
        else
          course,
    ];
  }

  Future<Map<String, Set<int>>?> _askAmbiguousCalendarCourseTerms(
    List<GakujoCalendarCourse> courses, {
    required String? selectedTermName,
  }) {
    if (!mounted) {
      return Future<Map<String, Set<int>>?>.value(null);
    }
    final initialTermCode = selectedTermName == null
        ? null
        : _calendarTermCodeFromName(selectedTermName);
    final selections = <String, Set<int>>{
      for (final course in courses)
        GakujoCalendarExport.courseIdentityKey(course): <int>{
          if (initialTermCode != null) initialTermCode,
        },
    };
    return showDialog<Map<String, Set<int>>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('期間不明の授業を確認'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '開講番号の3桁目が0の授業は、実施タームを判定できません。追加するタームを選んでください。',
                      ),
                      const SizedBox(height: 12),
                      for (final course in courses) ...[
                        _AmbiguousCalendarCourseTermSelector(
                          course: course,
                          selectedTerms:
                              selections[GakujoCalendarExport.courseIdentityKey(
                                    course,
                                  )] ??
                                  <int>{},
                          onChanged: (term, selected) {
                            final key =
                                GakujoCalendarExport.courseIdentityKey(course);
                            final next = {
                              ...(selections[key] ?? <int>{}),
                            };
                            if (selected) {
                              next.add(term);
                            } else {
                              next.remove(term);
                            }
                            selections[key] = next;
                            setDialogState(() {});
                          },
                        ),
                        const Divider(height: 20),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop({}),
                  child: const Text('すべてスキップ'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(
                    selections.map(
                      (key, value) => MapEntry(key, Set<int>.of(value)),
                    ),
                  ),
                  child: const Text('適用'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  int? _calendarTermCodeFromName(String termName) {
    final match = RegExp(r'第([1-4])ターム').firstMatch(
      termName
          .replaceAll('１', '1')
          .replaceAll('２', '2')
          .replaceAll('３', '3')
          .replaceAll('４', '4')
          .replaceAll(RegExp(r'\s+'), ''),
    );
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  String _calendarTermNameForCode(int term) {
    return '第$termターム';
  }

  Future<void> _showScheduleIntegrationDialog() async {
    final initialSettings = _effectiveCalendarImportSettings(
      _appSettings.calendarImportSettings,
    );
    final calendarTitleController = TextEditingController(
      text: initialSettings.effectiveCalendarTitle,
    );
    try {
      var selectedSettings = initialSettings;
      final result = await showDialog<_ScheduleIntegrationDialogResult>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              GakujoCalendarImportSettings currentSettings() {
                return selectedSettings.copyWith(
                  calendarTitle: calendarTitleController.text,
                );
              }

              void popWith(_ScheduleIntegrationAction action) {
                Navigator.of(dialogContext).pop(
                  _ScheduleIntegrationDialogResult(
                    action: action,
                    settings: currentSettings(),
                  ),
                );
              }

              return AlertDialog(
                title: const Text('Googleスケジュール連携'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '追加する授業予定は学務のGoogle連携から取れたものだけを使い、ターム期間と授業なしの日はMore Better Gakujo側で判定します。',
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<GakujoCalendarImportMethod>(
                        initialValue: selectedSettings.method,
                        decoration: const InputDecoration(
                          labelText: '取り込み方法',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final method in _calendarImportMethodChoices())
                            DropdownMenuItem(
                              value: method,
                              child: Text(method.label),
                            ),
                        ],
                        onChanged: (method) {
                          if (method == null) {
                            return;
                          }
                          selectedSettings = selectedSettings.copyWith(
                            method: method,
                          );
                          setDialogState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<GakujoCalendarTermSource>(
                        initialValue: selectedSettings.termSource,
                        decoration: const InputDecoration(
                          labelText: 'ターム期間の決め方',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final source in GakujoCalendarTermSource.values)
                            DropdownMenuItem(
                              value: source,
                              child: Text(source.label),
                            ),
                        ],
                        onChanged: (source) {
                          if (source == null) {
                            return;
                          }
                          selectedSettings = selectedSettings.copyWith(
                            termSource: source,
                          );
                          setDialogState(() {});
                        },
                      ),
                      if (selectedSettings.termSource ==
                          GakujoCalendarTermSource
                              .officialAcademicCalendar) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<GakujoCalendarTermTarget>(
                          initialValue: selectedSettings.termTarget,
                          decoration: const InputDecoration(
                            labelText: '追加するターム',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final target
                                in GakujoCalendarTermTarget.values)
                              DropdownMenuItem(
                                value: target,
                                child: Text(target.label),
                              ),
                          ],
                          onChanged: (target) {
                            if (target == null) {
                              return;
                            }
                            selectedSettings = selectedSettings.copyWith(
                              termTarget: target,
                            );
                            setDialogState(() {});
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('授業なしの日を除外する'),
                        subtitle: const Text('公式授業暦から取得できた休講日を予定生成から外します。'),
                        value: selectedSettings.includeNoClassDates,
                        onChanged: (value) {
                          selectedSettings = selectedSettings.copyWith(
                            includeNoClassDates: value ?? true,
                          );
                          setDialogState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: calendarTitleController,
                        decoration: const InputDecoration(
                          labelText: '追加先カレンダー名',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      if (selectedSettings.method ==
                          GakujoCalendarImportMethod.officialGoogle) ...[
                        const SizedBox(height: 8),
                        Text(
                          '本家Google連携を開く場合、日付範囲は学務側の動作に従います。ターム自動判定を使う場合は「自動で選ぶ」か「OSカレンダーへ直接追加」を使ってください。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (!_calendarService.supportsDirectSync) ...[
                        const SizedBox(height: 8),
                        Text(
                          'WindowsではOSカレンダーへ直接書き込めないため、iCalendarファイルを書き出して既定のカレンダーアプリで開きます。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('閉じる'),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        popWith(_ScheduleIntegrationAction.validation),
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('検証'),
                  ),
                  TextButton.icon(
                    onPressed: () => popWith(
                      _ScheduleIntegrationAction.deleteDeviceCalendar,
                    ),
                    icon: const Icon(Icons.event_busy_outlined),
                    label: const Text('追加済みを削除'),
                  ),
                  FilledButton.icon(
                    onPressed: () =>
                        popWith(_ScheduleIntegrationAction.syncCalendar),
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('適用'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (result == null) {
        return;
      }
      await _saveCalendarImportSettings(result.settings);
      // #region DEBUG
      _appendCalendarDebugLog(
        '[DEBUG H0] scheduleDialogResult action=${result.action.name} '
        'method=${result.settings.method.name} '
        'termSource=${result.settings.termSource.name} '
        'termTarget=${result.settings.termTarget.name} '
        'directSupported=${_calendarService.supportsDirectSync}',
      );
      // #endregion DEBUG
      switch (result.action) {
        case _ScheduleIntegrationAction.syncCalendar:
          await _exportCurrentScheduleToCalendar(
            importSettings: result.settings,
          );
          return;
        case _ScheduleIntegrationAction.deleteDeviceCalendar:
          await _deleteAddedCalendarEvents(
            importSettings: result.settings,
          );
          return;
        case _ScheduleIntegrationAction.validation:
          await _showCalendarValidationDialog();
          return;
      }
    } finally {
      calendarTitleController.dispose();
    }
  }

  Future<void> _saveCalendarImportSettings(
    GakujoCalendarImportSettings settings,
  ) async {
    await _appSettingsStore.saveCalendarImportSettings(settings);
    if (!mounted) {
      return;
    }
    setState(() {
      _appSettings = _appSettings.copyWith(
        calendarImportSettings: settings,
      );
    });
  }

  Future<void> _saveMessageExcludeKeywords(List<String> keywords) async {
    final normalized = normalizeMessageExcludeKeywords(keywords);
    await _appSettingsStore.saveMessageExcludeKeywords(normalized);
    if (!mounted) {
      return;
    }
    setState(() {
      _appSettings = _appSettings.copyWith(
        messageExcludeKeywords: normalized,
      );
    });
    await _injectMessageFilterIfAllowed();
  }

  Future<_OfficialGoogleScheduleIntegration>
      _runOfficialGoogleScheduleIntegrationScript({
    required bool activate,
  }) async {
    final result = await _controller.runJavaScriptReturningResult(
      GakujoCalendarExport.officialGoogleScheduleIntegrationScript(
        activate: activate,
      ),
    );
    return _OfficialGoogleScheduleIntegration.fromJson(
      _stringFromJavaScriptResult(result),
    );
  }

  Future<_OfficialGoogleScheduleIntegration>
      _runOfficialScheduleExportExecutionScript({
    required bool activate,
    GakujoCalendarTermRange? termRange,
  }) async {
    final result = await _controller.runJavaScriptReturningResult(
      GakujoCalendarExport.officialScheduleExportExecutionScript(
        activate: activate,
        startDate: termRange == null ? '' : _formatDate(termRange.start),
        endDate: termRange == null ? '' : _formatDate(termRange.end),
      ),
    );
    return _OfficialGoogleScheduleIntegration.fromJson(
      _stringFromJavaScriptResult(result),
    );
  }

  Future<_OfficialScheduleExportFetch> _runOfficialScheduleExportFetchScript({
    GakujoCalendarTermRange? termRange,
  }) async {
    final result = await _controller.runJavaScriptReturningResult(
      GakujoCalendarExport.officialScheduleExportFetchScript(
        startDate: termRange == null ? '' : _formatDate(termRange.start),
        endDate: termRange == null ? '' : _formatDate(termRange.end),
      ),
    );
    return _OfficialScheduleExportFetch.fromJson(
      _stringFromJavaScriptResult(result),
    );
  }

  // #region DEBUG
  void _appendCalendarDebugLog(String message) {
    final line = '${DateTime.now().toIso8601String()} $message\n';
    const paths = [
      '/Users/yoshidateruhiko/devthings/morebettergakujo_android/morebettergakujo-flutter/.claude/debug.log',
      '/Users/yoshidateruhiko/Library/Containers/net.yoshida.morebettergakujoFlutter/Data/Library/Application Support/MoreBetterGakujo/debug.log',
      '/Users/yoshidateruhiko/Library/Containers/net.yoshida.morebettergakujoFlutter/Data/tmp/morebettergakujo-debug.log',
      '/tmp/.claude/debug.log',
    ];
    for (final path in paths) {
      try {
        final file = File(path);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(line, mode: FileMode.append, flush: true);
      } on Object {
        // Best-effort debug file logging. Unified logging below still records it.
      }
    }
    developer.log(message, name: 'MoreBetterGakujo');
  }

  String _calendarDebugUrl(String? rawUrl) {
    final uri = Uri.tryParse(rawUrl ?? '');
    if (uri == null) {
      return 'invalid';
    }
    final queryKeys = uri.queryParametersAll.keys.toList()..sort();
    return '${uri.scheme}://${uri.host}${uri.path}'
        ' keys=${queryKeys.join(',')} length=${rawUrl?.length ?? 0}';
  }

  String _calendarDebugIntegration(
    _OfficialGoogleScheduleIntegration integration,
  ) {
    return 'status=${integration.status} '
        'url=${_calendarDebugUrl(integration.url)} '
        'labelLength=${integration.label.length} '
        'diagnostics=${jsonEncode(integration.diagnostics)}';
  }
  // #endregion DEBUG

  Future<bool> _openOfficialGoogleScheduleIntegration({
    required bool showMissingMessage,
    String? successMessage,
    bool showSuccessMessage = true,
    bool waitForNavigation = false,
  }) async {
    if (!_canRunPageScripts) {
      if (showMissingMessage) {
        _showSnackBar('スケジュールページを読み込んでから使ってください');
      }
      return false;
    }

    try {
      final pageFinished = waitForNavigation
          ? _waitForNextPageFinished(timeout: const Duration(seconds: 6))
          : Future<String?>.value(null);
      final integration = await _runOfficialGoogleScheduleIntegrationScript(
        activate: true,
      );
      // #region DEBUG
      _appendCalendarDebugLog(
        '[DEBUG H2 H3] openOfficial ${_calendarDebugIntegration(integration)}',
      );
      // #endregion DEBUG
      developer.log(
        'Official Google schedule integration status=${integration.status}',
        name: 'MoreBetterGakujo',
      );
      if (integration.status == 'url' && integration.url.isNotEmpty) {
        final uri = Uri.tryParse(integration.url);
        if (uri == null) {
          if (showMissingMessage) {
            _showSnackBar('本家Google連携のURLを開けませんでした');
          }
          return false;
        }
        if (uri.host.toLowerCase().endsWith('google.com')) {
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (waitForNavigation) {
            _nextPageFinishedCompleter = null;
          }
          if (!launched) {
            _showSnackBar('本家Google連携を外部ブラウザで開けませんでした');
          }
          return launched;
        }
        if (AllowedWebOrigins.canNavigate(
          integration.url,
          debugAllowed: _debugAllowed,
        )) {
          await _controller.loadUrl(integration.url);
          if (waitForNavigation) {
            await pageFinished;
          }
          return true;
        }
        if (showMissingMessage) {
          _showSnackBar('本家Google連携のURLは許可されていません');
        }
        if (waitForNavigation) {
          _nextPageFinishedCompleter = null;
        }
        return false;
      }
      if (integration.status == 'clicked') {
        if (waitForNavigation) {
          await pageFinished;
        }
        if (showSuccessMessage) {
          _showSnackBar(successMessage ?? '本家Googleスケジュール連携を開きました');
        }
        return true;
      }
      if (showMissingMessage) {
        _showSnackBar('本家Googleスケジュール連携が見つかりませんでした。スケジュールタブで実行してください');
      }
      if (waitForNavigation) {
        _nextPageFinishedCompleter = null;
      }
      return false;
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to open official Google schedule integration',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (showMissingMessage) {
        _showSnackBar('本家Googleスケジュール連携を開けませんでした: $error');
      }
      return false;
    }
  }

  String _calendarSyncMessage(GakujoCalendarSyncResult result, String? term) {
    final termText = term == null ? '' : ' ($term)';
    final removedText = result.removed > 0 ? '、古い予定${result.removed}件を更新' : '';
    return '${result.added}件の授業予定をカレンダーに追加$removedTextしました$termText';
  }

  Future<void> _deleteAddedCalendarEvents({
    GakujoCalendarImportSettings? importSettings,
  }) async {
    if (!_calendarService.supportsDirectSync) {
      _showSnackBar(
        'この環境ではOSカレンダーの一括削除に未対応です。取り込んだ予定はカレンダーアプリ側で削除してください',
      );
      return;
    }

    final settings = importSettings ?? _appSettings.calendarImportSettings;
    try {
      final resolvedTerm = await _resolveCalendarTerm(
        settings: settings,
        manualTitle: '削除するターム期間を入力',
        manualDescription: '削除対象にする期間を入力してください。',
        manualActionLabel: '次へ',
      );
      if (resolvedTerm == null) {
        return;
      }
      final termRange = resolvedTerm.termRange;

      final confirmed = await _confirmDeleteCalendarEvents(
        termRange: termRange,
        termName: resolvedTerm.termName,
        calendarTitle: settings.effectiveCalendarTitle,
      );
      if (confirmed != true) {
        return;
      }

      final result = await _calendarService.deleteAddedEvents(
        rangeStart: termRange.start,
        rangeEnd: termRange.end,
        calendarTitle: settings.effectiveCalendarTitle,
      );
      _showSnackBar(_calendarDeleteMessage(result, resolvedTerm.termName));
    } on PlatformException catch (error) {
      developer.log(
        'Failed to delete calendar events',
        name: 'MoreBetterGakujo',
        error: error,
      );
      _showSnackBar('カレンダー予定を削除できませんでした: ${error.message ?? error.code}');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to delete calendar events',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnackBar('カレンダー予定を削除できませんでした: $error');
    }
  }

  Future<bool?> _confirmDeleteCalendarEvents({
    required GakujoCalendarTermRange termRange,
    required String? termName,
    required String calendarTitle,
  }) {
    if (!mounted) {
      return Future<bool?>.value(false);
    }
    final termText = termName == null ? '' : ' ($termName)';
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('カレンダー追加を取り消し'),
          content: Text(
            'More Better Gakujo が追加した授業予定だけを削除します。\n'
            '対象カレンダー: $calendarTitle\n'
            '対象期間: ${_formatDate(termRange.start)}〜${_formatDate(termRange.end)}$termText\n'
            '手動で作成した予定や他アプリの予定は削除しません。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('削除'),
            ),
          ],
        );
      },
    );
  }

  String _calendarDeleteMessage(
      GakujoCalendarDeleteResult result, String? term) {
    final termText = term == null ? '' : ' ($term)';
    if (result.removed == 0) {
      return '削除対象の授業予定はありませんでした$termText';
    }
    return '${result.removed}件の追加済み授業予定を削除しました$termText';
  }

  Future<void> _showCalendarValidationDialog() async {
    if (!mounted) {
      return;
    }
    final termRange = _calendarValidationTermRange();
    final events = _calendarValidationEvents(termRange);
    final action = await showDialog<_CalendarValidationAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('カレンダー連携を検証'),
          content: Text(
            '専用カレンダー「$_calendarValidationTitle」に検証用予定${events.length}件を追加します。\n'
            '対象期間: ${_formatDate(termRange.start)}〜${_formatDate(termRange.end)}\n'
            '通常の授業予定とは別のカレンダーで検証できます。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_CalendarValidationAction.delete),
              child: const Text('検証予定を削除'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(_CalendarValidationAction.add),
              child: const Text('検証予定を追加'),
            ),
          ],
        );
      },
    );

    switch (action) {
      case _CalendarValidationAction.add:
        await _addCalendarValidationEvents(termRange);
        return;
      case _CalendarValidationAction.delete:
        await _deleteCalendarValidationEvents(termRange);
        return;
      case null:
        return;
    }
  }

  Future<void> _addCalendarValidationEvents(
    GakujoCalendarTermRange termRange,
  ) async {
    final courses = _calendarValidationCourses(termRange);
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: courses,
      rangeStart: termRange.start,
      rangeEnd: termRange.end,
      uidNamespace: _calendarValidationUidNamespace,
      termLabel: 'カレンダー連携検証',
    );
    if (_calendarService.supportsDirectSync) {
      try {
        final result = await _calendarService.syncEvents(
          events: events,
          rangeStart: termRange.start,
          rangeEnd: termRange.end,
          calendarTitle: _calendarValidationTitle,
        );
        _showSnackBar(
          '検証用カレンダーに${result.added}件の予定を追加しました'
          '${result.removed > 0 ? '、古い検証予定${result.removed}件を更新しました' : ''}',
        );
        return;
      } on PlatformException catch (error) {
        developer.log(
          'Failed to validate direct calendar sync',
          name: 'MoreBetterGakujo',
          error: error,
        );
        _showSnackBar('検証用予定を追加できませんでした: ${error.message ?? error.code}');
        return;
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to validate direct calendar sync',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
        _showSnackBar('検証用予定を追加できませんでした: $error');
        return;
      }
    }

    await _writeCalendarFallbackFile(
      courses: courses,
      termRange: termRange,
      uidNamespace: _calendarValidationUidNamespace,
      termLabel: 'カレンダー連携検証',
      reason: 'この環境ではOSカレンダー直接連携が未対応のため検証用ICSとして',
      fileName: 'more-better-gakujo-calendar-validation.ics',
    );
  }

  Future<void> _deleteCalendarValidationEvents(
    GakujoCalendarTermRange termRange,
  ) async {
    if (!_calendarService.supportsDirectSync) {
      _showSnackBar(
        'この環境ではOSカレンダーの直接削除に未対応です。取り込んだ検証用ICSはカレンダーアプリ側で削除してください',
      );
      return;
    }

    try {
      final result = await _calendarService.deleteAddedEvents(
        rangeStart: termRange.start,
        rangeEnd: termRange.end,
        calendarTitle: _calendarValidationTitle,
      );
      if (result.removed == 0) {
        _showSnackBar('削除対象の検証予定はありませんでした');
        return;
      }
      _showSnackBar('検証用カレンダーから${result.removed}件の予定を削除しました');
    } on PlatformException catch (error) {
      developer.log(
        'Failed to delete validation calendar events',
        name: 'MoreBetterGakujo',
        error: error,
      );
      _showSnackBar('検証用予定を削除できませんでした: ${error.message ?? error.code}');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to delete validation calendar events',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnackBar('検証用予定を削除できませんでした: $error');
    }
  }

  GakujoCalendarTermRange _calendarValidationTermRange() {
    final now = DateTime.now().toLocal();
    final start = DateTime(now.year, now.month, now.day).add(
      const Duration(days: 1),
    );
    return GakujoCalendarTermRange(
      start: start,
      end: start.add(const Duration(days: 1)),
      sourceText: 'More Better Gakujo カレンダー検証',
    );
  }

  List<GakujoCalendarCourse> _calendarValidationCourses(
    GakujoCalendarTermRange termRange,
  ) {
    final nextDay = termRange.start.add(const Duration(days: 1));
    return [
      GakujoCalendarCourse(
        title: '[検証] 1限カレンダー連携',
        weekday: termRange.start.weekday,
        period: 1,
        location: '検証教室 A',
        teacher: 'More Better Gakujo',
      ),
      GakujoCalendarCourse(
        title: '[検証] 2限カレンダー連携',
        weekday: termRange.start.weekday,
        period: 2,
        location: '検証教室 B',
        teacher: 'More Better Gakujo',
      ),
      GakujoCalendarCourse(
        title: '[検証] 翌日3限カレンダー連携',
        weekday: nextDay.weekday,
        period: 3,
        location: '検証教室 C',
        teacher: 'More Better Gakujo',
      ),
    ];
  }

  List<GakujoCalendarEvent> _calendarValidationEvents(
    GakujoCalendarTermRange termRange,
  ) {
    return GakujoCalendarEventBuilder.buildEvents(
      courses: _calendarValidationCourses(termRange),
      rangeStart: termRange.start,
      rangeEnd: termRange.end,
      uidNamespace: _calendarValidationUidNamespace,
      termLabel: 'カレンダー連携検証',
    );
  }

  Future<void> _writeCalendarFallbackFile({
    required List<GakujoCalendarCourse> courses,
    required GakujoCalendarTermRange termRange,
    required String uidNamespace,
    required String termLabel,
    required String? reason,
    String fileName = 'more-better-gakujo-classes.ics',
  }) async {
    final ics = GakujoCalendarExport.buildIcs(
      courses: courses,
      rangeStart: termRange.start,
      rangeEnd: termRange.end,
      noClassDates: termRange.noClassDates,
      uidNamespace: uidNamespace,
      termLabel: termLabel,
    );
    final file = await _writeCalendarFile(ics, fileName: fileName);
    unawaited(_openSavedDownload(file.path));
    final prefix = reason == null ? '' : '$reason、';
    _showSnackBar(
      '$prefix${courses.length}件の授業を${_formatDate(termRange.start)}〜${_formatDate(termRange.end)}で書き出しました。カレンダーアプリで取り込んでください: ${file.path}',
    );
  }

  Future<GakujoCalendarExtraction> _readCalendarScheduleFromPage() async {
    final result = await _controller.runJavaScriptReturningResult(
      GakujoCalendarExport.extractionScript(),
    );
    final raw = _stringFromJavaScriptResult(result);
    final extraction = GakujoCalendarExport.extractionFromJson(raw);
    // #region DEBUG
    final debugCourseTitles = extraction.courses
        .take(8)
        .map(GakujoCalendarExport.displayTitleForCourse)
        .join('|');
    _appendCalendarDebugLog(
      '[DEBUG H4 H5] pageExtraction courses=${extraction.courses.length} '
      'hasTermRange=${extraction.termRange != null} '
      'titles=$debugCourseTitles',
    );
    // #endregion DEBUG
    developer.log(
      'Calendar page extraction courses=${extraction.courses.length} '
      'hasTermRange=${extraction.termRange != null}',
      name: 'MoreBetterGakujo',
    );
    return extraction;
  }

  Future<GakujoCalendarExtraction> _readCalendarScheduleForImport({
    GakujoCalendarTermRange? preferredTermRange,
  }) async {
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H4] importStart current=${_calendarDebugUrl(await _controller.currentUrl())}',
    );
    // #endregion DEBUG
    var fallbackExtraction = await _readCalendarScheduleFromPage();

    final scheduleReady = await _ensureSchedulePageForCalendarImport(
      forceReload: true,
    );
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H4] ensureSchedulePage ready=$scheduleReady '
      'current=${_calendarDebugUrl(await _controller.currentUrl())}',
    );
    // #endregion DEBUG
    if (!scheduleReady) {
      final postLoadExtraction = await _waitForBetterScheduleExtraction(
        fallback: fallbackExtraction,
      );
      if (_isUsableScheduleExtraction(postLoadExtraction)) {
        return postLoadExtraction;
      }
      return const GakujoCalendarExtraction(courses: [], termRange: null);
    }

    await _activateScheduleMonthViewForCalendarImport();
    fallbackExtraction = await _readCalendarScheduleFromPage();

    final waitedExtraction = await _waitForScheduleCoursesOrOfficial(
      termRange: fallbackExtraction.termRange ?? preferredTermRange,
    );
    if (waitedExtraction != null &&
        _isUsableScheduleExtraction(waitedExtraction)) {
      return waitedExtraction;
    }

    final officialExtraction = await _readOfficialGoogleScheduleAfterActivation(
      termRange: fallbackExtraction.termRange ?? preferredTermRange,
    );
    if (officialExtraction != null &&
        _isUsableScheduleExtraction(officialExtraction)) {
      return officialExtraction;
    }

    final timetableExtraction = await _readCourseTimetableForCalendarImport(
      preferredTermRange: fallbackExtraction.termRange ?? preferredTermRange,
    );
    if (_isBroadScheduleExtraction(timetableExtraction)) {
      return timetableExtraction;
    }

    return _isBroadScheduleExtraction(fallbackExtraction)
        ? fallbackExtraction
        : const GakujoCalendarExtraction(courses: [], termRange: null);
  }

  Future<void> _activateScheduleMonthViewForCalendarImport() async {
    if (!_canRunPageScripts) {
      return;
    }
    for (var attempt = 1; attempt <= 6; attempt += 1) {
      try {
        final result = await _controller.runJavaScriptReturningResult(
          GakujoCalendarExport.scheduleMonthViewActivationScript(),
        );
        final raw = _stringFromJavaScriptResult(result);
        // #region DEBUG
        _appendCalendarDebugLog(
          '[DEBUG H12] monthViewActivation attempt=$attempt $raw',
        );
        // #endregion DEBUG
        if (raw.contains('"clicked"') || raw.contains('clicked')) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          return;
        }
        if (raw.contains('"ready"') || raw.contains('ready')) {
          return;
        }
      } catch (error, stackTrace) {
        // #region DEBUG
        _appendCalendarDebugLog(
          '[DEBUG H12] monthViewActivation attempt=$attempt error=$error',
        );
        // #endregion DEBUG
        developer.log(
          'Failed activating schedule month view',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<GakujoCalendarExtraction> _waitForBetterScheduleExtraction({
    required GakujoCalendarExtraction fallback,
  }) async {
    var best = fallback;
    for (var attempt = 1; attempt <= 5; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final extraction = await _readCalendarScheduleFromPage();
      if (_scheduleExtractionScore(extraction) >
          _scheduleExtractionScore(best)) {
        best = extraction;
      }
      // A real schedule import page should expose several classes or a term
      // range. A tiny two-course result is usually just a sidebar/day view.
      if (best.termRange != null || best.courses.length >= 4) {
        break;
      }
    }
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H4 H5] betterScheduleExtraction '
      'fallback=${fallback.courses.length} best=${best.courses.length} '
      'hasTermRange=${best.termRange != null}',
    );
    // #endregion DEBUG
    return best;
  }

  int _scheduleExtractionScore(GakujoCalendarExtraction extraction) {
    return extraction.courses.length +
        (extraction.termRange == null ? 0 : 1000);
  }

  bool _isUsableScheduleExtraction(GakujoCalendarExtraction extraction) {
    if (extraction.courses.isEmpty) {
      return false;
    }
    if (_isBroadScheduleExtraction(extraction)) {
      return true;
    }
    if (extraction.courses.length >= 4) {
      return true;
    }
    return false;
  }

  bool _isBroadScheduleExtraction(GakujoCalendarExtraction extraction) {
    final weekdayCount = extraction.courses
        .where((course) => course.weekday >= 1 && course.weekday <= 7)
        .map((course) => course.weekday)
        .toSet()
        .length;
    final codedCourseCount = extraction.courses
        .where((course) => course.courseCode.trim().isNotEmpty)
        .length;
    return weekdayCount >= 3 && codedCourseCount >= 4;
  }

  Future<GakujoCalendarExtraction?> _waitForScheduleCoursesOrOfficial({
    GakujoCalendarTermRange? termRange,
  }) async {
    for (var attempt = 1; attempt <= 12; attempt += 1) {
      await Future<void>.delayed(const Duration(seconds: 1));

      final extraction = await _readCalendarScheduleFromPage();
      // #region DEBUG
      _appendCalendarDebugLog(
        '[DEBUG H4 H5] waitSchedule attempt=$attempt '
        'courses=${extraction.courses.length} '
        'hasTermRange=${extraction.termRange != null}',
      );
      // #endregion DEBUG

      final integration = await _runOfficialGoogleScheduleIntegrationScript(
        activate: false,
      );
      // #region DEBUG
      _appendCalendarDebugLog(
        '[DEBUG H2 H3] waitOfficial attempt=$attempt '
        '${_calendarDebugIntegration(integration)}',
      );
      // #endregion DEBUG
      if (integration.url.isNotEmpty ||
          integration.status == 'clickable' ||
          integration.status == 'clicked') {
        final officialExtraction =
            await _readOfficialGoogleScheduleAfterActivation(
          termRange: extraction.termRange ?? termRange,
        );
        if (officialExtraction != null &&
            _isUsableScheduleExtraction(officialExtraction)) {
          return officialExtraction;
        }
        final timetableExtraction = await _readCourseTimetableForCalendarImport(
          preferredTermRange: extraction.termRange ?? termRange,
        );
        if (_isBroadScheduleExtraction(timetableExtraction)) {
          return timetableExtraction;
        }
        if (_isBroadScheduleExtraction(extraction)) {
          // #region DEBUG
          _appendCalendarDebugLog(
            '[DEBUG H4 H5] waitOfficialFallbackToPage '
            'attempt=$attempt courses=${extraction.courses.length}',
          );
          // #endregion DEBUG
          return extraction;
        }
      }
      if (_isUsableScheduleExtraction(extraction)) {
        return extraction;
      }
    }
    return null;
  }

  Future<GakujoCalendarExtraction> _readCourseTimetableForCalendarImport({
    GakujoCalendarTermRange? preferredTermRange,
  }) async {
    if (!_canRunPageScripts) {
      return const GakujoCalendarExtraction(courses: [], termRange: null);
    }

    try {
      final pageFinished = _waitForNextPageFinished(
        timeout: const Duration(seconds: 8),
      );
      final jumped = await _quickJumpTo('履修');
      if (!jumped) {
        _nextPageFinishedCompleter = null;
        return const GakujoCalendarExtraction(courses: [], termRange: null);
      }
      await pageFinished;
      await Future<void>.delayed(const Duration(milliseconds: 900));

      var best = const GakujoCalendarExtraction(courses: [], termRange: null);
      for (var attempt = 1; attempt <= 6; attempt += 1) {
        final extraction = await _readCalendarScheduleFromPage();
        if (_scheduleExtractionScore(extraction) >
            _scheduleExtractionScore(best)) {
          best = extraction;
        }
        // #region DEBUG
        _appendCalendarDebugLog(
          '[DEBUG H13] timetableExtraction attempt=$attempt '
          'courses=${extraction.courses.length} '
          'broad=${_isBroadScheduleExtraction(extraction)} '
          'current=${_calendarDebugUrl(await _controller.currentUrl())}',
        );
        // #endregion DEBUG
        if (_isBroadScheduleExtraction(best)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }

      if (best.courses.isEmpty) {
        return const GakujoCalendarExtraction(courses: [], termRange: null);
      }
      return GakujoCalendarExtraction(
        courses: best.courses,
        termRange: best.termRange ?? preferredTermRange,
      );
    } on Object catch (error, stackTrace) {
      _nextPageFinishedCompleter = null;
      // #region DEBUG
      _appendCalendarDebugLog(
        '[DEBUG H13] timetableExtraction error=$error',
      );
      // #endregion DEBUG
      developer.log(
        'Failed to read course timetable for calendar import',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return const GakujoCalendarExtraction(courses: [], termRange: null);
    }
  }

  Future<GakujoCalendarExtraction?> _readOfficialGoogleScheduleAfterActivation({
    GakujoCalendarTermRange? termRange,
  }) async {
    if (!_canRunPageScripts) {
      return null;
    }

    try {
      final pageFinished = _waitForNextPageFinished(
        timeout: const Duration(seconds: 6),
      );
      final integration = await _runOfficialGoogleScheduleIntegrationScript(
        activate: true,
      );
      // #region DEBUG
      _appendCalendarDebugLog(
        '[DEBUG H1 H2 H3] officialImport '
        '${_calendarDebugIntegration(integration)}',
      );
      // #endregion DEBUG
      developer.log(
        'Official Google schedule import status=${integration.status}',
        name: 'MoreBetterGakujo',
      );
      if (integration.status == 'url' && integration.url.isNotEmpty) {
        final courses =
            GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls(
          [integration.url],
        );
        developer.log(
          'Official Google schedule URL courses=${courses.length}',
          name: 'MoreBetterGakujo',
        );
        // #region DEBUG
        _appendCalendarDebugLog(
          '[DEBUG H3 H5] officialUrlParse courses=${courses.length} '
          'url=${_calendarDebugUrl(integration.url)}',
        );
        // #endregion DEBUG
        if (courses.isNotEmpty) {
          _nextPageFinishedCompleter = null;
          return GakujoCalendarExtraction(
            courses: courses,
            termRange: termRange,
          );
        }

        final uri = Uri.tryParse(integration.url);
        if (uri != null &&
            !uri.host.toLowerCase().endsWith('google.com') &&
            AllowedWebOrigins.canNavigate(
              integration.url,
              debugAllowed: _debugAllowed,
            )) {
          await _controller.loadUrl(integration.url);
          await pageFinished;
          await Future<void>.delayed(const Duration(milliseconds: 700));
          final extraction = await _readCalendarScheduleFromPage();
          return GakujoCalendarExtraction(
            courses: extraction.courses,
            termRange: extraction.termRange ?? termRange,
          );
        }

        _nextPageFinishedCompleter = null;
        return null;
      }

      if (integration.status == 'clicked') {
        await pageFinished;
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final currentUrl = await _controller.currentUrl();
        final courses =
            GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls([
          if (currentUrl != null) currentUrl,
        ]);
        // #region DEBUG
        _appendCalendarDebugLog(
          '[DEBUG H1 H5] clickedAfterNavigation '
          'courses=${courses.length} current=${_calendarDebugUrl(currentUrl)}',
        );
        // #endregion DEBUG
        if (courses.isNotEmpty) {
          return GakujoCalendarExtraction(
            courses: courses,
            termRange: termRange,
          );
        }
        final extraction = await _readCalendarScheduleFromPage();
        final exportExtraction =
            await _readOfficialScheduleExportAfterExecution(
          termRange: extraction.termRange ?? termRange,
        );
        if (exportExtraction != null && exportExtraction.courses.isNotEmpty) {
          return exportExtraction;
        }
        return null;
      }

      _nextPageFinishedCompleter = null;
      return null;
    } on Object catch (error, stackTrace) {
      _nextPageFinishedCompleter = null;
      developer.log(
        'Failed to read official Google schedule integration',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<GakujoCalendarExtraction?> _readOfficialScheduleExportAfterExecution({
    GakujoCalendarTermRange? termRange,
  }) async {
    if (!_canRunPageScripts) {
      return null;
    }

    final inspect = await _runOfficialScheduleExportExecutionScript(
      activate: false,
      termRange: termRange,
    );
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H6 H7] exportFormInspect '
      '${_calendarDebugIntegration(inspect)}',
    );
    // #endregion DEBUG
    if (inspect.status != 'clickable') {
      return null;
    }

    final fetched = await _runOfficialScheduleExportFetchScript(
      termRange: termRange,
    );
    final fetchedCourses =
        GakujoCalendarExport.coursesFromOfficialScheduleExportText(
      fetched.text,
    );
    final fetchedGoogleCourses =
        GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls([
      fetched.text,
    ]);
    final fetchedTextSample = fetched.text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .characters
        .take(500)
        .toString();
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H8 H9] exportFetch status=${fetched.status} '
      'http=${fetched.httpStatus} contentType=${fetched.contentType} '
      'textLength=${fetched.textLength} courses=${fetchedCourses.length} '
      'googleCourses=${fetchedGoogleCourses.length} '
      'url=${_calendarDebugUrl(fetched.url)} '
      'sample=$fetchedTextSample',
    );
    // #endregion DEBUG
    final fetchedUsableCourses =
        fetchedCourses.isNotEmpty ? fetchedCourses : fetchedGoogleCourses;
    if (fetchedUsableCourses.isNotEmpty) {
      return GakujoCalendarExtraction(
        courses: fetchedUsableCourses,
        termRange: termRange,
      );
    }

    final pageFinished = _waitForNextPageFinished(
      timeout: const Duration(seconds: 8),
    );
    final execution = await _runOfficialScheduleExportExecutionScript(
      activate: true,
      termRange: termRange,
    );
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H6 H7] exportFormExecute '
      '${_calendarDebugIntegration(execution)}',
    );
    // #endregion DEBUG
    if (execution.status != 'clicked') {
      _nextPageFinishedCompleter = null;
      return null;
    }

    await pageFinished;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final currentUrl = await _controller.currentUrl();
    final courses = GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls([
      if (currentUrl != null) currentUrl,
    ]);
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H6 H7] exportAfterNavigation '
      'courses=${courses.length} current=${_calendarDebugUrl(currentUrl)}',
    );
    // #endregion DEBUG
    if (courses.isNotEmpty) {
      return GakujoCalendarExtraction(
        courses: courses,
        termRange: termRange,
      );
    }

    final extraction = await _readCalendarScheduleFromPage();
    final integration = await _runOfficialGoogleScheduleIntegrationScript(
      activate: false,
    );
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H6 H7] exportAfterOfficial '
      '${_calendarDebugIntegration(integration)}',
    );
    // #endregion DEBUG
    if (integration.url.isNotEmpty) {
      return _readOfficialGoogleScheduleAfterActivation(
        termRange: extraction.termRange ?? termRange,
      );
    }
    return null;
  }

  Future<bool> _ensureSchedulePageForCalendarImport({
    bool forceReload = false,
  }) async {
    final currentUrl =
        ((await _controller.currentUrl()) ?? _currentPageUrl ?? '')
            .toLowerCase();
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H4] ensureSchedulePage forceReload=$forceReload '
      'current=${_calendarDebugUrl(currentUrl)}',
    );
    // #endregion DEBUG
    if (!forceReload && currentUrl.contains('tabid=sch')) {
      return true;
    }

    final pageFinished = _waitForNextPageFinished(
      timeout: const Duration(seconds: 8),
    );
    await _loadAllowedPageUrl(_schedulePortalUrl);
    final finishedUrl = await pageFinished;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final afterUrl = ((await _controller.currentUrl()) ?? _currentPageUrl ?? '')
        .toLowerCase();
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H4] directScheduleLoad finished=${_calendarDebugUrl(finishedUrl)} '
      'current=${_calendarDebugUrl(afterUrl)}',
    );
    // #endregion DEBUG
    return afterUrl.contains('tabid=sch') ||
        (finishedUrl ?? '').toLowerCase().contains('tabid=sch');
  }

  Future<GakujoAcademicTerm?> _officialAcademicTermFor(
    DateTime date, {
    GakujoCalendarTermTarget target = GakujoCalendarTermTarget.current,
  }) async {
    final academicYear = GakujoAcademicCalendar.academicYearFor(date);
    GakujoAcademicTerm? pickTerm(List<GakujoAcademicTerm> terms) {
      final termName = target.termName;
      if (termName == null) {
        return GakujoAcademicCalendar.termForDateIn(date, terms);
      }
      for (final term in terms) {
        if (term.academicYear == academicYear && term.name == termName) {
          return term;
        }
      }
      return null;
    }

    try {
      final terms = await _academicCalendarResolver
          .fetchTermsForAcademicYear(academicYear);
      final fetched = pickTerm(terms);
      if (fetched != null) {
        return GakujoAcademicCalendar.mergeWithBuiltInDetails(fetched);
      }
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to fetch official academic calendar PDF',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
    final fallback = pickTerm(GakujoAcademicCalendar.officialTerms);
    return fallback == null
        ? null
        : GakujoAcademicCalendar.mergeWithBuiltInDetails(fallback);
  }

  Future<GakujoCalendarTermRange?> _askCalendarTermRange({
    String title = 'ターム期間を入力',
    String description = 'ページからターム期間を読み取れませんでした。書き出す授業期間を入力してください。',
    String actionLabel = '書き出し',
  }) async {
    if (!mounted) {
      return null;
    }
    final today = DateTime.now();
    final startController = TextEditingController(
      text: '${today.year}/${today.month.toString().padLeft(2, '0')}/01',
    );
    final endController = TextEditingController();
    String? errorText;
    try {
      return showDialog<GakujoCalendarTermRange>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              void submit() {
                final start = _parseCalendarDate(startController.text);
                final end = _parseCalendarDate(endController.text);
                if (start == null || end == null || end.isBefore(start)) {
                  setDialogState(() {
                    errorText = 'YYYY/MM/DD形式で、終了日が開始日以降になるように入力してください';
                  });
                  return;
                }
                Navigator.of(dialogContext).pop(
                  GakujoCalendarTermRange(start: start, end: end),
                );
              }

              return AlertDialog(
                title: Text(title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(description),
                    const SizedBox(height: 12),
                    TextField(
                      controller: startController,
                      decoration: const InputDecoration(
                        labelText: '開始日',
                        hintText: '2026/06/11',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.datetime,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: endController,
                      decoration: const InputDecoration(
                        labelText: '終了日',
                        hintText: '2026/08/08',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.datetime,
                      onSubmitted: (_) => submit(),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('キャンセル'),
                  ),
                  FilledButton(
                    onPressed: submit,
                    child: Text(actionLabel),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      startController.dispose();
      endController.dispose();
    }
  }

  DateTime? _parseCalendarDate(String raw) {
    final match = RegExp(
      r'^\s*((?:20)?[0-9]{2})[/-]([0-9]{1,2})[/-]([0-9]{1,2})\s*$',
    ).firstMatch(raw);
    if (match == null) {
      return null;
    }
    final rawYear = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (rawYear == null || month == null || day == null) {
      return null;
    }
    final year = rawYear < 100 ? rawYear + 2000 : rawYear;
    return DateTime(year, month, day);
  }

  Future<File> _writeCalendarFile(
    String ics, {
    String fileName = 'more-better-gakujo-classes.ics',
  }) async {
    try {
      final location = await getSaveLocation(
        initialDirectory: await _defaultExportDirectoryPath(),
        suggestedName: fileName,
        confirmButtonText: '保存',
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'iCalendar',
            extensions: ['ics'],
            mimeTypes: ['text/calendar'],
          ),
        ],
        canCreateDirectories: true,
      );
      if (location == null) {
        throw PlatformException(
          code: 'cancelled',
          message: '保存をキャンセルしました',
        );
      }
      final file = File(location.path);
      await file.writeAsString(ics, flush: true);
      return file;
    } on MissingPluginException {
      return _writeCalendarFileToDocuments(fileName: fileName, ics: ics);
    } on UnimplementedError {
      return _writeCalendarFileToDocuments(fileName: fileName, ics: ics);
    }
  }

  Future<File> _writeCalendarFileToDocuments({
    required String fileName,
    required String ics,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory =
        Directory(_joinLocalPath(documents.path, 'MoreBetterGakujoCalendar'));
    await directory.create(recursive: true);
    final file = File(_joinLocalPath(directory.path, fileName));
    await file.writeAsString(ics, flush: true);
    return file;
  }

  Future<String?> _defaultExportDirectoryPath() async {
    try {
      return (await getApplicationDocumentsDirectory()).path;
    } on Object {
      return null;
    }
  }

  String _dateFileStamp(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${twoDigits(value.month)}${twoDigits(value.day)}';
  }

  Future<void> _loadAllowedPageUrl(String url) async {
    if (!AllowedWebOrigins.canNavigate(url, debugAllowed: _debugAllowed)) {
      _showSnackBar('許可されていない外部URLは開けません');
      return;
    }
    await _controller.loadUrl(url);
  }

  Future<String?> _waitForNextPageFinished({
    Duration timeout = const Duration(seconds: 4),
  }) {
    final completer = Completer<String>();
    _nextPageFinishedCompleter = completer;
    return completer.future.timeout(timeout, onTimeout: () => '').then(
      (url) {
        if (identical(_nextPageFinishedCompleter, completer)) {
          _nextPageFinishedCompleter = null;
        }
        return url.isEmpty ? null : url;
      },
    );
  }

  void _notifyPageFinishedWaiters(String url) {
    final completer = _nextPageFinishedCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete(url);
    _nextPageFinishedCompleter = null;
  }

  String _favoriteTitle(String? title, String url) {
    final trimmed = title?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    return segments.isEmpty ? 'Gakujo' : segments.last;
  }

  Future<bool> _quickJumpTo(String label, {String? fallbackUrl}) async {
    if (!_canRunPageScripts) {
      if (fallbackUrl != null) {
        await _loadAllowedPageUrl(fallbackUrl);
        return true;
      } else {
        _showSnackBar('ページを読み込んでから使ってください');
      }
      return false;
    }

    try {
      final escapedLabel = jsonEncode(label);
      final result = await _controller.runJavaScriptReturningResult('''
(function() {
  var label = $escapedLabel;
  var documents = [];
  function collect(win) {
    try {
      if (!win || !win.document || documents.indexOf(win.document) !== -1) {
        return;
      }
      documents.push(win.document);
      for (var i = 0; i < win.frames.length; i += 1) {
        collect(win.frames[i]);
      }
    } catch (e) {}
  }
  collect(window);
  for (var d = 0; d < documents.length; d += 1) {
    var candidates = Array.prototype.slice.call(
      documents[d].querySelectorAll('a, button, input, img, td, div, span')
    );
    for (var i = 0; i < candidates.length; i += 1) {
      var node = candidates[i];
      var text = [
        node.innerText || '',
        node.textContent || '',
        node.getAttribute && node.getAttribute('alt') || '',
        node.getAttribute && node.getAttribute('title') || '',
        node.getAttribute && node.getAttribute('value') || ''
      ].join(' ');
      if (text.indexOf(label) === -1) {
        continue;
      }
      var clickable = node.closest && node.closest('a, button, input');
      (clickable || node).click();
      return true;
    }
  }
  return false;
})()
''');
      if (_boolFromJavaScriptResult(result)) {
        _setStatus('$label へ移動します');
        return true;
      }
    } catch (error, stackTrace) {
      developer.log(
        'Failed to quick jump',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (fallbackUrl != null) {
      await _loadAllowedPageUrl(fallbackUrl);
      return true;
    } else {
      _showSnackBar('$label が見つかりませんでした');
    }
    return false;
  }

  Future<void> _refreshActivityCounts() async {
    try {
      final deadlines = await _activityStore.loadDeadlines();
      if (!mounted) {
        return;
      }
      setState(() {
        _deadlineCount = deadlines.length;
      });
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to refresh activity counts',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<_ActivityScanResult?> _scanCurrentActionablePageActivity() async {
    final url = await _currentActionableUrl();
    if (url == null) {
      return null;
    }
    return _scanCurrentPageActivity(url);
  }

  Future<_ActivityScanResult?> _rescanActivityForBell() async {
    final originalUrl = await _currentActionableUrl();
    try {
      var combinedResult = await _scanCurrentActionablePageActivity();
      if (!_appSettings.isFeatureEnabled(GakujoFeatureFlag.deadlineScan)) {
        return combinedResult;
      }

      final currentUrl = (await _currentActionableUrl())?.toLowerCase() ?? '';
      if (!currentUrl.contains('report') && !currentUrl.contains('enq')) {
        combinedResult = _mergeActivityScanResults(
          combinedResult,
          await _scanQuickJumpPageForBell(
            label: 'レポート',
          ),
        );
      }

      final isMessagePage = currentUrl.contains('tabid=kj') ||
          currentUrl.contains('keiji') ||
          currentUrl.contains('message');
      if (!isMessagePage) {
        combinedResult = _mergeActivityScanResults(
          combinedResult,
          await _scanQuickJumpPageForBell(
            label: '連絡通知',
          ),
        );
      }

      return combinedResult;
    } finally {
      await _restorePageAfterBellScan(originalUrl);
    }
  }

  Future<void> _restorePageAfterBellScan(String? originalUrl) async {
    if (!mounted ||
        originalUrl == null ||
        !AllowedWebOrigins.canLoad(originalUrl, debugAllowed: _debugAllowed)) {
      return;
    }
    final currentUrl = await _currentActionableUrl();
    if (currentUrl == originalUrl) {
      return;
    }
    await _loadAllowedPageUrl(originalUrl);
  }

  Future<_ActivityScanResult?> _scanQuickJumpPageForBell({
    required String label,
  }) async {
    final finished = _waitForNextPageFinished();
    final jumped = await _quickJumpTo(label);
    if (!jumped) {
      return null;
    }

    await finished;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final nextUrl = await _currentActionableUrl();
    if (nextUrl == null) {
      return null;
    }
    return _scanCurrentPageActivity(nextUrl);
  }

  _ActivityScanResult? _mergeActivityScanResults(
    _ActivityScanResult? a,
    _ActivityScanResult? b,
  ) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return _ActivityScanResult(
      updateCount: a.updateCount + b.updateCount,
      deadlineCount: a.deadlineCount + b.deadlineCount,
    );
  }

  Future<_ActivityScanResult?> _scanCurrentPageActivity(String url) async {
    final shouldRecordActivity =
        _appSettings.isFeatureEnabled(GakujoFeatureFlag.activityScan);
    final shouldScanDeadlines =
        _appSettings.isFeatureEnabled(GakujoFeatureFlag.deadlineScan);
    final shouldCacheReports =
        _appSettings.isFeatureEnabled(GakujoFeatureFlag.reportListCache);
    if (!shouldReadPageForActivityFeatures(_appSettings)) {
      return null;
    }
    if (!AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
      return null;
    }
    final result = await _readPageTextForActivity();
    if (result == null) {
      return null;
    }

    final category = GakujoActivityClassifier.categoryFor(
      url: url,
      title: result.title,
      text: result.text,
    );
    final title = GakujoActivityClassifier.displayTitleFor(
      url: url,
      title: result.title,
      text: result.text,
      category: category,
    );
    final content = GakujoActivityClassifier.stableContentFor(
      url: url,
      title: result.title,
      text: result.text,
      category: category,
    );
    GakujoActivitySnapshot? snapshot;
    if (shouldRecordActivity && content.trim().isNotEmpty) {
      snapshot = await _activityStore.recordSnapshot(
        category: category,
        title: title,
        url: url,
        content: content,
      );
    }
    var newDeadlineCount = 0;
    if (shouldScanDeadlines) {
      final extractedDeadlines = _extractDeadlines(
        category: category,
        title: title,
        url: url,
        text: result.text,
        messageItems: result.messageItems,
      );
      final newDeadlines = await _activityStore.mergeDeadlines(
        extractedDeadlines,
      );
      newDeadlineCount = newDeadlines.length;
      await _notifyNewDeadlines(newDeadlines);
    }
    if (category == 'レポート・小テスト' && shouldCacheReports) {
      await _activityStore.saveReportList(
        GakujoCachedReportList(
          title: title,
          url: url,
          capturedAt: DateTime.now(),
          items: _extractReportListItems(result.text),
        ),
      );
    }
    await _refreshActivityCounts();
    return _ActivityScanResult(
      updateCount: snapshot?.hasUpdate == true ? 1 : 0,
      deadlineCount: newDeadlineCount,
    );
  }

  Future<_PageTextSnapshot?> _readPageTextForActivity() async {
    if (!_canRunPageScripts) {
      return null;
    }
    try {
      final result = await _controller.runJavaScriptReturningResult(r'''
(function() {
  var texts = [];
  var messageItems = [];
  var seenMessageItems = {};
  var datePattern = /((?:令和[0-9]{1,2}年|(?:20)?[0-9]{2}(?:[\/.\-]|年))[0-9]{1,2}(?:[\/.\-]|月)[0-9]{1,2}日?(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?|[0-9]{1,2}[\/.][0-9]{1,2}(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?|[0-9]{1,2}月[0-9]{1,2}日(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?)/;
  function compactText(element) {
    return (element && (element.innerText || element.textContent || element.value) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }
  function compactRawText(text) {
    return String(text || '').replace(/\s+/g, ' ').trim();
  }
  function normalizeDateText(text) {
    return String(text || '')
      .replace(/[０-９]/g, function(ch) {
        return String.fromCharCode(ch.charCodeAt(0) - 0xFEE0);
      })
      .replace(/：/g, ':')
      .replace(/／/g, '/')
      .replace(/．/g, '.')
      .replace(/[－−]/g, '-');
  }
  function isPortalNoiseText(text) {
    var normalized = normalizeDateText(compactRawText(text));
    if (!normalized) {
      return true;
    }
    if (normalized.indexOf('MYスケジュール') >= 0 ||
        normalized.indexOf('前回ログイン日時') >= 0 ||
        normalized.indexOf('ログアウト') >= 0 ||
        normalized.indexOf('残り約') >= 0 ||
        /^Copyright/.test(normalized)) {
      return true;
    }
    if (/^[0-9]{4}\/[0-9]{1,2}\/[0-9]{1,2}\([A-Za-z]+\)$/.test(normalized)) {
      return true;
    }
    if (/^[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日\s*[0-9]{1,2}時[0-9]{1,2}分\s*(から|まで)?$/.test(normalized)) {
      return true;
    }
    return false;
  }
  function hasDate(text) {
    return datePattern.test(normalizeDateText(text));
  }
  function messageTable(doc) {
    var direct = doc.querySelector('table.normal:nth-child(9)');
    if (direct) {
      return direct;
    }
    var tables = doc.querySelectorAll('table');
    for (var i = 0; i < tables.length; i += 1) {
      var text = compactText(tables[i]);
      if ((text.indexOf('掲示') >= 0 || text.indexOf('連絡') >= 0) &&
          tables[i].querySelector('a[href]')) {
        return tables[i];
      }
    }
    return null;
  }
  function messageUrl(doc, node) {
    var link = node && node.closest && node.closest('a[href]');
    if (!link && node && node.querySelector) {
      link = node.querySelector('a[href]');
    }
    var href = link && link.href || '';
    if (href && !/^javascript:/i.test(href)) {
      return href;
    }
    try {
      return doc.location.href || document.location.href;
    } catch (e) {
      return document.location.href;
    }
  }
  function messageTitle(node, text) {
    var link = node && node.querySelector && node.querySelector('a, button, input');
    var label = compactText(link || node);
    if (!label || label.length > 120) {
      label = text.split(/(?:\s{2,}| \/ |\n)/)[0] || text;
    }
    return label.length > 120 ? label.substring(0, 120) + '...' : label;
  }
  function addMessageData(doc, title, url, text) {
    text = compactRawText(text);
    title = compactRawText(title);
    if (text.length < 6 || isPortalNoiseText(text) || !hasDate(text)) {
      return;
    }
    if (!title || title.length > 120) {
      title = text.split(/(?:\s{2,}| \/ |\n)/)[0] || text;
    }
    if (title.length > 120) {
      title = title.substring(0, 120) + '...';
    }
    url = url || doc.location.href || document.location.href;
    var key = title + '|' + url + '|' + text;
    if (seenMessageItems[key]) {
      return;
    }
    seenMessageItems[key] = true;
    messageItems.push({
      title: title,
      url: url,
      text: text
    });
  }
  function addMessageItem(doc, node) {
    var text = compactText(node);
    addMessageData(doc, messageTitle(node, text), messageUrl(doc, node), text);
  }
  function collectNoticeDetail(doc) {
    var raw = doc.body && (doc.body.innerText || doc.body.textContent) || '';
    if (!raw || raw.indexOf('連絡通知元') < 0) {
      return false;
    }
    var lines = raw.split(/\r?\n/)
      .map(function(line) { return line.replace(/\s+/g, ' ').trim(); })
      .filter(Boolean);
    var start = -1;
    for (var i = 0; i < lines.length; i += 1) {
      if (lines[i] === '連絡通知') {
        start = i + 1;
        break;
      }
    }
    if (start < 0) {
      start = 0;
    }
    while (start < lines.length && (
      lines[start] === '[image]' ||
      lines[start] === '連絡通知' ||
      lines[start].indexOf('指定した個数を既読') >= 0
    )) {
      start += 1;
    }
    if (start >= lines.length) {
      return false;
    }
    var end = lines.findIndex(function(line, index) {
      return index > start && (
        line === '連絡通知元' ||
        line === '連絡通知期間' ||
        line === 'メール送信' ||
        line === '送信日時' ||
        line === '対象学生所属'
      );
    });
    if (end < 0) {
      end = lines.length;
    }
    var title = lines[start].replace(/\s*\[[^\]]+\]\s*$/g, '').trim();
    var body = lines.slice(start, end).join(' ');
    if (!hasDate(body)) {
      return false;
    }
    addMessageData(doc, title, doc.location.href, body);
    return true;
  }
  function collectMessageItems(doc) {
    try {
      if (collectNoticeDetail(doc)) {
        return;
      }
      var table = messageTable(doc);
      var candidates = table ?
        table.querySelectorAll('tr') :
        doc.querySelectorAll('tr, li, a, button');
      for (var i = 0; i < candidates.length; i += 1) {
        addMessageItem(doc, candidates[i]);
      }
    } catch (e) {}
  }
  function collectReportRows(doc) {
    var rows = [];
    try {
      var table = doc.querySelector('#enqListForm table:nth-of-type(2)');
      if (!table || !table.rows) {
        return rows;
      }
      for (var i = 1; i < table.rows.length; i += 1) {
        var cells = table.rows[i].cells;
        if (!cells || cells.length < 8) {
          continue;
        }
        var title = compactText(cells[1]);
        var status = compactText(cells[2]);
        var number = compactText(cells[3]);
        var period = compactText(cells[7]);
        if (!title || !period) {
          continue;
        }
        rows.push(
          'レポート課題: ' + title +
          (number ? ' / 開講番号: ' + number : '') +
          (status ? ' / 状態: ' + status : '') +
          ' / 提出期間: ' + period
        );
      }
    } catch (e) {}
    return rows;
  }
  function collect(win) {
    try {
      if (win.document && win.document.body) {
        texts.push(win.document.body.innerText || '');
        collectMessageItems(win.document);
        var reportRows = collectReportRows(win.document);
        if (reportRows.length) {
          texts.push(reportRows.join('\n'));
        }
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        collect(win.frames[i]);
      }
    } catch (e) {}
  }
  collect(window);
  return JSON.stringify({
    title: document.title || '',
    text: texts.join('\n'),
    messageItems: messageItems
  });
})()
''');
      final raw = _stringFromJavaScriptResult(result);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final rawMessageItems = decoded['messageItems'];
      return _PageTextSnapshot(
        title: decoded['title']?.toString() ?? '',
        text: decoded['text']?.toString() ?? '',
        messageItems: rawMessageItems is List<dynamic>
            ? rawMessageItems
                .whereType<Map<dynamic, dynamic>>()
                .map(_MessageActivityCandidate.fromJson)
                .toList()
            : const [],
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to scan page activity',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  List<GakujoDeadlineEntry> _extractDeadlines({
    required String category,
    required String title,
    required String url,
    required String text,
    required List<_MessageActivityCandidate> messageItems,
  }) {
    final now = DateTime.now();
    final entries = <GakujoDeadlineEntry>[];
    final seen = <String>{};
    void addEntry({
      required String entryTitle,
      required String entryUrl,
      required String entryText,
      required String kind,
    }) {
      final normalizedText = _datedActivityText(entryText);
      if (GakujoDatedActivity.isNoiseText(normalizedText) ||
          !_containsDate(normalizedText)) {
        return;
      }
      final normalizedTitle = entryTitle.trim().isEmpty
          ? _datedActivityTitle(normalizedText)
          : GakujoDatedActivity.compactText(entryTitle, maxLength: 80);
      final safeUrl = entryUrl.trim().isEmpty ? url : entryUrl;
      final key = '$kind|$safeUrl|$normalizedTitle|$normalizedText';
      if (!seen.add(key)) {
        return;
      }
      entries.add(
        GakujoDeadlineEntry(
          title: normalizedTitle,
          url: safeUrl,
          dueText: normalizedText,
          detectedAt: now,
          kind: kind,
        ),
      );
    }

    for (final item in messageItems) {
      addEntry(
        entryTitle: item.title,
        entryUrl: item.url,
        entryText: item.text,
        kind: GakujoDatedActivity.kindFor(text: item.text, category: category),
      );
    }

    if (category == '連絡通知' && messageItems.isNotEmpty) {
      return entries;
    }

    final lines = GakujoActivityClassifier.stableLinesFor(text).where((line) {
      final hasDeadlineWord = line.contains('期限') ||
          line.contains('締切') ||
          line.contains('締め切') ||
          line.contains('提出');
      if (category == '連絡通知') {
        return _containsDate(line);
      }
      return hasDeadlineWord;
    }).toList();
    for (final line in lines.take(40)) {
      if (!_containsDate(line)) {
        continue;
      }
      addEntry(
        entryTitle: _datedActivityLineTitle(
            category: category, title: title, line: line),
        entryUrl: url,
        entryText: line,
        kind: GakujoDatedActivity.kindFor(text: line, category: category),
      );
    }
    return entries;
  }

  bool _containsDate(String text) {
    return GakujoDatedActivity.containsDate(text);
  }

  String _datedActivityText(String text) {
    return GakujoDatedActivity.compactText(text);
  }

  String _datedActivityTitle(String text) {
    return GakujoDatedActivity.titleFor(text);
  }

  String _datedActivityLineTitle({
    required String category,
    required String title,
    required String line,
  }) {
    final trimmed = title.trim();
    if (category != '連絡通知') {
      return trimmed;
    }
    const genericTitles = {
      '',
      'Gakujo',
      'お知らせ',
      '新着情報',
      '連絡通知',
      'CampusSquare for WEB [CampusSquare]',
    };
    return genericTitles.contains(trimmed) || trimmed.startsWith('CampusSquare')
        ? _datedActivityTitle(line)
        : trimmed;
  }

  List<String> _extractReportListItems(String text) {
    final keywords = RegExp(
      r'(レポート|課題|小テスト|アンケート|提出|期限|締切|締め切)',
    );
    final seen = <String>{};
    final items = <String>[];
    for (final line in text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())) {
      if (line.length < 4 || !keywords.hasMatch(line)) {
        continue;
      }
      final item = line.length > 160 ? '${line.substring(0, 160)}...' : line;
      if (seen.add(item)) {
        items.add(item);
      }
      if (items.length >= 80) {
        break;
      }
    }
    return items;
  }

  Future<void> _notifyNewDeadlines(List<GakujoDeadlineEntry> entries) async {
    final deadlineEntries = entries.where((entry) => entry.isDeadline).toList();
    if (deadlineEntries.isEmpty) {
      return;
    }
    if (!_appSettings.isFeatureEnabled(
      GakujoFeatureFlag.deadlineNotifications,
    )) {
      return;
    }
    final granted = await _notificationService.requestPermission();
    if (!granted) {
      return;
    }
    for (final entry in deadlineEntries.take(5)) {
      await _notificationService.notifyDeadline(entry);
    }
  }

  Future<void> _handleSessionExpiredIfNeeded(String url) async {
    if (!_appSettings.isFeatureEnabled(
      GakujoFeatureFlag.sessionRecoveryGuide,
    )) {
      return;
    }
    if (!AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
      return;
    }
    if (!_looksLikeLoginOrTimeoutUrl(url)) {
      return;
    }
    _setStatus('ログインが切れた可能性があります: ${_displayUrl(url)}');
    final recoveryUrl = _sessionRecoveryUrl ?? _pendingLoginRestoreUrl;
    if (!mounted ||
        recoveryUrl == null ||
        !AllowedWebOrigins.canLoad(recoveryUrl, debugAllowed: _debugAllowed)) {
      return;
    }
    if (_lastSessionRecoveryNoticeUrl == url) {
      return;
    }
    _lastSessionRecoveryNoticeUrl = url;
    _pendingLoginRestoreUrl = recoveryUrl;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('ログインが切れた可能性があります'),
        action: SnackBarAction(
          label: '復帰予約',
          onPressed: () {
            _pendingLoginRestoreUrl = recoveryUrl;
            _loginRestoreAttempted = false;
            _showSnackBar('再ログイン後に前のページへ戻ります');
          },
        ),
      ),
    );
  }

  bool _looksLikeLoginOrTimeoutUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('timeout') ||
        lower.contains('login') ||
        lower.contains('logout');
  }

  Future<void> _exportSettingsToClipboard() async {
    final payload = await _backupPayload();
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
    );
    _showSnackBar('設定をクリップボードにコピーしました');
  }

  Future<Map<String, Object?>> _backupPayload() async {
    final history = await _downloadHistoryStore.load();
    final failedDownloads = await _downloadHistoryStore.loadFailedDownloads();
    final favorites = await _activityStore.loadFavorites();
    final deadlines = await _activityStore.loadDeadlines();
    final changes = await _activityStore.loadChanges();
    final reportLists = await _activityStore.loadReportLists();
    return {
      'version': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'downloadSaveMode': _appSettings.downloadSaveMode.storageValue,
      'pageMode': _appSettings.pageMode.storageValue,
      'setupCompleted': _appSettings.setupCompleted,
      'calendarImportSettings': _appSettings.calendarImportSettings.toJson(),
      'messageExcludeKeywords': _appSettings.messageExcludeKeywords,
      'disabledFeatureFlags': _appSettings.disabledFeatureFlags
          .map((flag) => flag.storageValue)
          .toList(),
      'downloadHistory': history.map((entry) => entry.toJson()).toList(),
      'failedDownloads':
          failedDownloads.map((entry) => entry.toJson()).toList(),
      'favorites': favorites.map((entry) => entry.toJson()).toList(),
      'deadlines': deadlines.map((entry) => entry.toJson()).toList(),
      'changes': changes.map((entry) => entry.toJson()).toList(),
      'reportLists': reportLists.map((entry) => entry.toJson()).toList(),
    };
  }

  Future<void> _importSettingsFromClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.trim().isEmpty) {
      _showSnackBar('クリップボードに設定JSONがありません');
      return;
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON object expected');
      }
      final downloadSaveMode = decoded.containsKey('downloadSaveMode')
          ? DownloadSaveModeLabels.fromStorageValue(
              decoded['downloadSaveMode']?.toString(),
            )
          : _appSettings.downloadSaveMode;
      final pageMode = decoded.containsKey('pageMode')
          ? GakujoPageModeLabels.fromStorageValue(
              decoded['pageMode']?.toString(),
            )
          : _appSettings.pageMode;
      final setupCompleted = decoded['setupCompleted'] is bool
          ? decoded['setupCompleted'] as bool
          : _appSettings.setupCompleted;
      final calendarImportSettings =
          decoded.containsKey('calendarImportSettings')
              ? GakujoCalendarImportSettings.fromJson(
                  decoded['calendarImportSettings'],
                )
              : _appSettings.calendarImportSettings;
      final messageExcludeKeywords =
          decoded.containsKey('messageExcludeKeywords')
              ? normalizeMessageExcludeKeywords(
                  _decodeBackupList(
                    decoded['messageExcludeKeywords'],
                    (value) => value.toString(),
                  ),
                )
              : _appSettings.messageExcludeKeywords;
      final disabledFeatureFlags = decoded.containsKey('disabledFeatureFlags')
          ? _decodeBackupList(
              decoded['disabledFeatureFlags'],
              (value) => GakujoFeatureFlagLabels.fromStorageValue(
                value.toString(),
              ),
            ).whereType<GakujoFeatureFlag>().toSet()
          : _appSettings.disabledFeatureFlags;
      final importedFavorites = _decodeBackupMaps(
        decoded['favorites'],
        GakujoFavoritePage.fromJson,
      ).where((entry) => _isAllowedBackupNavigationUrl(entry.url)).toList();
      final importedFailedDownloads = _decodeBackupMaps(
        decoded['failedDownloads'],
        GakujoFailedDownloadEntry.fromJson,
      ).where((entry) => _isAllowedBackupUrl(entry.request.url)).toList();
      final importedDeadlines = _decodeBackupMaps(
        decoded['deadlines'],
        GakujoDeadlineEntry.fromJson,
      ).where((entry) => _isAllowedBackupUrl(entry.url)).toList();
      final importedChanges = _decodeBackupMaps(
        decoded['changes'],
        GakujoActivityChangeEntry.fromJson,
      ).where((entry) => _isAllowedBackupUrl(entry.url)).toList();
      final importedReportLists = _decodeBackupMaps(
        decoded['reportLists'],
        GakujoCachedReportList.fromJson,
      ).where((entry) => _isAllowedBackupUrl(entry.url)).toList();
      await Future.wait([
        _appSettingsStore.saveDownloadSaveMode(downloadSaveMode),
        _appSettingsStore.savePageMode(pageMode),
        _appSettingsStore.saveDisabledFeatureFlags(disabledFeatureFlags),
        _appSettingsStore.saveSetupCompleted(setupCompleted),
        _appSettingsStore.saveCalendarImportSettings(calendarImportSettings),
        _appSettingsStore.saveMessageExcludeKeywords(messageExcludeKeywords),
        _downloadHistoryStore.replaceHistory(
          _decodeBackupMaps(
            decoded['downloadHistory'],
            GakujoDownloadHistoryEntry.fromJson,
          ),
        ),
        _downloadHistoryStore.replaceFailedDownloads(importedFailedDownloads),
        _activityStore.replaceFavorites(importedFavorites),
        _activityStore.replaceDeadlines(importedDeadlines),
        _activityStore.replaceChanges(importedChanges),
        _activityStore.replaceReportLists(importedReportLists),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _appSettings = _appSettings.copyWith(
          downloadSaveMode: downloadSaveMode,
          pageMode: pageMode,
          disabledFeatureFlags: disabledFeatureFlags,
          setupCompleted: setupCompleted,
          calendarImportSettings: calendarImportSettings,
          messageExcludeKeywords: messageExcludeKeywords,
        );
      });
      await _injectMessageFilterIfAllowed();
      await _refreshActivityCounts();
      _scheduleAutoBackup();
      _showSnackBar('設定をインポートしました');
    } on Object {
      _showSnackBar('設定JSONを読み取れませんでした');
    }
  }

  List<T> _decodeBackupMaps<T>(
    Object? value,
    T Function(Map<dynamic, dynamic>) fromJson,
  ) {
    if (value is! List<dynamic>) {
      return const [];
    }
    final entries = <T>[];
    for (final item in value.whereType<Map<dynamic, dynamic>>()) {
      try {
        entries.add(fromJson(item));
      } on Object {
        // Skip malformed entries from older backups.
      }
    }
    return entries;
  }

  List<T> _decodeBackupList<T>(
    Object? value,
    T? Function(Object value) fromJson,
  ) {
    if (value is! List<dynamic>) {
      return const [];
    }
    final entries = <T>[];
    for (final item in value) {
      if (item == null) {
        continue;
      }
      final decoded = fromJson(item);
      if (decoded != null) {
        entries.add(decoded);
      }
    }
    return entries;
  }

  bool _isAllowedBackupUrl(String url) {
    return AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed);
  }

  bool _isAllowedBackupNavigationUrl(String url) {
    return AllowedWebOrigins.canNavigate(url, debugAllowed: _debugAllowed);
  }

  Future<void> _copyDiagnosticInfo() async {
    final payload = await _diagnosticPayload(includeStoredData: false);
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
    );
    _showSnackBar('診断情報をコピーしました');
  }

  Future<Map<String, Object?>> _diagnosticPayload({
    required bool includeStoredData,
  }) async {
    final hasTwoFactorSecret = await _secretStore.load() != null;
    final historyCount = (await _downloadHistoryStore.load()).length;
    final failedDownloadCount =
        (await _downloadHistoryStore.loadFailedDownloads()).length;
    final snapshots = await _activityStore.loadSnapshots();
    final deadlines = await _activityStore.loadDeadlines();
    final favorites = await _activityStore.loadFavorites();
    final changes = await _activityStore.loadChanges();
    final reportLists = await _activityStore.loadReportLists();
    final payload = <String, Object?>{
      'app': 'More Better Gakujo',
      'platform': defaultTargetPlatform.name,
      'createdAt': DateTime.now().toIso8601String(),
      'canGoBack': _canGoBack,
      'canGoForward': _canGoForward,
      'downloadRootConfigured': _downloadRoot.isConfigured,
      'downloadRootLabel': downloadRootLabel(
        _downloadRoot,
        includePath: includeStoredData,
      ),
      'downloadSaveMode': _appSettings.downloadSaveMode.storageValue,
      'pageMode': _appSettings.pageMode.storageValue,
      'calendarImportSettings': _appSettings.calendarImportSettings.toJson(),
      'loginCredentialsConfigured': _appSettings.hasLoginCredentials,
      'twoFactorSecretConfigured': hasTwoFactorSecret,
      'desktopZoom': _desktopZoom,
      'downloadHistoryCount': historyCount,
      'failedDownloadCount': failedDownloadCount,
      'unseenUpdateCount':
          snapshots.where((snapshot) => snapshot.hasUpdate).length,
      'deadlineCount': deadlines.length,
      'favoriteCount': favorites.length,
      'changeHistoryCount': changes.length,
      'cachedReportListCount': reportLists.length,
    };
    if (includeStoredData) {
      payload['currentUrl'] = _displayUrl(_currentPageUrl);
      payload['lastAllowedUrl'] = _displayUrl(_lastAllowedPageUrl);
      payload['backup'] = await _backupPayload();
      payload['failedDownloads'] =
          (await _downloadHistoryStore.loadFailedDownloads())
              .map((entry) => entry.toJson())
              .toList();
    }
    return payload;
  }

  Future<void> _handleDownloadMessage(String message) async {
    if (!_appSettings.isFeatureEnabled(GakujoFeatureFlag.downloadCapture)) {
      return;
    }
    late final GakujoDownloadRequest request;
    try {
      request = GakujoDownloadRequest.fromJsonText(message);
      if (kDebugMode) {
        debugPrint(
          'MoreBetterGakujo download candidate ${request.method} '
          '${_displayUrl(request.url)} as "${request.fileName}" '
          'course="${request.courseName}"',
        );
      }
    } on FormatException {
      _setStatus('保存エラー: ダウンロード情報を読めませんでした');
      _showSnackBar('ダウンロード情報を読めませんでした');
      return;
    }

    await _handleDownloadRequest(request);
  }

  void _handleLoginAutofillMessage(String message) {
    if (kDebugMode) {
      debugPrint('MoreBetterGakujo login autofill $message');
      developer.log(
        'Login autofill $message',
        name: 'MoreBetterGakujo',
      );
    }
  }

  Future<void> _handleDownloadRequest(
    GakujoDownloadRequest request, {
    String? retryEntryId,
  }) async {
    if (!AllowedWebOrigins.canLoad(
      request.url,
      debugAllowed: _debugAllowed,
    )) {
      _setStatus('ブロック: ${_displayUrl(request.url)}');
      _showSnackBar('Gakujo以外のダウンロードをブロックしました');
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
    if (kDebugMode) {
      debugPrint(
        'Download request course="${effectiveRequest.courseName}" '
        'file="${effectiveRequest.fileName}"',
      );
    }

    var root = _downloadRoot;
    if (_appSettings.downloadSaveMode.needsConfiguredRoot) {
      root = await _downloadService.getDownloadRoot();
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadRoot = root;
      });
    }
    if (_appSettings.downloadSaveMode.needsConfiguredRoot &&
        !root.isConfigured) {
      _showSnackBar('ダウンロード保存先を選択してください');
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
        cookieHeader: await _cookieHeader(effectiveRequest.url),
        sharePositionOrigin: _sharePositionOrigin(),
        saveMode: _appSettings.downloadSaveMode,
      );
      await _downloadHistoryStore.add(
        GakujoDownloadHistoryEntry(
          fileName: result.fileName,
          courseName: result.courseName.isEmpty
              ? effectiveRequest.courseName
              : result.courseName,
          savedAt: DateTime.now(),
          location: _nonEmptyOrNull(result.location),
        ),
      );
      if (retryEntryId != null) {
        await _downloadHistoryStore.removeFailedDownload(retryEntryId);
      }
      final savedPath = result.courseName.isEmpty
          ? result.fileName
          : '${result.courseName}/${result.fileName}';
      _setStatus('保存しました: $savedPath');
      _showDownloadSavedSnackBar(result);
    } on PlatformException catch (error) {
      final message = error.message ?? error.code;
      if (isCancelledDownloadError(error)) {
        _setStatus('保存をキャンセルしました');
        _showSnackBar(message);
        return;
      }
      await _downloadHistoryStore.addFailedDownload(
        request: effectiveRequest,
        errorMessage: message,
      );
      _setStatus('保存エラー: $message');
      _showSnackBar('保存できませんでした。失敗キューに追加しました: $message');
    }
  }

  Future<String?> _userAgent() async {
    final result = await _controller.runJavaScriptReturningResult(
      'navigator.userAgent',
    );
    return _stringFromJavaScriptResult(result);
  }

  Rect? _sharePositionOrigin() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  String? get _downloadDestinationHelperText {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return null;
    }
    return 'iCloud Drive はフォルダ指定と自動仕分けに対応します。Google Drive に保存する場合は「自動仕分けなし+適宜保存場所指定」を使います。';
  }

  Future<String?> _cookieHeader(String url) async {
    final cookieStoreHeader = await _controller.cookieHeaderForUrl(url);
    if (cookieStoreHeader != null && cookieStoreHeader.trim().isNotEmpty) {
      return cookieStoreHeader;
    }

    if (!_canRunPageScripts) {
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

  Future<AuthenticatedDownloadedFile> _downloadBytesWithWebViewSession(
    GakujoDownloadRequest request, {
    String? userAgent,
  }) async {
    if (!Platform.isWindows) {
      throw PlatformException(
        code: 'unsupported_platform',
        message: 'WebViewセッションでの取得はWindows専用です',
      );
    }
    if (!AllowedWebOrigins.canLoad(request.url, debugAllowed: false)) {
      throw PlatformException(
        code: 'blocked_url',
        message: 'Gakujo以外のダウンロードをブロックしました',
      );
    }

    final script = '''
(async function() {
  const inputUrl = ${jsonEncode(request.url)};
  const method = ${jsonEncode(request.method.toUpperCase() == 'POST' ? 'POST' : 'GET')};
  const fields = ${jsonEncode(request.formFields)};
  const url = new URL(inputUrl, window.location.href);
  const options = { method, credentials: 'include', redirect: 'follow' };
  if (method === 'GET') {
    Object.keys(fields || {}).forEach(function(key) {
      url.searchParams.set(key, String(fields[key]));
    });
  } else {
    const body = new URLSearchParams();
    Object.keys(fields || {}).forEach(function(key) {
      body.append(key, String(fields[key]));
    });
    options.body = body.toString();
    options.headers = {
      'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'
    };
  }
  const response = await fetch(url.toString(), options);
  const buffer = await response.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode.apply(
      null,
      bytes.subarray(i, i + chunkSize)
    );
  }
  return JSON.stringify({
    status: response.status,
    ok: response.ok,
    finalUrl: response.url,
    mimeType: response.headers.get('content-type') || '',
    contentDisposition: response.headers.get('content-disposition') || '',
    bodyBase64: btoa(binary)
  });
})()
''';

    final raw = _stringFromJavaScriptResult(
      await _controller.runJavaScriptReturningResult(script),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('WebView download result must be an object');
    }
    final status = int.tryParse(decoded['status']?.toString() ?? '') ?? 0;
    final finalUrl = decoded['finalUrl']?.toString() ?? request.url;
    if (!AllowedWebOrigins.canLoad(finalUrl, debugAllowed: false)) {
      throw PlatformException(
        code: 'blocked_url',
        message: 'Gakujo以外へのリダイレクトをブロックしました',
      );
    }
    if (status < 200 || status > 299 || decoded['ok'] != true) {
      throw PlatformException(
        code: 'download_failed',
        message: 'ダウンロードに失敗しました HTTP $status',
      );
    }
    return AuthenticatedDownloadedFile(
      bytes: base64Decode(decoded['bodyBase64']?.toString() ?? ''),
      finalUrl: finalUrl,
      mimeType: _mimeTypeFromContentType(decoded['mimeType']?.toString()),
      contentDispositionFileName:
          DownloadFileNamePolicy.fileNameFromContentDisposition(
        decoded['contentDisposition']?.toString(),
      ),
    );
  }

  String? _mimeTypeFromContentType(String? raw) {
    final value = raw?.split(';').first.trim().toLowerCase();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _injectDownloadCaptureIfAllowed() async {
    if (!_canRunPageScripts ||
        !_appSettings.isFeatureEnabled(GakujoFeatureFlag.downloadCapture)) {
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

  Future<void> _injectGpaDisplayIfAllowed() async {
    if (!_canRunPageScripts ||
        !_appSettings.isFeatureEnabled(GakujoFeatureFlag.gpaDisplay)) {
      return;
    }

    try {
      await _controller.runJavaScript(GakujoGpaDisplayScript.build());
    } catch (error, stackTrace) {
      developer.log(
        'Failed to inject GPA display script',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _injectOriginalExtensionFeaturesIfAllowed() async {
    if (!_canRunPageScripts) {
      return;
    }

    final scripts = [
      if (_appSettings.isFeatureEnabled(GakujoFeatureFlag.sessionExtender))
        GakujoSessionExtenderScript.build(),
      if (_appSettings.isFeatureEnabled(GakujoFeatureFlag.reportTools))
        GakujoReportSorterScript.build(),
      if (_appSettings.isFeatureEnabled(GakujoFeatureFlag.messageTools))
        GakujoMessageReaderScript.build(),
    ];
    for (final script in scripts) {
      try {
        await _controller.runJavaScript(script);
      } catch (error, stackTrace) {
        developer.log(
          'Failed to inject original extension feature script',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _injectMessageFilterIfAllowed() async {
    if (!_canRunPageScripts) {
      return;
    }

    try {
      await _controller.runJavaScript(
        GakujoMessageFilterScript.build(
          keywords: _appSettings.messageExcludeKeywords,
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to inject message filter script',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _injectReportDraftIfAllowed() async {
    if (!_canRunPageScripts) {
      return;
    }

    try {
      await _controller.runJavaScript(GakujoReportDraftScript.build());
    } catch (error, stackTrace) {
      developer.log(
        'Failed to inject report draft script',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _injectLoginAutofillAssistIfAllowed() async {
    if (!_canRunPageScripts) {
      return;
    }
    await _loadStoredLoginForAutofillIfNeeded();
    if (!_appSettings.isFeatureEnabled(GakujoFeatureFlag.loginAutofill)) {
      return;
    }

    try {
      final credentials = _appSettings.loginCredentials;
      if (kDebugMode) {
        debugPrint(
          'MoreBetterGakujo inject login autofill '
          'hasCredentials=${credentials?.isComplete ?? false}',
        );
        developer.log(
          'Inject login autofill url=${_displayUrl(_currentPageUrl)} '
          'hasCredentials=${credentials?.isComplete ?? false}',
          name: 'MoreBetterGakujo',
        );
      }
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

  Future<void> _loadStoredLoginForAutofillIfNeeded() async {
    if (_secureStorageAccessAllowed ||
        _loginAutofillStorageLoadAttempted ||
        !Platform.isMacOS) {
      return;
    }
    if (!AllowedWebOrigins.canAutofill(
      _currentPageUrl,
      debugAllowed: _debugAllowed,
    )) {
      return;
    }

    _loginAutofillStorageLoadAttempted = true;
    // #region DEBUG
    _appendCalendarDebugLog('[DEBUG H11] loginAutofillStorageLoad start');
    // #endregion DEBUG
    final loaded = await _loadAppSettings(allowMacosKeychainPrompt: true);
    // #region DEBUG
    _appendCalendarDebugLog('[DEBUG H11] loginAutofillStorageLoad=$loaded');
    // #endregion DEBUG
  }

  Future<void> _injectTwoFactorAutofillIfAllowed() async {
    if (!_appSettings.isFeatureEnabled(GakujoFeatureFlag.twoFactorAutofill)) {
      return;
    }
    if (!AllowedWebOrigins.canAutofill(
      _currentPageUrl,
      debugAllowed: _debugAllowed,
    )) {
      return;
    }

    try {
      final secret = await _secretStore.load();
      if (secret == null) {
        return;
      }

      final token = _totpGenerator.currentToken(secret);
      final script = TwoFactorAutofillScript.build(token: token);
      await _controller.runJavaScript(script);
    } catch (error, stackTrace) {
      developer.log(
        'Failed to inject two-factor autofill script',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadInitialPage() async {
    // #region DEBUG
    _appendCalendarDebugLog('[DEBUG H11] loadInitialPage enter');
    // #endregion DEBUG
    await _webViewReady;
    // #region DEBUG
    _appendCalendarDebugLog('[DEBUG H11] webViewReady complete');
    // #endregion DEBUG
    await _webViewService.configureController(
      _controller,
      debugAllowed: _debugAllowed,
    );
    // #region DEBUG
    _appendCalendarDebugLog('[DEBUG H11] configureController complete');
    // #endregion DEBUG
    unawaited(_saveInitialTwoFactorSecretIfAllowed());
    final appSettingsLoaded = await _loadAppSettings();
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H11] appSettingsLoaded=$appSettingsLoaded '
      'setupCompleted=${_appSettings.setupCompleted} '
      'hasLogin=${_appSettings.hasLoginCredentials}',
    );
    // #endregion DEBUG
    if (appSettingsLoaded && !_appSettings.setupCompleted && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_showInitialSetupWizard());
        }
      });
    }
    final savedUrl = appSettingsLoaded
        ? await _lastPageStore.load(debugAllowed: _debugAllowed)
        : null;
    if (_appSettings.hasLoginCredentials && savedUrl != null) {
      _pendingLoginRestoreUrl = savedUrl;
    }
    final startUrl = _resolveStartUrl(
      _appSettings.hasLoginCredentials ? null : savedUrl,
    );
    // #region DEBUG
    _appendCalendarDebugLog(
      '[DEBUG H11] loadInitialPage startUrl=${_calendarDebugUrl(startUrl)} '
      'saved=${_calendarDebugUrl(savedUrl)}',
    );
    // #endregion DEBUG
    await _controller.loadUrl(startUrl);
    // #region DEBUG
    _appendCalendarDebugLog('[DEBUG H11] loadUrl invoked');
    // #endregion DEBUG
  }

  Future<void> _configureWebViewController() async {
    await _controller.setJavaScriptModeUnrestricted();
    await _controller.addJavaScriptChannel(
      GakujoDownloadCaptureScript.channelName,
      onMessageReceived: _handleDownloadMessage,
    );
    await _controller.addJavaScriptChannel(
      LoginAutofillAssistScript.channelName,
      onMessageReceived: _handleLoginAutofillMessage,
    );
    await _controller.setNavigationDelegate(
      GakujoNavigationDelegate(
        onNavigationRequest: _handleNavigationRequest,
        onPageStarted: (url) {
          // #region DEBUG
          _appendCalendarDebugLog(
            '[DEBUG H11] onPageStarted ${_calendarDebugUrl(url)}',
          );
          // #endregion DEBUG
          if (_isInternalBlankUrl(url)) {
            return;
          }
          _currentPageUrl = url;
          if (AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
            _lastAllowedPageUrl = url;
            if (!_looksLikeLoginOrTimeoutUrl(url)) {
              _sessionRecoveryUrl = url;
              _lastSessionRecoveryNoticeUrl = null;
            }
          }
          unawaited(_refreshNavigationState());
          _setStatus('読込中: ${_displayUrl(url)}');
        },
        onPageFinished: (url) async {
          // #region DEBUG
          _appendCalendarDebugLog(
            '[DEBUG H11] onPageFinished ${_calendarDebugUrl(url)}',
          );
          // #endregion DEBUG
          _notifyPageFinishedWaiters(url);
          if (_isInternalBlankUrl(url)) {
            await _injectDownloadCaptureIfAllowed();
            await _injectGpaDisplayIfAllowed();
            await _injectOriginalExtensionFeaturesIfAllowed();
            await _injectMessageFilterIfAllowed();
            await _injectReportDraftIfAllowed();
            await _applyDesktopZoomIfAllowed();
            return;
          }
          _currentPageUrl = url;
          if (AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
            _lastAllowedPageUrl = url;
            if (!_looksLikeLoginOrTimeoutUrl(url)) {
              _sessionRecoveryUrl = url;
              _lastSessionRecoveryNoticeUrl = null;
            }
          }
          _setStatus('表示中: ${_displayUrl(url)}');
          await _saveLastPageUrl(url);
          await _refreshNavigationState();
          await _injectLoginAutofillAssistIfAllowed();
          await _injectTwoFactorAutofillIfAllowed();
          await _injectDownloadCaptureIfAllowed();
          await _injectGpaDisplayIfAllowed();
          await _injectOriginalExtensionFeaturesIfAllowed();
          await _injectMessageFilterIfAllowed();
          await _injectReportDraftIfAllowed();
          await _applyDesktopZoomIfAllowed();
          await _refreshEstimatedCourseName();
          await _handleSessionExpiredIfNeeded(url);
          await _scanCurrentPageActivity(url);
          await _restoreLastPageAfterLoginIfNeeded(url);
        },
        onWebResourceError: (error) {
          // #region DEBUG
          _appendCalendarDebugLog(
            '[DEBUG H11] onWebResourceError ${error.description}',
          );
          // #endregion DEBUG
          _setStatus('読込エラー: ${error.description}');
        },
      ),
    );
  }

  Future<bool> _loadAppSettings({bool allowMacosKeychainPrompt = false}) async {
    if (Platform.isMacOS && !allowMacosKeychainPrompt) {
      // Unsigned development builds can trigger a macOS Keychain prompt on
      // every launch. Keep startup usable and only touch Keychain after an
      // explicit user action such as retrying storage access or saving login
      // settings.
      setState(() {
        _appSettings = const GakujoAppSettings(
          disabledFeatureFlags: {
            GakujoFeatureFlag.twoFactorAutofill,
          },
        );
        _appSettingsLoaded = true;
      });
      return false;
    }

    try {
      // #region DEBUG
      _appendCalendarDebugLog('[DEBUG H11] loadAppSettings start');
      // #endregion DEBUG
      final settings = allowMacosKeychainPrompt
          ? await _appSettingsStore.load()
          : await _appSettingsStore.load().timeout(const Duration(seconds: 3));
      // #region DEBUG
      _appendCalendarDebugLog('[DEBUG H11] loadAppSettings success');
      // #endregion DEBUG
      if (!mounted) {
        return true;
      }

      _secureStorageAccessAllowed = true;
      setState(() {
        _appSettings = settings;
        _appSettingsLoaded = true;
      });
      await _loadDownloadRoot();
      unawaited(_compactStoredData());
      _scheduleAutoBackup();
      return true;
    } on Object catch (error, stackTrace) {
      // #region DEBUG
      _appendCalendarDebugLog('[DEBUG H11] loadAppSettings failed=$error');
      // #endregion DEBUG
      developer.log(
        'Failed to load app settings from secure storage',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return false;
      }

      final fallbackSettings = error is TimeoutException
          ? const GakujoAppSettings(
              disabledFeatureFlags: {
                GakujoFeatureFlag.loginAutofill,
                GakujoFeatureFlag.twoFactorAutofill,
              },
            )
          : const GakujoAppSettings();
      setState(() {
        _appSettings = fallbackSettings;
        _appSettingsLoaded = true;
      });
      _setStatus('キーチェーンにアクセスできません');
      if (error is! TimeoutException) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_showSecureStorageRecoveryDialog(error));
          }
        });
      }
      return false;
    }
  }

  Future<void> _retrySecureStorageLoad() async {
    SecureStorageFactory.resetMacosCache();
    _secureStorageAccessAllowed = true;
    await _loadAppSettings(allowMacosKeychainPrompt: true);
    await _injectLoginAutofillAssistIfAllowed();
    await _injectTwoFactorAutofillIfAllowed();
  }

  Future<void> _showSecureStorageRecoveryDialog(Object error) async {
    if (_secureStorageRecoveryDialogVisible || !mounted) {
      return;
    }

    _secureStorageRecoveryDialogVisible = true;
    final action = await showDialog<_SecureStorageRecoveryAction>(
      context: context,
      builder: (context) {
        final details = error is PlatformException
            ? (error.message ?? error.code)
            : error.toString();
        return AlertDialog(
          title: const Text('キーチェーンにアクセスできません'),
          content: Text(
            '保存済みログイン情報や2FA設定を読み込めませんでした。\n\n'
            '先にすべて拒否した場合でも、このバージョンでは新しい保存領域を使って復旧できます。'
            'まず「保存データをリセット」を実行し、ログイン情報と2FA設定を入れ直してください。'
            '旧保存領域は起動時に自動で読みに行かないため、許可待ちで固まることはありません。\n\n'
            '詳細: $details',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                _SecureStorageRecoveryAction.continueWithoutStorage,
              ),
              child: const Text('このまま使う'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                _SecureStorageRecoveryAction.reset,
              ),
              child: const Text('保存データをリセット'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _SecureStorageRecoveryAction.retry,
              ),
              child: const Text('再試行'),
            ),
          ],
        );
      },
    );
    _secureStorageRecoveryDialogVisible = false;

    if (action == _SecureStorageRecoveryAction.retry && mounted) {
      await _retrySecureStorageLoad();
    } else if (action == _SecureStorageRecoveryAction.reset && mounted) {
      await _resetSecureStorageAfterConfirmation();
    }
  }

  Future<void> _resetSecureStorageAfterConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('保存データをリセットしますか'),
          content: const Text(
            'Keychain に保存したログイン情報、2FA秘密鍵、設定、履歴データを削除します。'
            '削除後はログイン情報と2FA設定を入れ直してください。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('リセット'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await SecureStorageFactory.resetMacosStorage();
      if (!mounted) {
        return;
      }
      setState(() {
        _appSettings = const GakujoAppSettings();
        _appSettingsLoaded = true;
        _deadlineCount = 0;
      });
      _setStatus('キーチェーン保存データをリセットしました');
      _showSnackBar('保存データをリセットしました。ログイン情報と2FA設定を入れ直してください');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to reset secure storage',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showSnackBar('キーチェーンをリセットできませんでした: $error');
      }
    }
  }

  Future<void> _saveInitialTwoFactorSecretIfAllowed() async {
    final secret = widget._initialTwoFactorSecret;
    if (!_debugAllowed || secret == null || secret.isEmpty) {
      return;
    }

    try {
      await _secretStore.save(secret).timeout(const Duration(seconds: 3));
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to save initial two-factor secret',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      // #region DEBUG
      _appendCalendarDebugLog(
        '[DEBUG H11] initialTwoFactorSecretSaveFailed=$error',
      );
      // #endregion DEBUG
    }
  }

  String _resolveStartUrl(String? savedUrl) {
    return GakujoStartUrlResolver.resolve(
      debugAllowed: _debugAllowed,
      debugStartUrl: widget._startUrl,
      savedUrl: savedUrl,
      fallbackUrl: _appSettings.pageMode.startUrl,
    );
  }

  Future<void> _restoreLastPageAfterLoginIfNeeded(String currentUrl) async {
    final restoreUrl = _pendingLoginRestoreUrl;
    if (_loginRestoreAttempted ||
        restoreUrl == null ||
        restoreUrl == currentUrl ||
        _looksLikeLoginOrTimeoutUrl(currentUrl) ||
        !AllowedWebOrigins.canLoad(restoreUrl, debugAllowed: _debugAllowed) ||
        !AllowedWebOrigins.canLoad(currentUrl, debugAllowed: _debugAllowed)) {
      return;
    }

    _loginRestoreAttempted = true;
    _pendingLoginRestoreUrl = null;
    _setStatus('前回のページに戻ります: ${_displayUrl(restoreUrl)}');
    await _controller.loadUrl(restoreUrl);
  }

  Future<void> _handleSystemBack() async {
    if (await _goBackIfPossible()) {
      return;
    }

    if (!mounted) {
      return;
    }
    _showSnackBar('前のページはありません');
  }

  Future<void> _goBack() async {
    if (!await _goBackIfPossible() && mounted) {
      _showSnackBar('前のページはありません');
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
    await _goForwardIfPossible();
    await _refreshNavigationState();
  }

  Future<bool> _goForwardIfPossible() async {
    if (!await _controller.canGoForward()) {
      await _refreshNavigationState();
      return false;
    }

    await _controller.goForward();
    await _refreshNavigationState();
    return true;
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
    if (_isInternalBlankUrl(url)) {
      return;
    }
    if (!_secureStorageAccessAllowed) {
      return;
    }
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

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showDownloadSavedSnackBar(GakujoDownloadResult result) {
    if (!mounted) {
      return;
    }

    final location = _nonEmptyOrNull(result.location);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('保存しました: ${result.fileName}'),
        action: location == null
            ? null
            : SnackBarAction(
                label: '開く',
                onPressed: () => unawaited(_openSavedDownload(location)),
              ),
      ),
    );
  }

  Future<void> _openSavedDownload(String location) async {
    final uri = savedDownloadLocationUri(location);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showSnackBar('ファイルを開けませんでした');
    }
  }

  bool get _canRunPageScripts {
    if (AllowedWebOrigins.canLoad(
      _currentPageUrl,
      debugAllowed: _debugAllowed,
    )) {
      return true;
    }
    if (!_isInternalBlankUrl(_currentPageUrl)) {
      return false;
    }
    return AllowedWebOrigins.canLoad(
      _lastAllowedPageUrl,
      debugAllowed: _debugAllowed,
    );
  }

  bool _isInternalBlankUrl(String? url) {
    return (url ?? '').trim().toLowerCase() == 'about:blank';
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

  String? _nonEmptyOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)}';
  }

  String _calendarRangeLabel(GakujoCalendarTermRange termRange) {
    return '${_formatDate(termRange.start)}〜${_formatDate(termRange.end)}';
  }

  String _downloadRootLabel(DownloadDestinationSettings root) {
    return downloadRootLabel(root, includePath: true);
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

  bool _boolFromJavaScriptResult(Object? result) {
    return javaScriptResultAsBool(result);
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
      if (kDebugMode) {
        debugPrint(
          'MoreBetterGakujo course estimate body="$estimated" '
          'candidates="${candidates.take(3).join(' / ')}"',
        );
      }
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
      if (kDebugMode) {
        debugPrint(
          'MoreBetterGakujo course estimate table="$estimated" '
          'raw="$rawEstimate"',
        );
      }
      return estimated;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('MoreBetterGakujo course estimate table failed: $error');
      }
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
          iconSize: _toolbarIconSize,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(
            width: _toolbarButtonExtent,
            height: _toolbarButtonExtent,
          ),
        ),
        IconButton(
          tooltip: '次のページ',
          onPressed: canGoForward ? onForward : null,
          icon: const Icon(Icons.arrow_forward),
          iconSize: _toolbarIconSize,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(
            width: _toolbarButtonExtent,
            height: _toolbarButtonExtent,
          ),
        ),
      ],
    );
  }
}

class GakujoZoomActions extends StatelessWidget {
  const GakujoZoomActions({
    super.key,
    required this.zoomPercent,
    required this.canZoomOut,
    required this.canZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
  });

  final int zoomPercent;
  final bool canZoomOut;
  final bool canZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '縮小',
          onPressed: canZoomOut ? onZoomOut : null,
          icon: const Icon(Icons.remove),
          iconSize: _toolbarIconSize,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(
            width: _toolbarButtonExtent,
            height: _toolbarButtonExtent,
          ),
        ),
        TextButton(
          onPressed: onReset,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            fixedSize: const Size(_zoomResetButtonWidth, _toolbarButtonExtent),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            '$zoomPercent%',
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ),
        IconButton(
          tooltip: '拡大',
          onPressed: canZoomIn ? onZoomIn : null,
          icon: const Icon(Icons.add),
          iconSize: _toolbarIconSize,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(
            width: _toolbarButtonExtent,
            height: _toolbarButtonExtent,
          ),
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

    return AutofillGroup(
      child: Column(
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
            autofillHints: const [
              AutofillHints.username,
              AutofillHints.email,
            ],
            keyboardType: TextInputType.emailAddress,
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
            autofillHints: const [AutofillHints.password],
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
      ),
    );
  }
}

class DownloadDestinationSection extends StatelessWidget {
  const DownloadDestinationSection({
    super.key,
    required this.rootLabel,
    required this.isConfigured,
    required this.saveMode,
    required this.helperText,
    required this.onSaveModeChanged,
    required this.onPick,
    required this.onClear,
  });

  final String rootLabel;
  final bool isConfigured;
  final DownloadSaveMode saveMode;
  final String? helperText;
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
        SettingsRadioGroup<DownloadSaveMode>(
          groupValue: saveMode,
          values: DownloadSaveMode.values,
          labelFor: (mode) => mode.label,
          onChanged: onSaveModeChanged,
          decoration: const InputDecoration(
            labelText: 'ファイル保存モード',
            border: OutlineInputBorder(),
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
        if (helperText != null) ...[
          const SizedBox(height: 8),
          Text(
            helperText!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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

class SettingsRadioGroup<T> extends StatelessWidget {
  const SettingsRadioGroup({
    super.key,
    required this.groupValue,
    required this.values,
    required this.labelFor,
    required this.onChanged,
    required this.decoration,
  });

  final T groupValue;
  final Iterable<T> values;
  final String Function(T value) labelFor;
  final ValueChanged<T?> onChanged;
  final InputDecoration decoration;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: decoration,
      child: RadioGroup<T>(
        groupValue: groupValue,
        onChanged: onChanged,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final value in values)
              RadioListTile<T>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: value,
                title: Text(labelFor(value)),
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsExpansionSection extends StatelessWidget {
  const SettingsExpansionSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      initiallyExpanded: initiallyExpanded,
      maintainState: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [child],
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
        SettingsRadioGroup<GakujoPageMode>(
          groupValue: pageMode,
          values: GakujoPageMode.values,
          labelFor: (mode) => mode.label,
          onChanged: onChanged,
          decoration: const InputDecoration(
            labelText: '開く画面',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class FeatureFlagsSection extends StatelessWidget {
  const FeatureFlagsSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final GakujoAppSettings settings;
  final void Function(GakujoFeatureFlag flag, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '機能のオン/オフ',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final flag in GakujoFeatureFlag.values)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(flag.label),
            value: settings.isFeatureEnabled(flag),
            onChanged: (value) => onChanged(flag, value ?? true),
          ),
      ],
    );
  }
}

class MessageExcludeKeywordsSection extends StatelessWidget {
  const MessageExcludeKeywordsSection({
    super.key,
    required this.keywords,
    required this.controller,
    required this.canAdd,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> keywords;
  final TextEditingController controller;
  final bool canAdd;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onAdd;
  final Future<void> Function(String keyword) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '連絡通知の除外キーワード',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          '連絡通知タブの通知一覧で、タイトルや行の文字に含まれるキーワードを非表示にします。',
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'キーワード',
                  hintText: '例: アンケート',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onChanged: onChanged,
                onSubmitted: canAdd
                    ? (_) {
                        unawaited(onAdd());
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: canAdd ? () => unawaited(onAdd()) : null,
              icon: const Icon(Icons.add),
              label: const Text('追加'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (keywords.isEmpty)
          const Text('除外キーワードは未設定です。')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in keywords)
                InputChip(
                  label: Text(keyword),
                  onDeleted: () => unawaited(onRemove(keyword)),
                ),
            ],
          ),
      ],
    );
  }
}

class AppMaintenanceSection extends StatelessWidget {
  const AppMaintenanceSection({
    super.key,
    required this.onCheckUpdates,
    required this.onCreateBackup,
    required this.onCreateErrorReport,
    required this.onExportSettings,
    required this.onImportSettings,
    required this.onCheckDownloadDestination,
    required this.onCopyDiagnostics,
  });

  final Future<void> Function() onCheckUpdates;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onCreateErrorReport;
  final Future<void> Function() onExportSettings;
  final Future<void> Function() onImportSettings;
  final Future<void> Function() onCheckDownloadDestination;
  final Future<void> Function() onCopyDiagnostics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'バックアップと診断',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          '設定、履歴、お気に入り、課題キャッシュをコピーします。ログイン情報と2FA秘密鍵は含めません。',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => unawaited(onCheckUpdates()),
              icon: const Icon(Icons.system_update_alt),
              label: const Text('更新を確認'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onCreateBackup()),
              icon: const Icon(Icons.backup_outlined),
              label: const Text('バックアップ作成'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onExportSettings()),
              icon: const Icon(Icons.upload_file),
              label: const Text('設定をコピー'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onImportSettings()),
              icon: const Icon(Icons.download),
              label: const Text('設定を読み込み'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onCheckDownloadDestination()),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('保存先を確認'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onCreateErrorReport()),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('エラー報告パッケージ作成'),
            ),
            TextButton.icon(
              onPressed: () => unawaited(onCopyDiagnostics()),
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('診断情報をコピー'),
            ),
          ],
        ),
      ],
    );
  }
}

class AppDataShortcutsSection extends StatelessWidget {
  const AppDataShortcutsSection({
    super.key,
    required this.onShowDownloadHistory,
    required this.onShowFailedDownloads,
    required this.onShowCourseMaterials,
    required this.onShowCachedReports,
    required this.onShowChangeHistory,
    required this.onShowFavorites,
    required this.onShowDataManagement,
  });

  final Future<void> Function() onShowDownloadHistory;
  final Future<void> Function() onShowFailedDownloads;
  final Future<void> Function() onShowCourseMaterials;
  final Future<void> Function() onShowCachedReports;
  final Future<void> Function() onShowChangeHistory;
  final Future<void> Function() onShowFavorites;
  final Future<void> Function() onShowDataManagement;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'データと履歴',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text('保存済みデータ、履歴、一覧キャッシュを確認します。'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowDownloadHistory()),
              icon: const Icon(Icons.history),
              label: const Text('ダウンロード履歴'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowFailedDownloads()),
              icon: const Icon(Icons.error_outline),
              label: const Text('失敗したダウンロード'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowCourseMaterials()),
              icon: const Icon(Icons.folder_copy_outlined),
              label: const Text('授業ごとの資料'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowCachedReports()),
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('保存済み課題一覧'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowChangeHistory()),
              icon: const Icon(Icons.manage_history),
              label: const Text('変更履歴'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowFavorites()),
              icon: const Icon(Icons.star_border),
              label: const Text('お気に入り'),
            ),
            OutlinedButton.icon(
              onPressed: () => unawaited(onShowDataManagement()),
              icon: const Icon(Icons.storage_outlined),
              label: const Text('データ管理'),
            ),
          ],
        ),
      ],
    );
  }
}

class AppIntegrationSection extends StatelessWidget {
  const AppIntegrationSection({
    super.key,
    required this.onScheduleIntegration,
  });

  final Future<void> Function() onScheduleIntegration;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '外部連携',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        const Text('Gakujoの情報を外部アプリと連携します。'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => unawaited(onScheduleIntegration()),
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('スケジュール連携'),
          ),
        ),
      ],
    );
  }
}

class _AmbiguousCalendarCourseTermSelector extends StatelessWidget {
  const _AmbiguousCalendarCourseTermSelector({
    required this.course,
    required this.selectedTerms,
    required this.onChanged,
  });

  final GakujoCalendarCourse course;
  final Set<int> selectedTerms;
  final void Function(int term, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final title = GakujoCalendarExport.displayTitleForCourse(course);
    final details = [
      if (course.courseCode.trim().isNotEmpty) '開講番号: ${course.courseCode}',
      '${_weekdayLabel(course.weekday)}曜 ${course.period}限',
      if (GakujoCalendarExport.displayLocationForCourse(course).isNotEmpty)
        GakujoCalendarExport.displayLocationForCourse(course),
    ].join(' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(details),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var term = 1; term <= 4; term += 1)
              FilterChip(
                label: Text('第$termターム'),
                selected: selectedTerms.contains(term),
                onSelected: (selected) => onChanged(term, selected),
              ),
          ],
        ),
      ],
    );
  }

  static String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => '月',
      DateTime.tuesday => '火',
      DateTime.wednesday => '水',
      DateTime.thursday => '木',
      DateTime.friday => '金',
      DateTime.saturday => '土',
      DateTime.sunday => '日',
      _ => '曜日未定',
    };
  }
}

class _DataCountTile extends StatelessWidget {
  const _DataCountTile({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text('$count件'),
    );
  }
}

class _PageTextSnapshot {
  const _PageTextSnapshot({
    required this.title,
    required this.text,
    required this.messageItems,
  });

  final String title;
  final String text;
  final List<_MessageActivityCandidate> messageItems;
}

class _MessageActivityCandidate {
  const _MessageActivityCandidate({
    required this.title,
    required this.url,
    required this.text,
  });

  final String title;
  final String url;
  final String text;

  factory _MessageActivityCandidate.fromJson(Map<dynamic, dynamic> json) {
    return _MessageActivityCandidate(
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
    );
  }
}

class _ActivityScanResult {
  const _ActivityScanResult({
    required this.updateCount,
    required this.deadlineCount,
  });

  final int updateCount;
  final int deadlineCount;
}

class _ResolvedCalendarTerm {
  const _ResolvedCalendarTerm({
    required this.termRange,
    required this.uidNamespace,
    required this.label,
    required this.termName,
  });

  final GakujoCalendarTermRange termRange;
  final String uidNamespace;
  final String label;
  final String? termName;
}

class _ScheduleIntegrationDialogResult {
  const _ScheduleIntegrationDialogResult({
    required this.action,
    required this.settings,
  });

  final _ScheduleIntegrationAction action;
  final GakujoCalendarImportSettings settings;
}

class _OfficialGoogleScheduleIntegration {
  const _OfficialGoogleScheduleIntegration({
    required this.status,
    required this.url,
    required this.label,
    required this.diagnostics,
  });

  const _OfficialGoogleScheduleIntegration.notFound()
      : status = 'not_found',
        url = '',
        label = '',
        diagnostics = const {};

  final String status;
  final String url;
  final String label;
  final Map<String, Object?> diagnostics;

  factory _OfficialGoogleScheduleIntegration.fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<dynamic, dynamic>) {
        final rawDiagnostics = decoded['diagnostics'];
        return _OfficialGoogleScheduleIntegration(
          status: decoded['status']?.toString() ?? 'not_found',
          url: decoded['url']?.toString() ?? '',
          label: decoded['label']?.toString() ?? '',
          diagnostics: rawDiagnostics is Map<dynamic, dynamic>
              ? rawDiagnostics.map(
                  (key, value) => MapEntry(key.toString(), value),
                )
              : const {},
        );
      }
    } on FormatException {
      // Fall through to not_found.
    }
    return const _OfficialGoogleScheduleIntegration.notFound();
  }
}

class _OfficialScheduleExportFetch {
  const _OfficialScheduleExportFetch({
    required this.status,
    required this.httpStatus,
    required this.url,
    required this.contentType,
    required this.text,
    required this.diagnostics,
  });

  const _OfficialScheduleExportFetch.notFound()
      : status = 'not_found',
        httpStatus = 0,
        url = '',
        contentType = '',
        text = '',
        diagnostics = const {};

  final String status;
  final int httpStatus;
  final String url;
  final String contentType;
  final String text;
  final Map<String, Object?> diagnostics;

  int get textLength => text.length;

  factory _OfficialScheduleExportFetch.fromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<dynamic, dynamic>) {
        final rawDiagnostics = decoded['diagnostics'];
        return _OfficialScheduleExportFetch(
          status: decoded['status']?.toString() ?? 'not_found',
          httpStatus:
              int.tryParse(decoded['httpStatus']?.toString() ?? '') ?? 0,
          url: decoded['url']?.toString() ?? '',
          contentType: decoded['contentType']?.toString() ?? '',
          text: decoded['text']?.toString() ?? '',
          diagnostics: rawDiagnostics is Map<dynamic, dynamic>
              ? rawDiagnostics.map(
                  (key, value) => MapEntry(key.toString(), value),
                )
              : const {},
        );
      }
    } on FormatException {
      // Fall through to not_found.
    }
    return const _OfficialScheduleExportFetch.notFound();
  }
}
