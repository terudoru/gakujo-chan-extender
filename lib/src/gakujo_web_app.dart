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
import 'gakujo_backup_export.dart';
import 'gakujo_backup_import.dart';
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
import 'gakujo_local_prefs_store.dart';
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
import 'widgets/app_data_sections.dart';
import 'widgets/gakujo_toolbar_actions.dart';
import 'widgets/settings_sections.dart';

export 'widgets/app_data_sections.dart';
export 'widgets/gakujo_toolbar_actions.dart';
export 'widgets/settings_sections.dart';

part 'widgets/gakujo_web_app_private_widgets.dart';
part 'gakujo_web_app_calendar.dart';
part 'gakujo_web_app_diagnostics.dart';
part 'gakujo_web_app_downloads.dart';
part 'gakujo_web_app_models.dart';

extension GakujoQuickJumpDestinationLabels on GakujoQuickJumpDestination {
  String get label {
    return switch (this) {
      GakujoQuickJumpDestination.grades => '成績',
      GakujoQuickJumpDestination.reports => 'レポート',
      GakujoQuickJumpDestination.messages => '連絡通知',
      GakujoQuickJumpDestination.downloads => 'ダウンロード',
      GakujoQuickJumpDestination.syllabus => 'シラバス',
      GakujoQuickJumpDestination.schedule => 'スケジュール',
    };
  }
}

const _calendarValidationTitle = 'More Better Gakujo 検証';
const _calendarValidationUidNamespace = 'calendar-validation';
const _schedulePortalUrl =
    'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=sch';
const _compactToolbarHeight = 40.0;
const _toolbarButtonExtent = 40.0;
const _toolbarIconSize = 20.0;

@visibleForTesting
DateTime? parseCalendarDate(String raw) {
  final match = RegExp(
    r'^\s*((?:20)?[0-9]{2})[/-]([0-9]{1,2})[/-]([0-9]{1,2})\s*$',
  ).firstMatch(raw);
  if (match == null) {
    return null;
  }
  final rawYear = int.tryParse(match.group(1) ?? '');
  final month = int.tryParse(match.group(2) ?? '');
  final day = int.tryParse(match.group(3) ?? '');
  if (rawYear == null ||
      month == null ||
      day == null ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31) {
    return null;
  }
  final year = rawYear < 100 ? rawYear + 2000 : rawYear;
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

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

@visibleForTesting
bool isLikelyMacosKeychainUserDeniedError(Object error) {
  if (error is! PlatformException) {
    return false;
  }
  final haystack = [
    error.code,
    error.message,
    error.details?.toString(),
  ].whereType<String>().join(' ').toLowerCase();
  return haystack.contains('usercanceled') ||
      haystack.contains('user canceled') ||
      haystack.contains('usercancelled') ||
      haystack.contains('user cancelled') ||
      haystack.contains('authfailed') ||
      haystack.contains('auth failed') ||
      haystack.contains('-128') ||
      haystack.contains('-25293') ||
      haystack.contains('errsecusercanceled') ||
      haystack.contains('errsecauthfailed');
}

@visibleForTesting
bool isMissingKeychainEntitlementError(Object error) {
  if (error is! PlatformException) {
    return false;
  }
  final haystack = [
    error.code,
    error.message,
    error.details?.toString(),
  ].whereType<String>().join(' ').toLowerCase();
  return haystack.contains('-34018') ||
      haystack.contains('required entitlement') ||
      haystack.contains('missing entitlement');
}

@visibleForTesting
String secureStorageRecoveryGuidance(
  Object error, {
  required TargetPlatform platform,
}) {
  if (isMissingKeychainEntitlementError(error)) {
    return 'このアプリに必要なキーチェーン権限がありません。'
        'アプリを最新版へ更新してから、もう一度起動してください。';
  }
  if (platform == TargetPlatform.iOS) {
    return '一時的な失敗なら「再試行」で読み込み直せます。\n\n'
        '再試行しても復旧しない場合はアプリを最新版へ更新してください。'
        '保存領域の破損が疑われる場合に限り「保存データをリセット」を使用してください。'
        'その場合はログイン情報と2FA設定の再入力が必要です。';
  }

  final userDenied = isLikelyMacosKeychainUserDeniedError(error);
  if (platform == TargetPlatform.macOS && userDenied) {
    return 'macOS が拒否を記憶している場合、「再試行」だけでは許可ダイアログが再表示されません。\n\n'
        'データを残して復旧するには、キーチェーンアクセス.app を開き、'
        'ログインキーチェーン内の More Better Gakujo / '
        'net.yoshida.morebettergakujoFlutter.secure_storage.v2 に関連する項目を探して、'
        'アクセス制御でこのアプリを許可してから「再試行」してください。\n\n'
        '項目が見つからない、または許可できない場合は「保存データをリセット」で保存領域を作り直せます。'
        'その場合はログイン情報と2FA設定の再入力が必要です。';
  }
  if (platform == TargetPlatform.macOS) {
    return '一時的な失敗なら「再試行」で読み込み直せます。\n\n'
        '以前に許可ダイアログを拒否した場合は、キーチェーンアクセス.app でこのアプリのアクセスを許可してから'
        '再試行してください。それでも不可なら「保存データをリセット」で保存領域を作り直せます。'
        'その場合はログイン情報と2FA設定の再入力が必要です。';
  }
  return '一時的な失敗なら「再試行」で読み込み直せます。\n\n'
      'それでも不可なら「保存データをリセット」で保存領域を作り直せます。'
      'その場合はログイン情報と2FA設定の再入力が必要です。';
}

class GakujoWebApp extends StatefulWidget {
  const GakujoWebApp({
    super.key,
    TwoFactorSecretStore? secretStore,
    TotpGenerator? totpGenerator,
    GakujoLastPageStore? lastPageStore,
    GakujoAppSettingsStore? appSettingsStore,
    GakujoLocalPrefsStore? localPrefsStore,
    String? startUrl,
    String? initialTwoFactorSecret,
    bool? debugAllowed,
  })  : _secretStore = secretStore,
        _totpGenerator = totpGenerator,
        _lastPageStore = lastPageStore,
        _appSettingsStore = appSettingsStore,
        _localPrefsStore = localPrefsStore,
        _startUrl = startUrl,
        _initialTwoFactorSecret = initialTwoFactorSecret,
        _debugAllowed = debugAllowed;

  final TwoFactorSecretStore? _secretStore;
  final TotpGenerator? _totpGenerator;
  final GakujoLastPageStore? _lastPageStore;
  final GakujoAppSettingsStore? _appSettingsStore;
  final GakujoLocalPrefsStore? _localPrefsStore;
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
bool get activityBellToolbarButtonEnabled => true;

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
  late final GakujoLocalPrefsStore _localPrefsStore;
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
    _localPrefsStore = widget._localPrefsStore ?? GakujoLocalPrefsStore();
    _debugAllowed = widget._debugAllowed ?? kDebugMode;

    _controller = _webViewService.createController();
    _downloadService = Platform.isWindows
        ? FileSystemGakujoDownloadService(
            authenticatedBytesLoader: _downloadBytesWithWebViewSession,
          )
        : platformService.createDownloadService();
    _webViewReady = _configureWebViewController();

    if (_secureStorageAccessAllowed) {
      unawaited(_loadDownloadRoot());
      unawaited(_compactStoredData());
    }
    if (_secureStorageAccessAllowed && activityBellToolbarButtonEnabled) {
      unawaited(_refreshActivityCounts());
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
              child: PopupMenuButton<Object>(
                tooltip: 'メニュー',
                padding: EdgeInsets.zero,
                iconSize: _toolbarIconSize,
                icon: const Icon(Icons.more_vert),
                itemBuilder: (context) => [
                  for (final destination in GakujoQuickJumpDestination.values)
                    PopupMenuItem<Object>(
                      value: destination,
                      child: Text('${destination.label}へ移動'),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<Object>(
                    value: _ToolbarAction.addFavorite,
                    child: Text('お気に入りに追加'),
                  ),
                  const PopupMenuItem<Object>(
                    value: _ToolbarAction.copyUrl,
                    child: Text('URLをコピー'),
                  ),
                  const PopupMenuItem<Object>(
                    value: _ToolbarAction.openExternal,
                    child: Text('外部ブラウザで開く'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<Object>(
                    value: _ToolbarAction.reload,
                    child: Text('再読込'),
                  ),
                ],
                onSelected: (selection) =>
                    unawaited(_handleToolbarSelection(selection)),
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
                      final nextSettings = _appSettings.copyWith(
                        downloadSaveMode: mode,
                      );
                      await _syncLocalSettingsMirror(nextSettings);
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _appSettings = nextSettings;
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
                      final nextSettings = _appSettings.copyWith(
                        pageMode: mode,
                      );
                      await _syncLocalSettingsMirror(nextSettings);
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _appSettings = nextSettings;
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
                      final nextSettings = _appSettings.copyWith(
                        disabledFeatureFlags: disabled,
                      );
                      await _syncLocalSettingsMirror(nextSettings);
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _appSettings = nextSettings;
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
                await _syncLocalSettingsMirror(wizardSettings);
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
                  onPressed: () => Navigator.of(dialogContext).pop(),
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
                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.of(dialogContext).pop();
                      _showSnackBar('保存済み課題一覧を削除しました');
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
                      if (!dialogContext.mounted) {
                        return;
                      }
                      Navigator.of(dialogContext).pop();
                      _showSnackBar('変更履歴を削除しました');
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
                    if (!dialogContext.mounted) {
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
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                _showSnackBar('保存データを削除しました');
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

  Future<void> _handleToolbarSelection(Object selection) async {
    if (selection is GakujoQuickJumpDestination) {
      await _quickJumpTo(selection.label);
      return;
    }
    await _handleToolbarAction(selection as _ToolbarAction);
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

  Future<void> _saveCalendarImportSettings(
    GakujoCalendarImportSettings settings,
  ) async {
    await _appSettingsStore.saveCalendarImportSettings(settings);
    final nextSettings = _appSettings.copyWith(
      calendarImportSettings: settings,
    );
    await _syncLocalSettingsMirror(nextSettings);
    if (!mounted) {
      return;
    }
    setState(() {
      _appSettings = nextSettings;
    });
  }

  Future<void> _syncLocalSettingsMirror(
    GakujoAppSettings settings,
  ) async {
    try {
      await _localPrefsStore.saveAppSettings(settings);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to update local app settings mirror',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _saveMessageExcludeKeywords(List<String> keywords) async {
    final normalized = normalizeMessageExcludeKeywords(keywords);
    await _appSettingsStore.saveMessageExcludeKeywords(normalized);
    final nextSettings = _appSettings.copyWith(
      messageExcludeKeywords: normalized,
    );
    await _syncLocalSettingsMirror(nextSettings);
    if (!mounted) {
      return;
    }
    setState(() {
      _appSettings = nextSettings;
    });
    await _injectMessageFilterIfAllowed();
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
    return buildGakujoBackupPayload(
      appSettings: _appSettings,
      downloadHistory: history,
      failedDownloads: failedDownloads,
      favorites: favorites,
      deadlines: deadlines,
      changes: changes,
      reportLists: reportLists,
    );
  }

  Future<void> _importSettingsFromClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.trim().isEmpty) {
      _showSnackBar('クリップボードに設定JSONがありません');
      return;
    }

    final GakujoBackupImport backup;
    try {
      backup = parseGakujoBackup(text);
    } on GakujoBackupImportException catch (error) {
      _showSnackBar(error.message);
      return;
    } on Object {
      _showSnackBar('設定JSONを読み取れませんでした');
      return;
    }

    final downloadSaveMode =
        backup.downloadSaveMode ?? _appSettings.downloadSaveMode;
    final pageMode = backup.pageMode ?? _appSettings.pageMode;
    final setupCompleted = backup.setupCompleted ?? _appSettings.setupCompleted;
    final calendarImportSettings =
        backup.calendarImportSettings ?? _appSettings.calendarImportSettings;
    final messageExcludeKeywords =
        backup.messageExcludeKeywords ?? _appSettings.messageExcludeKeywords;
    final disabledFeatureFlags =
        backup.disabledFeatureFlags ?? _appSettings.disabledFeatureFlags;

    try {
      if (backup.downloadSaveMode != null) {
        await _appSettingsStore.saveDownloadSaveMode(downloadSaveMode);
      }
      if (backup.pageMode != null) {
        await _appSettingsStore.savePageMode(pageMode);
      }
      if (backup.disabledFeatureFlags != null) {
        await _appSettingsStore.saveDisabledFeatureFlags(disabledFeatureFlags);
      }
      if (backup.setupCompleted != null) {
        await _appSettingsStore.saveSetupCompleted(setupCompleted);
      }
      if (backup.calendarImportSettings != null) {
        await _appSettingsStore.saveCalendarImportSettings(
          calendarImportSettings,
        );
      }
      if (backup.messageExcludeKeywords != null) {
        await _appSettingsStore.saveMessageExcludeKeywords(
          messageExcludeKeywords,
        );
      }
      final downloadHistory = backup.downloadHistory;
      if (downloadHistory != null) {
        await _downloadHistoryStore.replaceHistory(downloadHistory);
      }
      final failedDownloads = backup.failedDownloads;
      if (failedDownloads != null) {
        await _downloadHistoryStore.replaceFailedDownloads(
          failedDownloads
              .where(
                (entry) => _isAllowedBackupUrl(entry.request.url),
              )
              .toList(),
        );
      }
      final favorites = backup.favorites;
      if (favorites != null) {
        await _activityStore.replaceFavorites(
          favorites
              .where(
                (entry) => _isAllowedBackupNavigationUrl(entry.url),
              )
              .toList(),
        );
      }
      final deadlines = backup.deadlines;
      if (deadlines != null) {
        await _activityStore.replaceDeadlines(
          deadlines.where((entry) => _isAllowedBackupUrl(entry.url)).toList(),
        );
      }
      final changes = backup.changes;
      if (changes != null) {
        await _activityStore.replaceChanges(
          changes.where((entry) => _isAllowedBackupUrl(entry.url)).toList(),
        );
      }
      final reportLists = backup.reportLists;
      if (reportLists != null) {
        await _activityStore.replaceReportLists(
          reportLists.where((entry) => _isAllowedBackupUrl(entry.url)).toList(),
        );
      }
      final nextSettings = _appSettings.copyWith(
        downloadSaveMode: downloadSaveMode,
        pageMode: pageMode,
        disabledFeatureFlags: disabledFeatureFlags,
        setupCompleted: setupCompleted,
        calendarImportSettings: calendarImportSettings,
        messageExcludeKeywords: messageExcludeKeywords,
      );
      await _syncLocalSettingsMirror(nextSettings);
      if (!mounted) {
        return;
      }
      setState(() {
        _appSettings = nextSettings;
      });
      await _injectMessageFilterIfAllowed();
      await _refreshActivityCounts();
      _scheduleAutoBackup();
      _showSnackBar('設定をインポートしました');
    } on Object {
      _showSnackBar('設定のインポートに失敗しました');
    }
  }

  bool _isAllowedBackupUrl(String url) {
    return AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed);
  }

  bool _isAllowedBackupNavigationUrl(String url) {
    return AllowedWebOrigins.canNavigate(url, debugAllowed: _debugAllowed);
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
    await _loadAppSettings(allowMacosKeychainPrompt: true);
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
    await _webViewReady;
    await _webViewService.configureController(
      _controller,
      debugAllowed: _debugAllowed,
    );
    unawaited(_saveInitialTwoFactorSecretIfAllowed());
    final appSettingsLoaded = await _loadAppSettings();
    if (appSettingsLoaded && !_appSettings.setupCompleted && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_showInitialSetupWizard());
        }
      });
    }
    final savedUrl = appSettingsLoaded ? await _loadInitialLastPageUrl() : null;
    if (_appSettings.hasLoginCredentials && savedUrl != null) {
      _pendingLoginRestoreUrl = savedUrl;
    }
    final startUrl = _resolveStartUrl(
      _appSettings.hasLoginCredentials ? null : savedUrl,
    );
    await _controller.loadUrl(startUrl);
  }

  Future<String?> _loadInitialLastPageUrl() async {
    if (Platform.isMacOS && !_secureStorageAccessAllowed) {
      try {
        final url = (await _localPrefsStore.load())?.lastPageUrl;
        if (AllowedWebOrigins.canRestoreLastPage(
          url,
          debugAllowed: _debugAllowed,
        )) {
          return url;
        }
        if (url != null) {
          await _syncLocalLastPageMirror(null);
        }
        return null;
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to load local last page mirror',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
        return null;
      }
    }

    final url = await _lastPageStore.load(debugAllowed: _debugAllowed);
    if (Platform.isMacOS) {
      await _syncLocalLastPageMirror(url);
    }
    return url;
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
      GakujoLocalPrefs? localPrefs;
      try {
        localPrefs = await _localPrefsStore.load();
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to load local app settings mirror',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (!mounted) {
        return true;
      }
      setState(() {
        _appSettings = macosStartupSettingsFromLocalPrefs(localPrefs);
        _appSettingsLoaded = true;
      });
      return true;
    }

    try {
      final settings = allowMacosKeychainPrompt
          ? await _appSettingsStore.load()
          : await _appSettingsStore.load().timeout(const Duration(seconds: 3));
      await _syncLocalSettingsMirror(settings);
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
      if (activityBellToolbarButtonEnabled) {
        unawaited(_refreshActivityCounts());
      }
      _scheduleAutoBackup();
      return true;
    } on Object catch (error, stackTrace) {
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
        final missingEntitlement = isMissingKeychainEntitlementError(error);
        final guidance = secureStorageRecoveryGuidance(
          error,
          platform: defaultTargetPlatform,
        );
        return AlertDialog(
          title: const Text('キーチェーンにアクセスできません'),
          content: Text(
            '保存済みログイン情報や2FA設定を読み込めませんでした。\n\n'
            '$guidance\n\n'
            '詳細: $details',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                _SecureStorageRecoveryAction.continueWithoutStorage,
              ),
              child: const Text('このまま使う'),
            ),
            if (!missingEntitlement) ...[
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
      await _localPrefsStore.clear();
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
    if (!AllowedWebOrigins.canRestoreLastPage(
      url,
      debugAllowed: _debugAllowed,
    )) {
      return;
    }
    if (!_secureStorageAccessAllowed) {
      if (Platform.isMacOS) {
        await _syncLocalLastPageMirror(url);
      }
      return;
    }
    try {
      await _lastPageStore.saveIfAllowed(url, debugAllowed: _debugAllowed);
      if (Platform.isMacOS) {
        await _syncLocalLastPageMirror(url);
      }
    } catch (error, stackTrace) {
      developer.log(
        'Failed to save last page URL',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _syncLocalLastPageMirror(String? url) async {
    try {
      await _localPrefsStore.saveLastPageUrl(url);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to update local last page mirror',
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
