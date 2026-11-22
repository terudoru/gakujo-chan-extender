import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart'
    show LinuxDownloadProgress, LinuxKeyZoomAction;

import 'generated/history_marker.g.dart';
import 'generated/document_cookie.g.dart';
import 'generated/document_title.g.dart';
import 'generated/favorite_page_identity.g.dart';
import 'generated/navigator_user_agent.g.dart';
import 'generated/page_text_activity.g.dart';
import 'generated/pdf_preview_ready.g.dart';
import 'generated/preview_navigate.g.dart';
import 'generated/portal_auth_state_probe.g.dart';
import 'generated/authenticated_session_reset.g.dart';
import 'allowed_web_origins.dart';
import 'app_update_service.dart';
import 'base32.dart';
import 'course_planner_handoff.dart';
import 'generated/registration_assist.g.dart';
import 'registration_handoff.dart';
import 'widgets/registration_assist_panel.dart';
import 'desktop_page_zoom_script.dart';
import 'download_destination_settings.dart';
import 'download_file_name_policy.dart';
import 'external_service_notice.dart';
import 'gakujo_activity_store.dart';
import 'gakujo_activity_classifier.dart';
import 'gakujo_academic_calendar.dart';
import 'gakujo_academic_calendar_resolver.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_assignment.dart';
import 'gakujo_backup_export.dart';
import 'gakujo_backup_import.dart';
import 'gakujo_backup_restore.dart';
import 'gakujo_calendar_export.dart';
import 'gakujo_calendar_service.dart';
import 'gakujo_course_name_estimator.dart';
import 'gakujo_dated_activity.dart';
import 'gakujo_download_capture_script.dart';
import 'gakujo_download_history_store.dart';
import 'gakujo_download_request.dart';
import 'gakujo_external_url.dart';
import 'gakujo_download_service.dart';
import 'gakujo_download_url_policy.dart';
import 'gakujo_expired_page_recovery_script.dart';
import 'file_system_gakujo_download_service.dart';
import 'gakujo_gpa_display_script.dart';
import 'gakujo_history_navigation.dart';
import 'gakujo_last_page_store.dart';
import 'gakujo_local_prefs_store.dart';
import 'gakujo_message_filter_script.dart';
import 'gakujo_message_list_script.dart';
import 'gakujo_message_reader_script.dart';
import 'gakujo_message_star_script.dart';
import 'gakujo_notification_history.dart';
import 'gakujo_notification_service.dart';
import 'gakujo_offline_retry.dart';
import 'gakujo_pdf_preview_server.dart';
import 'gakujo_report_draft_script.dart';
import 'gakujo_quick_jump_script.dart';
import 'gakujo_report_sorter_script.dart';
import 'gakujo_session_extender_script.dart';
import 'gakujo_starred_message_query.dart';
import 'gakujo_timeout_popup_script.dart';
import 'gakujo_upload_compression_libraries.dart';
import 'gakujo_upload_compression_script.dart';
import 'gakujo_upload_preview_script.dart';
import 'google_drive_file_saver.dart';
import 'platform/platform_service.dart';
import 'report_form.dart';
import 'secure_storage_factory.dart';
import 'protected_secret_page_probe.dart';
import 'protected_secrets_vault.dart';
import 'secure_storage_transaction.dart';
import 'star_sync/star_sync_engine.dart';
import 'star_sync/drive_download_preference.dart';
import 'star_sync/star_sync_adapters.dart';
import 'star_sync/star_sync_collections.dart';
import 'star_sync/star_sync_config.dart';
import 'star_sync/star_sync_google_auth.dart';
import 'star_sync/star_sync_quota_meter.dart';
import 'star_sync/star_sync_google_drive_transport.dart';
import 'gakujo_start_url_resolver.dart';
import 'login_autofill_assist_script.dart';
import 'linux_overlay_guard.dart';
import 'linux_session_settings.dart';
import 'macos_input_focus_service.dart';
import 'totp_generator.dart';
import 'two_factor_autofill_script.dart';
import 'two_factor_secret_store.dart';
import 'web_view_service.dart';
import 'windows_webview_authenticated_download.dart';
import 'widgets/app_about_section.dart';
import 'widgets/app_data_sections.dart';
import 'widgets/app_update_banner.dart';
import 'widgets/drive_save_folder_dialog.dart';
import 'widgets/gakujo_gpa_taunt.dart';
import 'widgets/gakujo_toolbar_actions.dart';
import 'widgets/linux_find_bar.dart';
import 'widgets/linux_download_strip.dart';
import 'widgets/linux_native_toolbar_tooltips.dart';
import 'widgets/linux_snack_bar_strip.dart';
import 'widgets/settings_sections.dart';
import 'widgets/notification_history_dialog.dart';
import 'widgets/star_sync_section.dart';

export 'widgets/app_data_sections.dart';
export 'widgets/gakujo_toolbar_actions.dart';
export 'widgets/settings_sections.dart';

part 'widgets/gakujo_web_app_private_widgets.dart';
part 'gakujo_web_app_calendar.dart';
part 'gakujo_web_app_course_planner.dart';
part 'gakujo_web_app_registration.dart';
part 'gakujo_web_app_diagnostics.dart';
part 'gakujo_web_app_downloads.dart';
part 'gakujo_web_app_models.dart';
part 'gakujo_web_app_message_stars.dart';
part 'gakujo_web_app_report_drafts.dart';

@visibleForTesting
bool handleReportDraftSavedMessage(String message, void Function() onSaved) {
  try {
    final data = jsonDecode(message);
    if (data is! Map || data['type'] != 'reportDraftSaved') return false;
    onSaved();
    return true;
  } on FormatException {
    return false;
  }
}

@visibleForTesting
class GakujoCollectionSyncScheduler {
  GakujoCollectionSyncScheduler({
    required this.canSync,
    required this.schedule,
    Timer Function(Duration, void Function())? timerFactory,
  }) : _timerFactory = timerFactory ?? Timer.new;

  final bool Function() canSync;
  final void Function(StarSyncTrigger, Duration) schedule;
  final Timer Function(Duration, void Function()) _timerFactory;
  Timer? _draftTimer;

  void localChange() {
    if (canSync()) {
      schedule(StarSyncTrigger.localChange, const Duration(seconds: 5));
    }
  }

  void pageLoaded() {
    if (canSync()) {
      schedule(StarSyncTrigger.resume, const Duration(seconds: 5));
    }
  }

  void draftChanged() {
    if (!canSync()) return;
    _draftTimer?.cancel();
    _draftTimer = _timerFactory(const Duration(seconds: 60), () {
      if (canSync()) schedule(StarSyncTrigger.localChange, Duration.zero);
    });
  }

  void dispose() => _draftTimer?.cancel();
}

class _SyncActivityStore extends GakujoActivityStore {
  _SyncActivityStore(this.onNotifiedKeysChanged);

  final void Function() onNotifiedKeysChanged;

  @override
  Future<void> addNotifiedDeadlineKeys(Iterable<String> deadlineKeys) async {
    final keys = deadlineKeys.toSet();
    if (keys.isEmpty) return;
    final before = await loadNotifiedDeadlineKeys();
    await super.addNotifiedDeadlineKeys(keys);
    final after = await loadNotifiedDeadlineKeys();
    if (after.difference(before).isNotEmpty) onNotifiedKeysChanged();
  }
}

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

  String get portalTabId {
    return switch (this) {
      GakujoQuickJumpDestination.grades => 'si',
      GakujoQuickJumpDestination.reports => 'en',
      GakujoQuickJumpDestination.messages => 'kj',
      GakujoQuickJumpDestination.downloads => 'sd',
      GakujoQuickJumpDestination.syllabus => 'sy',
      GakujoQuickJumpDestination.schedule => 'sch',
    };
  }

  String get portalUrl =>
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=$portalTabId';
}

const _calendarValidationTitle =
    GakujoCalendarImportSettings.validationCalendarTitle;
const _calendarValidationUidNamespace = 'calendar-validation';
const _messageListPortalUrl =
    'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=kj';
const _reportListPortalUrl =
    'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=en';
const _schedulePortalUrl =
    'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=sch';
// Gakujo's own HOME tab (`#tab-home`), verified on the PC portal.
const gakujoHomePortalUrl =
    'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=home';
const _compactToolbarHeight = 40.0;
const _toolbarButtonExtent = 40.0;
const _toolbarIconSize = 20.0;

typedef _PageScriptBuilder = String Function();

final Map<GakujoFeatureFlag, _PageScriptBuilder>
    _originalExtensionFeatureBuilders = {
  GakujoFeatureFlag.sessionExtender: GakujoSessionExtenderScript.build,
  GakujoFeatureFlag.uploadCompression: GakujoUploadCompressionScript.build,
};

@visibleForTesting
Map<String, String Function()> gakujoPageScriptBuilders(
  GakujoAppSettings settings, {
  Iterable<String> starredIds = const [],
}) => {
  'gpa': GakujoGpaDisplayScript.build,
  'report': GakujoReportSorterScript.build,
  'reader': GakujoMessageReaderScript.build,
  'stars': () => GakujoMessageStarScript.build(starredIds: starredIds),
  for (final entry in _originalExtensionFeatureBuilders.entries)
    if (settings.isFeatureEnabled(entry.key)) entry.key.storageValue: entry.value,
};

final Map<GakujoFeatureFlag, _PageScriptBuilder>
    _originalExtensionFeatureTeardownBuilders = {
  GakujoFeatureFlag.sessionExtender: GakujoSessionExtenderScript.buildTeardown,
  GakujoFeatureFlag.loginAutofill: LoginAutofillAssistScript.buildTeardown,
  GakujoFeatureFlag.twoFactorAutofill: TwoFactorAutofillScript.buildTeardown,
  GakujoFeatureFlag.uploadCompression:
      GakujoUploadCompressionScript.buildTeardown,
};

@visibleForTesting
bool portableSyncSettingsMatch(
  GakujoAppSettings settings,
  Map<String, Object?> basedOn,
) => starSyncCanonicalJson(exportStarSyncPortableSettings(settings)) ==
    starSyncCanonicalJson(basedOn);

@visibleForTesting
GakujoMessageNotificationSettings? restoredMessageNotification(
  GakujoBackupImport backup,
  Set<String> backupKeys,
) => backupKeys.contains('messageNotification') ||
        backupKeys.contains('notificationTopics')
    ? backup.messageNotification
    : null;

@visibleForTesting
Map<String, Set<String>?> restoredSyncCollections(
  GakujoBackupImport backup,
  Set<String> backupKeys,
) {
  final settings = <String>{
    if (backup.disabledFeatureFlags != null) 'disabledFeatureFlags',
    if (backup.calendarImportSettings != null) 'calendarImportSettings',
    if (backup.messageExcludeKeywords != null) 'messageExcludeKeywords',
    if (backup.notificationTopics != null) 'notificationTopics',
    if (backup.messageNotification != null) 'messageNotification',
    if (backup.notificationPreferences != null) 'notificationPreferences',
  }..retainAll(backupKeys);
  if (backup.messageNotification != null &&
      backupKeys.contains('notificationTopics')) {
    settings.add('messageNotification');
  }
  return {
    if (backup.favorites != null) 'favorites': null,
    if (settings.isNotEmpty) 'settings': settings,
  };
}

Map<String, Object?> portableSyncBackupPayload(Map<String, Object?> payload, {
  Set<String> disabledCollections = const {},
}) {
  Object? clean(Object? value) {
    if (value is List) return value.map(clean).toList();
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key is String &&
              !RegExp(r'password|passwd|secret|credential|token|api.?key|private.?key|login.?id', caseSensitive: false)
                  .hasMatch(entry.key as String) &&
              !RegExp(r'^(location|.*path|.*uri)$', caseSensitive: false)
                  .hasMatch(entry.key as String))
            entry.key as String: clean(entry.value),
      };
    }
    return value;
  }
  final result = clean({
    for (final key in [
      'version', 'createdAt', 'starredMessages', 'favorites',
      'notifiedDeadlineKeys', ...starSyncPortableSettingKeys,
    ])
      if (payload.containsKey(key)) key: payload[key],
  }) as Map<String, Object?>;
  result.remove('downloadSaveMode');
  result.remove('pageMode');
  if (disabledCollections.contains('favorites')) result.remove('favorites');
  if (disabledCollections.contains('notified-deadlines')) result.remove('notifiedDeadlineKeys');
  if (disabledCollections.contains('settings')) {
    for (final key in starSyncPortableSettingKeys) {
      result.remove(key);
    }
  }
  result.remove('reportDrafts');
  final stars = result['starredMessages'];
  if (stars is List) {
    result['starredMessages'] = [
      for (final star in stars)
        if (star is Map)
          {for (final key in ['keijitype', 'genrecd', 'seqNo', 'title', 'starredAt'])
            if (star.containsKey(key)) key: star[key]},
    ];
  }
  final flags = result['disabledFeatureFlags'];
  if (flags is List) {
    result['disabledFeatureFlags'] = flags
        .where((flag) => !const {
          'gpa_display', 'report_tools', 'message_tools', 'message_stars',
        }.contains(flag))
        .toList();
  }
  final preferences = result['notificationPreferences'];
  if (preferences is Map) {
    preferences.remove('mutedCourses');
  }
  return result;
}

@visibleForTesting
List<GakujoStarredMessage> mergeSyncBackupStars(
  List<GakujoStarredMessage> incoming,
  List<GakujoStarredMessage> local,
) {
  final existing = {for (final star in local) star.id: star};
  return [
    for (final star in incoming)
      GakujoStarredMessage(
        keijitype: star.keijitype,
        genrecd: star.genrecd,
        seqNo: star.seqNo,
        title: star.title,
        starredAt: star.starredAt,
        genre: existing[star.id]?.genre ?? '',
        sender: existing[star.id]?.sender ?? '',
        period: existing[star.id]?.period ?? '',
        postedAt: existing[star.id]?.postedAt ?? '',
        body: existing[star.id]?.body ?? '',
      ),
  ];
}

@visibleForTesting
List<int> encodePortableSyncBackup(Map<String, Object?> payload, {
  Set<String> disabledCollections = const {},
}) {
  final bytes = utf8.encode(jsonEncode(portableSyncBackupPayload(payload, disabledCollections: disabledCollections)));
  if (bytes.length > maxGakujoBackupBytes) {
    throw const GakujoBackupImportException('バックアップが大きすぎるため、同期先に保存できませんでした');
  }
  return bytes;
}

@visibleForTesting
Future<bool?> showGakujoBackupRestoreConfirmation(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('バックアップから復元しますか？'),
        content: const Text(
          '現在の設定、スター、通知済みの判定、ダウンロード履歴はバックアップの内容に置き換えられます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('復元する'),
          ),
        ],
      );
    },
  );
}

@visibleForTesting
Future<bool?> showPendingDriveCheckConfirmation(BuildContext context) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('確認が終わっていないファイルがあります。先に確認しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('このまま続ける'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('確認する'),
          ),
        ],
      ),
    );

@visibleForTesting
String? gakujoRuntimeTeardownScriptForFeature(GakujoFeatureFlag flag) {
  return _originalExtensionFeatureTeardownBuilders[flag]?.call();
}

@visibleForTesting
String gakujoCachedAssignmentText(GakujoAssignment assignment) {
  final due = assignment.dueInJapan;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${assignment.kind} ${assignment.title}'
      '${assignment.course.isEmpty ? '' : '（${assignment.course}）'}'
      ' ${assignment.status} 締切 ${due.year}/${two(due.month)}/${two(due.day)} '
      '${two(due.hour)}:${two(due.minute)}';
}

@visibleForTesting
List<String> gakujoExtractReportListItems(String text) {
  final keywords = RegExp(
    r'(レポート|課題|小テスト|アンケート|提出|期限|締切|締め切)',
  );
  final seen = <String>{};
  final items = <String>[];
  for (final line in text
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())) {
    if (line.length < 4 ||
        !keywords.hasMatch(line) ||
        !GakujoDatedActivity.containsDate(line)) {
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
Future<XFile?> pickGakujoBackupFile() async {
  const types = [
    XTypeGroup(
      label: 'JSON',
      extensions: ['json'],
      mimeTypes: ['application/json', 'text/plain'],
      uniformTypeIdentifiers: ['public.json'],
    ),
  ];
  if (defaultTargetPlatform == TargetPlatform.linux) {
    const channel = MethodChannel('net.yoshida.morebettergakujo/window');
    final path = await channel.invokeMethod<String>('pickOpenFile', {
      'allowedTypeGroups': [
        for (final type in types)
          {
            'label': type.label,
            'extensions': type.extensions,
            'mimeTypes': type.mimeTypes,
          },
      ],
    });
    return path == null ? null : XFile(path);
  }
  return openFile(acceptedTypeGroups: types);
}

@visibleForTesting
String gakujoUserFacingMessage(
  String message, {
  required TargetPlatform platform,
}) {
  if (platform != TargetPlatform.linux) return message;
  if (message.contains('KeyringLocked')) {
    return 'キーリングがロックされているため、設定を読み書きできません。'
        'キーリング管理アプリでロックを解除してから、アプリを起動し直してください。';
  }
  return message;
}

@visibleForTesting
String gakujoBlockedNavigationUrlLabel(
  String url, {
  required TargetPlatform platform,
}) {
  if (platform == TargetPlatform.linux && Uri.tryParse(url)?.scheme == 'file') {
    try {
      return Uri.decodeFull(url);
    } on FormatException {
      return 'ローカルファイル';
    }
  }
  return url;
}

@visibleForTesting
String secureStorageRecoveryGuidance(
  Object error, {
  required TargetPlatform platform,
  LinuxSecretServiceStatus? linuxSecretService,
}) {
  if (isMissingKeychainEntitlementError(error)) {
    return 'このアプリに必要なキーチェーン権限がありません。'
        'アプリを最新版へ更新してから、もう一度起動してください。';
  }
  if (platform == TargetPlatform.iOS) {
    return '一時的な失敗なら「再試行」で読み込み直せます。\n\n'
        '再試行しても復旧しない場合はアプリを最新版へ更新してください。'
        '保存領域が壊れている疑いがあるときだけ「保存データをリセット」を使ってください。'
        'その場合はログイン情報と2FA設定の再入力が必要です。';
  }

  if (platform == TargetPlatform.macOS && error is TimeoutException) {
    return 'macOS のキーチェーン確認ダイアログが開いたままになっている可能性があります。\n\n'
        'ダイアログで「常に許可」を選んでから「再試行」を押してください。';
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
        '再試行してください。それでも読み込めないときは「保存データをリセット」で保存領域を作り直せます。'
        'その場合はログイン情報と2FA設定の再入力が必要です。';
  }
  if (platform == TargetPlatform.linux &&
      error is PlatformException &&
      error.code == 'KeyringLocked') {
    if (linuxSecretService == LinuxSecretServiceStatus.missing) {
      return 'ログイン情報を安全に保管するサービス（GNOME Keyring や KWallet など）が見つかりません。\n\n'
          'サービスを入れて有効にしてから「再試行」を押してください。'
          'それまでは「このまま使う」で、ログイン情報を保存せずに使えます。';
    }
    // The data is intact; resetting would only throw it away.
    return 'キーリング（GNOME Keyring や KWallet など）がロックされています。\n\n'
        '「再試行」を押すとロック解除の画面がもう一度表示されるので、ログインパスワードでロックを解除してください。'
        '解除するまでは「このまま使う」で、保存済みのログイン情報なしで使えます。';
  }
  if (platform == TargetPlatform.linux) {
    return 'ログイン情報を安全に保管するサービス（GNOME Keyring や KWallet など）を使えない可能性があります。\n\n'
        'サービスが動いていることを確かめてから「再試行」を押してください。'
        'それでも読み込めないときは「保存データをリセット」で保存領域を作り直せます。'
        'その場合はログイン情報と2FA設定の再入力が必要です。';
  }
  return '一時的な失敗なら「再試行」で読み込み直せます。\n\n'
      'それでも読み込めないときは「保存データをリセット」で保存領域を作り直せます。'
      'その場合はログイン情報と2FA設定の再入力が必要です。';
}

const _offlineRetryStatus = 'オフラインのようです。接続が戻ると自動で再読み込みします';
const _manualReloadStatus = '読み込めませんでした。接続を確認して再読み込みを押してください';

bool _isHiddenOrPaused(AppLifecycleState? state) =>
    state == AppLifecycleState.hidden || state == AppLifecycleState.paused;

@visibleForTesting
void handleGakujoWebResourceError(
  GakujoWebResourceError error, {
  required int offlineAutoReloads,
  required void Function(String) setStatus,
  required void Function() startOfflineRetry,
}) {
  if (error.isForMainFrame && error.isConnectivityError) {
    if (offlineAutoReloads >= 3) {
      setStatus(_manualReloadStatus);
      return;
    }
    setStatus(_offlineRetryStatus);
    startOfflineRetry();
    return;
  }
  if (!error.isForMainFrame) {
    // The portal iframe can fail offline; reloading could discard its form.
    if (error.isConnectivityError) {
      setStatus('オフラインのようです。接続が戻ったら再読み込みしてください');
    }
    developer.log(
      'Sub-resource load error: ${error.description}',
      name: 'MoreBetterGakujo',
    );
    return;
  }
  setStatus('読み込みエラー: ${error.description}');
}

@visibleForTesting
bool allowsGakujoPdfPreviewNavigation(
  GakujoNavigationRequest request, {
  required TargetPlatform platform,
  required bool Function(String url) isViewerUrl,
}) {
  // Before WebKit 2.56 an unnamed iframe can be reported as the main frame.
  // Only the exact app-owned capability URL gets this Linux exception.
  return (!request.isMainFrame || platform == TargetPlatform.linux) &&
      isViewerUrl(request.url);
}

class GakujoWebApp extends StatefulWidget {
  const GakujoWebApp({
    super.key,
    this._secretStore,
    this._totpGenerator,
    this._lastPageStore,
    this._appSettingsStore,
    this._localPrefsStore,
    this._startUrl,
    this._initialTwoFactorSecret,
    this._debugAllowed,
    this._gakujoReachable,
    this._updateService,
    this.updateNow = DateTime.now,
    this._webViewService,
    this.linuxOverlayObscured,
  });

  final TwoFactorSecretStore? _secretStore;
  final TotpGenerator? _totpGenerator;
  final GakujoLastPageStore? _lastPageStore;
  final GakujoAppSettingsStore? _appSettingsStore;
  final GakujoLocalPrefsStore? _localPrefsStore;
  final String? _startUrl;
  final String? _initialTwoFactorSecret;
  final bool? _debugAllowed;
  final Future<bool> Function()? _gakujoReachable;
  final AppUpdateService? _updateService;
  final DateTime Function() updateNow;
  final GakujoWebViewService? _webViewService;
  final ValueListenable<bool>? linuxOverlayObscured;

  @override
  State<GakujoWebApp> createState() => _GakujoWebAppState();
}

const _settingsSaveFailureMessage = '設定を保存できませんでした。しばらくしてからもう一度お試しください';

@visibleForTesting
class GakujoStartupFlow {
  Future<bool>? _settingsLoad;
  bool _storageRecoveryShown = false;
  bool _setupShown = false;
  bool continuedWithoutStorage = false;

  Future<bool> loadSettings(Future<bool> Function() load) =>
      _settingsLoad ??= Future<bool>.sync(load);

  bool claimStorageRecovery({bool automatic = true}) {
    if (automatic && _storageRecoveryShown) return false;
    _storageRecoveryShown = true;
    return true;
  }

  bool claimSetup() {
    if (_setupShown) return false;
    _setupShown = true;
    return true;
  }
}

@visibleForTesting
class ProtectedSecretPromptGate {
  bool paused = false;
  bool _backgrounded = false;
  bool _readErrorReported = false;
  int? _waitingRevision;
  int? _attemptedRevision;

  void background() => _backgrounded = true;
  bool resume() {
    final shouldRetry = _backgrounded && paused;
    if (_backgrounded) reset();
    _backgrounded = false;
    return shouldRetry;
  }
  void reset() {
    paused = false;
    _attemptedRevision = null;
  }
  void cancel() => paused = true;
  void waitingForForm(int revision) => _waitingRevision = revision;
  bool claimInitialLoad(int revision) {
    if (paused || _attemptedRevision == revision) return false;
    _attemptedRevision = revision;
    return true;
  }
  bool claimLateLoad(int revision) {
    if (paused || _waitingRevision != revision || _attemptedRevision == revision) {
      return false;
    }
    _attemptedRevision = revision;
    return true;
  }
  bool reportReadError() {
    if (_readErrorReported) return false;
    _readErrorReported = true;
    return true;
  }
}

@visibleForTesting
String? gakujoLoginAutofillStatus(String event, bool hasCredentials) {
  if (event == 'submit-blocked' ||
      (event == 'ready-no-submit' && hasCredentials)) {
    return 'ログインが切れました。自動ログインを止めました。ID とパスワードを入力してください';
  }
  if (event == 'challenge' || event == 'ready-no-submit') {
    return hasCredentials
        ? 'ログインが切れました。自動ログインしています'
        : 'ログインが切れました。ログイン情報を入力してください';
  }
  return null;
}

@visibleForTesting
Future<void> gakujoWaitForDialogDismissal(ModalRoute<void>? route) async {
  if (route != null) {
    await route.completed;
  }
}

@visibleForTesting
GakujoAppSettings gakujoSettingsAfterInitialSetup({
  required GakujoAppSettings currentSettings,
  required GakujoAppSettings wizardSettings,
  required Set<GakujoFeatureFlag> placeholderFeatureFlags,
  Set<GakujoFeatureFlag> changedFeatureFlags = const {},
}) {
  // A placeholder the wizard did not touch takes the value loaded since.
  bool keepsCurrent(GakujoFeatureFlag flag) =>
      placeholderFeatureFlags.contains(flag) &&
      !changedFeatureFlags.contains(flag);
  return currentSettings.copyWith(
    downloadSaveMode: wizardSettings.downloadSaveMode,
    pageMode: wizardSettings.pageMode,
    disabledFeatureFlags: {
      for (final flag in wizardSettings.disabledFeatureFlags)
        if (!keepsCurrent(flag)) flag,
      for (final flag in currentSettings.disabledFeatureFlags)
        if (keepsCurrent(flag)) flag,
    },
    setupCompleted: true,
  );
}

@visibleForTesting
bool gakujoLoginStorageLoadAttemptedAfterFailure({
  required bool attempted,
  required Object error,
}) {
  return attempted && error is! TimeoutException;
}

@visibleForTesting
GakujoAppSettings gakujoSettingsAfterStorageLoadFailure({
  required GakujoAppSettings currentSettings,
  required bool isMacOS,
  required Object error,
}) {
  if (isMacOS) {
    return currentSettings;
  }
  return error is TimeoutException
      ? const GakujoAppSettings(
          disabledFeatureFlags: {
            GakujoFeatureFlag.loginAutofill,
            GakujoFeatureFlag.twoFactorAutofill,
          },
        )
      : const GakujoAppSettings();
}

@visibleForTesting
Future<T?> readGakujoSavedData<T extends Object>(
  Future<T> Function() read, {
  required ValueChanged<String> showSnackBar,
}) async {
  try {
    return await read();
  } on Object catch (error) {
    final message =
        defaultTargetPlatform == TargetPlatform.linux &&
            error is PlatformException &&
            error.code == 'KeyringLocked'
        ? gakujoUserFacingMessage(error.code, platform: defaultTargetPlatform)
        : '保存データを読み込めませんでした。しばらくしてからもう一度お試しください';
    showSnackBar(message);
    return null;
  }
}

@visibleForTesting
Future<bool> saveGakujoSettingsSafely(
  Future<void> Function() save, {
  required ValueChanged<String> showSnackBar,
}) async {
  try {
    await save();
    return true;
  } on Object {
    showSnackBar(_settingsSaveFailureMessage);
    return false;
  }
}

@visibleForTesting
Future<void> saveGakujoSettingsChange({
  required Future<void> Function() save,
  required GakujoAppSettings Function() currentSettings,
  required GakujoAppSettings Function(GakujoAppSettings) update,
  required ValueChanged<GakujoAppSettings> apply,
  required Future<void> Function(GakujoAppSettings) mirror,
  StorageOperationQueue? operations,
}) {
  Future<void> change() async {
    await save();
    final settings = update(currentSettings());
    // Apply before awaiting the mirror so overlapping changes see this value.
    apply(settings);
    await mirror(settings);
  }

  return operations == null ? change() : operations.run(change);
}

@visibleForTesting
Future<bool> applyGakujoSyncedSettings({
  required StorageOperationQueue operations,
  required GakujoAppSettings Function() currentSettings,
  required Map<String, Object?> entries,
  required Map<String, Object?> basedOn,
  required bool Function() isMounted,
  required Future<void> Function(
    GakujoBackupImport backup, void Function() beforeWrite,
  ) restore,
  required void Function(GakujoAppSettings next, bool flagsChanged) publish,
  required Future<void> Function(GakujoAppSettings next) mirror,
  List<Future<void> Function(GakujoAppSettings, GakujoAppSettings)> effects = const [],
  bool Function()? stillCurrent,
  StarSyncLocalCommit? commit,
}) => operations.runExclusive(() async {
  final previous = currentSettings();
  if (!isMounted() || !portableSyncSettingsMatch(previous, basedOn)) return false;
  void checkCurrent() {
    if (stillCurrent != null && !stillCurrent()) {
      throw const StarSyncAccountMismatchException();
    }
  }
  final backup = importStarSyncPortableSettings(previous, entries);
  Future<bool> writeLocal() async {
    await restore(backup, checkCurrent);
    return true;
  }
  final applied = commit == null ? await writeLocal() : await commit(writeLocal);
  if (!applied) return false;
  checkCurrent();
  // Publish only after the pair and its final transaction guard commit. Rebase
  // on the latest model so nonportable fields retain their current values.
  final current = currentSettings();
  final patch = importStarSyncPortableSettings(current, entries);
  final next = current.copyWith(
    disabledFeatureFlags: patch.disabledFeatureFlags,
    calendarImportSettings: backup.calendarImportSettings,
    messageExcludeKeywords: backup.messageExcludeKeywords,
    notificationTopics: backup.notificationTopics,
    messageNotification: backup.messageNotification,
    notificationPreferences: backup.notificationPreferences,
  );
  publish(next, backup.disabledFeatureFlags != null);
  Future<void> afterCommit(Future<void> Function() effect) async {
    try {
      await effect();
    } on Object catch (error, stackTrace) {
      developer.log('Failed to refresh committed settings',
        name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
    }
  }
  await afterCommit(() => mirror(next));
  for (final effect in effects) {
    if (!isMounted() || (stillCurrent != null && !stillCurrent())) break;
    await afterCommit(() => effect(previous, next));
  }
  return true;
});

@visibleForTesting
Future<GakujoAppSettings> restoreGakujoSettingsLocally({
  required StorageOperationQueue operations,
  required GakujoBackupImport backup,
  required GakujoAppSettings Function() currentSettings,
  required Future<void> Function() restore,
  required void Function(GakujoAppSettings next, bool flagsRestored) publish,
  required Future<void> Function(GakujoAppSettings next) mirror,
}) => operations.runExclusive(() async {
  await restore();
  final next = currentSettings().copyWith(
    downloadSaveMode: backup.downloadSaveMode,
    pageMode: backup.pageMode,
    disabledFeatureFlags: backup.disabledFeatureFlags,
    setupCompleted: backup.setupCompleted,
    calendarImportSettings: backup.calendarImportSettings,
    messageExcludeKeywords: backup.messageExcludeKeywords,
    notificationTopics: backup.notificationTopics,
    messageNotification: backup.messageNotification,
    notificationPreferences: backup.notificationPreferences,
  );
  Future<void> afterRestore(FutureOr<void> Function() operation) async {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      // The raw restore committed. Do not let refresh/mirror failure make the
      // engine remove the durable marker for this explicit replacement.
      developer.log('Failed to refresh restored settings',
        name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
    }
  }
  await afterRestore(() => publish(next, backup.disabledFeatureFlags != null));
  await afterRestore(() => mirror(next));
  return next;
});

@visibleForTesting
Future<bool> applyGakujoSyncedReportDrafts({
  required Map<String, Object?> drafts,
  required Map<String, Object?> basedOn,
  required int? readRevision,
  required int Function() navigationRevision,
  required Future<bool> Function() canSync,
  required Future<String> Function(String script) evaluate,
  bool Function()? stillCurrent,
}) async {
  final revision = navigationRevision();
  if (revision != readRevision) return false;
  try {
    if (!await canSync()) return false;
  } on Object {
    // A failed page check precedes script invocation and cannot have written.
    return false;
  }
  final script = GakujoReportDraftScript.buildImportAll(drafts, basedOn);
  if (stillCurrent != null && !stillCurrent()) {
    throw const StarSyncAccountMismatchException();
  }
  if (revision != navigationRevision()) return false;
  final value = await evaluate(script);
  // The script's false result guarantees no writes, even if the page moved.
  if (value == 'false') return false;
  if (value != 'true' || revision != navigationRevision() || !await canSync()) {
    throw StateError('Draft write failed');
  }
  return true;
}

@visibleForTesting
Future<GakujoLoginCredentials> saveGakujoLoginCredentials({
  required GakujoAppSettingsStore store,
  required String loginId,
  required String password,
}) async {
  final credentials = GakujoLoginCredentials(
    loginId: loginId.trim(),
    password: password,
  );
  await store.saveLoginCredentials(
    loginId: credentials.loginId,
    password: credentials.password,
  );
  await store.saveFeatureEnabled(
    GakujoFeatureFlag.loginAutofill,
    enabled: true,
  );
  return credentials;
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
    // Keep malformed or untrusted URI-like values away from dart:io's
    // platform path parser, while still treating them as local locations.
    return Uri(scheme: 'file', path: trimmed);
  }

  return Uri.file(File(trimmed).absolute.path);
}

@visibleForTesting
Future<void> pruneJsonFilesForRetention(
  Directory directory, {
  required int keep,
  String? fileNamePrefix,
  File? protectedFile,
}) async {
  final files = await directory
      .list()
      .where((entity) {
        if (entity is! File || !entity.path.endsWith('.json')) {
          return false;
        }
        if (fileNamePrefix == null) {
          return true;
        }
        final fileName = entity.path.split(Platform.pathSeparator).last;
        return fileName.startsWith(fileNamePrefix);
      })
      .cast<File>()
      .toList();
  files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  if (keep > 0 && protectedFile != null) {
    // A clock correction can put the just-written file below the mtime cutoff.
    final protectedUri = protectedFile.absolute.uri;
    final index = files.indexWhere(
      (file) => file.absolute.uri == protectedUri,
      keep,
    );
    if (index != -1) {
      files.insert(0, files.removeAt(index));
    }
  }
  for (final file in files.skip(keep)) {
    try {
      await file.delete();
    } on FileSystemException {
      // Best-effort cleanup only.
    }
  }
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

enum GakujoHistoryNavigation {
  back,
  forward,
}

@visibleForTesting
class DesktopHistorySwipeTracker {
  double _distance = 0;
  double _horizontalTravel = 0;
  double _verticalTravel = 0;
  bool _triggered = false;
  Timer? _timer;

  GakujoHistoryNavigation? add(Offset delta,
      {required bool positiveIsBack,
      required double threshold,
      required double dominance}) {
    if (_triggered) {
      // Momentum can last longer than the idle interval; every event extends
      // the latch so one continuous gesture cannot move several pages.
      scheduleReset();
      return null;
    }
    final horizontal = delta.dx.abs();
    final vertical = delta.dy.abs();
    _horizontalTravel += horizontal;
    _verticalTravel += vertical;
    if (_verticalTravel > 12 &&
        _verticalTravel * dominance >= _horizontalTravel) {
      // A scroll stays a scroll even when its diagonal/momentum tail turns
      // horizontal. Do not restart recognition in the middle of the stream.
      suppress();
      return null;
    }
    if (horizontal <= vertical * dominance) {
      if (vertical > horizontal) {
        scheduleReset();
      }
      return null;
    }
    _distance += positiveIsBack ? delta.dx : -delta.dx;
    scheduleReset();
    if (_distance.abs() < threshold) {
      return null;
    }
    _triggered = true;
    return _distance > 0
        ? GakujoHistoryNavigation.back
        : GakujoHistoryNavigation.forward;
  }

  void scheduleReset() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), reset);
  }

  void suppress() {
    _triggered = true;
    scheduleReset();
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _distance = 0;
    _horizontalTravel = 0;
    _verticalTravel = 0;
    _triggered = false;
  }

  void dispose() => reset();
}

@visibleForTesting
GakujoHistoryNavigation? gakujoEdgeSwipeNavigation({
  required double startX,
  required double viewportWidth,
  required Offset delta,
  double edgeExtent = 36,
  double triggerDistance = 80,
  double horizontalDominance = 1.25,
}) {
  if (viewportWidth <= 0 ||
      delta.dx.abs() < triggerDistance ||
      delta.dx.abs() <= delta.dy.abs() * horizontalDominance) {
    return null;
  }
  if (startX <= edgeExtent && delta.dx > 0) {
    return GakujoHistoryNavigation.back;
  }
  if (startX >= viewportWidth - edgeExtent && delta.dx < 0) {
    return GakujoHistoryNavigation.forward;
  }
  return null;
}

@visibleForTesting
SnackBar buildTransientGakujoSnackBar(
  String message, {
  SnackBarAction? action,
}) {
  return SnackBar(
    content: Text(message),
    action: action,
    // Leave time to reach the button; plain messages can go sooner.
    duration: Duration(seconds: action == null ? 7 : 12),
    persist: false,
  );
}

enum GakujoPortalAuthState {
  authenticated,
  login,
  twoFactor,
  unknown,
  fieldFree,
}

@visibleForTesting
Future<GakujoPortalAuthState?> waitForResolvedGakujoAuthState({
  required Future<GakujoPortalAuthState> Function(bool Function()) probe,
  required Future<void> Function(Duration) delay,
  required bool Function() stillCurrent,
  Duration Function()? elapsed,
  Duration limit = const Duration(seconds: 15),
  Duration interval = const Duration(milliseconds: 500),
}) async {
  final stopwatch = Stopwatch()..start();
  final timeElapsed = elapsed ?? () => stopwatch.elapsed;
  var running = true;
  bool valid() => running && stillCurrent() && timeElapsed() < limit;
  try {
    while (valid()) {
      final remaining = limit - timeElapsed();
      await delay(interval < remaining ? interval : remaining).timeout(remaining);
      if (!valid()) return null;
      final state = await probe(valid).timeout(limit - timeElapsed());
      if (!valid()) return null;
      if (state != GakujoPortalAuthState.unknown) return state;
    }
  } on TimeoutException {
    return null;
  } finally {
    running = false;
    stopwatch.stop();
  }
  return null;
}

@visibleForTesting
GakujoPortalAuthState gakujoPortalAuthStateFromSignals({
  required bool hasLoginFields,
  required bool hasTwoFactorField,
  required bool hasAuthenticatedMarker,
}) {
  if (hasTwoFactorField) {
    return GakujoPortalAuthState.twoFactor;
  }
  if (hasLoginFields) {
    return GakujoPortalAuthState.login;
  }
  if (hasAuthenticatedMarker) {
    return GakujoPortalAuthState.authenticated;
  }
  return GakujoPortalAuthState.unknown;
}

@visibleForTesting
GakujoPortalAuthState gakujoPortalAuthStateFromJavaScriptResult(
  Object? result,
) {
  Object? decoded = result;
  for (var attempt = 0; attempt < 2 && decoded is String; attempt += 1) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      break;
    }
  }
  if (decoded is! Map) {
    return GakujoPortalAuthState.unknown;
  }
  return gakujoPortalAuthStateFromSignals(
    hasLoginFields: decoded['hasLoginFields'] == true,
    hasTwoFactorField: decoded['hasTwoFactorField'] == true,
    hasAuthenticatedMarker: decoded['hasAuthenticatedMarker'] == true,
  );
}

@visibleForTesting
bool isGakujoAuthenticationChallenge({
  required GakujoPortalAuthState authState,
  required bool urlLooksLikeLoginOrTimeout,
}) {
  return urlLooksLikeLoginOrTimeout ||
      authState == GakujoPortalAuthState.login ||
      authState == GakujoPortalAuthState.twoFactor;
}

const googleRevocationUnconfirmedMessage =
    'Google 側の接続解除を確認できませんでした。Google アカウントの設定から確認してください';

@visibleForTesting
class GakujoLoginIdentity {
  String? active;
  String? pending;
  String? restored;
  int revision = 0;
  int? pendingNavigation;
  bool pageConfirmed = false;
  bool pageSeen = false;

  bool submit(String account, {int? navigation}) {
    pending = account;
    pendingNavigation = navigation;
    restored = null;
    pageConfirmed = false;
    revision++;
    final changed = active != account;
    if (changed) active = null;
    return changed;
  }

  void challenge() {
    active = null;
    pageSeen = true;
    pageConfirmed = false;
    restored = null;
  }

  void invalidateLoginNavigation(String url, void Function() cancelUploads) {
    if (!AllowedWebOrigins.isLoginOrTimeoutPage(url)) return;
    // The login form posts back to login.do, so the submitted candidate must
    // survive its own navigation; a failed login drops it in loginFormShown.
    challenge();
    cancelUploads();
  }

  /// A login form on a page loaded after the submit means the login failed.
  /// A probe that started before a newer submit leaves that one alone.
  void loginFormShown({required int probeRevision, required int navigation}) {
    final submittedAt = pendingNavigation;
    if (pending == null || probeRevision != revision) return;
    if (submittedAt != null && navigation <= submittedAt) return;
    pending = null;
    pendingNavigation = null;
  }

  String? confirm(GakujoPortalAuthState authState) {
    if (authState != GakujoPortalAuthState.authenticated) return null;
    pageSeen = true;
    pageConfirmed = true;
    final account = pending ?? restored;
    pending = null;
    pendingNavigation = null;
    restored = null;
    return account;
  }
}

@visibleForTesting
bool shouldResetGakujoLoginRestoreAttempt({
  required GakujoPortalAuthState authState,
  required bool urlLooksLikeLoginOrTimeout,
  required bool hasRecoveryUrl,
}) {
  return hasRecoveryUrl &&
      isGakujoAuthenticationChallenge(
        authState: authState,
        urlLooksLikeLoginOrTimeout: urlLooksLikeLoginOrTimeout,
      );
}

@visibleForTesting
bool shouldRestorePendingGakujoPage({
  required GakujoPortalAuthState authState,
  required bool restoreAttempted,
  required bool hasRestoreUrl,
  required bool currentUrlMatchesRestoreUrl,
}) {
  return authState == GakujoPortalAuthState.authenticated &&
      !restoreAttempted &&
      hasRestoreUrl &&
      !currentUrlMatchesRestoreUrl;
}

@visibleForTesting
bool shouldConsumePendingGakujoPage({
  required GakujoPortalAuthState authState,
  required String currentUrl,
  required String? restoreUrl,
}) {
  return authState == GakujoPortalAuthState.authenticated &&
      restoreUrl == currentUrl;
}

@visibleForTesting
bool shouldAdoptGakujoPageFinishedUrl({
  required String url,
  required String? currentUrl,
  required String? webViewUrl,
  required int navigationRevision,
  required int currentNavigationRevision,
  required int? pendingNavigationRevision,
}) {
  return currentUrl != null &&
      currentUrl != url &&
      webViewUrl == url &&
      navigationRevision == currentNavigationRevision &&
      pendingNavigationRevision == navigationRevision;
}

@visibleForTesting
bool isGakujoNavigationRecoveryCandidateUrl(
  String url, {
  required bool debugAllowed,
}) {
  if (!AllowedWebOrigins.canRestoreLastPage(
    url,
    debugAllowed: debugAllowed,
  )) {
    return false;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return false;
  }
  final path = uri.path.toLowerCase().replaceAll(RegExp(r';[^/]*'), '');
  final query = {
    for (final entry in uri.queryParameters.entries)
      entry.key.toLowerCase(): entry.value.toLowerCase(),
  };
  if (GakujoDownloadUrlPolicy.shouldDownload(url) ||
      (query['_eventid']?.contains('download') ?? false) ||
      (query['_flowid'] == 'sdw-filerefer-flow' &&
          (query['fileid']?.trim().isNotEmpty ?? false)) ||
      RegExp(r'\.(pdf|docx?|xlsx?|pptx?|zip|csv|txt|png|jpe?g)$')
          .hasMatch(path)) {
    return false;
  }
  // These shared shell URLs can reveal login controls without changing URL.
  // They cannot identify the protected page that triggered authentication.
  if (path.endsWith('/campussmart.do')) {
    return false;
  }
  if (path.endsWith('/campusportal.do')) {
    return uri.queryParameters['page'] == 'main' &&
        (uri.queryParameters['tabId']?.trim().isNotEmpty ?? false);
  }
  return true;
}

@visibleForTesting
String? captureGakujoNavigationRecoveryCandidate({
  required String url,
  required String? currentUrl,
  required String? authenticatedUrl,
  required String? navigationCandidateUrl,
  String? authenticatedPageUrl,
  bool navigationCandidateFailed = false,
  bool debugAllowed = false,
}) {
  // Keep the original protected request through redirects and login POSTs.
  // A failed destination survives retries but yields to a new protected request.
  if (navigationCandidateUrl != null) {
    if (navigationCandidateFailed &&
        isGakujoNavigationRecoveryCandidateUrl(url,
            debugAllowed: debugAllowed)) {
      return url;
    }
    return navigationCandidateUrl;
  }
  if (currentUrl != null &&
      (currentUrl == authenticatedUrl || currentUrl == authenticatedPageUrl) &&
      url != authenticatedUrl &&
      isGakujoNavigationRecoveryCandidateUrl(url, debugAllowed: debugAllowed)) {
    return url;
  }
  return null;
}

@visibleForTesting
bool gakujoNavigationRecoveryCandidateAfterError(
  GakujoWebResourceError error, {
  required String? navigationCandidateUrl,
  required String? navigationUrl,
  bool navigationCandidateFailed = false,
}) {
  // A login redirect can fail too; retain its original protected destination.
  return navigationCandidateUrl != null &&
      (navigationCandidateFailed ||
          (error.isForMainFrame &&
              error.isConnectivityError &&
              navigationCandidateUrl == navigationUrl));
}

@visibleForTesting
String? selectGakujoSessionRecoveryUrl({
  required String? navigationCandidateUrl,
  required String? authenticatedUrl,
  required String? pendingRestoreUrl,
  bool debugAllowed = false,
}) {
  for (final url in [
    navigationCandidateUrl,
    pendingRestoreUrl,
    authenticatedUrl,
  ]) {
    if (AllowedWebOrigins.canRestoreLastPage(url, debugAllowed: debugAllowed)) {
      return url;
    }
  }
  return null;
}

@visibleForTesting
String? usableGakujoNavigationCandidateForChallenge({
  required String? navigationCandidateUrl,
  required String challengeUrl,
  bool debugAllowed = false,
}) {
  if (navigationCandidateUrl != null &&
      navigationCandidateUrl == challengeUrl &&
      !isGakujoNavigationRecoveryCandidateUrl(
        navigationCandidateUrl,
        debugAllowed: debugAllowed,
      )) {
    return null;
  }
  return navigationCandidateUrl;
}

@visibleForTesting
bool canRunGakujoPageScripts({
  required String? currentUrl,
  String? lastAllowedUrl,
  bool debugAllowed = false,
}) {
  return AllowedWebOrigins.canLoad(currentUrl, debugAllowed: debugAllowed) ||
      ((currentUrl ?? '').trim().toLowerCase() == 'about:blank' &&
          AllowedWebOrigins.canLoad(lastAllowedUrl,
              debugAllowed: debugAllowed));
}

@visibleForTesting
Future<void> handleGakujoJavaScriptMessage({
  required String? currentUrl,
  String? lastAllowedUrl,
  required String channelName,
  required String message,
  required FutureOr<void> Function(String) onMessageReceived,
}) async {
  if (!canRunGakujoPageScripts(
    currentUrl: currentUrl,
    lastAllowedUrl: lastAllowedUrl,
  )) {
    if (kDebugMode) {
      debugPrint('Ignored $channelName message outside the Gakujo origin');
    }
    return;
  }
  await onMessageReceived(message);
}

@visibleForTesting
class GakujoMessageOpenNavigation {
  String? _url;
  int? _revision;

  void record(String? url, int navigationRevision) {
    _url = url;
    _revision = navigationRevision;
  }

  bool owns(String url, int navigationRevision) {
    return _revision == navigationRevision && (_url == null || _url == url);
  }

  bool shouldCancelFor(
      GakujoNavigationRequest request, int navigationRevision) {
    return request.isMainFrame && !owns(request.url, navigationRevision);
  }

  bool consume(String url, int navigationRevision) {
    final matches = owns(url, navigationRevision);
    _url = null;
    _revision = null;
    return matches;
  }
}

@visibleForTesting
String? gakujoInitialPendingRestoreUrl({
  required String? pendingNotificationUrl,
  required String? savedUrl,
}) {
  return pendingNotificationUrl ?? savedUrl;
}

@visibleForTesting
String? gakujoNotificationRestoreTarget(
  String url, {
  required bool debugAllowed,
}) {
  return AllowedWebOrigins.canRestoreLastPage(
    url,
    debugAllowed: debugAllowed,
  )
      ? url
      : null;
}

@visibleForTesting
({String keijitype, String genrecd, String seqNo})? gakujoMessageTargetFromUrl(
  String url,
) {
  if (!AllowedWebOrigins.canLoad(url, debugAllowed: false)) {
    return null;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.path != '/campusweb/campussquare.do') {
    return null;
  }
  try {
    final params = uri.queryParameters;
    if (params['_flowId'] != 'KJW0001100-flow') {
      return null;
    }
    final keijitype = params['keijitype'];
    final genrecd = params['genrecd'];
    final seqNo = params['seqNo'];
    final numeric = RegExp(r'^[0-9]+$');
    if (keijitype == null ||
        genrecd == null ||
        seqNo == null ||
        !numeric.hasMatch(keijitype) ||
        !numeric.hasMatch(genrecd) ||
        !numeric.hasMatch(seqNo)) {
      return null;
    }
    return (keijitype: keijitype, genrecd: genrecd, seqNo: seqNo);
  } on FormatException {
    return null;
  }
}

@visibleForTesting
class GakujoCalendarOperationGate {
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  bool tryStart() {
    if (_isRunning) {
      return false;
    }
    _isRunning = true;
    return true;
  }

  void finish() {
    _isRunning = false;
  }
}

@visibleForTesting
const gakujoPortalAuthStateProbeScript = gakujoPortalAuthStateProbeJs;

@visibleForTesting
const gakujoAuthenticatedSessionResetScript = gakujoAuthenticatedSessionResetJs;

class GoogleDriveAccountChanged implements Exception {
  const GoogleDriveAccountChanged();
}

Future<String> googleDriveTokenForAccount(
  StarSyncGoogleAuth auth,
  String email, {
  bool forceRefresh = false,
}) async {
  if (auth.currentEmail != email) throw const GoogleDriveAccountChanged();
  final token = await auth.accessToken(forceRefresh: forceRefresh);
  if (auth.currentEmail != email) throw const GoogleDriveAccountChanged();
  return token;
}

class GoogleDriveSaveFolderPicker {
  StarSyncGoogleAuthSession? _active;

  Future<GoogleDriveFolder?> pick({
    required StarSyncGoogleAuthSession session,
    required GoogleDriveFileSaver saver,
    required void Function() checkCurrent,
  }) async {
    checkCurrent();
    final previous = _active;
    if (previous != null) {
      if (previous.generation == session.generation) {
        throw const StarSyncGoogleAuthException(StarSyncGoogleAuthErrorKind.failed);
      }
      cancel(previous);
    }
    _active = session;
    final String? id;
    try {
      id = await session.auth.pickDriveFolder();
      if (!identical(_active, session)) return null;
    } finally {
      if (identical(_active, session)) _active = null;
    }
    checkCurrent();
    if (id == null) return null;
    final folder = await saver.getPrivateFolder(id);
    checkCurrent();
    return folder;
  }

  void cancel(StarSyncGoogleAuthSession session) {
    if (!identical(_active, session)) return;
    _active = null;
    session.auth.cancelPendingDriveFolderPick();
  }
}

class _PageRestoreReservation {
  String? url;
  Object? _owner;

  void reserve(String? target, {Object? owner}) {
    url = target;
    _owner = owner;
  }

  // Redirect and authentication callbacks can reselect the existing target.
  // A new notification uses reserve even when it has exactly the same URL.
  void update(String? target) {
    if (url != target) reserve(target);
  }

  bool owns(Object owner) => identical(_owner, owner);

  bool release(Object owner) {
    if (!owns(owner)) return false;
    reserve(null);
    return true;
  }
}

class _GakujoWebAppState extends State<GakujoWebApp>
    with WidgetsBindingObserver {
  late final GakujoWebViewController _controller;
  Future<void> Function()? _refreshOpenFavorites;
  Future<void> Function()? _refreshOpenStarredMessages;
  late final GakujoOfflineRetry _offlineRetry;
  late bool _appInBackground;
  int? _offlineRetryNavigationRevision;
  // Reloads since the last successful Gakujo page. The probe can reach the
  // host while the WebView still fails (proxy, captive portal), so cap it.
  int _offlineAutoReloads = 0;
  late final Future<void> _webViewReady;
  late final Future<void> _initialPageLoaded;
  late final NotificationTapConsumer _notificationConsumer;
  late final Future<bool> _notificationNavigationReady;
  late final TwoFactorSecretStore _secretStore;
  late final TotpGenerator _totpGenerator;
  late final GakujoWebViewService _webViewService;
  late final GakujoDownloadService _downloadService;
  late final GakujoCalendarService _calendarService;
  late final GakujoDownloadHistoryStore _downloadHistoryStore;
  late final GakujoActivityStore _activityStore;
  late final StarSyncGoogleAuth _starSyncGoogleAuth;
  final _driveSaveFolderPicker = GoogleDriveSaveFolderPicker();
  GoogleDriveFileSaver? _googleDriveFileSaver;
  String? _driveSaverEmail;
  String? _starSyncGoogleEmail;
  int? _draftReadRevision;
  final _driveDownloadPreference = DriveDownloadPreference();
  final _driveUploads = DriveDownloadQueue();
  bool _driveDownloadsSuspended = false;
  bool _driveSwitchSigningIn = false;
  bool get _driveDownloadsEnabled => !_driveDownloadsSuspended && _appSettingsLoaded &&
      _driveDownloadPreference.matches(_driveAccountHash, _starSyncGoogleAuth.currentEmail);
  final _loginIdentity = GakujoLoginIdentity();
  String? get _activeLoginAccount => _loginIdentity.active;
  final _notificationHistoryAccount = ValueNotifier<String?>(null);
  ({String account, Object owner, _PendingMessageOpen? message})? _historyNavigation;
  set _activeLoginAccount(String? value) {
    _loginIdentity.active = value;
    if (value != null && _historyNavigation?.account != value) {
      _discardHistoryNavigation();
    }
    _notificationHistoryAccount.value = value;
  }

  void _discardHistoryNavigation() {
    final history = _historyNavigation;
    if (history == null) return;
    _historyNavigation = null;
    _loginRestore.release(history.owner);
    if (_navigationRecovery.release(history.owner)) {
      _navigationRecoveryCandidateFailed = false;
    }
    if (history.message != null && identical(history.message, _pendingMessageOpen)) {
      _pendingMessageOpenTimer?.cancel();
      _pendingMessageOpen = null;
    }
  }

  bool _keepsHistoryMessageDuringLogin(String url) {
    final history = _historyNavigation;
    return history != null &&
        history.message != null &&
        identical(history.message, _pendingMessageOpen) &&
        (_activeLoginAccount == null || _looksLikeLoginOrTimeoutUrl(url)) &&
        AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed);
  }
  String? get _driveAccountHash => _activeLoginAccount;
  late Future<void> _driveDownloadsLoad;
  int _googleCancelGeneration = 0;
  final _driveDownloadQueue = StorageOperationQueue();
  late final StarSyncEngine _starSyncEngine;
  Future<void>? _starSyncLoad;
  late final GakujoNotificationService _notificationService;
  late final GakujoDeadlineNotificationCoordinator
      _deadlineNotificationCoordinator;
  late final AppUpdateService _updateService;
  AppUpdateInfo? _availableUpdate;
  DateTime? _lastDailyUpdateCheckAt;
  DateTime? _updateRetryNotBefore;
  bool _isCheckingUpdateInBackground = false;
  late final GakujoAcademicCalendarResolver _academicCalendarResolver;
  late final GakujoLastPageStore _lastPageStore;
  late final GakujoAppSettingsStore _appSettingsStore;
  late final GakujoLocalPrefsStore _localPrefsStore;
  late final MacosInputFocusService _macosInputFocusService;
  late final bool _debugAllowed;
  String? _currentPageUrl;
  String? _lastAllowedPageUrl;
  final _status = ValueNotifier('準備中');
  SnackBar? _linuxSnackBar;
  final _linuxDownloads = <String, LinuxDownloadProgress>{};
  bool _linuxFindOpen = false;
  final _linuxFindController = TextEditingController();
  final _linuxFindFocusNode = FocusNode();
  int _linuxFindMatches = 0;
  bool _linuxFindFound = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _previewNavigationState = 'none';
  String? _activePreviewToken;
  String? _detachedPreviewToken;
  bool _virtualPreviewForward = false;
  String? _returnDialogMarker;
  String? _pendingReturnDialog;
  Timer? _pendingReturnDialogTimer;
  BuildContext? _returnedDialogContext;
  int? _returnedDialogRevision;
  bool get _returnedDialogOpening =>
      _returnedDialogRevision == _navigationRevision;
  DownloadDestinationSettings _downloadRoot =
      const DownloadDestinationSettings(isConfigured: false);
  GakujoAppSettings _appSettings = const GakujoAppSettings();
  double? _reportedGpa;
  bool _externalServiceNoticeDismissed = false;
  String? _currentCourseName;
  int _courseDocument = 0;
  final _loginRestore = _PageRestoreReservation();
  String? get _pendingLoginRestoreUrl => _loginRestore.url;
  set _pendingLoginRestoreUrl(String? url) => _loginRestore.update(url);
  String? _sessionRecoveryUrl;
  String? _authenticatedPageUrl;
  final _navigationRecovery = _PageRestoreReservation();
  String? get _navigationRecoveryCandidateUrl => _navigationRecovery.url;
  set _navigationRecoveryCandidateUrl(String? url) =>
      _navigationRecovery.update(url);
  bool _navigationRecoveryCandidateFailed = false;
  String? _mainFrameNavigationUrl;
  String? _deferredNavigationAfterPageOperationUrl;
  String? _deferredNotificationAfterPageOperationUrl;
  _PendingMessageOpen? _pendingMessageOpen;
  Timer? _pendingMessageOpenTimer;
  Completer<void>? _messageOpenProcessing;
  int? _messageOpenReadyNavigationRevision;
  String? _lastSessionRecoveryNoticeUrl;
  bool _loginRestoreAttempted = false;
  bool _isSettingsDialogOpen = false;
  final _linuxOverlayGuardKey = GlobalKey<LinuxOverlayGuardState>();
  final _linuxOverlayNavigation = ValueNotifier<int>(0);
  // The setup wizard can open before macOS reads the saved download folder.
  VoidCallback? _refreshSetupWizard;
  DateTime? _lastAssignmentRefresh;
  DateTime? _lastMessageRefresh;
  bool _backgroundActivityRefreshRunning = false;
  Timer? _backgroundRefreshTimer;
  late final GakujoCollectionSyncScheduler _collectionSyncScheduler;
  bool _isImportingSettings = false;
  final _backupOperations = StorageOperationQueue();
  final _settingsOperations = StorageOperationQueue();
  bool _appSettingsLoaded = false;
  bool _secureStorageAccessAllowed = !Platform.isMacOS;
  final _linuxSessionSettings = LinuxSessionSettings();
  final _startupFlow = GakujoStartupFlow();
  final _startupPlaceholderFeatureFlags = <GakujoFeatureFlag>{};
  bool _loginAutofillStorageLoadAttempted = false;
  bool _secureStorageRecoveryDialogVisible = false;
  double _desktopZoom = 1.0;
  double _desktopPanZoomStartZoom = 1.0;
  final _desktopPanZoomGesture = DesktopPanZoomGesture();
  final _desktopHistorySwipe = DesktopHistorySwipeTracker();
  final _historyTouchPointers = <int>{};
  bool _desktopPanZoomSuppressed = false;
  bool _desktopPanZoomActive = false;
  bool _desktopPanZoomInterrupted = false;
  double _desktopLastPinchScale = 1;
  int _previewGestureRevision = 0;
  int? _desktopWheelZoomRevision;
  Timer? _previewGestureTimer;
  int? _touchHistorySwipePointer;
  Offset? _touchHistorySwipeStart;
  double _touchHistorySwipeViewportWidth = 0;
  int _desktopZoomApplyRevision = 0;
  Offset? _desktopZoomOrigin;
  Timer? _autoBackupTimer;
  Timer? _autoBackupDebounce;
  bool _autoBackupWrittenThisLaunch = false;
  DateTime? _lastAutomaticBackupAt;
  Completer<String>? _nextPageFinishedCompleter;
  ({String url, int revision, Completer<void> disposed})? _deferredPageNavigation;
  ({String url, Completer<void> completer})? _pageFinishedProcessing;
  Future<void> _desktopZoomApplyQueue = Future<void>.value();
  final GakujoCalendarOperationGate _calendarOperationGate =
      GakujoCalendarOperationGate();
  final GakujoDownloadOperationGate _downloadOperationGate =
      GakujoDownloadOperationGate();
  final GakujoUploadLibraryGate _uploadLibraryGate = GakujoUploadLibraryGate();
  final GakujoPdfPreviewServer _pdfPreviewServer = GakujoPdfPreviewServer();
  int _webViewDownloadRequestSequence = 0;
  int _navigationRevision = 0;
  static final _protectedSecretPromptGate = ProtectedSecretPromptGate();
  int? _authRetryNavigationRevision;
  int? _pendingPageFinishedNavigationRevision;
  int? _loginAutofillStoppedNavigationRevision;
  bool _deferLoginAutofillDuringSetup = false;

  static const double _minimumDesktopZoom = 0.5;
  static const double _maximumDesktopZoom = 2.0;
  static const double _desktopZoomStep = 0.1;
  static const double _desktopHistorySwipeThreshold = 120;
  static const double _desktopHorizontalSwipeDominance = 1.35;

  @override
  void initState() {
    super.initState();
    _appInBackground = _isHiddenOrPaused(WidgetsBinding.instance.lifecycleState);
    WidgetsBinding.instance.addObserver(this);
    _appSettingsStore = widget._appSettingsStore ?? GakujoAppSettingsStore();
    _secretStore = widget._secretStore ?? TwoFactorSecretStore(
      protectionState: _appSettingsStore.protectionState,
    );
    _totpGenerator = widget._totpGenerator ?? const TotpGenerator();
    final platformService = GakujoPlatformService.current();
    _webViewService = widget._webViewService ?? platformService.createWebViewService();
    _calendarService = platformService.createCalendarService();
    _downloadHistoryStore = GakujoDownloadHistoryStore();
    _activityStore = _SyncActivityStore(() {
      if (_activeLoginAccount != null) _scheduleStarSync();
    });
    _starSyncGoogleAuth = createStarSyncGoogleAuth();
    _driveDownloadsLoad = _loadDriveDownloadsPreference();
    _starSyncEngine = StarSyncEngine(
      setupGuard: (config) => StarSyncGoogleAuthSession(
        _starSyncGoogleAuth, email: config.googleEmail,
      ).checkCurrent,
      transportFactory: (config) => StarSyncGoogleDriveTransport(
        accessToken: StarSyncGoogleAuthSession(
          _starSyncGoogleAuth, email: config.googleEmail,
        ).accessToken,
      ),
      activityStore: _activityStore,
      collections: [
        StarSyncFavoritesCollection(_activityStore, onChanged: () async {
          await _refreshOpenFavorites?.call();
        }),
        StarSyncNotifiedDeadlinesCollection(_activityStore),
        StarSyncSettingsCollection(
          read: () async => exportStarSyncPortableSettings(_appSettings),
          apply: _applySyncedSettings,
          localCommitStorage: _appSettingsStore.backupStorage,
          commitLock: _settingsOperations.runExclusive,
          applyWithCommit: _applySyncedSettings,
        ),
        StarSyncReportDraftsCollection(
          read: _readSyncedReportDrafts,
          apply: _applySyncedReportDrafts,
        ),
      ],
      clearDraftsBefore: _clearSyncedDraftsBefore,
      loginId: () => _appSettings.savedLoginId,
      accountHash: () => _activeLoginAccount,
      canSync: () => _canSyncStars,
      canUploadAutomaticBackup: () => mounted && _appSettingsLoaded &&
          _secureStorageAccessAllowed &&
          _appSettings.isFeatureEnabled(GakujoFeatureFlag.autoBackup),
      onLocalStarsChanged: () {
        if (_canSyncStars) {
          unawaited(_refreshMessageStars());
          unawaited(_refreshOpenStarredMessages?.call());
        }
      },
    );
    _collectionSyncScheduler = GakujoCollectionSyncScheduler(
      canSync: () => _canSyncStars,
      schedule: (trigger, delay) => _starSyncEngine.scheduleSync(
        trigger: trigger,
        delay: delay,
        shouldSync: () => _canSyncStars,
      ),
    );
    _notificationService = GakujoNotificationService(
      activeAccount: () => _activeLoginAccount,
    );
    _deadlineNotificationCoordinator = GakujoDeadlineNotificationCoordinator(
      activityStore: _activityStore,
      notificationService: _notificationService,
    );
    _updateService = widget._updateService ?? const AppUpdateService();
    _academicCalendarResolver = const GakujoAcademicCalendarResolver();
    _lastPageStore = widget._lastPageStore ?? GakujoLastPageStore();
    _localPrefsStore = widget._localPrefsStore ?? GakujoLocalPrefsStore();
    unawaited(_restoreSavedGpa());
    _macosInputFocusService = const MacosInputFocusService();
    _debugAllowed = widget._debugAllowed ?? kDebugMode;

    _controller = _webViewService.createController();
    final controller = _controller;
    Future<void> onMouseHistoryNavigation(
      MouseHistoryNavigation direction,
    ) async {
      if (direction == MouseHistoryNavigation.back) {
        await _goBackIfPossible();
      } else {
        await _goForwardIfPossible();
      }
    }
    if (controller is WindowsGakujoWebViewController) {
      controller.onMouseHistoryNavigation = onMouseHistoryNavigation;
    } else if (controller is WebViewFlutterGakujoWebViewController) {
      controller.onMouseHistoryNavigation = onMouseHistoryNavigation;
      if (defaultTargetPlatform == TargetPlatform.linux) {
        controller.onWheelZoom = (dyNotches, position) {
          _handleDesktopWheelZoom(dyNotches * kLinuxWheelNotchPixels, position);
        };
        controller.onDownloadProgress = (progress) {
          if (!mounted) return;
          setState(() {
            if (progress.isActive) {
              _linuxDownloads[progress.id] = progress;
            } else {
              _linuxDownloads.remove(progress.id);
            }
          });
        };
        controller.onDownloadSaved = (url, path) {
          _showWebKitDownloadSavedSnackBar(path);
        };
        controller.onDownloadFailed = (url, description) {
          _showWebKitDownloadFailedSnackBar(url);
        };
        controller.onKeyZoom = (action) {
          if (!mounted || !_supportsDesktopZoom) return;
          switch (action) {
            case LinuxKeyZoomAction.zoomIn:
              unawaited(_changeDesktopZoomBy(_desktopZoomStep));
              break;
            case LinuxKeyZoomAction.zoomOut:
              unawaited(_changeDesktopZoomBy(-_desktopZoomStep));
              break;
            case LinuxKeyZoomAction.reset:
              unawaited(_setDesktopZoom(1.0));
              break;
          }
        };
        controller.onPinchZoom = (phase, scale, position) {
          switch (phase) {
            case 'begin':
              _startDesktopPanZoom(position);
              break;
            case 'update':
              _updateDesktopPinchZoom(scale, position);
              break;
            case 'end':
              _endDesktopPanZoom();
              break;
          }
        };
        controller.onWheelScroll = (dxNotches, dyNotches) {
          _handleDesktopHistorySwipeDelta(
            Offset(dxNotches, dyNotches) * kLinuxWheelNotchPixels,
            positiveIsBack: false,
          );
        };
        controller.onFindRequest = _openLinuxFind;
        controller.onFindAgain = _findAgainLinux;
        controller.onFindResult = (matches, found) {
          if (!mounted || !_linuxFindOpen) return;
          setState(() {
            _linuxFindMatches = matches;
            _linuxFindFound = found;
          });
        };
      }
    }
    _offlineRetry = GakujoOfflineRetry(
      probe: widget._gakujoReachable ?? probeGakujoReachability,
      onReachable: () => unawaited(_reloadAfterConnectivityRestored()),
      onExpired: _onOfflineRetryExpired,
    );
    _downloadService = Platform.isWindows
        ? FileSystemGakujoDownloadService(
            authenticatedBytesLoader: _downloadBytesWithWebViewSession,
          )
        : platformService.createDownloadService();
    _webViewReady = _configureWebViewController();

    if (_secureStorageAccessAllowed) {
      unawaited(_loadDownloadRoot());
    }
    _notificationConsumer = _notificationService.bindNotificationTaps(
      _acceptDeadlineNotification,
    );
    _initialPageLoaded = _loadInitialPage();
    _notificationNavigationReady = Future.any([
      _initialPageLoaded.then((_) => true, onError: (Object _) => false),
      _notificationConsumer.detached.then((_) => false),
    ]);
    unawaited(_initialPageLoaded);
    // A desktop window can stay on one page all day; keep assignments and
    // 連絡通知 current anyway. The refresh itself runs at most half-hourly;
    // checking more often keeps a tick that lands just short of 30 minutes
    // after a page-load refresh from stretching the gap to an hour.
    _backgroundRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) {
        unawaited(_refreshAssignmentsInBackground());
        unawaited(_checkForUpdatesInBackground());
      },
    );
    unawaited(_checkForUpdatesAfterInitialPage());
  }

  @override
  void dispose() {
    _notificationConsumer.dispose();
    _notificationHistoryAccount.dispose();
    _registrationSession?.timer?.cancel();
    _cancelDriveUploads();
    _deferredPageNavigation?.disposed.complete();
    _status.dispose();
    unawaited(_pdfPreviewServer.close());
    _cancelOfflineRetry();
    _backgroundRefreshTimer?.cancel();
    _collectionSyncScheduler.dispose();
    _starSyncEngine.dispose();
    _pendingMessageOpenTimer?.cancel();
    _pendingReturnDialogTimer?.cancel();
    unawaited(_saveCurrentPageUrl());
    final controller = _controller;
    if (controller is WebViewFlutterGakujoWebViewController) {
      controller.onWheelZoom = null;
      controller.onKeyZoom = null;
      controller.onDownloadProgress = null;
      controller.onDownloadSaved = null;
      controller.onDownloadFailed = null;
      controller.onPinchZoom = null;
      controller.onWheelScroll = null;
      controller.onFindRequest = null;
      controller.onFindAgain = null;
      controller.onFindResult = null;
    }
    _linuxOverlayNavigation.dispose();
    _linuxFindController.dispose();
    _linuxFindFocusNode.dispose();
    unawaited(_controller.dispose());
    _desktopHistorySwipe.dispose();
    _previewGestureTimer?.cancel();
    _autoBackupTimer?.cancel();
    _autoBackupDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _protectedSecretPromptGate.background();
    if (state == AppLifecycleState.resumed && _protectedSecretPromptGate.resume()) {
      // The cancelled prompt may have been the 2FA one; retry both.
      unawaited(() async {
        await _injectLoginAutofillAssistIfAllowed();
        await _injectTwoFactorAutofillIfAllowed();
      }());
    }
    if (_isHiddenOrPaused(state)) {
      _appInBackground = true;
      // Keep the failed navigation until the app is visible again.
      _offlineRetry.cancel();
    } else if (state == AppLifecycleState.resumed ||
        (_appInBackground &&
            defaultTargetPlatform == TargetPlatform.windows &&
            state == AppLifecycleState.inactive)) {
      // Windows can restore a minimized window without giving it focus.
      _appInBackground = false;
      if (_offlineRetryNavigationRevision == _navigationRevision) {
        _offlineRetry.start();
      }
    }
    if (state == AppLifecycleState.resumed && _appSettingsLoaded) {
      unawaited(_checkForUpdatesInBackground());
      unawaited(_resumeNotificationsAndRefresh());
      unawaited(_syncStarsInBackground(StarSyncTrigger.resume));
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_saveCurrentPageUrl());
      // Desktop windows turn inactive on every focus change; keep the ten
      // retained backups from rotating away within minutes.
      final lastBackup = _lastAutomaticBackupAt;
      if (_appSettingsLoaded &&
          _appSettings.isFeatureEnabled(GakujoFeatureFlag.autoBackup) &&
          (lastBackup == null ||
              DateTime.now().difference(lastBackup) >=
                  const Duration(minutes: 10))) {
        unawaited(_writeAutomaticBackup());
      }
    }
  }

  bool get _canSyncStars => mounted && _appSettingsLoaded &&
      _secureStorageAccessAllowed;

  static const _activeLoginAccountKey = 'more_better_gakujo_active_login_account';

  Future<void> _loadActiveLoginAccount() async {
    final revision = _loginIdentity.revision;
    final restored = await SecureStorageFactory.create().read(key: _activeLoginAccountKey);
    if (revision != _loginIdentity.revision ||
        (_loginIdentity.pageSeen && !_loginIdentity.pageConfirmed)) {
      return;
    }
    _loginIdentity.restored = restored;
    if (_loginIdentity.pageSeen && _loginIdentity.pageConfirmed && restored != null) {
      _loginIdentity.restored = null;
      await _setActiveLoginAccount(restored);
    }
  }

  int _mainFrameNavigationStarts = 0;
  int _plannerNavigationStarts = 0;
  bool _registrationAvailable = false;
  bool _registrationOpening = false;
  _RegistrationSession? _registrationSession;
  String? _registrationSummary;

  void _redrawRegistration() => setState(() {});

  void _setRegistrationAvailable(bool value) {
    if (_registrationAvailable != value && mounted) {
      setState(() => _registrationAvailable = value);
    }
  }

  void _setRegistrationSession(_RegistrationSession? session, {required String? summary}) {
    setState(() {
      _registrationSession = session;
      _registrationSummary = summary;
    });
  }
  bool _plannerOpening = false;

  void _submitLoginAccount(String account) {
    final navigation = _navigationRevision;
    if (_loginIdentity.submit(account, navigation: navigation)) {
      unawaited(_setActiveLoginAccount(null, resync: false).catchError(
        (Object error, StackTrace stackTrace) {
          developer.log('Failed to clear active login account',
              name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
        },
      ));
    }
    // A reported submit that starts no navigation was stopped (validation, a
    // page handler); it must not wait to be promoted by some later page.
    final starts = _mainFrameNavigationStarts;
    bool stillThisSubmit() =>
        mounted &&
        _loginIdentity.pending == account &&
        _loginIdentity.pendingNavigation == navigation;
    Timer(const Duration(seconds: 30), () {
      if (_mainFrameNavigationStarts == starts && stillThisSubmit()) {
        _dropPendingLogin();
      }
    });
    // Login, including typing a 2FA code, ends well within this; a candidate
    // left over from an abandoned attempt must not wait for some later page.
    Timer(const Duration(minutes: 5), () {
      if (stillThisSubmit()) _dropPendingLogin();
    });
  }

  void _dropPendingLogin() {
    _loginIdentity.pending = null;
    _loginIdentity.pendingNavigation = null;
  }

  Future<void> _storedLoginAccountWrites = Future<void>.value();

  /// Stored identity writes run in order, so an invalidating delete issued
  /// while an activation write is in flight lands after it.
  Future<void> _writeStoredLoginAccount(String? account) {
    final write = _storedLoginAccountWrites.then((_) {
      final storage = SecureStorageFactory.create();
      return account == null
          ? storage.delete(key: _activeLoginAccountKey)
          : storage.write(key: _activeLoginAccountKey, value: account);
    });
    _storedLoginAccountWrites = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> _setActiveLoginAccount(String? account, {bool resync = true, bool Function()? stillValid}) async {
    if (account != null && _activeLoginAccount == account) return;
    _finishRegistration('ログイン状態が変わったため終了しました。');
    _setRegistrationAvailable(false);
    if (account == null) _authenticatedPageUrl = null;
    final revision = ++_loginIdentity.revision;
    _activeLoginAccount = null;
    _cancelDriveUploads();
    // Delete the stored identity now, not behind a running sync: a crash in
    // between must not restore it onto the next person's session.
    final deletion = account == null ? _writeStoredLoginAccount(null) : null;
    // Awaited in the queue below; this only keeps an early failure from being
    // reported as unhandled before then.
    if (deletion != null) unawaited(deletion.then<void>((_) {}, onError: (Object _) {}));
    await _starSyncEngine.runAccountChange(() async {
      if (account == null) {
        await deletion;
      } else {
        if (revision != _loginIdentity.revision) return;
        if (!(stillValid?.call() ?? true)) {
          _loginIdentity.pending = account;
          return;
        }
        await _writeStoredLoginAccount(account);
        if (mounted && revision == _loginIdentity.revision && (stillValid?.call() ?? true)) {
          _activeLoginAccount = account;
          _lastAssignmentRefresh = null;
          _lastMessageRefresh = null;
          unawaited(_syncReminders(allowPermissionRequest: false));
        } else {
          await _writeStoredLoginAccount(null);
          if (revision == _loginIdentity.revision) _loginIdentity.pending = account;
        }
      }
    });
    if (mounted) setState(() {});
    if (resync && revision == _loginIdentity.revision) unawaited(_syncStarsInBackground(StarSyncTrigger.resume));
  }

  Future<void> _ensureStarSyncLoaded() async {
    try {
      await (_starSyncLoad ??= () async {
        await _starSyncEngine.load();
        if (_starSyncEngine.config != null) {
          try {
            _starSyncGoogleEmail = await _driveDownloadQueue.run(
              () => _starSyncGoogleAuth.restore(
                expectedEmail: _starSyncEngine.config?.googleEmail,
              ),
            );
          } on Object catch (error) {
            developer.log('Failed to restore Google sign-in: ${error.runtimeType}',
                name: 'MoreBetterGakujo');
          }
        }
      }());
    } on Object {
      _starSyncLoad = null;
      rethrow;
    }
  }

  Future<void> _syncStarsInBackground([
    StarSyncTrigger trigger = StarSyncTrigger.startup,
  ]) async {
    if (!_appSettingsLoaded || !_secureStorageAccessAllowed) return;
    try {
      await _ensureStarSyncLoaded();
      if (!_canSyncStars) return;
      await _starSyncEngine.syncNow(trigger: trigger);
    } on Object catch (error) {
      developer.log('Failed to sync message stars: ${error.runtimeType}',
          name: 'MoreBetterGakujo');
    }
  }

  void _scheduleStarSync() => _collectionSyncScheduler.localChange();

  void _scheduleDraftSync() => _collectionSyncScheduler.draftChanged();

  Future<void> _resumeNotificationsAndRefresh() async {
    unawaited(_notificationService.collectHistory());
    try {
      await _deadlineNotificationCoordinator.onAppResumed(
        notificationsEnabled: _appSettings.isFeatureEnabled(
          GakujoFeatureFlag.deadlineNotifications,
        ),
        topics: _appSettings.notificationTopics,
        preferences: _appSettings.notificationPreferences,
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to sync reminders after notification permission check',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (!mounted) {
      return;
    }
    await _refreshAssignmentsInBackground(allowPermissionRequest: false);
  }

  @override
  Widget build(BuildContext context) {
    final compactPreviewForKeyboard = Platform.isAndroid &&
        _previewNavigationState == 'visible' &&
        MediaQuery.orientationOf(context) == Orientation.landscape &&
        MediaQuery.viewInsetsOf(context).bottom > 0;
    final page = PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleSystemBack());
      },
      child: Scaffold(
        appBar: compactPreviewForKeyboard ? null : _wrapToolbar(AppBar(
          toolbarHeight: _compactToolbarHeight,
          titleSpacing: 12,
          title: GakujoGpaTaunt(
            gpa: _reportedGpa,
          ),
          centerTitle: false,
          actions: [
            GakujoNavigationActions(
              canGoBack: (_canGoBack || _returnDialogMarker != null ||
                      _previewNavigationState == 'visible') &&
                  !_calendarOperationGate.isRunning,
              canGoForward: (_previewNavigationState == 'hidden' ||
                      (_previewNavigationState == 'none' &&
                          (_canGoForward || _virtualPreviewForward))) &&
                  !_calendarOperationGate.isRunning,
              onBack: () => unawaited(_goBack()),
              onForward: () => unawaited(_goForward()),
            ),
            GakujoReloadAction(
              enabled: !_calendarOperationGate.isRunning,
              onReload: () => unawaited(
                _handleToolbarAction(_ToolbarAction.reload),
              ),
            ),
            IconButton(
              tooltip: '学務のHOMEへ',
              onPressed: _calendarOperationGate.isRunning
                  ? null
                  : () => unawaited(_openGakujoHome()),
              icon: const Icon(Icons.home_outlined),
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
                tooltip: 'スター付き連絡通知',
                onPressed: _calendarOperationGate.isRunning
                    ? null
                    : () => unawaited(_showStarredMessagesDialog()),
                icon: const Icon(Icons.star_outline),
                iconSize: _toolbarIconSize,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: _toolbarButtonExtent,
                  height: _toolbarButtonExtent,
                ),
              ),
            IconButton(
              tooltip: 'AKIKO（空き講義室検索・CIRCLE 運営の外部サービス）',
              onPressed: () => unawaited(_openAkiko()),
              icon: const Icon(Icons.meeting_room_outlined),
              iconSize: _toolbarIconSize,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(
                width: _toolbarButtonExtent,
                height: _toolbarButtonExtent,
              ),
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
                enabled: !_calendarOperationGate.isRunning,
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
                    value: _ToolbarAction.coursePlanner,
                    child: Text('履修手帖を開く'),
                  ),
                  const PopupMenuItem<Object>(
                    value: _ToolbarAction.notificationHistory,
                    child: Text('通知履歴'),
                  ),
                  const PopupMenuItem<Object>(
                    value: _ToolbarAction.importCoursePlanner,
                    child: Text('学務の照会結果をプランナーに取り込む'),
                  ),
                  const PopupMenuItem<Object>(
                    value: _ToolbarAction.copyCoursePlanner,
                    child: Text('学務の照会結果を履修手帖用にコピー'),
                  ),
                  PopupMenuItem<Object>(
                    value: _ToolbarAction.registrationAssist,
                    enabled: _registrationAvailable && _hasRegistrationIdentity &&
                        _registrationSession == null,
                    child: const Text('履修手帖の時間割を履修登録に入力'),
                  ),
                  const PopupMenuItem<Object>(
                    value: _ToolbarAction.addFavorite,
                    child: Text('お気に入りに追加'),
                  ),
                    const PopupMenuItem<Object>(
                      value: _ToolbarAction.messageStars,
                      child: Text('スター付き連絡通知'),
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
                    child: Text('再読み込み'),
                  ),
                ],
                onSelected: (selection) =>
                    unawaited(_handleToolbarSelection(selection)),
              ),
            ),
          ],
        )),
        body: Column(
          children: [
            if (!compactPreviewForKeyboard) Material(
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
                    child: ValueListenableBuilder<String>(
                      valueListenable: _status,
                      builder: (context, status, _) => Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (defaultTargetPlatform == TargetPlatform.linux &&
                _linuxSnackBar != null)
              LinuxSnackBarStrip(
                snackBar: _linuxSnackBar!,
                onDismiss: () => setState(() => _linuxSnackBar = null),
              ),
            if (_availableUpdate != null &&
                _appSettings.isFeatureEnabled(GakujoFeatureFlag.updateNotice) &&
                !compactPreviewForKeyboard)
              _buildUpdateBanner(_availableUpdate!),
            if (defaultTargetPlatform == TargetPlatform.linux &&
                _linuxFindOpen &&
                !_isSettingsDialogOpen)
              LinuxNativeToolbarTooltips(
                child: LinuxFindBar(
                  controller: _linuxFindController,
                  focusNode: _linuxFindFocusNode,
                  matches: _linuxFindMatches,
                  found: _linuxFindFound,
                  onFind: _searchLinuxFind,
                  onClose: () => _closeLinuxFind(focusPage: true),
                ),
              ),
            Expanded(
              // Android 15+ draws edge to edge; without this the end of a
              // page (often a submit button) stays under the navigation bar.
              child: SafeArea(
                top: compactPreviewForKeyboard,
                child: _isSettingsDialogOpen &&
                        defaultTargetPlatform != TargetPlatform.linux
                    ? const SizedBox.expand()
                    : _buildWebViewArea(),
              ),
            ),
            ?_buildRegistrationPanel(),
            if (defaultTargetPlatform == TargetPlatform.linux &&
                _linuxDownloads.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 144),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final progress in _linuxDownloads.values)
                        LinuxDownloadStrip(
                          key: ValueKey(progress.id),
                          progress: progress,
                          onCancel: () => _cancelLinuxDownload(progress.id),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (defaultTargetPlatform != TargetPlatform.linux) return page;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleLinuxFindKeyEvent,
      child: page,
    );
  }

  PreferredSizeWidget _wrapToolbar(PreferredSizeWidget toolbar) {
    if (defaultTargetPlatform != TargetPlatform.linux) return toolbar;
    return PreferredSize(
      preferredSize: toolbar.preferredSize,
      child: LinuxNativeToolbarTooltips(child: toolbar),
    );
  }

  Widget _buildWebViewArea() {
    Widget content = Listener(
      onPointerDown: _handleTouchHistorySwipeDown,
      onPointerMove: _handleTouchHistorySwipeMove,
      onPointerUp: _handleTouchHistorySwipeEnd,
      onPointerCancel: _handleTouchHistorySwipeEnd,
      child: _webViewService.buildWidget(
        _controller,
        onError: (message) => _showSnackBar('ファイルを選べませんでした: $message'),
      ),
    );

    if (defaultTargetPlatform == TargetPlatform.linux) {
      final controller = _controller;
      content = LinuxOverlayGuard(
        key: _linuxOverlayGuardKey,
        obscured: widget.linuxOverlayObscured,
        forceObscured: _isSettingsDialogOpen,
        navigation: _linuxOverlayNavigation,
        onObscuredChanged: controller is WebViewFlutterGakujoWebViewController
            ? controller.setLinuxPageObscured
            : null,
        takeSnapshot: controller is WebViewFlutterGakujoWebViewController
            ? controller.takeLinuxSnapshot
            : null,
        hasNativeFocus: controller is WebViewFlutterGakujoWebViewController
            ? controller.hasLinuxFocus
            : null,
        restoreNativeFocus: controller is WebViewFlutterGakujoWebViewController
            ? controller.restoreLinuxFocus
            : null,
        child: content,
      );
    }

    if (!_supportsDesktopZoom) {
      return AbsorbPointer(
        absorbing: _calendarOperationGate.isRunning,
        child: content,
      );
    }

    return AbsorbPointer(
      absorbing: _calendarOperationGate.isRunning,
      child: Focus(
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
      ),
    );
  }

  void _handleTouchHistorySwipeDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      _historyTouchPointers.add(event.pointer);
    }
    if (_previewNavigationState == 'visible' ||
        _historyTouchPointers.length > 1) {
      _resetTouchHistorySwipe();
      return;
    }
    if (supportsNativeGakujoHistoryGestures(defaultTargetPlatform) ||
        event.kind != PointerDeviceKind.touch ||
        _touchHistorySwipePointer != null) {
      return;
    }
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final startX = event.localPosition.dx;
    const edgeExtent = 36.0;
    if (startX > edgeExtent && startX < viewportWidth - edgeExtent) {
      return;
    }
    _touchHistorySwipePointer = event.pointer;
    _touchHistorySwipeStart = event.localPosition;
    _touchHistorySwipeViewportWidth = viewportWidth;
  }

  void _handleTouchHistorySwipeMove(PointerMoveEvent event) {
    if (_previewNavigationState == 'visible') {
      _resetTouchHistorySwipe();
      return;
    }
    final start = _touchHistorySwipeStart;
    if (_touchHistorySwipePointer != event.pointer || start == null) {
      return;
    }
    final delta = event.localPosition - start;
    if (delta.dy.abs() > 32 && delta.dy.abs() > delta.dx.abs()) {
      _resetTouchHistorySwipe();
      return;
    }
    final navigation = gakujoEdgeSwipeNavigation(
      startX: start.dx,
      viewportWidth: _touchHistorySwipeViewportWidth,
      delta: delta,
    );
    if (navigation == null) {
      return;
    }
    _resetTouchHistorySwipe();
    switch (navigation) {
      case GakujoHistoryNavigation.back:
        unawaited(_goBackIfPossible());
        break;
      case GakujoHistoryNavigation.forward:
        unawaited(_goForwardIfPossible());
        break;
    }
  }

  void _handleTouchHistorySwipeEnd(PointerEvent event) {
    _historyTouchPointers.remove(event.pointer);
    if (_touchHistorySwipePointer == event.pointer) {
      _resetTouchHistorySwipe();
    }
  }

  void _resetTouchHistorySwipe() {
    _touchHistorySwipePointer = null;
    _touchHistorySwipeStart = null;
    _touchHistorySwipeViewportWidth = 0;
  }

  void _handleDesktopPointerHover(PointerHoverEvent event) {
    _desktopZoomOrigin = event.localPosition;
  }

  void _handleDesktopPointerDown(PointerDownEvent event) {
    _desktopZoomOrigin = event.localPosition;
  }

  bool get _supportsDesktopZoom {
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  KeyEventResult _handleDesktopZoomKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_handleLinuxFindKeyEvent(node, event) == KeyEventResult.handled) {
      return KeyEventResult.handled;
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

  KeyEventResult _handleLinuxFindKeyEvent(FocusNode node, KeyEvent event) {
    if (defaultTargetPlatform == TargetPlatform.linux &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyF &&
        !_isSettingsDialogOpen) {
      _openLinuxFind();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openLinuxFind({bool forward = true}) {
    if (!mounted || _isSettingsDialogOpen) return;
    final wasOpen = _linuxFindOpen;
    setState(() => _linuxFindOpen = true);
    if (!wasOpen && _linuxFindController.text.isNotEmpty) {
      _searchLinuxFind(_linuxFindController.text, forward: forward);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_linuxFindOpen || _isSettingsDialogOpen) return;
      _linuxFindFocusNode.requestFocus();
      _linuxFindController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _linuxFindController.text.length,
      );
    });
  }

  void _searchLinuxFind(String text, {bool forward = true}) {
    final controller = _controller;
    if (controller is WebViewFlutterGakujoWebViewController) {
      unawaited(controller.findText(text, forward: forward));
    }
  }

  void _findAgainLinux(bool forward) {
    if (!mounted || _isSettingsDialogOpen) return;
    if (!_linuxFindOpen) {
      _openLinuxFind(forward: forward);
    } else if (_linuxFindController.text.isNotEmpty) {
      _searchLinuxFind(_linuxFindController.text, forward: forward);
    }
  }

  void _closeLinuxFind({bool focusPage = false}) {
    if (!mounted || !_linuxFindOpen) return;
    setState(() {
      _linuxFindOpen = false;
      _linuxFindMatches = 0;
      _linuxFindFound = false;
    });
    final controller = _controller;
    if (controller is WebViewFlutterGakujoWebViewController) {
      unawaited(controller.finishFind(focusPage: focusPage));
    }
  }

  Future<void> _handleDesktopZoomMessage(String message) async {
    if (!_supportsDesktopZoom) {
      return;
    }
    switch (message) {
      case 'in':
        await _changeDesktopZoomBy(_desktopZoomStep);
        break;
      case 'out':
        await _changeDesktopZoomBy(-_desktopZoomStep);
        break;
      case 'reset':
        await _setDesktopZoom(1.0);
        break;
    }
  }

  void _handleDesktopZoomPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (!HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed) {
      _handleDesktopHistorySwipeDelta(
        event.scrollDelta,
        positiveIsBack: false,
      );
      return;
    }

    _handleDesktopWheelZoom(event.scrollDelta.dy, event.localPosition);
  }

  void _handleDesktopWheelZoom(double dy, Offset origin) {
    if (dy == 0) return;
    _desktopHistorySwipe.suppress();
    final interrupted = _desktopWheelZoomRevision != null &&
        _desktopWheelZoomRevision != _previewGestureRevision;
    _desktopWheelZoomRevision ??= _previewGestureRevision;
    _schedulePreviewWheelIdle();
    if (interrupted) return;
    if (_previewNavigationState == 'visible') {
      _zoomPreviewBy(desktopWheelZoom(1, dy));
      return;
    }
    _desktopZoomOrigin = origin;
    unawaited(_setDesktopZoomSmooth(
      desktopWheelZoom(_desktopZoom, dy),
    ));
  }

  void _handleDesktopPanZoomStart(PointerPanZoomStartEvent event) {
    _startDesktopPanZoom(event.localPosition);
  }

  void _startDesktopPanZoom(Offset position) {
    _desktopPanZoomActive = true;
    _desktopPanZoomInterrupted = false;
    _desktopPanZoomSuppressed = _previewNavigationState == 'visible';
    _desktopLastPinchScale = 1;
    _desktopPanZoomStartZoom = _desktopZoom;
    _desktopPanZoomGesture.reset();
    _desktopZoomOrigin = position;
    _resetDesktopHistorySwipe();
  }

  void _handleDesktopPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (_desktopPanZoomInterrupted) {
      _desktopHistorySwipe.suppress();
      return;
    }
    _desktopZoomOrigin = event.localPosition;
    if (_desktopPanZoomGesture.update(event.panDelta, event.scale)) {
      _desktopHistorySwipe.suppress();
      _updateDesktopPinchZoom(event.scale, event.localPosition);
      return;
    }

    if (_desktopPanZoomSuppressed) {
      _desktopHistorySwipe.suppress();
      return;
    }
    _handleDesktopHistorySwipeDelta(
      event.panDelta,
      positiveIsBack: true,
    );
  }

  void _updateDesktopPinchZoom(double scale, Offset position) {
    if (_desktopPanZoomInterrupted) return;
    if (!scale.isFinite || scale <= 0) return;
    final factor = scale / _desktopLastPinchScale;
    _desktopLastPinchScale = scale;
    if (_previewNavigationState == 'visible') {
      _desktopHistorySwipe.suppress();
      _desktopPanZoomSuppressed = true;
      _zoomPreviewBy(factor);
      return;
    }
    if (_desktopPanZoomSuppressed) return;
    _desktopZoomOrigin = position;
    unawaited(_setDesktopZoomSmooth(_desktopPanZoomStartZoom * scale));
  }

  void _handleDesktopPanZoomEnd(PointerPanZoomEndEvent event) {
    _endDesktopPanZoom();
  }

  void _endDesktopPanZoom() {
    _desktopPanZoomActive = false;
    _desktopPanZoomGesture.reset();
    _scheduleDesktopHistorySwipeReset();
  }

  void _handleDesktopHistorySwipeDelta(
    Offset delta, {
    required bool positiveIsBack,
  }) {
    if (_previewNavigationState == 'visible') {
      _desktopHistorySwipe.suppress();
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.windows &&
        defaultTargetPlatform != TargetPlatform.linux) {
      return;
    }
    if (!desktopHistorySwipeAllowed(_desktopZoom)) return;
    final direction = _desktopHistorySwipe.add(
      delta,
      positiveIsBack: positiveIsBack,
      threshold: _desktopHistorySwipeThreshold,
      dominance: _desktopHorizontalSwipeDominance,
    );
    if (direction == GakujoHistoryNavigation.back) {
      unawaited(_goBackIfPossible());
    } else if (direction == GakujoHistoryNavigation.forward) {
      unawaited(_goForwardIfPossible());
    }
  }

  void _scheduleDesktopHistorySwipeReset() {
    _desktopHistorySwipe.scheduleReset();
  }

  void _resetDesktopHistorySwipe() {
    _desktopHistorySwipe.reset();
  }

  void _schedulePreviewWheelIdle() {
    _previewGestureTimer?.cancel();
    _previewGestureTimer = Timer(const Duration(milliseconds: 250), () {
      _desktopWheelZoomRevision = null;
    });
  }

  void _zoomPreviewBy(double factor) {
    if (!factor.isFinite || factor <= 0 || factor == 1) return;
    unawaited(_controller.runJavaScript(
      'window.__MBG_PREVIEW_ZOOM && window.__MBG_PREVIEW_ZOOM(${jsonEncode(factor)});',
    ).catchError((Object error, StackTrace stackTrace) {
      developer.log('Failed to zoom preview', name: 'MoreBetterGakujo',
          error: error, stackTrace: stackTrace);
    }));
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
    if (allowsGakujoPdfPreviewNavigation(
      request,
      platform: defaultTargetPlatform,
      isViewerUrl: _pdfPreviewServer.isViewerUrl,
    )) {
      return GakujoNavigationDecision.navigate;
    }
    if (request.isMainFrame) _invalidateLoginUrl(request.url);
    if (_isInternalBlankUrl(request.url)) {
      return GakujoNavigationDecision.navigate;
    }

    final canNavigate = AllowedWebOrigins.canNavigate(
      request.url,
      debugAllowed: _debugAllowed,
    );
    if (!canNavigate) {
      final label = gakujoBlockedNavigationUrlLabel(
        _displayUrl(request.url),
        platform: defaultTargetPlatform,
      );
      _setStatus('ブロック: $label');
      // Gakujo links to sites such as its own support form; keep them out of
      // this WebView but let the student open them in the browser on request.
      final external = Uri.tryParse(request.url);
      // Gakujo's external links open a new window (target=_blank), which
      // WebKit reports as a non-main-frame navigation.
      final canOpenExternally = external != null &&
          (external.scheme == 'https' || external.scheme == 'http') &&
          external.host.isNotEmpty;
      _showSnackBar(
        '許可されていない外部サイトをブロックしました',
        action: canOpenExternally
            ? SnackBarAction(
                label: 'ブラウザで開く',
                onPressed: () => unawaited(_launchExternalUrl(external)),
              )
            : null,
      );
      return GakujoNavigationDecision.prevent;
    }

    if (request.isMainFrame && AllowedWebOrigins.isLogoutPage(request.url)) {
      _discardHistoryNavigation();
    }
    final pending = _pendingMessageOpen;
    if (pending != null &&
        !_keepsHistoryMessageDuringLogin(request.url) &&
        pending.navigation.shouldCancelFor(request, _navigationRevision)) {
      _setPendingMessageUrl(null);
    }

    if (AllowedWebOrigins.canLoad(
          request.url,
          debugAllowed: _debugAllowed,
        ) &&
        _appSettings.isFeatureEnabled(GakujoFeatureFlag.downloadCapture) &&
        GakujoDownloadUrlPolicy.shouldDownload(request.url)) {
      final origin = _captureDownloadCourseOrigin();
      final course = await _estimateDownloadCourse(origin);
      await _handleDownloadRequest(
        GakujoDownloadRequest(
          url: request.url,
          method: 'GET',
          courseName: course.courseName ?? '',
          courseNameAmbiguous: course.isAmbiguous,
          fileName: '',
          formFields: const {},
        ),
        courseOrigin: origin,
      );
      return GakujoNavigationDecision.prevent;
    }

    // Android and WebKit also report only the redirected URL to
    // onPageStarted, so remember the student's original destination here.
    if (request.isMainFrame) {
      _captureNavigationRecoveryCandidate(request.url);
    }
    return GakujoNavigationDecision.navigate;
  }

  Future<GakujoCourseEstimate> _estimateCourseNameFromPage() async {
    String? fallbackTitle;
    try {
      // Native title notifications can still describe the previous document.
      final result = await _controller.runJavaScriptReturningResult(
        gakujoDocumentTitleJs,
      );
      if (result is String) fallbackTitle = _stringFromJavaScriptResult(result);
    } on Object {
      // The remaining course evidence can still identify the page.
    }
    return estimateGakujoPageCourseName(
      evaluate: _controller.runJavaScriptReturningResult,
      isUseful: isUsefulGakujoCourseName,
      fallbackTitle: fallbackTitle,
    );
  }

  void _beginCourseDocument() {
    _currentCourseName = null;
    _courseDocument += 1;
  }

  Future<void> _refreshEstimatedCourseName(int document) async {
    final revision = _navigationRevision;
    final estimated = await _estimateCourseNameFromPage();
    if (!mounted ||
        revision != _navigationRevision ||
        document != _courseDocument ||
        estimated.courseName == null) {
      return;
    }
    _currentCourseName = estimated.isAmbiguous ? null : estimated.courseName;
    if (kDebugMode) {
      debugPrint('MoreBetterGakujo current course="$_currentCourseName"');
    }
  }

  Future<bool> _saveLoginCredentialsInput({
    required String loginId,
    required String password,
    bool applyToCurrentPage = true,
  }) async {
    _protectedSecretPromptGate.reset();
    // Saving is an explicit action, so it may ask to unlock the keyring again.
    SecureStorageFactory.reopenLinuxKeyringGate();
    try {
      return await _starSyncEngine.runAccountChange(() => _settingsOperations.runExclusive(() async {
        final protectionBefore = await _appSettingsStore.protectionState.read();
        if (starSyncAccountHash(loginId) != _driveAccountHash) {
          _cancelDriveUploads();
        }
        final credentials = await saveGakujoLoginCredentials(
          store: _appSettingsStore,
          loginId: loginId,
          password: password,
        );
        final protectionAfter = await _appSettingsStore.protectionState.read();
        TextInput.finishAutofillContext(shouldSave: true);
        if (!mounted) {
          return false;
        }
        setState(() {
          _startupPlaceholderFeatureFlags.remove(
            GakujoFeatureFlag.loginAutofill,
          );
          _appSettings = _appSettings.copyWith(
            savedLoginId: credentials.loginId,
            disabledFeatureFlags: {
              for (final flag in _appSettings.disabledFeatureFlags)
                if (flag != GakujoFeatureFlag.loginAutofill) flag,
            },
          );
        });
        await _syncLocalSettingsMirror(_appSettings);
        if (!mounted) {
          return false;
        }
        if (_driveDownloadPreference.enabled && !_driveDownloadsEnabled) {
          _showSnackBar('ログインIDが変わったため、Google ドライブへの保存を見送りました');
        }
        _showSnackBar(protectionBefore.enabled &&
                protectionBefore.hasTwoFactorSecret &&
                !protectionAfter.hasTwoFactorSecret
            ? 'ログイン情報を保存しました。保存済みの2FA秘密鍵が失われたため、もう一度入力してください'
            : 'ログイン情報を保存しました');
        if (applyToCurrentPage) {
          await _applyFeatureFlagRuntimeState(
            GakujoFeatureFlag.loginAutofill,
            enabled: true,
          );
        }
        return true;
      }));
    } on Object catch (error, stackTrace) {
      if (isAuthenticationCancellation(error)) {
        _handleProtectedSecretReadError(error, stackTrace, _navigationRevision);
        return false;
      }
      developer.log(
        'Failed to save login credentials',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showSnackBar('ログイン情報を保存できませんでした');
      }
      return false;
    }
  }

  Future<bool> _saveTwoFactorSecretInput(String secret) async {
    _protectedSecretPromptGate.reset();
    // Saving is an explicit action, so it may ask to unlock the keyring again.
    SecureStorageFactory.reopenLinuxKeyringGate();
    try {
      final protectionBefore = await _secretStore.protectionState.read();
      await _secretStore.save(secret);
      final protectionAfter = await _secretStore.protectionState.read();
      await _appSettingsStore.saveFeatureEnabled(
        GakujoFeatureFlag.twoFactorAutofill,
        enabled: true,
      );
      if (!mounted) {
        return false;
      }
      setState(() {
        _startupPlaceholderFeatureFlags.remove(
          GakujoFeatureFlag.twoFactorAutofill,
        );
        _appSettings = _appSettings.copyWith(
          savedLoginId: protectionAfter.enabled
              ? protectionAfter.loginId
              : _appSettings.savedLoginId,
          disabledFeatureFlags: {
            for (final flag in _appSettings.disabledFeatureFlags)
              if (flag != GakujoFeatureFlag.twoFactorAutofill) flag,
          },
        );
      });
      await _syncLocalSettingsMirror(_appSettings);
      if (!mounted) {
        return false;
      }
      _showSnackBar(protectionBefore.enabled &&
              protectionBefore.loginId != null &&
              protectionAfter.loginId == null
          ? '2FA秘密鍵を保存しました。保存済みのログイン情報が失われたため、もう一度入力してください'
          : '2FA秘密鍵を保存しました');
      await _applyFeatureFlagRuntimeState(
        GakujoFeatureFlag.twoFactorAutofill,
        enabled: true,
      );
      return true;
    } on FormatException {
      if (mounted) {
        _showSnackBar('2FA秘密鍵（長いBase32文字列）を確認してください');
      }
      return false;
    } on Object catch (error, stackTrace) {
      if (isAuthenticationCancellation(error)) {
        _handleProtectedSecretReadError(error, stackTrace, _navigationRevision);
        return false;
      }
      developer.log(
        'Failed to save two-factor secret',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showSnackBar('2FA秘密鍵を保存できませんでした');
      }
      return false;
    }
  }

  Future<void> _prepareSettingsDialogInput() async {
    setState(() {
      _isSettingsDialogOpen = true;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    // Removing WKWebView and waiting for that frame prevents its native view
    // from remaining the macOS keyboard first responder behind the dialog.
    await WidgetsBinding.instance.endOfFrame;
    if (defaultTargetPlatform == TargetPlatform.linux && mounted) {
      await _linuxOverlayGuardKey.currentState?.overlayReady;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) {
      return;
    }
    final firstResponderRestored =
        await _macosInputFocusService.restoreFlutterFirstResponder();
    if (!firstResponderRestored) {
      developer.log(
        'Failed to restore the Flutter first responder before settings',
        name: 'MoreBetterGakujo',
      );
    }
  }

  Future<void> _showSettingsDialog() async {
    unawaited(_notificationService.checkPermission());
    var protectionEnabled = (Platform.isAndroid || Platform.isIOS)
        ? (await _appSettingsStore.protectionState.read()).enabled : false;
    var protectionAvailable = true;
    if (Platform.isAndroid) {
      try {
        protectionAvailable = await const MethodChannel(
          'net.yoshida.morebettergakujo/device_auth_support',
        ).invokeMethod<bool>('supportsDeviceCredential') ?? false;
      } on PlatformException {
        protectionAvailable = false;
      } on MissingPluginException {
        protectionAvailable = false;
      }
    }
    var protectionBusy = false;
    var secretInput = '';
    var loginIdInput = '';
    var loginPasswordInput = '';
    final secretController = TextEditingController();
    final loginIdController = TextEditingController();
    final loginPasswordController = TextEditingController();
    var messageExcludeKeywordInput = '';
    final messageExcludeKeywordController = TextEditingController();
    var messageNotificationKeywordInput = '';
    final messageNotificationKeywordController = TextEditingController();
    var starSyncBusy = false;
    var googleSetupHadDriveSession = false;
    int? googleSetupAuthGeneration;
    final messageExcludeKeywordFocusNode = FocusNode(
      debugLabel: 'message-exclude-keyword',
    );
    ModalRoute<void>? dialogRoute;
    try {
      await _prepareSettingsDialogInput();
      if (_secureStorageAccessAllowed) {
        try {
          await _ensureStarSyncLoaded();
        } on Object catch (error) {
          // A locked Linux keyring must not keep the settings from opening;
          // the sync section then shows sync as not set up.
          developer.log(
            'Failed to load star sync for settings: ${error.runtimeType}',
            name: 'MoreBetterGakujo',
          );
        }
      }
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        requestFocus: true,
        builder: (dialogContext) {
          final settingsRoute = ModalRoute.of<void>(dialogContext)!;
          dialogRoute = settingsRoute;
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
                  _noticeSessionDownloadRoot(next);
                  if (!dialogContext.mounted) {
                    return;
                  }
                  setDialogState(() {});
                } on PlatformException catch (error) {
                  if (mounted) {
                    _showSnackBar(
                      'ダウンロード保存先を設定できませんでした: ${error.message ?? error.code}',
                    );
                  }
                }
              }

              final rootLabel = _downloadRootLabel(_downloadRoot);
              final selectedDownloadSaveMode = _appSettings.downloadSaveMode;
              final selectedPageMode = _appSettings.pageMode;

              Future<void> onFlagChanged(
                GakujoFeatureFlag flag,
                bool enabled,
              ) async {
                if (!await _trySaveSettings(
                  () => saveGakujoSettingsChange(
                    operations: _settingsOperations,
                    save: () => _saveAppSettings(
                      () => _appSettingsStore.saveFeatureEnabled(
                        flag,
                        enabled: enabled,
                      ),
                    ),
                    currentSettings: () => _appSettings,
                    update: (settings) => settings.copyWith(
                      disabledFeatureFlags: {
                        for (final value in settings.disabledFeatureFlags)
                          if (value != flag) value,
                        if (!enabled) flag,
                      },
                    ),
                    apply: (settings) {
                      _startupPlaceholderFeatureFlags.remove(flag);
                      if (mounted) {
                        setState(() => _appSettings = settings);
                      }
                    },
                    mirror: _syncLocalSettingsMirror,
                  ),
                )) {
                  return;
                }
                if (!mounted) {
                  return;
                }
                _scheduleStarSync();
                if (flag == GakujoFeatureFlag.autoBackup) {
                  _scheduleAutoBackup();
                }
                if (dialogContext.mounted) {
                  setDialogState(() {});
                }
                await _applyFeatureFlagRuntimeState(flag, enabled: enabled);
                if (flag == GakujoFeatureFlag.deadlineNotifications) {
                  unawaited(_syncReminders());
                }
              }

              final sections = [
                SettingsExpansionSection(
                  title: 'ログイン',
                  icon: Icons.account_circle_outlined,
                  subtitle: 'ログイン情報・2FA・ログイン状態の維持',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LoginCredentialsSection(
                        loginIdController: loginIdController,
                        passwordController: loginPasswordController,
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
                          try {
                            await _starSyncEngine.runAccountChange(() async {
                              _cancelDriveUploads();
                              try {
                                await _appSettingsStore.clearLoginCredentials();
                              } finally {
                                try {
                                  await _applyFeatureFlagRuntimeState(
                                    GakujoFeatureFlag.loginAutofill,
                                    enabled: false,
                                  );
                                } finally {
                                  TextInput.finishAutofillContext(
                                    shouldSave: false,
                                  );
                                  if (mounted) {
                                    setState(() {
                                      _appSettings = _appSettings.copyWith(
                                        savedLoginId: null,
                                      );
                                    });
                                  }
                                }
                              }
                            });
                            if (!mounted) return;
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {});
                            _showSnackBar('ログイン情報を削除しました');
                          } on Object catch (error, stackTrace) {
                            developer.log(
                              'Failed to clear login credentials',
                              name: 'MoreBetterGakujo',
                              error: error,
                              stackTrace: stackTrace,
                            );
                            if (mounted) {
                              _showSnackBar('ログイン情報を削除できませんでした');
                            }
                          }
                        },
                        onSave: () async {
                          await _saveLoginCredentialsInput(
                            loginId: loginIdInput,
                            password: loginPasswordInput,
                          );
                          if (dialogContext.mounted) {
                            setDialogState(() {});
                          }
                        },
                      ),
                      if (Platform.isAndroid || Platform.isIOS) ...[
                        SecretProtectionSection(
                          enabled: protectionEnabled,
                          isAndroid: Platform.isAndroid,
                          onChanged: protectionBusy || (!protectionAvailable && !protectionEnabled) ? null : (enabled) async {
                            setDialogState(() => protectionBusy = true);
                            final controller = SecretProtectionController(_appSettingsStore.protectionState);
                            try {
                              if (enabled) {
                                await _appSettingsStore.runExclusive(controller.enable);
                              } else {
                                try {
                                  await _appSettingsStore.runExclusive(controller.disable);
                                } on ProtectedSecretsUnreadable {
                                  if (!dialogContext.mounted) return;
                                  final discard = await showDialog<bool>(
                                    context: dialogContext,
                                    builder: (context) => AlertDialog(
                                      content: const Text('保存済みのログイン情報を読み出せません。削除して本人確認をオフにしますか？（ログイン情報と2FA秘密鍵を入れ直す必要があります）'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
                                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除してオフ')),
                                      ],
                                    ),
                                  );
                                  if (discard != true) return;
                                  await _appSettingsStore.runExclusive(controller.disableAndDiscard);
                                  if (mounted) setState(() { _appSettings = _appSettings.copyWith(savedLoginId: null); });
                                }
                              }
                              protectionEnabled = enabled;
                            } on Object catch (error) {
                              if (mounted) {
                                _showSnackBar(enabled
                                    ? '本人確認を有効にできませんでした: ${error is PlatformException ? (error.message ?? error.code) : error.runtimeType}'
                                    : '本人確認をオフにできませんでした');
                              }
                            } finally {
                              try {
                                protectionEnabled = (await _appSettingsStore.protectionState.read()).enabled;
                              } on Object {
                                // Keep the last known value when state cannot be read.
                              }
                              if (dialogContext.mounted) setDialogState(() => protectionBusy = false);
                            }
                          },
                        ),
                      ],
                      const Divider(height: 32),
                      TwoFactorSecretSection(
                        controller: secretController,
                        canSave: canSaveSecret,
                        onChanged: (value) {
                          secretInput = value;
                          setDialogState(() {});
                        },
                        onClear: () async {
                          try {
                            await _secretStore.clear();
                            await _applyFeatureFlagRuntimeState(
                              GakujoFeatureFlag.twoFactorAutofill,
                              enabled: false,
                            );
                            if (mounted) {
                              _showSnackBar('2FA秘密鍵を削除しました');
                            }
                          } on Object catch (error, stackTrace) {
                            developer.log(
                              'Failed to clear two-factor secret',
                              name: 'MoreBetterGakujo',
                              error: error,
                              stackTrace: stackTrace,
                            );
                            if (mounted) {
                              _showSnackBar('2FA秘密鍵を削除できませんでした');
                            }
                          }
                        },
                        onSave: () async {
                          await _saveTwoFactorSecretInput(secretInput);
                          if (dialogContext.mounted) {
                            setDialogState(() {});
                          }
                        },
                      ),
                      const Divider(height: 32),
                      FeatureFlagsSection(
                        settings: _appSettings,
                        onChanged: onFlagChanged,
                        title: 'ログインの補助',
                        flags: settingsLoginFeatureFlags,
                      ),
                    ],
                  ),
                ),
                SettingsExpansionSection(
                  title: '学務情報システムの画面',
                  icon: Icons.web_asset_outlined,
                  subtitle: '開く画面・自動圧縮・除外キーワード',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GakujoPageModeSection(
                        pageMode: selectedPageMode,
                        onChanged: (mode) async {
                          if (mode == null) {
                            return;
                          }
                          final saved = await _settingsOperations.runExclusive(
                            () async {
                              if (!await _trySaveSettings(
                                () => _saveAppSettings(
                                  () => _appSettingsStore.savePageMode(mode),
                                ),
                              )) {
                                return false;
                              }
                              final nextSettings = _appSettings.copyWith(
                                pageMode: mode,
                              );
                              await _syncLocalSettingsMirror(nextSettings);
                              if (!mounted) {
                                return false;
                              }
                              setState(() {
                                _appSettings = _appSettings.copyWith(
                                  pageMode: mode,
                                );
                              });
                              return true;
                            },
                          );
                          if (!saved) return;
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {});
                          await _loadAllowedPageUrl(mode.startUrl);
                        },
                      ),
                      const Divider(height: 32),
                      FeatureFlagsSection(
                        settings: _appSettings,
                        onChanged: onFlagChanged,
                        title: 'レポート',
                        flags: settingsReportFeatureFlags,
                      ),
                      const SizedBox(height: 16),
                      SettingsExpansionSection(
                        title: '除外キーワード',
                        icon: Icons.filter_alt_outlined,
                        focusNodeOnExpand: messageExcludeKeywordFocusNode,
                        child: MessageExcludeKeywordsSection(
                          keywords: _appSettings.messageExcludeKeywords,
                          controller: messageExcludeKeywordController,
                          focusNode: messageExcludeKeywordFocusNode,
                          canAdd: canAddMessageExcludeKeyword,
                          onChanged: (value) {
                            messageExcludeKeywordInput = value;
                            setDialogState(() {});
                          },
                          onAdd: () async {
                            final keyword = messageExcludeKeywordInput;
                            if (!await _trySaveSettings(
                              () => _saveMessageExcludeKeywords(
                                (current) => [...current, keyword],
                              ),
                            )) {
                              return;
                            }
                            messageExcludeKeywordInput = '';
                            messageExcludeKeywordController.clear();
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {});
                          },
                          onRemove: (keyword) async {
                            if (!await _trySaveSettings(
                              () => _saveMessageExcludeKeywords(
                                (current) => current
                                    .where((value) => value != keyword)
                                    .toList(),
                              ),
                            )) {
                              return;
                            }
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SettingsExpansionSection(
                  title: 'ダウンロード',
                  icon: Icons.folder_outlined,
                  subtitle: '保存方法・保存先・Google ドライブ',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FeatureFlagsSection(
                        settings: _appSettings,
                        onChanged: onFlagChanged,
                        title: null,
                        flags: settingsDownloadFeatureFlags,
                      ),
                      DownloadDestinationSection(
                        rootLabel: rootLabel,
                        isConfigured: _downloadRoot.isConfigured,
                        saveMode: selectedDownloadSaveMode,
                        helperText: _downloadDestinationHelperText,
                        onSaveModeChanged: (mode) async {
                          if (mode == null) {
                            return;
                          }
                          final saved = await _settingsOperations.runExclusive(
                            () async {
                              if (!await _trySaveSettings(
                                () => _saveAppSettings(
                                  () => _appSettingsStore.saveDownloadSaveMode(
                                    mode,
                                  ),
                                ),
                              )) {
                                return false;
                              }
                              final nextSettings = _appSettings.copyWith(
                                downloadSaveMode: mode,
                              );
                              await _syncLocalSettingsMirror(nextSettings);
                              if (!mounted) {
                                return false;
                              }
                              setState(() {
                                _appSettings = _appSettings.copyWith(
                                  downloadSaveMode: mode,
                                );
                              });
                              return true;
                            },
                          );
                          if (!saved) return;
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
                      SettingsActionGroup(
                        actions: [
                          SettingsAction(
                            label: '保存先を確認',
                            icon: Icons.health_and_safety_outlined,
                            run: _checkDownloadDestinationHealth,
                          ),
                        ],
                      ),
                      if (const StarSyncGoogleAuthConfig().isAvailable) ...[
                        const Divider(height: 32),
                        DriveDownloadSwitch(
                          value: _driveDownloadsEnabled,
                          signingIn: _driveSwitchSigningIn,
                          enabled: !starSyncBusy,
                          subtitle:
                              _driveDownloadsEnabled &&
                                  _starSyncGoogleEmail != null
                              ? (_starSyncEngine.config != null
                                    ? '保存先: $_starSyncGoogleEmail\n同期と同じアカウントです。変えるには同期を無効にします'
                                    : '保存先: $_starSyncGoogleEmail\n別のアカウントにするには、一度オフにします')
                              : null,
                          onCancel:
                              Platform.isWindows ||
                                  Platform.isMacOS ||
                                  Platform.isLinux
                              ? _cancelGoogleSignIn
                              : null,
                          onChanged: (enabled) async {
                            if (enabled) {
                              setDialogState(
                                () => _driveSwitchSigningIn = true,
                              );
                            }
                            try {
                              if (!enabled) {
                                await _warnPendingDriveChecksBestEffort();
                              }
                              await _setDriveDownloadsEnabled(
                                enabled,
                                byStudentSwitch: true,
                              );
                            } on StarSyncGoogleAuthException catch (error) {
                              if (error.kind !=
                                  StarSyncGoogleAuthErrorKind.cancelled) {
                                _showSnackBar(starSyncErrorMessage(error));
                              }
                            } on StarSyncAccountRequiredException catch (
                              error
                            ) {
                              _showSnackBar(starSyncErrorMessage(error));
                            } on Object {
                              _showSnackBar('Google ドライブの設定を変更できませんでした');
                            } finally {
                              _driveSwitchSigningIn = false;
                              if (dialogContext.mounted) setDialogState(() {});
                            }
                          },
                        ),
                        if (_driveDownloadsEnabled && _starSyncGoogleEmail != null)
                          DriveSaveFolderTile(
                            name: _driveDownloadPreference.folderNameFor(_starSyncGoogleEmail),
                            onChange: () async {
                              await _chooseDriveSaveFolder(dialogContext);
                              if (dialogContext.mounted) setDialogState(() {});
                            },
                          ),
                      ],
                    ],
                  ),
                ),
                SettingsExpansionSection(
                  title: '通知',
                  icon: Icons.notifications_outlined,
                  subtitle: '提出期限・リマインド・連絡通知',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FeatureFlagsSection(
                        settings: _appSettings,
                        onChanged: onFlagChanged,
                        title: null,
                        flags: settingsNotificationFeatureFlags,
                      ),
                      const Divider(height: 32),
                      NotificationTopicsSection(
                        topics: _appSettings.notificationTopics,
                        messages: _appSettings.messageNotification,
                        preferences: _appSettings.notificationPreferences,
                        remindersOnlyWhileOpen:
                            Platform.isWindows || Platform.isLinux,
                        notificationPermission:
                            _notificationService.permissionGranted,
                        onOpenNotificationSettings:
                            Platform.isAndroid ||
                                Platform.isIOS ||
                                Platform.isMacOS
                            ? () => unawaited(
                                _notificationService.openNotificationSettings(),
                              )
                            : null,
                        onPreferencesChanged: (update) async {
                          await _saveNotificationPreferences(update);
                          if (dialogContext.mounted) {
                            setDialogState(() {});
                          }
                        },
                        keywordController: messageNotificationKeywordController,
                        canAddKeyword: messageNotificationKeywordInput
                            .trim()
                            .isNotEmpty,
                        onKeywordInputChanged: (value) {
                          messageNotificationKeywordInput = value;
                          setDialogState(() {});
                        },
                        onMessagesChanged: (update) async {
                          if (!await _trySaveSettings(
                            () => _saveMessageNotification(update),
                          )) {
                            return false;
                          }
                          if (dialogContext.mounted) {
                            setDialogState(() {});
                          }
                          return true;
                        },
                        notificationsEnabled: _appSettings.isFeatureEnabled(
                          GakujoFeatureFlag.deadlineNotifications,
                        ),
                        onChanged: (topic, enabled) async {
                          if (!await _trySaveSettings(
                            () => _saveNotificationTopics((current) => {
                              for (final value in current)
                                if (value != topic) value,
                              if (enabled) topic,
                            }),
                          )) {
                            return;
                          }
                          if (dialogContext.mounted) {
                            setDialogState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
                SettingsExpansionSection(
                  title: '外部連携',
                  icon: Icons.event_available_outlined,
                  subtitle: 'カレンダー・外部サービス',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppIntegrationSection(
                        onScheduleIntegration: _showScheduleIntegrationDialog,
                      ),
                      const Divider(height: 32),
                      Text(
                        '外部サービス',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('外部サービスを開く前に確認する'),
                        subtitle: const Text('AKIKO（空き講義室検索・CIRCLE 運営）'),
                        value: !_externalServiceNoticeDismissed,
                        onChanged: (confirm) async {
                          await _setExternalServiceNoticeDismissed(!confirm);
                          if (dialogContext.mounted) setDialogState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                SettingsExpansionSection(
                  title: '同期とバックアップ',
                  icon: Icons.sync,
                  subtitle: '端末間の同期・バックアップ',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '端末間の同期',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                        StarSyncSection(
                          status: _starSyncEngine.status,
                          onBusyChanged: (busy) {
                            starSyncBusy = busy;
                            if (dialogContext.mounted) setDialogState(() {});
                          },
                          onBackup: _uploadSyncBackup,
                          onListBackups: _starSyncEngine.listBackups,
                          onRestoreBackup: (id) {
                            final account = _starSyncEngine.requireAccount();
                            final generation = _starSyncEngine.accountGeneration;
                            return _starSyncEngine.runBoundToAccount(
                              expectedAccount: account,
                              expectedGeneration: generation,
                              action: () => _importSettings(() async {
                                final bytes = await _starSyncEngine.downloadBackup(id);
                                await _restoreSettingsFromText(
                                  utf8.decode(bytes),
                                  emptyMessage: 'バックアップが空です',
                                  alreadyConfirmed: true,
                                  fromSyncStorage: true,
                                  // A login navigation can end the session while
                                  // the restore waits; check before each write.
                                  beforeWrite: () {
                                    if (!_starSyncEngine.isBoundAccountCurrent(
                                      expectedAccount: account,
                                      expectedGeneration: generation,
                                    )) {
                                      throw const StarSyncAccountMismatchException();
                                    }
                                  },
                                );
                              }),
                            );
                          },
                          collectionEnabled: _starSyncEngine.collectionEnabled,
                          onCollectionChanged: _starSyncEngine.setCollectionEnabled,
                          googleAvailable: const StarSyncGoogleAuthConfig().isAvailable,
                          // With Google sync set up, only its recorded account counts.
                          googleEmail: () =>
                              _starSyncEngine.config != null
                                  ? _starSyncEngine.config?.googleEmail
                                  : _starSyncGoogleEmail,
                          onGoogleCancelSignIn: _cancelGoogleSignIn,
                          onGoogleSignIn:
                              ({
                                required clearLocalStars,
                                required expectedAccount,
                                required expectedGeneration,
                                required onSignedIn,
                              }) async {
                            final cancelGeneration = _googleCancelGeneration;
                            googleSetupHadDriveSession = _driveDownloadsEnabled &&
                                _starSyncGoogleAuth.currentEmail != null;
                            SecureStorageFactory.reopenLinuxKeyringGate();
                            _starSyncGoogleEmail = await _signInGoogle();
                            final authGeneration = _starSyncGoogleAuth.generation;
                            googleSetupAuthGeneration = authGeneration;
                            try {
                              if (cancelGeneration != _googleCancelGeneration) {
                                throw const StarSyncGoogleAuthException(StarSyncGoogleAuthErrorKind.cancelled);
                              }
                              onSignedIn();
                              return await _starSyncEngine.setUpWithDrive(
                                StarSyncConfig(googleEmail: _starSyncGoogleAuth.currentEmail),
                                clearLocalStars: clearLocalStars, expectedAccount: expectedAccount, expectedGeneration: expectedGeneration,
                              );
                            } on Object {
                              await _driveDownloadQueue.runExclusive(() async {
                                if (_starSyncGoogleAuth.generation != authGeneration ||
                                    googleSetupHadDriveSession || _starSyncEngine.status.value.enabled) {
                                  return;
                                }
                                await _setDriveDownloadsEnabled(false);
                                await _signOutGoogle(warn: false);
                                _starSyncGoogleEmail = null;
                              });
                              rethrow;
                            }
                          },
                          onGoogleSetupAbandoned: () => _driveDownloadQueue.runExclusive(() async {
                            if (googleSetupHadDriveSession ||
                                googleSetupAuthGeneration != _starSyncGoogleAuth.generation) {
                              return;
                            }
                            try {
                              await _setDriveDownloadsEnabled(false);
                              await _warnPendingDriveChecks();
                            } finally {
                              await _signOutGoogle(warn: false);
                              _starSyncGoogleEmail = null;
                            }
                          }),
                          onGoogleSignOut: () async {
                            try {
                              // Off first: a failing warning must not leave it on.
                              await _setDriveDownloadsEnabled(false);
                              await _warnPendingDriveChecks();
                            } finally {
                              await _signOutGoogle(warn: false);
                              _starSyncGoogleEmail = null;
                            }
                          },
                          onGoogleReSignIn: () async {
                            SecureStorageFactory.reopenLinuxKeyringGate();
                            _starSyncGoogleEmail = await _signInGoogle();
                            if (mounted) setState(() {});
                            await _starSyncEngine.syncNow(trigger: StarSyncTrigger.manual);
                          },
                          onLocalStarCount: _starSyncEngine.localStarCount,
                          onLocalCollectionCounts: _starSyncEngine.localCollectionCounts,
                          onSnapshotLocalStars: _starSyncEngine.snapshotLocalStars,
                          onRequireAccount: () {
                            final saved = starSyncAccountHash(_appSettings.savedLoginId);
                            if (saved == null) throw const StarSyncAccountRequiredException();
                            if (_activeLoginAccount != saved) throw const StarSyncActiveAccountRequiredException();
                            return _starSyncEngine.requireAccount();
                          },
                          onAccountGeneration: () => _starSyncEngine.accountGeneration,
                          onSetUpWithDrive: ({required resetExisting, required clearLocalStars, required expectedAccount, required expectedGeneration}) =>
                              _starSyncEngine.setUpWithDrive(
                                StarSyncConfig(googleEmail: _starSyncGoogleAuth.currentEmail),
                                resetExisting: resetExisting, clearLocalStars: clearLocalStars, expectedAccount: expectedAccount, expectedGeneration: expectedGeneration,
                              ),
                          onResetWithDrive: _starSyncEngine.resetRemoteWithDrive,
                          onSyncNow: () async {
                            SecureStorageFactory.reopenLinuxKeyringGate();
                            await _ensureStarSyncLoaded();
                            await _starSyncEngine.syncNow(trigger: StarSyncTrigger.manual);
                          },
                          onResumeKeepingLocal: _starSyncEngine.resumeKeepingLocal,
                          onResumeDiscardingLocal: _starSyncEngine.resumeDiscardingLocal,
                          onListDevices: () async {
                            await _ensureStarSyncLoaded();
                            return _starSyncEngine.listDevices();
                          },
                          onDeleteDevice: (id) async {
                            await _ensureStarSyncLoaded();
                            await _starSyncEngine.deleteDeviceFile(id);
                          },
                          onDisable: ({deleteOwnRemoteFile = false}) async {
                            await _ensureStarSyncLoaded();
                            final google = _starSyncEngine.config != null;
                            await _starSyncEngine.disable(
                              deleteOwnRemoteFile: deleteOwnRemoteFile,
                            );
                            if (google) {
                              try {
                                // Off first: a failing warning must not leave it on.
                                await _setDriveDownloadsEnabled(false);
                                await _warnPendingDriveChecks();
                              } finally {
                                await _signOutGoogle(warn: false);
                                _starSyncGoogleEmail = null;
                              }
                            }
                          },
                        ),
                      const Divider(height: 32),
                      AppBackupSection(
                        onCreateBackup: _createManualBackup,
                        onImportSettingsFromFile: () async {
                          await _importSettingsFromFile();
                          if (!dialogContext.mounted) {
                            return;
                          }
                          setDialogState(() {});
                        },
                      ),
                      FeatureFlagsSection(
                        settings: _appSettings,
                        onChanged: onFlagChanged,
                        title: null,
                        flags: settingsBackupFeatureFlags,
                      ),
                    ],
                  ),
                ),
                SettingsExpansionSection(
                  title: '保存データ',
                  icon: Icons.storage_outlined,
                  subtitle: '履歴・資料・下書き・お気に入り',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppDataShortcutsSection(
                        onShowDownloadHistory: () =>
                            _showDownloadHistoryDialog(settingsRoute),
                        onShowFailedDownloads: () =>
                            _showFailedDownloadsDialog(settingsRoute),
                        onShowCourseMaterials: () =>
                            _showCourseMaterialsDialog(settingsRoute),
                        onShowCachedReports: () =>
                            _showCachedReportsDialog(settingsRoute: settingsRoute),
                        onShowDrafts: () => _showReportDraftsDialog(settingsRoute),
                        onShowFavorites: () =>
                            _showFavoritesDialog(settingsRoute: settingsRoute),
                        onShowDataManagement: () =>
                            _showDataManagementDialog(settingsRoute),
                      ),
                    ],
                  ),
                ),
                SettingsExpansionSection(
                  title: 'このアプリについて',
                  icon: Icons.info_outline,
                  subtitle: 'バージョン・アップデート・不具合や要望の報告',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppAboutSection(
                        onOpenUrl: (url) => unawaited(_launchExternalUrl(url)),
                      ),
                      const Divider(height: 32),
                      AppUpdateSection(
                        settings: _appSettings,
                        onFlagChanged: onFlagChanged,
                        onCheckUpdates: _checkForUpdates,
                      ),
                      const Divider(height: 32),
                      AppSupportSection(
                        onCreateErrorReport: _createErrorReportPackage,
                        onOpenUrl: (url) async {
                          await _launchExternalUrl(url);
                        },
                        reportEndpoint: reportEndpointUrl == null
                            ? null
                            : Uri.parse(reportEndpointUrl!),
                        collectDiagnostics: () async =>
                            const JsonEncoder.withIndent('  ').convert(
                              await _diagnosticPayload(
                                includeStoredData: false,
                              ),
                            ),
                      ),
                    ],
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
                      separatorBuilder: (_, _) => const Divider(height: 1),
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
      // A sign-in left waiting would hold the Drive queue for its full timeout.
      _cancelGoogleSignIn();
      await gakujoWaitForDialogDismissal(dialogRoute);
      if (mounted) {
        setState(() {
          _isSettingsDialogOpen = false;
        });
      }
      messageExcludeKeywordController.dispose();
      messageExcludeKeywordFocusNode.dispose();
      messageNotificationKeywordController.dispose();
      secretController.dispose();
      loginIdController.dispose();
      loginPasswordController.dispose();
    }
  }

  Future<void> _showInitialSetupWizard() async {
    if (_isSettingsDialogOpen) {
      return;
    }
    if (!_startupFlow.claimSetup()) {
      return;
    }

    var loginIdInput = '';
    var loginPasswordInput = '';
    var secretInput = '';
    var isCompleting = false;
    final loginIdController = TextEditingController();
    final loginPasswordController = TextEditingController();
    final secretController = TextEditingController();
    var selectedDownloadSaveMode = _appSettings.downloadSaveMode;
    var selectedPageMode = _appSettings.pageMode;
    final disabledFeatureFlags = {..._appSettings.disabledFeatureFlags};
    final placeholderFeatureFlags = {..._startupPlaceholderFeatureFlags};
    final changedFeatureFlags = <GakujoFeatureFlag>{};
    ModalRoute<void>? dialogRoute;
    GakujoAppSettings buildWizardSettings() => _appSettings.copyWith(
          downloadSaveMode: selectedDownloadSaveMode,
          pageMode: selectedPageMode,
          disabledFeatureFlags: disabledFeatureFlags,
          setupCompleted: true,
        );

    try {
      await _prepareSettingsDialogInput();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        requestFocus: true,
        builder: (dialogContext) {
          dialogRoute = ModalRoute.of<void>(dialogContext);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              _refreshSetupWizard = () => setDialogState(() {});
              final wizardSettings = buildWizardSettings();

              Future<void> complete() async {
                if (isCompleting) {
                  return;
                }
                final loginId = loginIdInput.trim();
                final password = loginPasswordInput;
                final secret = secretInput;
                if (loginId.isNotEmpty != password.isNotEmpty) {
                  _showSnackBar('ログインIDとパスワードを両方入力してください');
                  return;
                }
                if (secret.trim().isNotEmpty &&
                    !Base32.isValid(Base32.normalize(secret))) {
                  _showSnackBar('2FA秘密鍵（長いBase32文字列）を確認してください');
                  return;
                }
                setDialogState(() {
                  isCompleting = true;
                });
                _deferLoginAutofillDuringSetup = true;
                try {
                  if (loginId.isNotEmpty) {
                    if (!await _saveLoginCredentialsInput(
                      loginId: loginId,
                      password: password,
                      applyToCurrentPage: false,
                    )) {
                      return;
                    }
                    if (!mounted || !dialogContext.mounted) {
                      return;
                    }
                    disabledFeatureFlags
                        .remove(GakujoFeatureFlag.loginAutofill);
                    changedFeatureFlags.add(GakujoFeatureFlag.loginAutofill);
                  }
                  if (secret.trim().isNotEmpty) {
                    if (!await _saveTwoFactorSecretInput(secret)) {
                      return;
                    }
                    if (!mounted || !dialogContext.mounted) {
                      return;
                    }
                    disabledFeatureFlags.remove(
                      GakujoFeatureFlag.twoFactorAutofill,
                    );
                    changedFeatureFlags
                        .add(GakujoFeatureFlag.twoFactorAutofill);
                  }
                  final completedWizardSettings = buildWizardSettings();
                  final settingsToSave = gakujoSettingsForPersistence(
                    completedWizardSettings,
                    placeholderFeatureFlags: placeholderFeatureFlags,
                    changedFeatureFlags: changedFeatureFlags,
                  );
                  _startupPlaceholderFeatureFlags
                      .removeAll(changedFeatureFlags);
                  Object? saveError;
                  StackTrace? saveStackTrace;
                  try {
                    await Future.wait([
                      _appSettingsStore.saveDownloadSaveMode(
                        selectedDownloadSaveMode,
                      ),
                      _appSettingsStore.savePageMode(selectedPageMode),
                      _appSettingsStore.saveDisabledFeatureFlags(
                        settingsToSave.disabledFeatureFlags,
                      ),
                      _appSettingsStore.saveSetupCompleted(true),
                    ]);
                    await _syncLocalSettingsMirror(settingsToSave);
                  } on Object catch (error, stackTrace) {
                    saveError = error;
                    saveStackTrace = stackTrace;
                  }
                  if (!mounted) {
                    return;
                  }
                  // Secure settings may have replaced startup while setup was open.
                  final previousSettings = _appSettings;
                  final nextSettings = gakujoSettingsAfterInitialSetup(
                    currentSettings: previousSettings,
                    wizardSettings: completedWizardSettings,
                    placeholderFeatureFlags: placeholderFeatureFlags
                        .difference(_startupPlaceholderFeatureFlags),
                    changedFeatureFlags: changedFeatureFlags,
                  );
                  setState(() {
                    _appSettings = nextSettings;
                  });
                  if (saveError == null && !portableSyncSettingsMatch(
                    previousSettings, exportStarSyncPortableSettings(nextSettings),
                  )) {
                    _scheduleStarSync();
                  }
                  _scheduleAutoBackup();
                  await _applyChangedRuntimeFeatureFlags(
                    previousSettings,
                    nextSettings,
                  );
                  // Startup may already have booked reminders before setup; turning
                  // notifications off here must cancel them.
                  unawaited(_syncReminders());
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
                    if (defaultTargetPlatform == TargetPlatform.linux) {
                      _secureStorageAccessAllowed = false;
                      _linuxSessionSettings.showNotice(_showSnackBar);
                    } else {
                      _showSnackBar(
                        '初回セットアップを保存できませんでした。キーチェーン設定を確認してください。',
                      );
                    }
                  }
                  _deferLoginAutofillDuringSetup = false;
                  await _loadAllowedPageUrl(selectedPageMode.startUrl);
                } finally {
                  _deferLoginAutofillDuringSetup = false;
                  if (dialogContext.mounted) {
                    setDialogState(() {
                      isCompleting = false;
                    });
                  }
                }
              }

              return AlertDialog(
                title: const Text('初回セットアップ'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('ここでの設定は、あとから「設定」画面でいつでも変えられます。'),
                      const SizedBox(height: 8),
                      const Text(
                        'ログイン情報と2FA秘密鍵は端末内に保存され、自動ログインに使われます。空欄のままでも続けられます。',
                      ),
                      const SizedBox(height: 12),
                      LoginCredentialsSection(
                        loginIdController: loginIdController,
                        passwordController: loginPasswordController,
                        isConfigured: _appSettings.hasLoginCredentials,
                        canSave: false,
                        onLoginIdChanged: (value) {
                          loginIdInput = value;
                        },
                        onPasswordChanged: (value) {
                          loginPasswordInput = value;
                        },
                      ),
                      const Divider(height: 32),
                      TwoFactorSecretSection(
                        controller: secretController,
                        canSave: false,
                        onChanged: (value) {
                          secretInput = value;
                        },
                      ),
                      const Divider(height: 32),
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
                            _noticeSessionDownloadRoot(root);
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {});
                          } on PlatformException catch (error) {
                            if (!mounted || !dialogContext.mounted) {
                              return;
                            }
                            _showSnackBar(
                              '保存先を設定できませんでした: ${error.message ?? error.code}',
                            );
                          }
                        },
                        onClear: () async {
                          final DownloadDestinationSettings root;
                          try {
                            root = await _downloadService.clearDownloadRoot();
                          } on Object catch (error, stackTrace) {
                            developer.log(
                              'Failed to clear download root during initial setup',
                              name: 'MoreBetterGakujo',
                              error: error,
                              stackTrace: stackTrace,
                            );
                            _showSnackBar('保存先を解除できませんでした');
                            return;
                          }
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _downloadRoot = root;
                          });
                          _noticeSessionDownloadRoot(root);
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
                          changedFeatureFlags.add(flag);
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
                    onPressed:
                        isCompleting ? null : () => unawaited(complete()),
                    child: const Text('完了'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      await gakujoWaitForDialogDismissal(dialogRoute);
      _refreshSetupWizard = null;
      if (mounted) {
        setState(() {
          _isSettingsDialogOpen = false;
        });
      }
      loginIdController.dispose();
      loginPasswordController.dispose();
      secretController.dispose();
    }
    // 「あとで」 or a tap outside used to bring the wizard back on every
    // launch. Keep the defaults and leave changes to the settings screen.
    if (mounted && !_appSettings.setupCompleted) {
      await _markInitialSetupSeen();
    }
  }

  Future<void> _markInitialSetupSeen() => _settingsOperations.runExclusive(() async {
    final nextSettings = _appSettings.copyWith(setupCompleted: true);
    try {
      await _appSettingsStore.saveSetupCompleted(true);
      await _syncLocalSettingsMirror(nextSettings);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to remember that the initial setup was seen',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (!Platform.isLinux) return;
    }
    if (mounted) {
      setState(() {
        _appSettings = _appSettings.copyWith(setupCompleted: true);
      });
    }
  });

  Future<void> _compactStoredData() async {
    try {
      await Future.wait([
        _downloadHistoryStore.compact(),
        _activityStore.compact(),
      ]);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to compact stored data',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _showCachedReportsDialog({
    ModalRoute<void>? settingsRoute,
    int? returnRevision,
  }) async {
    final reportLists = await _activityStore.loadReportLists();
    if (!mounted ||
        settingsRoute?.isActive == false ||
        _isStaleDialogReturn(returnRevision)) {
      return;
    }

    final returned = returnRevision != null;
    final sorted = [...reportLists]
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    var isDeleting = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        if (returned) _returnedDialogContext = dialogContext;
        return _historyDialogInput(
          returned: returned,
          child: AlertDialog(
          title: _historyDialogTitle('保存済み課題一覧', returned),
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
                                  _setPendingReturnDialog('cachedReports');
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
                      if (isDeleting) return;
                      isDeleting = true;
                      try {
                        await _activityStore.clearReportLists();
                      } on Object catch (error, stackTrace) {
                        developer.log(
                          'Failed to delete cached assignment lists',
                          name: 'MoreBetterGakujo',
                          error: error,
                          stackTrace: stackTrace,
                        );
                        _showSnackBar('削除できませんでした');
                        return;
                      } finally {
                        isDeleting = false;
                      }
                      // The assignments go with the lists, and so do their
                      // booked reminders; fetch the list again soon.
                      _lastAssignmentRefresh = null;
                      unawaited(_syncReminders());
                      if (!dialogContext.mounted) {
                        return;
                      }
                      if (ModalRoute.of(dialogContext)?.isCurrent == true) {
                        Navigator.of(dialogContext).pop();
                      }
                      _showSnackBar('保存済み課題一覧を削除しました');
                    },
              child: const Text('削除'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('閉じる'),
            ),
          ],
          ),
        );
      },
    );
  }

  Future<void> _showDataManagementDialog(ModalRoute<void> settingsRoute) async {
    final data = await readGakujoSavedData(
      () async => (
        history: await _downloadHistoryStore.load(),
        failedDownloads: await _downloadHistoryStore.loadFailedDownloads(),
        favorites: await _activityStore.loadFavoritesForBackup(),
        starredMessages: await _activityStore.loadStarredMessagesForBackup(),
        deadlines: await _activityStore.loadDeadlinesForBackup(),
        reportLists: await _activityStore.loadReportListsForBackup(),
      ),
      showSnackBar: _showSnackBar,
    );
    if (data == null || !mounted || !settingsRoute.isActive) {
      return;
    }

    var revocationUnconfirmed = false;
    Future<void> clearAll() async {
      _discardHistoryNavigation();
      _loginIdentity.pending = null;
      _loginIdentity.restored = null;
      await _setActiveLoginAccount(null, resync: false);
      try {
        await _ensureStarSyncLoaded();
      } on Object catch (error) {
        developer.log('Failed to load star sync before clearing data: ${error.runtimeType}',
            name: 'MoreBetterGakujo');
      }
      try {
        await _starSyncEngine.disable();
      } finally {
        try {
          await _setDriveDownloadsEnabled(false);
          await _driveDownloadQueue.runExclusive(_driveDownloadPreference.clear);
        } on Object catch (error) {
          developer.log('Failed to clear Drive saving while clearing data: ${error.runtimeType}',
              name: 'MoreBetterGakujo');
        }
        // Sign out even when the Drive preference could not be cleared.
        if (!await _signOutGoogle()) revocationUnconfirmed = true;
        _starSyncGoogleEmail = null;
      }
      await Future.wait([
        _downloadHistoryStore.clear(),
        _downloadHistoryStore.clearFailedDownloads(),
        _notificationService.clearHistory(),
        _activityStore.deleteRetiredData(),
        _activityStore.clearDeadlines(),
        _activityStore.clearNotifiedDeadlineTimes(),
        _activityStore.replaceNotifiedDeadlineKeys(const []),
        StarSyncQuotaMeter.shared.clear(),
        _activityStore.clearReportLists(),
        _activityStore.replaceFavorites(const []),
        _activityStore.replaceStarredMessages(const []),
      ]);
      await _refreshMessageStars();
      // Reminders booked with the OS were for the assignments just removed;
      // fetch the list again at the next chance.
      _lastAssignmentRefresh = null;
      unawaited(_syncReminders());
    }

    var isClearing = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('データ管理'),
            content: SizedBox(
              width: 520,
              child: ListView(
                shrinkWrap: true,
                children: [
                  _DataCountTile(label: 'ダウンロード履歴', count: data.history.length),
                  _DataCountTile(
                    label: '失敗したダウンロード',
                    count: data.failedDownloads.length,
                  ),
                  _DataCountTile(label: 'お気に入り', count: data.favorites.length),
                  _DataCountTile(
                    label: 'スター付き連絡通知',
                    count: data.starredMessages.length,
                  ),
                  _DataCountTile(
                    label: '新着情報・期限・予定',
                    count: data.deadlines.length,
                  ),
                  _DataCountTile(
                    label: '保存済み課題一覧',
                    count: data.reportLists.length,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isClearing
                    ? null
                    : () async {
                        if (isClearing) return;
                        setDialogState(() => isClearing = true);
                        try {
                          await clearAll();
                          if (!dialogContext.mounted ||
                              ModalRoute.of(dialogContext)?.isCurrent != true) {
                            return;
                          }
                          Navigator.of(dialogContext).pop();
                          // Keep the revocation warning: a success message would hide it.
                          _showSnackBar(
                            revocationUnconfirmed
                                ? '保存データを削除しました。$googleRevocationUnconfirmedMessage'
                                : '保存データを削除しました',
                          );
                        } finally {
                          if (dialogContext.mounted &&
                              ModalRoute.of(dialogContext)?.isCurrent == true) {
                            setDialogState(() => isClearing = false);
                          }
                        }
                      },
                child: const Text('全て削除'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _checkForUpdatesAfterInitialPage() async {
    try {
      await _initialPageLoaded;
    } catch (_) {
      // The initial page load reports its own errors.
    }
    if (!mounted) return;
    await _checkForUpdatesInBackground();
  }

  Future<void> _checkForUpdatesInBackground() async {
    if (!mounted ||
        !_appSettingsLoaded ||
        !_appSettings.isFeatureEnabled(GakujoFeatureFlag.updateNotice) ||
        _isCheckingUpdateInBackground) {
      return;
    }
    final now = widget.updateNow();
    if ((_updateRetryNotBefore?.isAfter(now) ?? false) ||
        !isUpdateCheckDue(_lastDailyUpdateCheckAt, now)) {
      return;
    }
    _isCheckingUpdateInBackground = true;
    final previouslyAvailable = _availableUpdate;
    try {
      final prefs = await _localPrefsStore.load();
      if (!mounted) return;
      if (!isUpdateCheckDue(prefs?.lastUpdateCheckAt, now)) {
        _lastDailyUpdateCheckAt = prefs!.lastUpdateCheckAt;
        _updateRetryNotBefore = null;
        return;
      }
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final info = await _updateService.checkLatestRelease(
        currentVersion: packageInfo.version,
      );
      if (!mounted ||
          !_appSettings.isFeatureEnabled(GakujoFeatureFlag.updateNotice)) {
        return;
      }
      final current = _availableUpdate;
      if (current != null && !identical(current, previouslyAvailable)) return;
      // Only dismissal can clear the banner while this single check is running.
      // Its queued save owns the dismissal timestamp.
      final dismissedDuringCheck = current == null ? previouslyAvailable : null;
      if (info.latestVersion != dismissedDuringCheck?.latestVersion &&
          shouldNotifyAboutUpdate(
            info,
            platform: defaultTargetPlatform,
            dismissedVersion: prefs?.dismissedUpdateVersion,
          )) {
        setState(() => _availableUpdate = info);
      } else if (dismissedDuringCheck == null) {
        if (current != null) {
          setState(() => _availableUpdate = null);
        }
        await _localPrefsStore.saveUpdateCheck(checkedAt: now);
        if (!mounted) return;
      }
      _lastDailyUpdateCheckAt = now;
      _updateRetryNotBefore = null;
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to check for application updates in background',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _lastDailyUpdateCheckAt = null;
      _updateRetryNotBefore = now.add(const Duration(hours: 1));
    } finally {
      _isCheckingUpdateInBackground = false;
    }
  }

  AppUpdateBanner _buildUpdateBanner(AppUpdateInfo displayed) {
    var dismissed = false;
    return AppUpdateBanner(
      latestVersion: displayed.latestVersion,
      currentVersion: displayed.currentVersion,
      onOpen: () => unawaited(_openUpdateReleasePage()),
      onDismiss: () {
        // The same button can still receive taps before the next frame.
        if (dismissed) return;
        dismissed = true;
        unawaited(_dismissUpdateNotice(displayed.latestVersion));
      },
    );
  }

  Future<void> _dismissUpdateNotice(String displayedVersion) async {
    if (!mounted) return;
    if (_availableUpdate?.latestVersion == displayedVersion) {
      setState(() => _availableUpdate = null);
    }
    try {
      await _localPrefsStore.saveUpdateCheck(
        checkedAt: widget.updateNow(),
        dismissedVersion: displayedVersion,
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to save dismissed update notice',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Opens [url] in the system browser; launcher errors (a Windows shell
  /// failure, a missing Linux launcher) become a message instead of escaping.
  Future<bool> _launchExternalUrl(Uri url) async {
    var launched = false;
    try {
      launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to open an external URL',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (!launched && mounted) _showSnackBar('外部ブラウザで開けませんでした');
    return launched;
  }

  Future<void> _openUpdateReleasePage() async {
    final info = _availableUpdate;
    if (info == null) return;
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(info.releaseUrl),
        mode: LaunchMode.externalApplication,
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to open update release page',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (mounted && !launched) {
      _showSnackBar('リリースページを開けませんでした');
    }
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
      _setStatus(
        info.hasUpdate
            ? 'アップデートがあります: ${info.latestVersion}'
            : '最新版です: ${info.currentVersion}',
      );
      await _showUpdateCheckResult(info);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to check for application updates',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      _setStatus('アップデートを確認できませんでした');
      await _showUpdateCheckError(error);
    }
  }

  Future<void> _showUpdateCheckResult(AppUpdateInfo info) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(info.hasUpdate ? 'アップデートがあります' : '最新版です'),
          content: Text(
            '現在のバージョン: ${info.currentVersion}\n'
            '最新のバージョン: ${info.latestVersion}',
          ),
          actions: [
            if (info.hasUpdate)
              TextButton(
                onPressed: () =>
                    unawaited(_launchExternalUrl(Uri.parse(info.releaseUrl))),
                child: const Text('リリースページを開く'),
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

  Future<void> _showUpdateCheckError(Object error) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('アップデートを確認できませんでした'),
          content: SelectableText(
            gakujoUserFacingMessage(
              error.toString(),
              platform: defaultTargetPlatform,
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

  Future<void> _createManualBackup() async {
    final File file;
    try {
      file = await _writeBackupFile(prefix: 'manual');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to write manual backup',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      _showSnackBar('バックアップを作成できませんでした: $error');
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      _showSnackBar('バックアップを作成しました: ${file.path}');
      return;
    }

    try {
      final now = DateTime.now();
      String twoDigits(int value) => value.toString().padLeft(2, '0');
      final fileName = 'morebettergakujo-backup-'
          '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}-'
          '${twoDigits(now.hour)}${twoDigits(now.minute)}.json';
      final result = await exportGakujoFileWithNativePicker(
        bytes: await file.readAsBytes(),
        fileName: fileName,
        mimeType: 'application/json',
      );
      final location = result.location?.trim();
      final destination =
          location == null || location.isEmpty ? result.fileName : location;
      _showSnackBar('バックアップを保存しました: $destination');
    } on Object catch (error, stackTrace) {
      if (error is PlatformException && isCancelledDownloadError(error)) {
        _showSnackBar('バックアップの保存をキャンセルしました。アプリ内には作成済みです');
        return;
      }
      developer.log(
        'Failed to export manual backup',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      final message = error is PlatformException
          ? error.message ?? error.code
          : error.toString();
      _showSnackBar('バックアップを書き出せませんでした: $message');
    }
  }

  void _scheduleAutoBackup() {
    _autoBackupTimer?.cancel();
    _autoBackupDebounce?.cancel();
    if (!_appSettings.isFeatureEnabled(GakujoFeatureFlag.autoBackup)) {
      return;
    }
    _autoBackupTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(_writeAutomaticBackup()),
    );
    if (!_autoBackupWrittenThisLaunch) {
      _autoBackupWrittenThisLaunch = true;
      unawaited(_writeAutomaticBackup());
      return;
    }
    // Only the last ten automatic backups are kept, so a burst of setting
    // changes must not rotate out older ones: write once things settle.
    _autoBackupDebounce = Timer(
      const Duration(minutes: 1),
      () => unawaited(_writeAutomaticBackup()),
    );
  }

  Future<File?> _writeAutomaticBackup() async {
    _lastAutomaticBackupAt = DateTime.now();
    try {
      final file = await _writeBackupFile(prefix: 'auto');
      unawaited(_uploadAutomaticSyncBackup());
      return file;
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
      payload: await _backupPayload(includeStarredMessages: prefix != 'auto'),
      pruneAfterWrite: prefix == 'auto',
      pruneFileNamePrefix: prefix == 'auto' ? 'auto-backup-' : null,
    );
  }

  Future<File> _writeJsonFile({
    required String directoryName,
    required String fileName,
    required Map<String, Object?> payload,
    bool pruneAfterWrite = true,
    String? pruneFileNamePrefix,
  }) async {
    final text = encodeGakujoBackupPayload(payload);
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(_joinLocalPath(documents.path, directoryName));
    await directory.create(recursive: true);
    final file = File(_joinLocalPath(directory.path, fileName));
    await file.writeAsString(
      text,
      flush: true,
    );
    if (pruneAfterWrite) {
      await pruneJsonFilesForRetention(
        directory,
        keep: 10,
        fileNamePrefix: pruneFileNamePrefix,
        protectedFile: file,
      );
    }
    return file;
  }

  String _joinLocalPath(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) {
      return '$parent$child';
    }
    return '$parent${Platform.pathSeparator}$child';
  }

  Future<void> _showFavoritesDialog({
    ModalRoute<void>? settingsRoute,
    int? returnRevision,
  }) async {
    var favorites = await _activityStore.loadFavorites();
    if (!mounted ||
        settingsRoute?.isActive == false ||
        _isStaleDialogReturn(returnRevision)) {
      return;
    }

    final returned = returnRevision != null;
    Future<void> Function()? refreshFavorites;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        if (returned) _returnedDialogContext = dialogContext;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            refreshFavorites ??= () async {
              final updatedFavorites = await _activityStore.loadFavorites();
              if (!dialogContext.mounted) return;
              setDialogState(() => favorites = updatedFavorites);
            };
            _refreshOpenFavorites = refreshFavorites;
            return _historyDialogInput(
              returned: returned,
              child: AlertDialog(
              title: _historyDialogTitle('お気に入り', returned),
              content: SizedBox(
                width: 520,
                child: favorites.isEmpty
                    ? const Text('メニューの「お気に入りに追加」で、開いているページを追加できます。')
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: favorites.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
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
                                try {
                                  await _activityStore.removeFavorite(
                                    favorite.url,
                                  );
                                } on Object catch (error, stackTrace) {
                                  developer.log(
                                    'Failed to delete favorite',
                                    name: 'MoreBetterGakujo',
                                    error: error,
                                    stackTrace: stackTrace,
                                  );
                                  _showSnackBar('お気に入りを削除できませんでした');
                                  return;
                                }
                                _scheduleStarSync();
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
                              _setPendingReturnDialog('favorites');
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
              ),
            );
          },
        );
      },
    );
    if (identical(_refreshOpenFavorites, refreshFavorites)) {
      _refreshOpenFavorites = null;
    }
  }

  Future<void> _openGakujoHome() async {
    _setPendingReturnDialog(null);
    if (_calendarOperationGate.isRunning) {
      _showSnackBar('カレンダー連携または再検出の完了後に移動してください');
      return;
    }
    _setPendingMessageUrl(null);
    await _loadAllowedPageUrl(gakujoHomePortalUrl);
  }

  Future<void> _handleToolbarSelection(Object selection) async {
    if (selection is GakujoQuickJumpDestination) {
      _setPendingReturnDialog(null);
      if (_calendarOperationGate.isRunning) {
        _showSnackBar('カレンダー連携または再検出の完了後に移動してください');
        return;
      }
      _setPendingMessageUrl(null);
      await _loadAllowedPageUrl(selection.portalUrl);
      return;
    }
    await _handleToolbarAction(selection as _ToolbarAction);
  }

  Future<void> _showNotificationHistory() async {
    final account = _activeLoginAccount;
    final identityRevision = _loginIdentity.revision;
    final navigation = _navigationRevision;
    final entries = account == null
        ? Future.value(const <GakujoNotificationHistoryEntry>[])
        : _notificationService.loadHistory(account);
    final target = await showDialog<String>(
      context: context,
      builder: (_) => NotificationHistoryDialog(
        account: account,
        activeAccount: _notificationHistoryAccount,
        entries: entries,
        targetUrl: (url) =>
            _notificationService.targetUrl(url, debugAllowed: _debugAllowed),
      ),
    );
    if (target == null || !mounted || account != _activeLoginAccount ||
        identityRevision != _loginIdentity.revision ||
        navigation != _navigationRevision || _calendarOperationGate.isRunning) {
      return;
    }
    try {
      await _handleDeadlineNotificationTapped(target, historyAccount: account);
    } on Object {
      if (mounted) _showSnackBar('通知のページを開けませんでした');
    }
  }

  Future<void> _handleToolbarAction(_ToolbarAction action) async {
    switch (action) {
      case _ToolbarAction.coursePlanner:
        await _launchExternalUrl(Uri.parse('https://gakujo.terudoru.com/syllabus/'));
        return;
      case _ToolbarAction.importCoursePlanner:
        await _openCoursePlanner(_PlannerDestination.clipboard);
        return;
      case _ToolbarAction.copyCoursePlanner:
        await _openCoursePlanner(_PlannerDestination.clipboard);
        return;
      case _ToolbarAction.registrationAssist:
        await _openRegistrationAssist();
        return;
      case _ToolbarAction.messageStars:
        await _showStarredMessagesDialog();
        return;
      case _ToolbarAction.notificationHistory:
        await _showNotificationHistory();
        return;
      case _ToolbarAction.reload:
        if (_calendarOperationGate.isRunning) {
          _showSnackBar('カレンダー連携または再検出の完了後に再読み込みしてください');
          return;
        }
        _beginNavigation();
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
        final title = await _titleForFavoriteUrl(url);
        try {
          await _activityStore.addFavorite(
            GakujoFavoritePage(
              title: _favoriteTitle(title, url),
              url: url,
              addedAt: DateTime.now(),
            ),
          );
          _scheduleStarSync();
        } on Object {
          _showSnackBar('お気に入りに追加できませんでした');
          return;
        }
        _showSnackBar('お気に入りに追加しました');
        return;
      case _ToolbarAction.copyUrl:
        final sanitizedUrl = sanitizeGakujoCopyUrl(url);
        if (sanitizedUrl.isEmpty) {
          _showSnackBar('このページのURLはコピーできません');
          return;
        }
        try {
          await Clipboard.setData(ClipboardData(text: sanitizedUrl));
        } on Object {
          _showSnackBar('URLをコピーできませんでした');
          return;
        }
        _showSnackBar('URLをコピーしました');
        return;
      case _ToolbarAction.openExternal:
        await _launchExternalUrl(Uri.parse(url));
        return;
      case _ToolbarAction.reload:
      case _ToolbarAction.coursePlanner:
      case _ToolbarAction.importCoursePlanner:
      case _ToolbarAction.copyCoursePlanner:
      case _ToolbarAction.registrationAssist:
      case _ToolbarAction.messageStars:
      case _ToolbarAction.notificationHistory:
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

  Future<void> _saveAppSettings(Future<void> Function() save) async {
    if (defaultTargetPlatform != TargetPlatform.linux) {
      await save();
      return;
    }
    if (!await _linuxSessionSettings.save(
      save,
      storageAvailable: _secureStorageAccessAllowed,
      showSnackBar: _showSnackBar,
    )) {
      _secureStorageAccessAllowed = false;
    }
  }

  void _noticeSessionDownloadRoot(DownloadDestinationSettings root) {
    if (!root.isSessionOnly) return;
    _secureStorageAccessAllowed = false;
    _linuxSessionSettings.showNotice(_showSnackBar);
  }

  Future<bool> _trySaveSettings(Future<void> Function() save) {
    return saveGakujoSettingsSafely(save, showSnackBar: _showSnackBar);
  }

  Future<void> _saveCalendarImportSettings(
    GakujoCalendarImportSettings settings,
  ) => _settingsOperations.runExclusive(() async {
    await _saveAppSettings(
      () => _appSettingsStore.saveCalendarImportSettings(settings),
    );
    final nextSettings = _appSettings.copyWith(
      calendarImportSettings: settings,
    );
    await _syncLocalSettingsMirror(nextSettings);
    if (!mounted) {
      return;
    }
    setState(() {
      _appSettings = _appSettings.copyWith(calendarImportSettings: settings);
    });
    _scheduleStarSync();
  });

  GakujoAppSettings _settingsForPersistence(GakujoAppSettings settings) {
    return gakujoSettingsForPersistence(
      settings,
      placeholderFeatureFlags: _startupPlaceholderFeatureFlags,
    );
  }

  Future<void> _syncLocalSettingsMirror(
    GakujoAppSettings settings,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.linux &&
        !_secureStorageAccessAllowed) {
      return;
    }
    try {
      await _localPrefsStore.saveAppSettings(_settingsForPersistence(settings));
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to update local app settings mirror',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _saveMessageNotification(
    MessageNotificationUpdate update,
  ) => _settingsOperations.runExclusive(() async {
    // Only messages posted from now on follow the new rule.
    final messages = update(_appSettings.messageNotification)
        .copyWith(since: DateTime.now());
    if (!Platform.isMacOS || _secureStorageAccessAllowed) {
      try {
        await _saveAppSettings(
          () => _appSettingsStore.saveMessageNotification(messages),
        );
      } on Object catch (error, stackTrace) {
        if (!Platform.isMacOS) {
          rethrow;
        }
        developer.log(
          'Failed to mirror message notification rule to secure storage',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (mounted) {
      setState(() {
        _appSettings = _appSettings.copyWith(messageNotification: messages);
      });
    }
    await _syncLocalSettingsMirror(
      _appSettings.copyWith(messageNotification: messages),
    );
    if (!mounted) {
      return;
    }
    _scheduleStarSync();
    await _injectMessageFilterIfAllowed();
  });

  Future<void> _saveNotificationTopics(
    Set<GakujoNotificationTopic> Function(Set<GakujoNotificationTopic>) update,
  ) => _settingsOperations.runExclusive(() async {
    final topics = update(_appSettings.notificationTopics);
    await saveGakujoSettingsChange(
      save: () async {
        if (!Platform.isMacOS || _secureStorageAccessAllowed) {
          try {
            await _saveAppSettings(
              () => _appSettingsStore.saveNotificationTopics(topics),
            );
          } on Object catch (error, stackTrace) {
            if (!Platform.isMacOS) rethrow;
            // macOS starts from the local mirror before Keychain access.
            developer.log(
              'Failed to mirror notification topics to secure storage',
              name: 'MoreBetterGakujo',
              error: error,
              stackTrace: stackTrace,
            );
          }
        }
      },
      currentSettings: () => _appSettings,
      update: (settings) => settings.copyWith(notificationTopics: topics),
      apply: (settings) {
        if (mounted) setState(() => _appSettings = settings);
      },
      mirror: _syncLocalSettingsMirror,
    );
    _scheduleStarSync();
    if (mounted) unawaited(_syncReminders());
  });

  Future<void> _saveNotificationPreferences(
    NotificationPreferencesUpdate update,
  ) {
    return _settingsOperations.runExclusive(() async {
      final preferences = update(_appSettings.notificationPreferences);
      try {
        await saveGakujoSettingsChange(
          save: () async {
            if (!Platform.isMacOS || _secureStorageAccessAllowed) {
              try {
                await _saveAppSettings(
                  () => _appSettingsStore.saveNotificationPreferences(
                    preferences,
                  ),
                );
              } on Object catch (error, stackTrace) {
                if (!Platform.isMacOS) rethrow;
                developer.log(
                  'Failed to mirror notification preferences to secure storage',
                  name: 'MoreBetterGakujo',
                  error: error,
                  stackTrace: stackTrace,
                );
              }
            }
            if (Platform.isMacOS) {
              await _localPrefsStore.saveAppSettings(
                _settingsForPersistence(_appSettings.copyWith(
                  notificationPreferences: preferences,
                )),
              );
            }
          },
          currentSettings: () => _appSettings,
          update: (settings) => settings.copyWith(
            notificationPreferences: preferences,
          ),
          apply: (settings) {
            if (mounted) setState(() => _appSettings = settings);
          },
          mirror: Platform.isMacOS ? (_) async {} : _syncLocalSettingsMirror,
        );
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to save notification preferences',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
        if (mounted) _showSnackBar(_settingsSaveFailureMessage);
        return;
      }
      _scheduleStarSync();
      if (mounted) {
        unawaited(_syncReminders());
      }
    });
  }

  Future<void> _saveMessageExcludeKeywords(
    List<String> Function(List<String>) update,
  ) => _settingsOperations.runExclusive(() async {
    final normalized = normalizeMessageExcludeKeywords(
      update(_appSettings.messageExcludeKeywords),
    );
    if (!Platform.isMacOS) {
      await _saveAppSettings(
        () => _appSettingsStore.saveMessageExcludeKeywords(normalized),
      );
    }
    if (mounted) {
      setState(() {
        _appSettings = _appSettings.copyWith(messageExcludeKeywords: normalized);
      });
    }
    // Apply before mirroring so concurrent saves cannot queue older keywords.
    // macOS persists these non-sensitive keywords locally before Keychain.
    await _syncLocalSettingsMirror(
      _appSettings.copyWith(messageExcludeKeywords: normalized),
    );
    if (Platform.isMacOS && _secureStorageAccessAllowed) {
      try {
        await _appSettingsStore.saveMessageExcludeKeywords(normalized);
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to mirror message filters to secure storage',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (!mounted) {
      return;
    }
    _scheduleStarSync();
    await _injectMessageFilterIfAllowed();
  });

  void _beginNavigation({bool preservesPendingMessageOpen = false, bool pageStarted = false}) {
    _setRegistrationAvailable(false);
    if (!pageStarted) _finishRegistration('別の画面への操作があったため終了しました。');
    if (mounted && (_virtualPreviewForward || _returnDialogMarker != null)) {
      setState(() {
        _virtualPreviewForward = false;
        _returnDialogMarker = null;
      });
    }
    _activePreviewToken = null;
    if (_previewNavigationState != 'none' && mounted) {
      _handlePreviewNavigationState('none');
    }
    if (!preservesPendingMessageOpen) {
      _setPendingMessageUrl(null);
    }
    _cancelOfflineRetry();
    _navigationRevision += 1;
    _linuxOverlayNavigation.value = _navigationRevision;
    _pendingPageFinishedNavigationRevision = null;
  }

  void _beginPendingMessageNavigation(String url) {
    _beginNavigation(preservesPendingMessageOpen: true);
    _pendingMessageOpen?.navigation.record(url, _navigationRevision);
  }

  void _requestOfflineRetry() {
    _offlineRetryNavigationRevision = _navigationRevision;
    if (!_appInBackground) _offlineRetry.start();
  }

  void _cancelOfflineRetry() {
    _offlineRetryNavigationRevision = null;
    _offlineRetry.cancel();
  }

  void _onOfflineRetryExpired() {
    if (!mounted || _offlineRetryNavigationRevision != _navigationRevision) {
      return;
    }
    _offlineRetryNavigationRevision = null;
    if (_status.value == _offlineRetryStatus) _setStatus(_manualReloadStatus);
  }

  Future<void> _reloadAfterConnectivityRestored() async {
    if (!mounted ||
        _appInBackground ||
        _offlineRetryNavigationRevision != _navigationRevision) {
      return;
    }
    _beginNavigation();
    _offlineAutoReloads += 1;
    final navigationRevision = _navigationRevision;
    _setStatus('接続が戻ったので再読み込みしました');
    try {
      // Android's reload() keeps the error page's 1:1 scale, so the desktop
      // page would not fit the width; a fresh load resets the overview.
      final failedUrl = _currentPageUrl;
      if (failedUrl != null &&
          AllowedWebOrigins.canLoad(failedUrl, debugAllowed: _debugAllowed)) {
        final deferred = _deferredPageNavigation;
        if (deferred != null && deferred.url == failedUrl) {
          // This retry can finish without another SourceChanged. Keep the
          // existing wait and deadline, but recognize the reissued navigation.
          _deferredPageNavigation = (
            url: failedUrl,
            revision: navigationRevision,
            disposed: deferred.disposed,
          );
        }
        await _controller.loadUrl(failedUrl);
      } else {
        await _controller.reload();
      }
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to reload after connectivity returned',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (navigationRevision == _navigationRevision) {
        _setStatus('読み込みエラー: $error');
      }
    }
  }

  Future<void> _loadAllowedPageUrl(
    String url, {
    bool ownsPageNavigationOperation = false,
  }) async {
    _detachedPreviewToken = null;
    if (mounted && _virtualPreviewForward) {
      setState(() => _virtualPreviewForward = false);
    }
    if (!AllowedWebOrigins.canNavigate(url, debugAllowed: _debugAllowed)) {
      _setPendingReturnDialog(null);
      _showSnackBar('許可されていない外部URLは開けません');
      return;
    }
    if (_calendarOperationGate.isRunning && !ownsPageNavigationOperation) {
      if (AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
        _setPendingMessageUrl(null);
        _deferredNotificationAfterPageOperationUrl = null;
        _deferredNavigationAfterPageOperationUrl = url;
        _showSnackBar('処理完了後にページを開きます');
      } else {
        _showSnackBar('カレンダー連携または再検出の完了後に移動してください');
      }
      return;
    }
    if (!ownsPageNavigationOperation) {
      _setPendingMessageUrl(url);
    }
    _beginPendingMessageNavigation(url);
    await _controller.loadUrl(url);
  }

  void _clearNavigationRestoreFor(String url) {
    if (_pendingLoginRestoreUrl == url) {
      _pendingLoginRestoreUrl = null;
    }
    if (_navigationRecoveryCandidateUrl == url) {
      _navigationRecoveryCandidateUrl = null;
      _navigationRecoveryCandidateFailed = false;
    }
  }

  void _setPendingMessageUrl(String? url, {Object? owner}) {
    final previous = _pendingMessageOpen;
    if (previous != null) _clearNavigationRestoreFor(previous.url);
    _pendingMessageOpenTimer?.cancel();
    _pendingMessageOpen = null;
    final message = url == null ? null : gakujoMessageTargetFromUrl(url);
    if (message == null || url == null) {
      return;
    }
    final pending = _PendingMessageOpen(url: url, message: message);
    _pendingMessageOpen = pending;
    _loginRestore.reserve(url, owner: owner);
    _loginRestoreAttempted = false;
    _navigationRecovery.reserve(url, owner: owner);
    _navigationRecoveryCandidateFailed = false;
    _pendingMessageOpenTimer = Timer(const Duration(minutes: 3), () {
      if (identical(_pendingMessageOpen, pending)) {
        _setPendingMessageUrl(null);
        _showSnackBar('連絡通知を開けませんでした');
      }
    });
  }

  Future<bool> _openPendingMessageIfNeeded(
    String url, {
    required int navigationRevision,
  }) async {
    final pending = _pendingMessageOpen;
    bool stillCurrent() =>
        identical(_pendingMessageOpen, pending) &&
        (!identical(_historyNavigation?.message, pending) ||
            _historyNavigation?.account == _activeLoginAccount) &&
        _isCurrentPageCallback(url, navigationRevision);
    if (pending == null ||
        !stillCurrent() ||
        _calendarOperationGate.isRunning ||
        !AllowedWebOrigins.canLoad(url, debugAllowed: false)) {
      return false;
    }
    final inFlight = _messageOpenProcessing;
    if (inFlight != null) {
      await inFlight.future;
    }
    if (!stillCurrent() ||
        _calendarOperationGate.isRunning ||
        _messageOpenProcessing != null ||
        pending.attemptedNavigationRevision == navigationRevision) {
      return false;
    }
    if (DateTime.now().difference(pending.startedAt) >=
        const Duration(minutes: 3)) {
      _setPendingMessageUrl(null);
      _showSnackBar('連絡通知を開けませんでした');
      return false;
    }
    final processing = Completer<void>();
    _messageOpenProcessing = processing;
    pending.attemptedNavigationRevision = navigationRevision;
    try {
      final result = await _controller.runJavaScriptReturningResult(
        GakujoMessageStarScript.buildOpen(
          keijitype: pending.message.keijitype,
          genrecd: pending.message.genrecd,
          seqNo: pending.message.seqNo,
        ),
      ).timeout(const Duration(seconds: 60));
      if (!stillCurrent()) {
        return false;
      }
      if (DateTime.now().difference(pending.startedAt) >=
          const Duration(minutes: 3)) {
        _setPendingMessageUrl(null);
        _showSnackBar('連絡通知を開けませんでした');
        return false;
      }
      final decoded = jsonDecode(_stringFromJavaScriptResult(result));
      if (decoded is! Map) throw const FormatException('Invalid open result');
      switch (decoded['status']) {
        case 'ok':
          final targetUrl = decoded['url'];
          if (targetUrl is! String ||
              !AllowedWebOrigins.canLoad(targetUrl, debugAllowed: false)) {
            throw const FormatException('Invalid message URL');
          }
          _setPendingMessageUrl(null);
          _beginNavigation();
          await _controller.loadUrl(targetUrl);
          return true;
        case 'gone':
          _setPendingMessageUrl(null);
          _showSnackBar('連絡通知が見つかりませんでした。一覧を開きます');
          _beginNavigation();
          await _controller.loadUrl(_messageListPortalUrl);
          return true;
        case 'missing':
          pending.missingResults += 1;
          if (pending.missingResults < 3) {
            return false;
          }
          break;
      }
      _setPendingMessageUrl(null);
      _showSnackBar('連絡通知を開けませんでした');
    } on TimeoutException {
      if (identical(_pendingMessageOpen, pending)) {
        _setPendingMessageUrl(null);
        _showSnackBar('連絡通知を開けませんでした');
      }
    } on Object catch (error, stackTrace) {
      developer.log('Failed to open pending message',
          name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      if (stillCurrent()) {
        _setPendingMessageUrl(null);
        _showSnackBar('連絡通知を開けませんでした');
      }
    } finally {
      _messageOpenProcessing = null;
      processing.complete();
    }
    return false;
  }

  Future<String?> _waitForNextPageFinished({
    Duration timeout = const Duration(seconds: 4),
    Completer<String>? waiter,
  }) {
    final completer = waiter ?? Completer<String>();
    _nextPageFinishedCompleter = completer;
    return completer.future.timeout(timeout, onTimeout: () => '').then(
      (url) async {
        if (identical(_nextPageFinishedCompleter, completer)) {
          _nextPageFinishedCompleter = null;
        }
        if (url.isEmpty) {
          return null;
        }
        final processing = _pageFinishedProcessing;
        if (processing != null && processing.url == url) {
          await processing.completer.future;
        }
        return url;
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

  Future<String?> _titleForFavoriteUrl(String url) async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        gakujoFavoritePageIdentityJs,
      );
      if (result is String) {
        final page = jsonDecode(_stringFromJavaScriptResult(result));
        if (page case {'url': final String pageUrl, 'title': final String title}
            when pageUrl == url) {
          return title;
        }
      }
    } on Object {
      // The selected URL still provides a title if the renderer is unavailable.
    }
    return null;
  }

  String _favoriteTitle(String? title, String url) {
    final trimmed = title?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    return segments.isEmpty ? 'Gakujo' : segments.last;
  }

  Future<bool> _quickJumpTo(
    String label, {
    String? fallbackUrl,
    bool ownsPageNavigationOperation = false,
  }) async {
    _detachedPreviewToken = null;
    if (mounted && _virtualPreviewForward) {
      setState(() => _virtualPreviewForward = false);
    }
    if (_calendarOperationGate.isRunning && !ownsPageNavigationOperation) {
      _showSnackBar('カレンダー連携または再検出の完了後に移動してください');
      return false;
    }
    if (!ownsPageNavigationOperation) {
      _setPendingMessageUrl(null);
      _beginNavigation();
    }
    if (!_canRunPageScripts) {
      if (fallbackUrl != null) {
        await _loadAllowedPageUrl(
          fallbackUrl,
          ownsPageNavigationOperation: ownsPageNavigationOperation,
        );
        return true;
      } else {
        _showSnackBar('ページを読み込んでから使ってください');
      }
      return false;
    }

    try {
      final result = await _controller.runJavaScriptReturningResult(
        GakujoQuickJumpScript.build(label),
      );
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
      await _loadAllowedPageUrl(
        fallbackUrl,
        ownsPageNavigationOperation: ownsPageNavigationOperation,
      );
      return true;
    } else {
      _showSnackBar('$label が見つかりませんでした');
    }
    return false;
  }

  Future<void> _scanCurrentPageActivity(String url) async {
    if (!AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
      return;
    }
    final account = _activeLoginAccount;
    final revision = _loginIdentity.revision;
    final navigation = _navigationRevision;
    final result = await _readPageTextForActivity();
    if (result == null) {
      return;
    }
    if (!mounted || revision != _loginIdentity.revision ||
        navigation != _navigationRevision || account != _activeLoginAccount) {
      return;
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
    {
      final assignments = [
        for (final row in result.reportItems)
          ?GakujoAssignment.fromReportRow(
            row,
            capturedAt: DateTime.now(),
            notificationAccount: account,
            // A reminder opens the list it can be submitted from, even when
            // the assignment was found elsewhere.
            url: category == 'レポート・小テスト'
                ? durableGakujoLink(url, category)
                : _reportListPortalUrl,
          ),
      ];
      await _activityStore.mergeAssignments(assignments);
      if (assignments.isNotEmpty) {
        unawaited(_syncReminders());
      }
      final extractedDeadlines = _extractDeadlines(
        category: category,
        title: title,
        url: url,
        text: result.text,
        messageItems: result.messageItems,
        assignments: assignments,
        notificationAccount: account,
      );
      await _activityStore.mergeDeadlines(
        extractedDeadlines,
      );
      await _notifyPendingDeadlines();
    }
    if (category == 'レポート・小テスト') {
      final capturedAt = DateTime.now();
      // Parsed rows read better than page lines, which include tab labels,
      // sort buttons and table headers.
      final rowItems = [
        for (final row in result.reportItems)
          if (GakujoAssignment.fromReportRow(
            row,
            capturedAt: capturedAt,
            url: url,
          )
              case final assignment?)
            gakujoCachedAssignmentText(assignment),
      ];
      await _activityStore.saveReportList(
        GakujoCachedReportList(
          title: title,
          url: url,
          capturedAt: capturedAt,
          items: rowItems.isEmpty
              ? gakujoExtractReportListItems(result.text)
              : rowItems,
        ),
      );
    }
  }

  Future<_PageTextSnapshot?> _readPageTextForActivity() async {
    if (!_canRunPageScripts) {
      return null;
    }
    try {
      final result = await _controller.runJavaScriptReturningResult(
        gakujoPageTextActivityJs,
      );
      final raw = _stringFromJavaScriptResult(result);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final rawMessageItems = decoded['messageItems'];
      final rawReportItems = decoded['reportItems'];
      return _PageTextSnapshot(
        reportItems: rawReportItems is List<dynamic>
            ? rawReportItems.whereType<Map<dynamic, dynamic>>().toList()
            : const [],
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
    List<GakujoAssignment> assignments = const [],
    String? notificationAccount,
  }) {
    // Grades pages contain personal records, not deadlines.
    if (category == '成績') {
      return const [];
    }

    final now = DateTime.now();
    final entries = <GakujoDeadlineEntry>[];
    final seen = <String>{};
    void addEntry({
      required String entryTitle,
      required String entryUrl,
      required String entryText,
      required String kind,
      String messageText = '',
    }) {
      final normalizedText = _datedActivityText(entryText);
      if (GakujoDatedActivity.isNoiseText(normalizedText) ||
          !_containsDate(normalizedText)) {
        return;
      }
      final normalizedTitle = entryTitle.trim().isEmpty
          ? _datedActivityTitle(normalizedText)
          : GakujoDatedActivity.compactText(entryTitle, maxLength: 80);
      final safeUrl = durableGakujoLink(
        entryUrl.trim().isEmpty ? url : entryUrl,
        category,
      );
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
          source: category,
          notificationAccount: notificationAccount,
          messageText: messageText.isEmpty || messageText.contains(entryTitle)
              ? messageText
              : '$messageText $entryTitle',
        ),
      );
    }

    // The schedule page and the レポート・小テスト list are read item by item
    // below. Their table rows also look like dated notices to the page scan,
    // and taken as such each assignment came again as one whole row, with
    // 「未提出」 read as a deadline word.
    final readsItemsItself = category == 'スケジュール' ||
        category == 'レポート・小テスト' ||
        assignments.isNotEmpty;
    for (final item in readsItemsItself
        ? const <_MessageActivityCandidate>[]
        : messageItems) {
      // 「[新着]」 disappears once read and would make it a new entry.
      final text = item.text.replaceAll('[新着]', ' ');
      final kind = GakujoDatedActivity.kindFor(text: text, category: category);
      addEntry(
        entryTitle: item.title.replaceAll('[新着]', '').trim(),
        entryUrl: gakujoMessageLinkFor(item.url),
        entryText: category == '連絡通知' && kind != 'notice'
            ? GakujoDatedActivity.messageContentForDates(text)
            : text,
        kind: kind,
        messageText: category == '連絡通知' ? text : '',
      );
    }

    if (category == '連絡通知' && messageItems.isNotEmpty) {
      return entries;
    }

    if (category == 'スケジュール') {
      return deadlineEntriesForSchedule(
        text,
        url: durableGakujoLink(url, category),
        detectedAt: now,
        notificationAccount: notificationAccount,
      );
    }

    if (assignments.isNotEmpty) {
      // The list gives each assignment's exact closing time.
      return deadlineEntriesForAssignments(
        assignments,
        url: durableGakujoLink(url, category),
        detectedAt: now,
      );
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
      final kind = GakujoDatedActivity.kindFor(text: line, category: category);
      addEntry(
        entryTitle: _datedActivityLineTitle(
            category: category, title: title, line: line),
        entryUrl: url,
        entryText: category == '連絡通知' && kind != 'notice'
            ? GakujoDatedActivity.messageContentForDates(line)
            : line,
        kind: kind,
        messageText: category == '連絡通知' ? line : '',
      );
    }
    return entries;
  }

  bool _containsDate(String text) {
    return GakujoDatedActivity.containsDate(text);
  }

  String _datedActivityText(String text) {
    return GakujoDatedActivity.datedTextPreview(text);
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

  Future<void> _notifyPendingDeadlines({bool allowPermissionRequest = true}) {
    return _deadlineNotificationCoordinator.notifyPendingDeadlines(
      notificationsEnabled: _appSettings.isFeatureEnabled(
        GakujoFeatureFlag.deadlineNotifications,
      ),
      topics: _appSettings.notificationTopics,
      messages: _appSettings.messageNotification,
      preferences: _appSettings.notificationPreferences,
      messageExcludeKeywords: _appSettings.messageExcludeKeywords,
      allowPermissionRequest: allowPermissionRequest,
      currentSettings: () => _appSettings,
    );
  }

  /// Keeps assignments and 連絡通知 current without opening their pages:
  /// fetches them in the background at most every half hour while signed
  /// in, then tells about new deadlines and messages and rebooks reminders.
  Future<void> _refreshAssignmentsInBackground({
    bool allowPermissionRequest = true,
  }) async {
    if (!_canRunPageScripts ||
        _calendarOperationGate.isRunning ||
        _backgroundActivityRefreshRunning) {
      return;
    }
    final now = DateTime.now();
    bool isDue(DateTime? last) =>
        last == null || now.difference(last) >= const Duration(minutes: 30);
    final fetchAssignments = isDue(_lastAssignmentRefresh);
    final messageMode = _appSettings.messageNotification.mode;
    final fetchMessages =
        isDue(_lastMessageRefresh) &&
        messageMode != GakujoMessageNotificationMode.off &&
        _appSettings.isFeatureEnabled(GakujoFeatureFlag.deadlineNotifications);
    if (!fetchAssignments && !fetchMessages) return;

    final account = _activeLoginAccount;
    final revision = _loginIdentity.revision;
    bool stillSameAccount() =>
        mounted &&
        revision == _loginIdentity.revision &&
        account == _activeLoginAccount;

    _backgroundActivityRefreshRunning = true;
    try {
      List<GakujoDeadlineEntry>? assignments;
      if (fetchAssignments) {
        try {
          assignments = await _fetchAssignmentDeadlinesInBackground(
            now,
            notificationAccount: account,
            stillSameAccount: stillSameAccount,
          );
          if (!stillSameAccount()) return;
          _lastAssignmentRefresh = assignments == null ? null : now;
        } on Object catch (error, stackTrace) {
          if (!stillSameAccount()) return;
          _lastAssignmentRefresh = null;
          developer.log(
            'Failed to refresh assignments in the background',
            name: 'MoreBetterGakujo',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      ({
        List<GakujoDeadlineEntry> entries,
        List<String>? unreadMessageUrls,
        bool partial,
      })? messages;
      if (fetchMessages) {
        try {
          messages = await _fetchMessageDeadlinesInBackground(
            messageMode,
            notificationAccount: account,
          );
          if (!stillSameAccount()) return;
          _lastMessageRefresh = messages == null || messages.partial ? null : now;
        } on Object catch (error, stackTrace) {
          if (!stillSameAccount()) return;
          _lastMessageRefresh = null;
          developer.log(
            'Failed to fetch message deadlines in the background',
            name: 'MoreBetterGakujo',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      if (assignments == null && messages == null) return;
      await _activityStore.mergeDeadlines([
        ...?assignments,
        ...?messages?.entries,
      ], unreadMessageUrls: messages?.unreadMessageUrls);
      if (!stillSameAccount()) return;
      await _notifyPendingDeadlines(
        allowPermissionRequest: allowPermissionRequest,
      );
      await _syncReminders(allowPermissionRequest: allowPermissionRequest);
    } on Object catch (error, stackTrace) {
      if (!stillSameAccount()) return;
      if (fetchAssignments) _lastAssignmentRefresh = null;
      if (fetchMessages) _lastMessageRefresh = null;
      developer.log(
        'Failed to process the background activity scan',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _backgroundActivityRefreshRunning = false;
    }
  }

  Future<List<GakujoDeadlineEntry>?> _fetchAssignmentDeadlinesInBackground(
    DateTime now, {
    required String? notificationAccount,
    required bool Function() stillSameAccount,
  }) async {
    final result = await _controller
        .runJavaScriptReturningResult(gakujoAssignmentListFetchScript)
        .timeout(const Duration(seconds: 60));
    if (!stillSameAccount()) return null;
    final decoded = jsonDecode(_stringFromJavaScriptResult(result));
    if (decoded is! Map || decoded['status'] != 'ok') return null;
    final rows = decoded['rows'];
    final assignments = [
      if (rows is List)
        for (final row in rows.whereType<Map<dynamic, dynamic>>())
          ?GakujoAssignment.fromReportRow(
            row,
            capturedAt: now,
            url: _reportListPortalUrl,
            notificationAccount: notificationAccount,
          ),
    ];
    final total = decoded['total'];
    await _activityStore.mergeAssignments(
      assignments,
      isWholeList: rows is List && total is num && rows.length == total,
    );
    return deadlineEntriesForAssignments(
      assignments,
      url: _reportListPortalUrl,
      detectedAt: now,
    );
  }

  /// The 連絡通知 未読一覧 as deadline entries, read the way a visit to the
  /// list reads them. Null means the list was unavailable.
  Future<
    ({
      List<GakujoDeadlineEntry> entries,
      List<String>? unreadMessageUrls,
      bool partial,
    })?
  >
  _fetchMessageDeadlinesInBackground(
    GakujoMessageNotificationMode mode, {
    required String? notificationAccount,
  }) async {
    final keywordMode = mode == GakujoMessageNotificationMode.keywords;
    final result = await _controller
        .runJavaScriptReturningResult(
          keywordMode
              ? gakujoKeywordMessageListFetchScript
              : gakujoMessageListFetchScript,
        )
        .timeout(const Duration(seconds: 60));
    final decoded = jsonDecode(_stringFromJavaScriptResult(result));
    if (decoded is! Map) return null;
    final status = decoded['status'];
    if (status != 'ok' && status != 'partial') return null;
    final complete = status == 'ok' && decoded['complete'] == true;
    final items = decoded['items'];
    if (items is! List) return null;
    final allEntries = _extractDeadlines(
      category: '連絡通知',
      title: '連絡通知',
      url: _messageListPortalUrl,
      text: '',
      messageItems: [
        for (final item in items.whereType<Map<dynamic, dynamic>>())
          _MessageActivityCandidate.fromJson(item),
      ],
      notificationAccount: notificationAccount,
    );
    // Prioritize matching rows before storing this bounded batch, so later
    // pages with matches are not crowded out by nonmatches on page one.
    final matches = keywordMode
        ? allEntries
              .where(
                (entry) => isNotifiableDeadline(
                  entry,
                  topics: const {},
                  messages: _appSettings.messageNotification,
                  excludeKeywords: _appSettings.messageExcludeKeywords,
                ),
              )
              .toSet()
        : const <GakujoDeadlineEntry>{};
    return (
      partial: status == 'partial',
      entries: keywordMode && allEntries.length > 60
          ? [
              ...matches,
              ...allEntries.take(60).where((entry) => !matches.contains(entry)),
            ].take(60).toList()
          : allEntries,
      // Only a complete keyword scan can use absence as evidence of a read.
      unreadMessageUrls: keywordMode && !complete
          ? null
          : [
              for (final item in items)
                gakujoMessageLinkFor(
                  item is Map ? item['url']?.toString() ?? '' : '',
                ),
            ],
    );
  }

  Future<void> _syncReminders({bool allowPermissionRequest = true}) {
    return _deadlineNotificationCoordinator.syncReminders(
      notificationsEnabled: _appSettings.isFeatureEnabled(
        GakujoFeatureFlag.deadlineNotifications,
      ),
      topics: _appSettings.notificationTopics,
      preferences: _appSettings.notificationPreferences,
      allowPermissionRequest: allowPermissionRequest,
    );
  }

  Future<GakujoPortalAuthState> _readPortalAuthState({
    int attempts = 3,
    bool Function()? stillValid,
  }) async {
    if (!_canRunPageScripts || !(stillValid?.call() ?? true)) {
      return GakujoPortalAuthState.unknown;
    }
    try {
      // campussmart.do can reveal its login controls shortly after the page
      // callback. Give that DOM mutation time to settle before classifying the
      // shared portal URL as an ordinary authenticated page.
      for (var attempt = 0; attempt < attempts; attempt += 1) {
        if (!_canRunPageScripts || !(stillValid?.call() ?? true)) {
          return GakujoPortalAuthState.unknown;
        }
        final probeRevision = _loginIdentity.revision;
        final navigation = _navigationRevision;
        final result = await _controller.runJavaScriptReturningResult(
          gakujoPortalAuthStateProbeScript,
        );
        if (!_canRunPageScripts || !(stillValid?.call() ?? true) ||
            navigation != _navigationRevision) {
          return GakujoPortalAuthState.unknown;
        }
        final state = gakujoPortalAuthStateFromJavaScriptResult(
          result,
        );
        if (state == GakujoPortalAuthState.login &&
            navigation == _navigationRevision) {
          _loginIdentity.loginFormShown(
            probeRevision: probeRevision,
            navigation: navigation,
          );
        }
        if (state == GakujoPortalAuthState.login ||
            state == GakujoPortalAuthState.twoFactor) {
          _loginIdentity.challenge();
          unawaited(_setActiveLoginAccount(null, resync: false).catchError(
            (Object error, StackTrace stackTrace) {
              developer.log('Failed to clear active login account',
                  name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
            },
          ));
        }
        if (state != GakujoPortalAuthState.unknown || attempt == attempts - 1) {
          return state;
        }
        await Future<void>.delayed(const Duration(milliseconds: 175));
      }
      return GakujoPortalAuthState.unknown;
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to inspect Gakujo authentication state',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return GakujoPortalAuthState.unknown;
    }
  }

  Future<void> _handlePortalAuthState(
    String url, {
    required GakujoPortalAuthState authState,
    required bool identityAllowed,
    required int identityRevision,
    required bool Function() stillCurrent,
  }) async {
    if (!stillCurrent()) return;
    final isAuthenticationChallenge = isGakujoAuthenticationChallenge(
      authState: authState,
      urlLooksLikeLoginOrTimeout: _looksLikeLoginOrTimeoutUrl(url),
    );
    if (!isAuthenticationChallenge && identityAllowed && identityRevision == _loginIdentity.revision &&
        authState == GakujoPortalAuthState.authenticated) {
      final account = _loginIdentity.confirm(authState);
      if (account != null) {
        await _setActiveLoginAccount(account, stillValid: stillCurrent);
        if (!stillCurrent()) return;
      }
    }
    await _handleSessionExpiredIfNeeded(url, authState: authState);
    if (!stillCurrent()) return;
    if (authState == GakujoPortalAuthState.authenticated) {
      _authenticatedPageUrl = url;
      _sessionRecoveryUrl = selectGakujoSessionRecoveryUrl(
        navigationCandidateUrl: url,
        authenticatedUrl: _sessionRecoveryUrl,
        pendingRestoreUrl: null,
        debugAllowed: _debugAllowed,
      );
      _navigationRecoveryCandidateUrl = null;
      _navigationRecoveryCandidateFailed = false;
      _lastSessionRecoveryNoticeUrl = null;
      if (_canRunPageScripts) {
        await _resetAutofillSessionStateAfterAuthentication();
        if (!stillCurrent()) return;
      }
      await _saveLastPageUrl(url);
    }
  }

  void _retryUnresolvedPortalAuthState(String url, int navigationRevision) {
    bool stillCurrent() => _isCurrentPageCallback(url, navigationRevision) &&
        _canRunPageScripts;
    if (!stillCurrent() ||
        !AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed) ||
        _looksLikeLoginOrTimeoutUrl(url) ||
        (_activeLoginAccount != null && _loginIdentity.pending == null &&
            _loginIdentity.restored == null) ||
        _authRetryNavigationRevision == navigationRevision) {
      return;
    }
    _authRetryNavigationRevision = navigationRevision;
    unawaited(() async {
      try {
        var identityRevision = _loginIdentity.revision;
        final authState = await waitForResolvedGakujoAuthState(
          stillCurrent: stillCurrent,
          delay: (duration) => Future<void>.delayed(duration),
          probe: (valid) {
            identityRevision = _loginIdentity.revision;
            return _readPortalAuthState(attempts: 1, stillValid: valid);
          },
        );
        if (authState == null || !stillCurrent()) return;
        await _handlePortalAuthState(
          url,
          authState: authState,
          identityAllowed: AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed),
          identityRevision: identityRevision,
          stillCurrent: stillCurrent,
        );
        if (!stillCurrent()) return;
        await _restoreLastPageAfterLoginIfNeeded(
          url,
          authState: authState,
          navigationRevision: navigationRevision,
        );
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to retry Gakujo authentication state',
          name: 'MoreBetterGakujo',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }());
  }

  Future<void> _resetAutofillSessionStateAfterAuthentication() async {
    try {
      await _controller.runJavaScript(gakujoAuthenticatedSessionResetScript);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to reset completed login autofill session state',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _isCurrentPageCallback(String url, int navigationRevision) {
    return mounted &&
        navigationRevision == _navigationRevision &&
        _currentPageUrl == url;
  }

  void _captureNavigationRecoveryCandidate(String url) {
    _mainFrameNavigationUrl = url;
    final candidate = captureGakujoNavigationRecoveryCandidate(
      url: url,
      currentUrl: _currentPageUrl,
      authenticatedUrl: _sessionRecoveryUrl,
      navigationCandidateUrl: _navigationRecoveryCandidateUrl,
      authenticatedPageUrl: _authenticatedPageUrl,
      navigationCandidateFailed: _navigationRecoveryCandidateFailed,
      debugAllowed: _debugAllowed,
    );
    if (candidate != _navigationRecoveryCandidateUrl || candidate == null) {
      _navigationRecoveryCandidateFailed = false;
    }
    _navigationRecoveryCandidateUrl = candidate;
  }

  Future<void> _handleSessionExpiredIfNeeded(
    String url, {
    required GakujoPortalAuthState authState,
  }) async {
    if (!AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
      return;
    }
    final urlLooksLikeLoginOrTimeout = _looksLikeLoginOrTimeoutUrl(url);
    if (!isGakujoAuthenticationChallenge(
      authState: authState,
      urlLooksLikeLoginOrTimeout: urlLooksLikeLoginOrTimeout,
    )) {
      return;
    }
    _authenticatedPageUrl = null;
    final navigationCandidateUrl = usableGakujoNavigationCandidateForChallenge(
      navigationCandidateUrl: _navigationRecoveryCandidateUrl,
      challengeUrl: url,
      debugAllowed: _debugAllowed,
    );
    if (navigationCandidateUrl == null &&
        _navigationRecoveryCandidateUrl == url) {
      _navigationRecoveryCandidateUrl = null;
      _navigationRecoveryCandidateFailed = false;
    }
    final recoveryUrl = selectGakujoSessionRecoveryUrl(
      navigationCandidateUrl: navigationCandidateUrl,
      authenticatedUrl: _sessionRecoveryUrl,
      pendingRestoreUrl: _pendingLoginRestoreUrl,
      debugAllowed: _debugAllowed,
    );
    if (shouldResetGakujoLoginRestoreAttempt(
      authState: authState,
      urlLooksLikeLoginOrTimeout: urlLooksLikeLoginOrTimeout,
      hasRecoveryUrl: recoveryUrl != null,
    )) {
      _pendingLoginRestoreUrl = recoveryUrl;
      _loginRestoreAttempted = false;
    }
    _setStatus('ログインが切れた可能性があります: ${_displayUrl(url)}');
    if (!mounted ||
        recoveryUrl == null ||
        !AllowedWebOrigins.canLoad(recoveryUrl, debugAllowed: _debugAllowed)) {
      return;
    }
    if (_lastSessionRecoveryNoticeUrl == url) {
      return;
    }
    _lastSessionRecoveryNoticeUrl = url;
    final canAutoLogin = _appSettings.isFeatureEnabled(
          GakujoFeatureFlag.loginAutofill,
        ) &&
        _appSettings.hasLoginCredentials;
    _showSnackBar(
      canAutoLogin
          ? 'ログインが切れました。自動ログイン後に前のページへ戻ります'
          : 'ログインが切れました。再ログイン後に前のページへ戻ります',
    );
  }

  void _invalidateLoginUrl(String url) {
    if (AllowedWebOrigins.isLogoutPage(url)) _discardHistoryNavigation();
    _loginIdentity.invalidateLoginNavigation(url, () {
      unawaited(_setActiveLoginAccount(null, resync: false).catchError(
        (Object error, StackTrace stackTrace) {
          developer.log('Failed to clear active login account',
              name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
        },
      ));
    });
  }

  bool _looksLikeLoginOrTimeoutUrl(String url) {
    return AllowedWebOrigins.isLoginOrTimeoutPage(url);
  }

  Future<Map<String, Object?>> _backupPayload({bool includeStarredMessages = true}) => _backupOperations.run(
        () => readGakujoBackupPayload(
          currentSettings: () => _settingsForPersistence(_appSettings),
          settingsStore: _appSettingsStore,
          historyStore: _downloadHistoryStore,
          activityStore: _activityStore,
          includeStarredMessages: includeStarredMessages,
        ),
      );

  Future<void> _chooseDriveSaveFolder(BuildContext dialogContext) async {
    final email = _starSyncGoogleEmail;
    if (email == null || !_driveDownloadsEnabled ||
        !sameGoogleAccount(email, _starSyncGoogleAuth.currentEmail)) {
      return;
    }
    final currentId = _driveDownloadPreference.folderIdFor(email);
    final generation = _driveUploads.generation;
    var closed = false;
    final session = StarSyncGoogleAuthSession(_starSyncGoogleAuth, email: email);
    void checkCurrent() {
      session.checkCurrent();
      if (closed || !mounted || !_driveDownloadsEnabled ||
          !_driveUploads.isCurrent(generation)) {
        throw const StarSyncGoogleAuthException(StarSyncGoogleAuthErrorKind.notSignedIn);
      }
    }
    final saver = GoogleDriveFileSaver(
      account: email,
      accessToken: ({bool forceRefresh = false}) async {
        checkCurrent();
        final token = await session.accessToken(forceRefresh: forceRefresh);
        checkCurrent();
        return token;
      },
    );
    try {
      await showDialog<void>(
        context: dialogContext,
        builder: (_) => DriveSaveFolderDialog(
          currentId: currentId,
          load: () async {
            final folders = await saver.listFolders(currentId: currentId);
            checkCurrent();
            return folders;
          },
          pick: () => _driveSaveFolderPicker.pick(
            session: session,
            saver: saver,
            checkCurrent: checkCurrent,
          ),
          create: (name) async {
            final folder = await saver.createFolder(name);
            checkCurrent();
            return folder;
          },
          save: (id, commit) => _driveDownloadQueue.runExclusive(() async {
            checkCurrent();
            final folder = id == null ? null : await saver.getPrivateFolder(id);
            checkCurrent();
            await commit(() async {
              await _driveDownloadPreference.saveFolder(folder?.id, folder?.name, email);
              if (mounted) setState(() {});
            });
          }),
        ),
      );
    } finally {
      closed = true;
      _driveSaveFolderPicker.cancel(session);
      saver.close();
    }
  }

  Future<File> _driveDownloadsPreferenceFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(_joinLocalPath(directory.path, 'drive_downloads_enabled'));
  }

  void _cancelGoogleSignIn() {
    _googleCancelGeneration++;
    _starSyncGoogleAuth.cancelPendingSignIn();
  }

  Future<String> _signInGoogle({bool enablingDriveSaving = false}) {
    final cancelGeneration = _googleCancelGeneration;
    return _driveDownloadQueue.runExclusive(() async {
    if (cancelGeneration != _googleCancelGeneration) {
      throw const StarSyncGoogleAuthException(StarSyncGoogleAuthErrorKind.cancelled);
    }
    final config = _starSyncEngine.config;
    // Re-login must not lose the Drive permission that saving relies on.
    final email = await _starSyncGoogleAuth.signIn(
      optionalScopes: enablingDriveSaving || _driveDownloadPreference.enabled
          ? const [googleDriveFileScope]
          : const [],
      loginHint: config?.googleEmail,
    );
    if (config != null &&
        !sameGoogleAccount(config.googleEmail, email)) {
      try {
        await _starSyncGoogleAuth.signOut();
      } finally {
        _starSyncGoogleEmail = null;
        final expected = config.googleEmail;
        if (mounted) {
          _showSnackBar(expected == null
              ? 'この同期の設定には Google アカウントの情報がありません。同期を無効にしてから、もう一度設定してください'
              : 'この同期は $expected で設定されています。同じアカウントでログインするか、同期を無効にしてから設定し直してください');
        }
      }
      throw StateError('Google account does not match sync binding');
    }
    if (_driveDownloadPreference.enabled &&
        _driveDownloadPreference.boundGoogleEmail != email) {
      _driveDownloadsSuspended = true;
      _cancelDriveUploads();
      await _driveDownloadPreference.save(false, null);
      if (mounted) _showSnackBar('Google アカウントが変わったため、Google ドライブへの保存を停止しました。もう一度オンにしてください');
    } else if (!enablingDriveSaving && _driveDownloadPreference.enabled) {
      // Only a confirmed refusal turns saving off; a failed check must not undo the sign-in.
      var granted = true;
      try {
        granted = await _starSyncGoogleAuth.hasScope(googleDriveFileScope);
      } on Object catch (error) {
        if (Platform.isAndroid && error is StarSyncGoogleAuthException &&
            error.kind == StarSyncGoogleAuthErrorKind.notSignedIn &&
            _starSyncGoogleAuth.currentEmail == null) {
          rethrow;
        }
        developer.log('Failed to check the Drive permission: ${error.runtimeType}',
            name: 'MoreBetterGakujo');
      }
      if (!granted) {
        _driveDownloadsSuspended = true;
        _cancelDriveUploads();
        await _driveDownloadPreference.save(false, null);
        if (mounted) _showSnackBar('Google ドライブへの保存の権限がなくなったため、保存をオフにしました。必要ならもう一度オンにしてください');
      }
    }
    return email;
    });
  }

  Future<bool> _signOutGoogle({bool warn = true}) async {
    if (warn) {
      // The warning is a courtesy; it must never keep the sign-out from running.
      try {
        await _warnPendingDriveChecks();
      } on Object catch (error) {
        developer.log('Failed to check saved Drive files: ${error.runtimeType}',
            name: 'MoreBetterGakujo');
      }
    }
    _driveDownloadsSuspended = true;
    _cancelDriveUploads();
    try {
      await _driveDownloadQueue.runExclusive(_starSyncGoogleAuth.signOut);
      return true;
    } on Object catch (error) {
      developer.log('Failed to sign out of Google: ${error.runtimeType}',
          name: 'MoreBetterGakujo');
      if (mounted) _showSnackBar(googleRevocationUnconfirmedMessage);
      return false;
    }
  }

  void _cancelDriveUploads() {
    _driveUploads.cancel();
    _googleDriveFileSaver?.close();
    _googleDriveFileSaver = null;
    _driveSaverEmail = null;
  }

  Future<void> _loadDriveDownloadsPreference() async {
    if (!_secureStorageAccessAllowed) return;
    try {
      await _driveDownloadPreference.load(await _driveDownloadsPreferenceFile());
      await _restoreDriveDownloadsAccount();
    } on Object catch (error) {
      developer.log('Failed to load Drive download preference: ${error.runtimeType}',
          name: 'MoreBetterGakujo');
    }
  }

  Future<void> _restoreDriveDownloadsAccount() async {
    if (_driveDownloadPreference.enabled) {
      _starSyncGoogleEmail = await _driveDownloadQueue.run(
        () => _starSyncGoogleAuth.restore(
          expectedEmail: _driveDownloadPreference.boundGoogleEmail,
        ),
      );
    }
    if (_driveDownloadPreference.enabled &&
        _starSyncGoogleAuth.currentEmail != null &&
        _driveDownloadPreference.boundGoogleEmail != _starSyncGoogleAuth.currentEmail) {
      _driveDownloadsSuspended = true;
      _cancelDriveUploads();
      await _driveDownloadPreference.save(false, null);
      if (mounted) _showSnackBar('Google アカウントが変わったため、Google ドライブへの保存を停止しました。もう一度オンにしてください');
    }
    if (mounted) setState(() {});
  }

  /// The warning is a courtesy; it must never keep the switch from working.
  Future<void> _warnPendingDriveChecksBestEffort() async {
    try {
      await _warnPendingDriveChecks();
    } on Object catch (error) {
      developer.log('Failed to check saved Drive files: ${error.runtimeType}',
          name: 'MoreBetterGakujo');
    }
  }

  Future<void> _warnPendingDriveChecks() async {
    if (!_secureStorageAccessAllowed) return;
    if (await GoogleDriveFileSaver.pendingCheckCount() == 0 || !mounted) return;
    final check = await showPendingDriveCheckConfirmation(context);
    if (check == true) await _retryPendingDriveChecksAtStartup();
  }

  Future<void> _retryPendingDriveChecksAtStartup() async {
    if (!_secureStorageAccessAllowed) return;
    try {
      await _driveDownloadsLoad;
      await _driveDownloadQueue.run(() async {
        if (await GoogleDriveFileSaver.pendingCheckCount() == 0) return;
        final email = _starSyncGoogleAuth.currentEmail ??
            await _starSyncGoogleAuth.restore(
              expectedEmail: _driveDownloadPreference.boundGoogleEmail ??
                  _starSyncEngine.config?.googleEmail,
            );
        if (email == null ||
            !await _starSyncGoogleAuth.hasScope(googleDriveFileScope)) {
          return;
        }
        final saver = GoogleDriveFileSaver(
          account: email,
          accessToken: ({bool forceRefresh = false}) async {
            if (_starSyncGoogleAuth.currentEmail != email ||
                !await _starSyncGoogleAuth.hasScope(googleDriveFileScope)) {
              throw const GoogleDriveAccountChanged();
            }
            return googleDriveTokenForAccount(
              _starSyncGoogleAuth, email, forceRefresh: forceRefresh,
            );
          },
        );
        try {
          await saver.processPendingChecks();
        } finally {
          saver.close();
        }
      });
    } on Object catch (error) {
      developer.log('Failed to verify saved Drive files: ${error.runtimeType}',
          name: 'MoreBetterGakujo');
    }
    try {
      final count = await GoogleDriveFileSaver.pendingCheckCount();
      if (count > 0 && mounted) {
        _showSnackBar('Google ドライブで確認できていないファイルがあります（$count件）。Google ドライブの共有設定を確認してください');
      }
    } on Object catch (error) {
      developer.log('Failed to read pending Drive checks: ${error.runtimeType}',
          name: 'MoreBetterGakujo');
    }
  }

  Future<void> _setDriveDownloadsEnabled(bool enabled, {bool byStudentSwitch = false}) async {
    try {
      await _applyDriveDownloadsEnabled(enabled, byStudentSwitch: byStudentSwitch);
    } on Object catch (error) {
      // A refused or cancelled attempt must not keep what may be the wrong
      // account: with the switch off there would be no other way to change it.
      if (!(Platform.isAndroid && error is StarSyncGoogleAuthException &&
              error.kind == StarSyncGoogleAuthErrorKind.network) &&
          enabled && byStudentSwitch && !_driveDownloadPreference.enabled &&
          _starSyncEngine.config == null &&
          _starSyncGoogleAuth.currentEmail != null) {
        try {
          await _driveDownloadQueue.runExclusive(_starSyncGoogleAuth.signOut);
        } on Object catch (error) {
          developer.log('Failed to sign out of Google: ${error.runtimeType}',
              name: 'MoreBetterGakujo');
        }
        _starSyncGoogleEmail = null;
      }
      rethrow;
    }
  }

  Future<void> _applyDriveDownloadsEnabled(bool enabled, {required bool byStudentSwitch}) async {
    if (enabled && byStudentSwitch) {
      SecureStorageFactory.reopenLinuxKeyringGate();
    }
    final cancelGeneration = _googleCancelGeneration;
    void checkCancelled() {
      if (enabled && cancelGeneration != _googleCancelGeneration) {
        throw const StarSyncGoogleAuthException(StarSyncGoogleAuthErrorKind.cancelled);
      }
    }

    if (!enabled) {
      _driveDownloadsSuspended = true;
      _cancelDriveUploads();
      if (mounted) setState(() {});
    }
    final generation = _driveUploads.generation;
    await _driveDownloadsLoad;
    checkCancelled();
    return _driveDownloadQueue.runExclusive(() async {
      checkCancelled();
      if (enabled) {
        final account = _driveAccountHash;
        if (account == null) throw const StarSyncAccountRequiredException();
        if (_driveDownloadPreference.enabled &&
            _driveDownloadPreference.boundAccount != null &&
            _driveDownloadPreference.boundAccount != account) {
          if (mounted) _showSnackBar('ログインIDが変わったため、Google ドライブへの保存を見送りました');
          return;
        }
        // A revoked token clears the auth state; a cached email must not skip sign-in.
        if (_starSyncGoogleAuth.currentEmail == null) _starSyncGoogleEmail = null;
        _starSyncGoogleEmail ??= await _starSyncGoogleAuth.restore(
          expectedEmail: _starSyncEngine.config?.googleEmail ??
              _driveDownloadPreference.boundGoogleEmail,
        );
        checkCancelled();
        _starSyncGoogleEmail ??= await _signInGoogle(enablingDriveSaving: true);
        final currentEmail = _starSyncGoogleAuth.currentEmail;
        if (_driveDownloadPreference.enabled &&
            _driveDownloadPreference.boundGoogleEmail != currentEmail) {
          _driveDownloadsSuspended = true;
          _cancelDriveUploads();
          await _driveDownloadPreference.save(false, null);
          if (mounted) _showSnackBar('Google アカウントが変わったため、Google ドライブへの保存を停止しました。もう一度オンにしてください');
          if (mounted) setState(() {});
          return;
        }
        checkCancelled();
        await _starSyncGoogleAuth.requestScopes([googleDriveFileScope]);
        if (!await _starSyncGoogleAuth.hasScope(googleDriveFileScope)) {
          throw const StarSyncGoogleAuthException(StarSyncGoogleAuthErrorKind.permissionDenied);
        }
        // Stored scopes say nothing about a grant revoked elsewhere; refreshing does.
        await _starSyncGoogleAuth.accessToken(forceRefresh: true);
        if (!_driveUploads.isCurrent(generation) || _driveAccountHash != account) return;
        final email = _starSyncGoogleAuth.currentEmail;
        if (email == null || email != _starSyncGoogleEmail) return;
        checkCancelled();
        await _driveDownloadPreference.save(true, account, email);
        if (cancelGeneration != _googleCancelGeneration) {
          await _driveDownloadPreference.save(false, null);
          throw const StarSyncGoogleAuthException(StarSyncGoogleAuthErrorKind.cancelled);
        }
        if (_driveUploads.isCurrent(generation) && _driveAccountHash == account) {
          _driveDownloadsSuspended = false;
        }
      } else {
        await _driveDownloadPreference.save(false, null);
        // With no sync tied to this account, turning saving off is the way to
        // change it; staying signed in would bring the same account back.
        if (_starSyncEngine.config == null &&
            byStudentSwitch &&
            _starSyncGoogleAuth.currentEmail != null) {
          try {
            await _starSyncGoogleAuth.signOut();
          } on Object catch (error) {
            developer.log('Failed to sign out of Google: ${error.runtimeType}',
                name: 'MoreBetterGakujo');
            if (mounted) _showSnackBar(googleRevocationUnconfirmedMessage);
          }
          _starSyncGoogleEmail = null;
        }
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _uploadSyncBackup() async {
    await _ensureStarSyncLoaded();
    // Bind the snapshot to the account it is read under.
    final account = _starSyncEngine.requireAccount();
    final generation = _starSyncEngine.accountGeneration;
    try {
      await _starSyncEngine.uploadBackup(encodePortableSyncBackup(await _backupPayload(), disabledCollections: {
        for (final name in ['favorites', 'settings', 'notified-deadlines'])
          if (!_starSyncEngine.collectionEnabled(name)) name,
      }), expectedAccount: account, expectedGeneration: generation);
    } on GakujoBackupImportException catch (error) {
      _showSnackBar(error.message);
    }
  }

  Future<void> _uploadAutomaticSyncBackup() async {
    try {
      if (!_secureStorageAccessAllowed) return;
      await _ensureStarSyncLoaded();
      await _starSyncEngine.uploadAutomaticBackupIfDue(() async =>
          encodePortableSyncBackup(await _backupPayload(), disabledCollections: {
        for (final name in ['favorites', 'settings', 'notified-deadlines'])
          if (!_starSyncEngine.collectionEnabled(name)) name,
      }));
    } on GakujoBackupImportException catch (error) {
      _showSnackBar(error.message);
    } on Object catch (error) {
      developer.log('Failed to upload automatic backup: ${error.runtimeType}',
          name: 'MoreBetterGakujo');
    }
  }

  Future<void> _importSettingsFromFile() =>
      _importSettings(_restoreSettingsFromFile);

  Future<void> _importSettings(Future<void> Function() restore) async {
    // The settings dialog can be closed and reopened during a storage call.
    // Keep the import guard on the app, beyond the maintenance widget's life.
    if (_isImportingSettings) {
      _showSnackBar('設定の読み込みを処理しています');
      return;
    }
    _isImportingSettings = true;
    try {
      await restore();
    } finally {
      _isImportingSettings = false;
    }
  }

  Future<void> _restoreSettingsFromFile() async {
    final file = await pickGakujoBackupFile();
    if (file == null) {
      return;
    }
    if (await file.length() > maxGakujoBackupBytes) {
      _showSnackBar('バックアップファイルが大きすぎます');
      return;
    }
    // XFile.readAsString() ignores its encoding for picked files held in
    // memory (Android) and decodes bytes as Latin-1, garbling Japanese.
    final decoded = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    final text = decoded.startsWith('﻿') ? decoded.substring(1) : decoded;
    await _restoreSettingsFromText(
      text,
      emptyMessage: 'ファイルに設定JSONがありません',
    );
  }

  Future<bool> _applySyncedSettings(
    Map<String, Object?> entries, {
    required Map<String, Object?> basedOn,
    bool Function()? stillCurrent,
    StarSyncLocalCommit? commit,
  }) => applyGakujoSyncedSettings(
    operations: _settingsOperations,
    currentSettings: () => _appSettings,
    entries: entries, basedOn: basedOn,
    isMounted: () => mounted,
    stillCurrent: stillCurrent, commit: commit,
    restore: (backup, beforeWrite) => restoreGakujoBackup(
      backup: backup,
      beforeWrite: beforeWrite,
      settingsStore: _appSettingsStore,
      historyStore: _downloadHistoryStore,
      activityStore: _activityStore,
      isAllowedUrl: _isAllowedBackupUrl,
      isAllowedNavigationUrl: _isAllowedBackupNavigationUrl,
    ),
    publish: (next, flagsChanged) {
      void update() {
        if (flagsChanged) _startupPlaceholderFeatureFlags.clear();
        _appSettings = next;
      }
      if (mounted) {
        setState(update);
      } else {
        update();
      }
    },
    mirror: _syncLocalSettingsMirror,
    effects: [
      _applyChangedRuntimeFeatureFlags,
      (_, _) => _injectMessageFilterIfAllowed(),
      (_, _) async { unawaited(_syncReminders()); },
      (previous, next) async {
        // Identical syncs must not rotate useful local backups away.
        if (!portableSyncSettingsMatch(previous, exportStarSyncPortableSettings(next))) {
          _scheduleAutoBackup();
        }
      },
    ],
  );

  Future<bool> _canSyncReportDrafts() async => mounted &&
      AllowedWebOrigins.canLoad(await _controller.currentUrl(), debugAllowed: _debugAllowed);

  Future<bool> _clearSyncedDraftsBefore(DateTime cutoff) async {
    final revision = _navigationRevision;
    if (!await _canSyncReportDrafts()) return false;
    final result = await _controller.runJavaScriptReturningResult(
      GakujoReportDraftScript.buildClearSavedBefore(cutoff),
    );
    return revision == _navigationRevision && await _canSyncReportDrafts() &&
        _stringFromJavaScriptResult(result) == 'true';
  }

  Future<Map<String, Object?>?> _readSyncedReportDrafts() async {
    final revision = _navigationRevision;
    if (!await _canSyncReportDrafts()) return null;
    final result = await _controller.runJavaScriptReturningResult(
      GakujoReportDraftScript.buildExportAll(),
    );
    final decoded = jsonDecode(_stringFromJavaScriptResult(result));
    if (decoded is! Map) throw const FormatException('Invalid report drafts');
    if (revision != _navigationRevision) throw StateError('Draft page changed');
    _draftReadRevision = revision;
    return Map<String, Object?>.from(decoded);
  }

  Future<bool> _applySyncedReportDrafts(
    Map<String, Object?> drafts, {
    required Map<String, Object?> basedOn,
    bool Function()? stillCurrent,
  }) => applyGakujoSyncedReportDrafts(
    drafts: drafts, basedOn: basedOn,
    readRevision: _draftReadRevision,
    navigationRevision: () => _navigationRevision,
    canSync: _canSyncReportDrafts,
    evaluate: (script) async => _stringFromJavaScriptResult(
      await _controller.runJavaScriptReturningResult(script),
    ),
    stillCurrent: stillCurrent,
  );

  Future<void> _restoreSettingsFromText(
    String text, {
    required String emptyMessage,
    bool alreadyConfirmed = false,
    bool fromSyncStorage = false,
    void Function()? beforeWrite,
  }) async {
    if (text.trim().isEmpty) {
      _showSnackBar(emptyMessage);
      return;
    }

    final GakujoBackupImport backup;
    late Set<String> backupKeys;
    try {
      if (fromSyncStorage) {
        final decoded = jsonDecode(text);
        if (decoded is! Map) throw const FormatException('Invalid backup');
        final portable = portableSyncBackupPayload(Map<String, Object?>.from(decoded));
        // Download history holds device-specific file locations; a restore
        // from the sync storage keeps this device's history as it is. This
        // also keeps the re-encoded payload below the restore size limit.
        portable.remove('downloadHistory');
        portable.remove('failedDownloads');
        text = jsonEncode(portable);
      }
      backup = parseGakujoBackup(
        text,
        currentReminderOffsets:
            _appSettings.notificationPreferences.reminderOffsets,
      );
      final decodedBackup = jsonDecode(text);
      backupKeys = decodedBackup is Map
          ? decodedBackup.keys.whereType<String>().toSet()
          : <String>{};
    } on GakujoBackupImportException catch (error) {
      _showSnackBar(error.message);
      return;
    } on Object {
      _showSnackBar('設定JSONを読み取れませんでした');
      return;
    }

    if (!mounted) {
      return;
    }
    final confirmed = alreadyConfirmed ||
        await showGakujoBackupRestoreConfirmation(context) == true;
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _ensureStarSyncLoaded();
      final previousSettings = _appSettings;
      late GakujoAppSettings nextSettings;
      final restoredCollections = restoredSyncCollections(backup, backupKeys);
      await _starSyncEngine.withBulkReplace(() => _settingsOperations.runExclusive(() async {
        final restoreBackup = GakujoBackupImport(
          version: backup.version,
          downloadSaveMode: backup.downloadSaveMode,
          pageMode: backup.pageMode,
          setupCompleted: backup.setupCompleted,
          calendarImportSettings: backup.calendarImportSettings,
          messageExcludeKeywords: backup.messageExcludeKeywords,
          notificationTopics: backup.notificationTopics,
          messageNotification: restoredMessageNotification(backup, backupKeys),
          notificationPreferences: backup.notificationPreferences,
          disabledFeatureFlags: backup.disabledFeatureFlags,
          downloadHistory: backup.downloadHistory,
          failedDownloads: backup.failedDownloads,
          favorites: backup.favorites,
          starredMessages: fromSyncStorage && backup.starredMessages != null
              ? mergeSyncBackupStars(backup.starredMessages!, await _activityStore.loadStarredMessagesForBackup())
              : backup.starredMessages,
          deadlines: backup.deadlines,
          notifiedDeadlineKeys: backup.notifiedDeadlineKeys,
          reportLists: backup.reportLists,
        );
        nextSettings = await restoreGakujoSettingsLocally(
          operations: _settingsOperations,
          backup: restoreBackup,
          currentSettings: () => _appSettings,
          restore: () => restoreGakujoBackup(
            backup: restoreBackup,
            settingsStore: _appSettingsStore,
            historyStore: _downloadHistoryStore,
            activityStore: _activityStore,
            beforeWrite: beforeWrite,
            isAllowedUrl: _isAllowedBackupUrl,
            isAllowedNavigationUrl: _isAllowedBackupNavigationUrl,
          ),
          publish: (next, flagsRestored) {
            if (flagsRestored) _startupPlaceholderFeatureFlags.clear();
            _appSettings = next;
            if (mounted) setState(() {});
          },
          mirror: _syncLocalSettingsMirror,
        );
      }), stars: backup.starredMessages != null, collections: restoredCollections,
        starIdsAfterRestore: backup.starredMessages?.where((star) => star.isValid).map((star) => star.id).toSet(),
        collectionKeysAfterRestore: {
          if (backup.favorites != null) 'favorites': backup.favorites!.where((favorite) => _isAllowedBackupNavigationUrl(favorite.url)).map((favorite) => favorite.durableUrl).toSet(),
          if (restoredCollections['settings'] != null) 'settings': restoredCollections['settings']!,
        },
      );
      if (!mounted) return;
      await _applyChangedRuntimeFeatureFlags(
        previousSettings,
        nextSettings,
      );
      await _injectMessageFilterIfAllowed();
      await _refreshMessageStars();
      if (backup.starredMessages != null) _scheduleStarSync();
      // The imported notification choices decide which reminders to book.
      unawaited(_syncReminders());
      _scheduleAutoBackup();
      _showSnackBar('設定を読み込みました');
    } on BackupRollbackException {
      _showSnackBar('設定の復元に失敗し、一部の変更を元に戻せませんでした。保存先を確認してください');
    } on Object {
      _showSnackBar('設定の読み込みに失敗しました');
    }
  }

  bool _isAllowedBackupUrl(String url) {
    return AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed);
  }

  bool _isAllowedBackupNavigationUrl(String url) {
    return AllowedWebOrigins.canNavigate(url, debugAllowed: _debugAllowed);
  }

  void _handleLoginAutofillMessage(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map &&
          (decoded['event'] == 'submit' || decoded['event'] == '2fa-submit')) {
        // Autofill is starting this navigation on behalf of the pending open.
        _pendingMessageOpen?.navigation.record(null, _navigationRevision);
      }
      if (decoded is Map && decoded['event'] == 'submit') {
        // Autofill always submits the saved login ID; some of its fallbacks
        // (form.submit) fire no event the login observer could see.
        final account = starSyncAccountHash(
          _appSettings.savedLoginId,
        );
        if (account != null) _submitLoginAccount(account);
      }
      if (decoded is Map && decoded['event'] == 'challenge') {
        _authenticatedPageUrl = null;
        final source = Uri.tryParse(decoded['url'] is String ? decoded['url'] as String : '');
        final current = Uri.tryParse(_currentPageUrl ?? '');
        if (decoded['hasCredentials'] != true && source != null && current != null && source.hasAuthority && current.hasAuthority &&
            source.origin == current.origin &&
            source.path == current.path.replaceAll(RegExp(r';jsessionid=[^;/]*', caseSensitive: false), '') &&
            _protectedSecretPromptGate.claimLateLoad(_navigationRevision)) {
          unawaited(_injectLoginAutofillAssistIfAllowed(lateForm: true));
        }
        final recoveryUrl = selectGakujoSessionRecoveryUrl(
          navigationCandidateUrl: _navigationRecoveryCandidateUrl,
          authenticatedUrl: _sessionRecoveryUrl,
          pendingRestoreUrl: _pendingLoginRestoreUrl,
          debugAllowed: _debugAllowed,
        );
        if (recoveryUrl != null &&
            AllowedWebOrigins.canLoad(
              recoveryUrl,
              debugAllowed: _debugAllowed,
            )) {
          _pendingLoginRestoreUrl = recoveryUrl;
          _loginRestoreAttempted = false;
        }
      }
      if (decoded is Map && decoded['event'] is String) {
        final event = decoded['event'] as String;
        final hasCredentials = decoded['hasCredentials'] == true;
        final status = _protectedSecretPromptGate.paused &&
                (event == 'challenge' || event == 'ready-no-submit')
            ? '自動ログインを一時停止中です。アプリをバックグラウンドから戻すか、設定でログイン情報を保存すると再開します'
            : gakujoLoginAutofillStatus(event, hasCredentials);
        if (event == 'submit-blocked' ||
            (event == 'ready-no-submit' && hasCredentials)) {
          _loginAutofillStoppedNavigationRevision = _navigationRevision;
        }
        if (status != null &&
            !(event == 'challenge' && hasCredentials &&
                _loginAutofillStoppedNavigationRevision == _navigationRevision)) {
          _setStatus(status);
        }
      }
    } on FormatException {
      // Older injected scripts may still send a plain diagnostic message.
    }
    if (kDebugMode) {
      debugPrint('MoreBetterGakujo login autofill $message');
      developer.log(
        'Login autofill $message',
        name: 'MoreBetterGakujo',
      );
    }
  }

  Future<void> _openAkiko() async {
    if (!_externalServiceNoticeDismissed) {
      final result = await showExternalServiceNoticeDialog(context);
      if (result == null || !mounted) return;
      if (result.dontShowAgain) {
        await _setExternalServiceNoticeDismissed(true);
      }
    }
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(akikoServiceUrl),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      launched = false;
    }
    if (!launched) _showSnackBar('AKIKOを開けませんでした');
  }

  Future<void> _setExternalServiceNoticeDismissed(bool dismissed) async {
    if (mounted) {
      setState(() => _externalServiceNoticeDismissed = dismissed);
    }
    try {
      await _localPrefsStore.saveExternalServiceNoticeDismissed(dismissed);
    } on Object catch (error, stackTrace) {
      // The choice still applies for this run; opening must not be blocked.
      developer.log(
        'Failed to save external service notice preference',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _restoreSavedGpa() async {
    try {
      final prefs = await _localPrefsStore.load();
      final lastGpa = prefs?.lastGpa;
      if (!mounted) return;
      setState(() {
        if (_reportedGpa == null && lastGpa != null) _reportedGpa = lastGpa;
        if (prefs?.externalServiceNoticeDismissed ?? false) {
          _externalServiceNoticeDismissed = true;
        }
      });
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to restore saved GPA',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _handleGpaReportMessage(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return;
      }
      final gpa = decoded['gpa'];
      if (gpa is! num || !gpa.isFinite || gpa < 0 || gpa > 5) {
        return;
      }
      if (mounted && _reportedGpa != gpa.toDouble()) {
        setState(() {
          _reportedGpa = gpa.toDouble();
        });
        unawaited(_localPrefsStore.saveLastGpa(gpa.toDouble()).catchError(
          (Object error, StackTrace stackTrace) {
            developer.log(
              'Failed to save last GPA',
              name: 'MoreBetterGakujo',
              error: error,
              stackTrace: stackTrace,
            );
          },
        ));
      }
    } on FormatException {
      return;
    }
  }

  Future<void> _injectExpiredPageRecoveryIfAllowed() async {
    if (!_canRunPageScripts) {
      return;
    }

    try {
      await _controller.runJavaScript(GakujoExpiredPageRecoveryScript.build());
    } catch (error, stackTrace) {
      developer.log(
        'Failed to inject expired page recovery script',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _injectLoginAndTimeoutHooksIfAllowed() async {
    if (!_canRunPageScripts) {
      return;
    }

    try {
      await _controller.runJavaScript(
        GakujoTimeoutPopupScript.buildWithLoginObserver(),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to install login observer and timeout popup handler',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _injectGpaDisplayIfAllowed() async {
    if (!_canRunPageScripts) {
      return;
    }

    try {
      await _controller.runJavaScript(
        gakujoPageScriptBuilders(_appSettings)['gpa']!(),
      );
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

    try {
      await _controller.runJavaScript(
        GakujoUploadPreviewScript.build(compactAndroid: Platform.isAndroid),
      );
      await _controller.runJavaScript(
        gakujoHistoryMarkerJs({'action': 'install-preview-tracker'}),
      );
    } catch (error, stackTrace) {
      developer.log('Failed to inject upload preview',
          name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
    }

    unawaited(_injectMessageStars());
    final builders = gakujoPageScriptBuilders(_appSettings);
    for (final builder in [
      builders['report']!,
      builders['reader']!,
    ]) {
      try {
        await _controller.runJavaScript(builder());
      } catch (error, stackTrace) {
        developer.log('Failed to inject page feature',
            name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      }
    }

    for (final flag in _originalExtensionFeatureBuilders.keys) {
      if (!_appSettings.isFeatureEnabled(flag)) {
        continue;
      }
      await _applyFeatureFlagRuntimeState(flag, enabled: true);
    }
  }

  Future<void> _applyFeatureFlagRuntimeState(
    GakujoFeatureFlag flag, {
    required bool enabled,
  }) async {
    final controller = _controller;
    if (flag == GakujoFeatureFlag.downloadCapture &&
        controller is WindowsGakujoWebViewController) {
      await controller.setDownloadInterceptionEnabled(enabled);
    }
    if (!_canRunPageScripts) {
      return;
    }

    if (enabled && flag == GakujoFeatureFlag.loginAutofill) {
      await _injectLoginAutofillAssistIfAllowed();
      return;
    }
    if (enabled && flag == GakujoFeatureFlag.twoFactorAutofill) {
      await _injectTwoFactorAutofillIfAllowed();
      return;
    }
    if (flag == GakujoFeatureFlag.deadlineNotifications) {
      await _injectMessageFilterIfAllowed();
      return;
    }
    final _PageScriptBuilder? builder;
    if (flag == GakujoFeatureFlag.downloadCapture) {
      builder = enabled
          ? GakujoDownloadCaptureScript.build
          : GakujoDownloadCaptureScript.buildTeardown;
    } else {
      builder = enabled
          ? _originalExtensionFeatureBuilders[flag]
          : _originalExtensionFeatureTeardownBuilders[flag];
    }
    if (builder == null) {
      return;
    }

    try {
      await _controller.runJavaScript(builder());
    } catch (error, stackTrace) {
      developer.log(
        'Failed to ${enabled ? 'inject' : 'tear down'} '
        '${flag.storageValue} script',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _applyChangedRuntimeFeatureFlags(
    GakujoAppSettings previousSettings,
    GakujoAppSettings nextSettings,
  ) async {
    for (final flag in GakujoFeatureFlag.values) {
      final wasEnabled = previousSettings.isFeatureEnabled(flag);
      final isEnabled = nextSettings.isFeatureEnabled(flag);
      if (wasEnabled != isEnabled) {
        await _applyFeatureFlagRuntimeState(
          flag,
          enabled: isEnabled,
        );
      }
    }
  }

  Future<void> _injectMessageFilterIfAllowed() async {
    if (!_canRunPageScripts) {
      return;
    }

    final messages = _appSettings.messageNotification;
    final keywordNotificationsEnabled =
        messages.mode == GakujoMessageNotificationMode.keywords &&
        _appSettings.isFeatureEnabled(GakujoFeatureFlag.deadlineNotifications);
    try {
      await _controller.runJavaScript(
        GakujoMessageFilterScript.build(
          keywords: _appSettings.messageExcludeKeywords,
          notificationKeywords:
              keywordNotificationsEnabled ? messages.keywords : const [],
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
      await _ensureStarSyncLoaded();
      if (!await _starSyncEngine.prepareLocalDrafts()) return;
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

  void _handleProtectedSecretReadError(Object error, StackTrace stackTrace, int revision) {
    if (isAuthenticationCancellation(error)) {
      _protectedSecretPromptGate.cancel();
      if (mounted && revision == _navigationRevision) {
        _setStatus('自動ログインを一時停止中です。アプリをバックグラウンドから戻すか、設定でログイン情報を保存すると再開します');
      }
      return;
    }
    if (_protectedSecretPromptGate.reportReadError()) {
      developer.log('Failed to read protected secrets', name: 'MoreBetterGakujo',
          error: error.runtimeType, stackTrace: stackTrace);
      if (mounted) _showSnackBar('保存したログイン情報を読み出せません。設定の「ログイン」でもう一度保存してください');
    }
  }

  Future<bool> _hasProtectedSecretForm(String script) async {
    try {
      final result = await _controller.runJavaScriptReturningResult(script);
      return _boolFromJavaScriptResult(result);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to probe protected secret form',
        name: 'MoreBetterGakujo',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _injectLoginAutofillAssistIfAllowed({bool lateForm = false}) async {
    final url = _currentPageUrl;
    final navigationRevision = _navigationRevision;
    bool stillCurrent() =>
        !_deferLoginAutofillDuringSetup &&
        url != null &&
        _isCurrentPageCallback(url, navigationRevision) &&
        AllowedWebOrigins.canAutofill(_currentPageUrl, debugAllowed: false);
    if (!stillCurrent()) {
      return;
    }
    await _loadStoredLoginForAutofillIfNeeded();
    if (!stillCurrent() ||
        !_appSettings.isFeatureEnabled(GakujoFeatureFlag.loginAutofill)) {
      return;
    }

    // campussmart.do can reveal the login form dynamically, so the injected
    // script positively identifies the login DOM before filling or submitting.
    try {
      final protectionEnabled =
          (await _appSettingsStore.protectionState.read()).enabled;
      if (!stillCurrent()) return;
      var hasForm = true;
      if (protectionEnabled) {
        hasForm = await _hasProtectedSecretForm(ProtectedSecretPageProbe.login());
        if (!stillCurrent()) return;
        if (!hasForm) {
          if (lateForm) return;
          _protectedSecretPromptGate.waitingForForm(navigationRevision);
        }
      }
      if (protectionEnabled && hasForm && !lateForm &&
          !_protectedSecretPromptGate.paused &&
          !_protectedSecretPromptGate.claimInitialLoad(navigationRevision)) {
        return;
      }
      GakujoLoginCredentials? credentials;
      if (hasForm && !(protectionEnabled && _protectedSecretPromptGate.paused)) {
        try {
          credentials = await _appSettingsStore.loadLoginCredentials();
        } on Object catch (error, stackTrace) {
          if (protectionEnabled) {
            _handleProtectedSecretReadError(error, stackTrace, navigationRevision);
            return;
          }
          rethrow;
        }
      }
      if (!stillCurrent() ||
          !_appSettings.isFeatureEnabled(GakujoFeatureFlag.loginAutofill)) {
        return;
      }
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
      final script = LoginAutofillAssistScript.build(
        credentials: credentials == null || !credentials.isComplete
            ? null
            : GakujoLoginAutofillCredentials(
                loginId: credentials.loginId,
                password: credentials.password,
              ),
        debugLogging: kDebugMode,
      );
      if (!stillCurrent()) {
        return;
      }
      await _controller.runJavaScript(script);
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
    final startupSettings = _appSettings;
    if (!await _loadAppSettings(allowMacosKeychainPrompt: true) || !mounted) {
      return;
    }
    // Page scripts after this one ran from the startup mirror meanwhile; bring
    // them in line with the keychain settings. The caller injects autofill.
    await _applyChangedRuntimeFeatureFlags(
      startupSettings.copyWith(disabledFeatureFlags: {
        ...startupSettings.disabledFeatureFlags.difference({
          GakujoFeatureFlag.loginAutofill,
          GakujoFeatureFlag.twoFactorAutofill,
        }),
        ..._appSettings.disabledFeatureFlags.intersection({
          GakujoFeatureFlag.loginAutofill,
          GakujoFeatureFlag.twoFactorAutofill,
        }),
      }),
      _appSettings,
    );
  }

  Future<void> _injectTwoFactorAutofillIfAllowed() async {
    if (!_appSettings.isFeatureEnabled(GakujoFeatureFlag.twoFactorAutofill)) {
      return;
    }
    final url = _currentPageUrl;
    final navigationRevision = _navigationRevision;
    if (kDebugMode &&
        Platform.isAndroid &&
        url != null &&
        url == 'file:///android_asset/qa/two_factor.html' &&
        _isCurrentPageCallback(url, navigationRevision)) {
      try {
        await _controller.runJavaScript(TwoFactorAutofillScript.buildDebugFixture());
      } on Object catch (error, stackTrace) {
        developer.log('Failed to inject local 2FA fixture',
            name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      }
      return;
    }
    bool stillCurrent() =>
        url != null &&
        _isCurrentPageCallback(url, navigationRevision) &&
        AllowedWebOrigins.canAutofill(_currentPageUrl, debugAllowed: false);
    if (!stillCurrent() || _protectedSecretPromptGate.paused) {
      return;
    }

    try {
      final protectionEnabled =
          (await _appSettingsStore.protectionState.read()).enabled;
      if (!stillCurrent()) return;
      if (protectionEnabled) {
        final hasForm = await _hasProtectedSecretForm(
          ProtectedSecretPageProbe.twoFactor(),
        );
        if (!stillCurrent() || !hasForm || _protectedSecretPromptGate.paused) return;
      }
      String? secret;
      try {
        secret = await _secretStore.load();
      } on Object catch (error, stackTrace) {
        if (protectionEnabled) {
          _handleProtectedSecretReadError(error, stackTrace, navigationRevision);
          return;
        }
        rethrow;
      }
      if (!stillCurrent() ||
          !_appSettings.isFeatureEnabled(GakujoFeatureFlag.twoFactorAutofill) ||
          secret == null) {
        return;
      }

      final token = _totpGenerator.currentToken(secret);
      final script = TwoFactorAutofillScript.build(
        token: token,
        secret: secret,
        debugLogging: kDebugMode,
      );
      if (!stillCurrent()) {
        return;
      }
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

  Future<bool> _acceptDeadlineNotification(String url) async {
    final targetUrl = _notificationService.targetUrl(
      url,
      debugAllowed: _debugAllowed,
    );
    if (targetUrl == null) return true; // A policy rejection is terminal.
    if (!await _notificationNavigationReady || !_notificationConsumer.isCurrent) {
      return false;
    }
    await _handleDeadlineNotificationTapped(targetUrl);
    return true;
  }

  Future<void> _loadInitialPage() async {
    await _webViewReady;
    if (!_notificationConsumer.isCurrent) return;
    await _webViewService.configureController(
      _controller,
      debugAllowed: _debugAllowed,
      // Keep native downloads until the saved feature choice has loaded.
      downloadInterceptionEnabled: false,
    );
    unawaited(_saveInitialTwoFactorSecretIfAllowed());
    final appSettingsLoaded = await _loadAppSettings();
    await _applyFeatureFlagRuntimeState(
      GakujoFeatureFlag.downloadCapture,
      enabled: _appSettings.isFeatureEnabled(GakujoFeatureFlag.downloadCapture),
    );
    if (appSettingsLoaded && !_appSettings.setupCompleted && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_showInitialSetupWizard());
        }
      });
    }
    final savedUrl = appSettingsLoaded ? await _loadInitialLastPageUrl() : null;
    await _notificationConsumer.dispatchStartup((pendingNotificationUrl) async {
      // Preserve the requested page even when login will be completed manually.
      // In particular, macOS can intentionally start from its non-secret mirror
      // without loading credentials from Keychain.
      final owner = pendingNotificationUrl == null ? null : Object();
      _loginRestore.reserve(
        gakujoInitialPendingRestoreUrl(
          pendingNotificationUrl: pendingNotificationUrl,
          savedUrl: savedUrl,
        ),
        owner: owner,
      );
      _setPendingMessageUrl(pendingNotificationUrl, owner: owner);
      final startUrl =
          pendingNotificationUrl != null && !_appSettings.hasLoginCredentials
          ? pendingNotificationUrl
          : _resolveStartUrl(
              _appSettings.hasLoginCredentials ? null : savedUrl,
            );
      await _loadReservedPage(startUrl, owner);
    }, debugAllowed: _debugAllowed);
  }

  Future<void> _loadReservedPage(String url, Object? owner) async {
    final message = _pendingMessageOpen;
    try {
      _beginPendingMessageNavigation(url);
      await _controller.loadUrl(url);
    } catch (_) {
      // Native retains a rejected notification for the next consumer. Its
      // former widget must release only reservations still held by this load.
      if (owner != null) {
        _loginRestore.release(owner);
        if (_navigationRecovery.release(owner)) {
          _navigationRecoveryCandidateFailed = false;
        }
        if (message != null && identical(message, _pendingMessageOpen)) {
          _pendingMessageOpenTimer?.cancel();
          _pendingMessageOpen = null;
        }
      }
      rethrow;
    }
  }

  Future<void> _handleDeadlineNotificationTapped(
    String targetUrl, {
    String? historyAccount,
  }) async {
    if (_calendarOperationGate.isRunning) {
      // Do not publish this as the auth restore target yet. An authenticated
      // callback from the in-flight calendar navigation would consume it and
      // interrupt extraction before the operation releases the WebView.
      _setPendingMessageUrl(null);
      _deferredNavigationAfterPageOperationUrl = null;
      _deferredNotificationAfterPageOperationUrl = targetUrl;
      _showSnackBar('処理完了後に通知のページを開きます');
      return;
    }
    final owner = Object();
    _setPendingMessageUrl(targetUrl, owner: owner);
    _reserveNotificationRestore(targetUrl, owner: owner);
    if (historyAccount != null) {
      _historyNavigation = (account: historyAccount, owner: owner, message: _pendingMessageOpen);
    }
    await _loadReservedPage(targetUrl, owner);
  }

  String? _reserveNotificationRestore(String targetUrl, {Object? owner}) {
    final restoreTarget = gakujoNotificationRestoreTarget(
      targetUrl,
      debugAllowed: _debugAllowed,
    );
    if (restoreTarget != null) {
      // A notification can be tapped while a login shell is already visible.
      // Preserve its destination explicitly because onPageStarted cannot infer
      // the protected request from an unauthenticated current page.
      _loginRestore.reserve(restoreTarget, owner: owner);
      _loginRestoreAttempted = false;
      _navigationRecovery.reserve(restoreTarget, owner: owner);
      _navigationRecoveryCandidateFailed = false;
    }
    return restoreTarget;
  }

  Future<String?> _loadInitialLastPageUrl() async {
    if (Platform.isMacOS && !_secureStorageAccessAllowed) {
      // Navigation URLs may contain session data and are never mirrored in
      // plaintext. Start at the home page until secure storage is available.
      return null;
    }

    return _lastPageStore.load(debugAllowed: _debugAllowed);
  }

  Future<void> _addGakujoJavaScriptChannel(
    String name, {
    required FutureOr<void> Function(String) onMessageReceived,
  }) {
    return _controller.addJavaScriptChannel(
      name,
      onMessageReceived: (message) => handleGakujoJavaScriptMessage(
        currentUrl: _currentPageUrl,
        lastAllowedUrl: _lastAllowedPageUrl,
        channelName: name,
        message: message,
        onMessageReceived: onMessageReceived,
      ),
    );
  }

  Future<void> _configureWebViewController() async {
    await _controller.setJavaScriptModeUnrestricted();
    await _addGakujoJavaScriptChannel(
      GakujoDownloadCaptureScript.channelName,
      onMessageReceived: _handleDownloadMessage,
    );
    await _addGakujoJavaScriptChannel(
      LoginAutofillAssistScript.channelName,
      onMessageReceived: _handleLoginAutofillMessage,
    );
    await _addGakujoJavaScriptChannel(
      GakujoUploadCompressionLibraries.channelName,
      onMessageReceived: _handleUploadCompressionLibraryRequest,
    );
    await _addGakujoJavaScriptChannel(
      GakujoMessageStarScript.channelName,
      onMessageReceived: _handleMessageStarMessage,
    );
    await _addGakujoJavaScriptChannel(
      GakujoGpaDisplayScript.channelName,
      onMessageReceived: _handleGpaReportMessage,
    );
    await _addGakujoJavaScriptChannel(
      DesktopPageZoomScript.channelName,
      onMessageReceived: _handleDesktopZoomMessage,
    );
    await _addGakujoJavaScriptChannel(
      'MbgPreviewNavigation',
      onMessageReceived: _handlePreviewNavigationState,
    );
    await _addGakujoJavaScriptChannel(
      'MbgRegistrationChoice',
      onMessageReceived: _registrationChoice,
    );
    await _controller.setNavigationDelegate(
      GakujoNavigationDelegate(
        onNavigationRequest: _handleNavigationRequest,
        // Windows SourceChanged only sees the final URL of an HTTP redirect.
        onNavigationStarting: (url) {
          _cancelOfflineRetry();
          _plannerNavigationStarts++;
          _invalidateLoginUrl(url);
          if (!_isRegistrationServlet(url)) _finishRegistration('履修登録画面を離れたため終了しました。');
          _captureNavigationRecoveryCandidate(url);
        },
        onDownloadStarting: _handleNativeDownload,
        onDocumentStarted: _beginCourseDocument,
        onPageStarted: (url) {
          _closeLinuxFind();
          if (!_isRegistrationServlet(url)) _finishRegistration('履修登録画面を離れたため終了しました。');
          // Only a page that starts loading counts: blocked requests do not.
          _mainFrameNavigationStarts += 1;
          _invalidateLoginUrl(url);
          if (_isInternalBlankUrl(url)) {
            _beginNavigation();
            _pendingPageFinishedNavigationRevision = _navigationRevision;
            _currentPageUrl = url;
            return;
          }
          _captureNavigationRecoveryCandidate(url);
          final preservesPendingMessageOpen = _pendingMessageOpen?.navigation
                  .consume(url, _navigationRevision) ??
              false;
          _beginNavigation(
            preservesPendingMessageOpen: preservesPendingMessageOpen ||
                _keepsHistoryMessageDuringLogin(url),
            pageStarted: true,
          );
          _pendingPageFinishedNavigationRevision = _navigationRevision;
          _currentPageUrl = url;
          if (AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
            _lastAllowedPageUrl = url;
          }
          unawaited(_refreshNavigationState(revision: _navigationRevision));
          _setStatus('読み込み中: ${_displayUrl(url)}');
        },
        onPageFinished: (url) async {
          final navigationRevision = _navigationRevision;
          final courseDocument = _courseDocument;
          bool stillCurrent() =>
              _isCurrentPageCallback(url, navigationRevision);
          if (!mounted) return;
          final deferred = _deferredPageNavigation;
          if (deferred != null &&
              _pendingPageFinishedNavigationRevision != navigationRevision) {
            // A previous page can finish before the next deferred page starts.
            // WebView2 can also finish the issued URL without a SourceChanged
            // event when it is already displayed.
            final finishedIssuedPage = deferred.revision == navigationRevision &&
                deferred.url == url && stillCurrent();
            if (!finishedIssuedPage) return;
          }
          if (_currentPageUrl != url &&
              _pendingPageFinishedNavigationRevision == navigationRevision) {
            // WebKit may finish at a server redirect without another start.
            // Confirm the committed URL so a superseded finish cannot adopt it.
            final String? webViewUrl;
            try {
              webViewUrl = await _controller.currentUrl();
            } on Object catch (error, stackTrace) {
              developer.log(
                'Failed to confirm redirected page URL',
                name: 'MoreBetterGakujo',
                error: error,
                stackTrace: stackTrace,
              );
              return;
            }
            if (!mounted ||
                !shouldAdoptGakujoPageFinishedUrl(
                  url: url,
                  currentUrl: _currentPageUrl,
                  webViewUrl: webViewUrl,
                  navigationRevision: navigationRevision,
                  currentNavigationRevision: _navigationRevision,
                  pendingNavigationRevision:
                      _pendingPageFinishedNavigationRevision,
                )) {
              return;
            }
            final requestedUrl = _currentPageUrl!;
            // Preserve the protected request even before any authenticated page.
            if (_navigationRecoveryCandidateUrl == null &&
                isGakujoNavigationRecoveryCandidateUrl(requestedUrl,
                    debugAllowed: _debugAllowed)) {
              _navigationRecoveryCandidateUrl = requestedUrl;
              _navigationRecoveryCandidateFailed = false;
            }
            _currentPageUrl = url;
            _mainFrameNavigationUrl = url;
          }
          if (stillCurrent()) {
            _pendingPageFinishedNavigationRevision = null;
          }
          GakujoPortalAuthState? finishedAuthState;
          var finishedNormally = false;
          final processing = Completer<void>();
          _pageFinishedProcessing = (url: url, completer: processing);
          try {
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
            if (!stillCurrent()) {
              return;
            }
            if (AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
              _cancelOfflineRetry();
              _offlineAutoReloads = 0;
              _lastAllowedPageUrl = url;
            }
            final identityAllowed = AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed);
            final loginUrl = _looksLikeLoginOrTimeoutUrl(url);
            if (loginUrl) _invalidateLoginUrl(url);
            final identityRevision = _loginIdentity.revision;
            _setStatus('表示中: ${_displayUrl(url)}');
            final authState = await _readPortalAuthState(stillValid: stillCurrent);
            finishedAuthState = authState;
            if (!stillCurrent()) {
              return;
            }
            final isAuthenticationChallenge = isGakujoAuthenticationChallenge(
              authState: authState,
              urlLooksLikeLoginOrTimeout: _looksLikeLoginOrTimeoutUrl(url),
            );
            await _handlePortalAuthState(
              url,
              authState: authState,
              identityAllowed: identityAllowed,
              identityRevision: identityRevision,
              stillCurrent: stillCurrent,
            );
            if (!stillCurrent()) return;
            unawaited(_refreshRegistrationAvailability());
            await _injectExpiredPageRecoveryIfAllowed();
            if (!stillCurrent()) {
              return;
            }
            // Intercept timeout popups before autofill can submit the form.
            await _injectLoginAndTimeoutHooksIfAllowed();
            if (!stillCurrent()) return;
            // Both read the keychain, which can wait on a macOS access dialog
            // indefinitely; do not hold back download capture and the rest.
            unawaited(() async {
              if (authState == GakujoPortalAuthState.twoFactor &&
                  _secureStorageAccessAllowed) {
                await _injectTwoFactorAutofillIfAllowed();
                if (stillCurrent()) await _injectLoginAutofillAssistIfAllowed();
              } else {
                await _injectLoginAutofillAssistIfAllowed();
                if (stillCurrent()) await _injectTwoFactorAutofillIfAllowed();
              }
            }());
            await _refreshNavigationState(revision: navigationRevision);
            if (!stillCurrent()) return;
            await _injectDownloadCaptureIfAllowed();
            if (!stillCurrent()) {
              return;
            }
            await _injectGpaDisplayIfAllowed();
            if (!stillCurrent()) {
              return;
            }
            await _injectOriginalExtensionFeaturesIfAllowed();
            if (!stillCurrent()) {
              return;
            }
            await _injectMessageFilterIfAllowed();
            if (!stillCurrent()) {
              return;
            }
            await _injectReportDraftIfAllowed();
            if (!stillCurrent()) {
              return;
            }
            if (AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
              // The resume trigger keeps the 2-minute and daily throttles;
              // draft syncs are scheduled only by real draft writes.
              _collectionSyncScheduler.pageLoaded();
            }
            await _applyDesktopZoomIfAllowed();
            if (!stillCurrent()) {
              return;
            }
            await _refreshEstimatedCourseName(courseDocument);
            if (!stillCurrent()) {
              return;
            }
            if (!isAuthenticationChallenge) {
              await _scanCurrentPageActivity(url);
              if (!stillCurrent()) {
                return;
              }
            }
            await _restoreLastPageAfterLoginIfNeeded(
              url,
              authState: authState,
              navigationRevision: navigationRevision,
            );
            if (!stillCurrent()) {
              return;
            }
            _messageOpenReadyNavigationRevision = navigationRevision;
            if (await _openPendingMessageIfNeeded(
              url,
              navigationRevision: navigationRevision,
            )) {
              return;
            }
            if (_canRunPageScripts && stillCurrent()) {
              await _finishHistoryMarkers(url, navigationRevision);
              if (!stillCurrent()) return;
            }
            // After the restore, so returning to the last page after login
            // does not wait for the fetch.
            if (!isAuthenticationChallenge && stillCurrent()) {
              unawaited(_refreshAssignmentsInBackground());
            }
            finishedNormally = true;
          } finally {
            if (!processing.isCompleted) {
              processing.complete();
            }
            if (finishedNormally && finishedAuthState == GakujoPortalAuthState.unknown) {
              _retryUnresolvedPortalAuthState(url, navigationRevision);
            }
          }
        },
        onWebResourceError: (error) {
          if (!mounted) {
            return;
          }
          // A login request that could not load proves nothing; a later page
          // must not promote its candidate. Aborted loads are left to the
          // timers: a redirect replacing the login POST also aborts it.
          if (error.isForMainFrame && error.isConnectivityError) {
            _dropPendingLogin();
          }
          _navigationRecoveryCandidateFailed =
              gakujoNavigationRecoveryCandidateAfterError(
            error,
            navigationCandidateUrl: _navigationRecoveryCandidateUrl,
            navigationUrl: _mainFrameNavigationUrl,
            navigationCandidateFailed: _navigationRecoveryCandidateFailed,
          );
          handleGakujoWebResourceError(
            error,
            offlineAutoReloads: _offlineAutoReloads,
            setStatus: _setStatus,
            startOfflineRetry: _requestOfflineRetry,
          );
        },
      ),
    );
  }

  Future<bool> _loadAppSettings({
    bool allowMacosKeychainPrompt = false,
    bool? automaticRecovery,
  }) {
    Future<bool> read() => _readAppSettings(
      allowMacosKeychainPrompt: allowMacosKeychainPrompt,
      automaticRecovery: automaticRecovery ?? !allowMacosKeychainPrompt,
    );
    // WebView recovery must retain the settings and choices from this run.
    return defaultTargetPlatform == TargetPlatform.linux &&
            !allowMacosKeychainPrompt
        ? _startupFlow.loadSettings(read)
        : read();
  }

  Future<bool> _readAppSettings({
    required bool allowMacosKeychainPrompt,
    required bool automaticRecovery,
  }) async {
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
        _startupPlaceholderFeatureFlags
          ..clear()
          ..addAll(_appSettings.disabledFeatureFlags.difference(
            localPrefs?.appSettings?.disabledFeatureFlags ?? const {},
          ));
        _appSettingsLoaded = true;
      });
      return true;
    }

    final settingsLoad = _appSettingsStore.load();
    try {
      final secureSettings = allowMacosKeychainPrompt
          ? await settingsLoad
          : await settingsLoad.timeout(const Duration(seconds: 3));
      var settings = secureSettings;
      if (Platform.isMacOS) {
        GakujoLocalPrefs? localPrefs;
        try {
          localPrefs = await _localPrefsStore.load();
        } on Object catch (error, stackTrace) {
          developer.log(
            'Failed to merge local macOS app settings',
            name: 'MoreBetterGakujo',
            error: error,
            stackTrace: stackTrace,
          );
        }
        settings = mergeMacosLocalMessageFiltersWithSecureSettings(
          secureSettings: secureSettings,
          localPrefs: localPrefs,
        );
        if (!listEquals(
          secureSettings.messageExcludeKeywords,
          settings.messageExcludeKeywords,
        )) {
          try {
            await _appSettingsStore.saveMessageExcludeKeywords(
              settings.messageExcludeKeywords,
            );
          } on Object catch (error, stackTrace) {
            developer.log(
              'Failed to reconcile local macOS message filters',
              name: 'MoreBetterGakujo',
              error: error,
              stackTrace: stackTrace,
            );
          }
        }
      }
      if (!mounted) {
        return true;
      }

      await _loadActiveLoginAccount();
      _secureStorageAccessAllowed = true;
      if (Platform.isMacOS) {
        _driveDownloadsLoad = _loadDriveDownloadsPreference();
      }
      setState(() {
        _startupPlaceholderFeatureFlags.clear();
        _appSettings = settings;
        _appSettingsLoaded = true;
      });
      unawaited(_syncStarsInBackground());
      unawaited(_retryPendingDriveChecksAtStartup());
      await _syncLocalSettingsMirror(settings);
      await _loadDownloadRoot();
      unawaited(_compactStoredData());
      _scheduleAutoBackup();
      // The macOS startup mirror must not read the secure activity store.
      unawaited(_syncReminders());
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

      _loginAutofillStorageLoadAttempted =
          gakujoLoginStorageLoadAttemptedAfterFailure(
        attempted: _loginAutofillStorageLoadAttempted,
        error: error,
      );
      final fallbackSettings = gakujoSettingsAfterStorageLoadFailure(
        currentSettings: _appSettings,
        isMacOS: Platform.isMacOS,
        error: error,
      );
      if (Platform.isLinux) {
        _secureStorageAccessAllowed = false;
      }
      setState(() {
        _appSettings = fallbackSettings;
        if (!Platform.isMacOS) {
          _startupPlaceholderFeatureFlags
            ..clear()
            ..addAll(fallbackSettings.disabledFeatureFlags);
        }
        _appSettingsLoaded = true;
      });
      _setStatus('保存データにアクセスできません');
      // On macOS a timeout here usually means the keychain dialog went
      // unanswered; nothing reloads once it is answered, so offer a retry.
      if (error is! TimeoutException ||
          (Platform.isMacOS && allowMacosKeychainPrompt)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_showSecureStorageRecoveryDialog(
              error,
              automatic: automaticRecovery,
            ));
          }
        });
      }
      // A Linux keyring unlock prompt outlasts the timeout; once it is
      // answered, load for real or offer the retry.
      if (Platform.isLinux &&
          error is TimeoutException &&
          !allowMacosKeychainPrompt) {
        unawaited(settingsLoad.then(
          (_) {
            if (mounted && !_startupFlow.continuedWithoutStorage) {
              unawaited(_retrySecureStorageLoad(automatic: true));
            }
          },
          onError: (Object later) {
            if (mounted) {
              unawaited(_showSecureStorageRecoveryDialog(later, automatic: true));
            }
          },
        ));
      }
      return false;
    }
  }

  Future<bool> _retrySecureStorageLoad({bool automatic = false}) async {
    if (defaultTargetPlatform == TargetPlatform.linux &&
        automatic && _startupFlow.continuedWithoutStorage) {
      return false;
    }
    _protectedSecretPromptGate.reset();
    SecureStorageFactory.resetMacosCache();
    SecureStorageFactory.reopenLinuxKeyringGate();
    _loginAutofillStorageLoadAttempted = true;
    if (!await _loadAppSettings(
      allowMacosKeychainPrompt: true,
      automaticRecovery: automatic,
    )) {
      // Other platforms keep storage access; only macOS defers the keychain.
      if (Platform.isMacOS) {
        _secureStorageAccessAllowed = false;
      }
      return false;
    }
    await _applyFeatureFlagRuntimeState(
      GakujoFeatureFlag.downloadCapture,
      enabled: _appSettings.isFeatureEnabled(GakujoFeatureFlag.downloadCapture),
    );
    await _injectLoginAutofillAssistIfAllowed();
    await _injectTwoFactorAutofillIfAllowed();
    return true;
  }

  Future<void> _showSecureStorageRecoveryDialog(
    Object error, {
    bool automatic = false,
  }) async {
    if (_secureStorageRecoveryDialogVisible || !mounted) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.linux &&
        !_startupFlow.claimStorageRecovery(automatic: automatic)) {
      return;
    }

    _secureStorageRecoveryDialogVisible = true;
    LinuxSecretServiceStatus? linuxSecretService;
    if (defaultTargetPlatform == TargetPlatform.linux &&
        error is PlatformException &&
        error.code == 'KeyringLocked') {
      linuxSecretService = await linuxSecretServiceStatus();
      if (!mounted) {
        _secureStorageRecoveryDialogVisible = false;
        return;
      }
    }
    ModalRoute<_SecureStorageRecoveryAction>? dialogRoute;
    final action = await showDialog<_SecureStorageRecoveryAction>(
      context: context,
      builder: (context) {
        dialogRoute = ModalRoute.of<_SecureStorageRecoveryAction>(context);
        final details = error is PlatformException
            ? (error.message ?? error.code)
            : error.toString();
        final missingEntitlement = isMissingKeychainEntitlementError(error);
        final guidance = secureStorageRecoveryGuidance(
          error,
          platform: defaultTargetPlatform,
          linuxSecretService: linuxSecretService,
        );
        return AlertDialog(
          title: const Text('保存データにアクセスできません'),
          content: Text(
            '保存済みログイン情報や2FA設定を読み込めませんでした。\n\n'
            '$guidance'
            '${defaultTargetPlatform == TargetPlatform.linux ? '' : '\n\n詳細: $details'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                _SecureStorageRecoveryAction.continueWithoutStorage,
              ),
              child: const Text('このまま使う'),
            ),
            if (!missingEntitlement) ...[
              // A timeout is not corruption; resetting would discard data.
              if (error is! TimeoutException)
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
    // Only an explicit retry should touch the keychain again; otherwise every
    // later login page would reopen this dialog after another timeout.
    if (action != _SecureStorageRecoveryAction.retry) {
      _loginAutofillStorageLoadAttempted = true;
    }

    var storageRecovered = false;
    if (action == _SecureStorageRecoveryAction.retry && mounted) {
      storageRecovered = await _retrySecureStorageLoad();
    } else if (action == _SecureStorageRecoveryAction.reset && mounted) {
      await _resetSecureStorageAfterConfirmation();
    }
    if (defaultTargetPlatform == TargetPlatform.linux &&
        action == _SecureStorageRecoveryAction.continueWithoutStorage) {
      _startupFlow.continuedWithoutStorage = true;
    }
    if (storageRecovered ||
        (defaultTargetPlatform == TargetPlatform.linux &&
            action == _SecureStorageRecoveryAction.continueWithoutStorage)) {
      await gakujoWaitForDialogDismissal(dialogRoute);
      if (mounted && !_appSettings.setupCompleted) {
        await _showInitialSetupWizard();
      }
    }
  }

  Future<void> _resetSecureStorageAfterConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('保存データをリセットしますか'),
          content: const Text(
            '安全な保存領域に保存したログイン情報、2FA秘密鍵、設定、履歴データを削除します。'
            '削除後はログイン情報と2FA設定を入力し直してください。',
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

    var revocationUnconfirmed = false;
    SecureStorageFactory.reopenLinuxKeyringGate();
    try {
      _discardHistoryNavigation();
      _loginIdentity.pending = null;
      _loginIdentity.restored = null;
      await _setActiveLoginAccount(null, resync: false);
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        await _notificationService.clearHistory();
      }
      try {
        await _warnPendingDriveChecks();
      } on Object catch (error) {
        developer.log('Failed to check saved Drive files: ${error.runtimeType}',
            name: 'MoreBetterGakujo');
      }
      await _starSyncEngine.runAccountChange(() async {
        await _starSyncEngine.resetInMemory();
        _starSyncLoad = null;
        try {
          await _setDriveDownloadsEnabled(false);
        } on Object catch (error) {
          developer.log('Failed to disable Drive saving: ${error.runtimeType}',
              name: 'MoreBetterGakujo');
        }
        _starSyncGoogleEmail = null;
        try {
          if (!await _signOutGoogle(warn: false)) revocationUnconfirmed = true;
        } on Object catch (error) {
          revocationUnconfirmed = true;
          developer.log('Failed to sign out of Google: ${error.runtimeType}',
              name: 'MoreBetterGakujo');
        }
        // Like 「データをすべて削除」, keep pending protections: the record of
        // unverified Drive uploads (the startup warning points at them) and a
        // deferred 「空にして始める」 draft clear (old drafts must not sync).
        const keptKeys = [googleDrivePendingChecksKey, starSyncPendingDraftClearKey];
        final kept = <String, String>{};
        for (final key in keptKeys) {
          try {
            final value = await SecureStorageFactory.create().read(key: key);
            if (value != null) kept[key] = value;
          } on Object {
            // An unreadable store has nothing left to carry over.
          }
        }
        if ((Platform.isAndroid || Platform.isIOS) &&
            (await _appSettingsStore.protectionState.read()).enabled) {
          try {
            await _appSettingsStore.protectionState.vault.delete();
          } on Object catch (error) {
            developer.log(
              'Failed to delete protected secrets: ${error.runtimeType}',
              name: 'MoreBetterGakujo',
            );
          }
        }
        await SecureStorageFactory.resetStorage();
        try {
          // Also drops the meter's in-memory usage, which would be written back.
          await StarSyncQuotaMeter.shared.clear();
        } on Object catch (error) {
          developer.log('Failed to clear the Drive quota record: ${error.runtimeType}',
              name: 'MoreBetterGakujo');
        }
        for (final entry in kept.entries) {
          try {
            await SecureStorageFactory.create()
                .write(key: entry.key, value: entry.value);
          } on Object catch (error) {
            developer.log(
                'Failed to keep a pending protection: ${error.runtimeType}',
                name: 'MoreBetterGakujo');
          }
        }
        _appSettings = _appSettings.copyWith(savedLoginId: null);
        _starSyncLoad = null;
      });
      await _localPrefsStore.clear();
      await _applyFeatureFlagRuntimeState(
        GakujoFeatureFlag.loginAutofill,
        enabled: false,
      );
      await _applyFeatureFlagRuntimeState(
        GakujoFeatureFlag.twoFactorAutofill,
        enabled: false,
      );
      if (!mounted) {
        return;
      }
      _secureStorageAccessAllowed = true;
      if (Platform.isMacOS) {
        _driveDownloadsLoad = _loadDriveDownloadsPreference();
      }
      _startupPlaceholderFeatureFlags.clear();
      setState(() {
        _appSettings = const GakujoAppSettings();
        _appSettingsLoaded = true;
        _reportedGpa = null;
      });
      await _applyFeatureFlagRuntimeState(
        GakujoFeatureFlag.downloadCapture,
        enabled:
            _appSettings.isFeatureEnabled(GakujoFeatureFlag.downloadCapture),
      );
      _setStatus('保存データをリセットしました');
      _showSnackBar(revocationUnconfirmed
          ? '保存データをリセットしました。$googleRevocationUnconfirmedMessage'
          : '保存データをリセットしました。ログイン情報と2FA設定を入力し直してください');
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to reset secure storage',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showSnackBar('保存データをリセットできませんでした: $error');
      }
    }
  }

  Future<void> _saveInitialTwoFactorSecretIfAllowed() async {
    final secret = widget._initialTwoFactorSecret;
    if (!_debugAllowed || secret == null || secret.isEmpty) {
      return;
    }

    try {
      final save = _secretStore.save(secret);
      if (Platform.isMacOS) {
        // This explicit debug secret can require a Keychain access prompt.
        await save;
      } else {
        await save.timeout(const Duration(seconds: 3));
      }
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

  Future<void> _restoreLastPageAfterLoginIfNeeded(
    String currentUrl, {
    required GakujoPortalAuthState authState,
    required int navigationRevision,
  }) async {
    final history = _historyNavigation;
    if (history != null && _loginRestore.owns(history.owner) &&
        _activeLoginAccount != history.account) {
      return;
    }
    final restoreUrl = _pendingLoginRestoreUrl;
    if (_isCurrentPageCallback(currentUrl, navigationRevision) &&
        shouldConsumePendingGakujoPage(
          authState: authState,
          currentUrl: currentUrl,
          restoreUrl: restoreUrl,
        )) {
      // The initial request may already have reached the saved page without a
      // login challenge. Consume the pending target so a later navigation does
      // not unexpectedly jump back to it.
      _pendingLoginRestoreUrl = null;
      return;
    }
    if (!_isCurrentPageCallback(currentUrl, navigationRevision) ||
        !shouldRestorePendingGakujoPage(
          authState: authState,
          restoreAttempted: _loginRestoreAttempted,
          hasRestoreUrl: restoreUrl != null,
          currentUrlMatchesRestoreUrl: restoreUrl == currentUrl,
        ) ||
        restoreUrl == null ||
        !AllowedWebOrigins.canRestoreLastPage(
          restoreUrl,
          debugAllowed: _debugAllowed,
        ) ||
        !AllowedWebOrigins.canLoad(currentUrl, debugAllowed: _debugAllowed)) {
      return;
    }

    _loginRestoreAttempted = true;
    _pendingLoginRestoreUrl = null;
    _setStatus('前回のページに戻ります: ${_displayUrl(restoreUrl)}');
    _beginPendingMessageNavigation(restoreUrl);
    await _controller.loadUrl(restoreUrl);
  }

  Future<void> _handleSystemBack() async {
    if (_calendarOperationGate.isRunning) {
      _showSnackBar('カレンダー連携または再検出の完了後に戻ってください');
      return;
    }
    if (await _goBackIfPossible()) {
      return;
    }

    if (!mounted) {
      return;
    }
    _showSnackBar('前のページはありません');
  }

  Future<void> _goBack() async {
    if (_calendarOperationGate.isRunning) {
      _showSnackBar('カレンダー連携または再検出の完了後に戻ってください');
      return;
    }
    if (!await _goBackIfPossible() && mounted) {
      _showSnackBar('前のページはありません');
    }
  }

  void _setPendingReturnDialog(String? kind) {
    _pendingReturnDialogTimer?.cancel();
    _pendingReturnDialog = kind;
    if (kind != null) {
      _pendingReturnDialogTimer = Timer(const Duration(minutes: 3), () {
        _pendingReturnDialog = null;
      });
    }
  }

  Future<Map<String, dynamic>> _readHistoryMarkers() async {
    if (!_canRunPageScripts) return {};
    try {
      final result = await _controller.runJavaScriptReturningResult(
        gakujoHistoryMarkerJs({
          'action': 'read',
          if (_detachedPreviewToken != null) 'token': _detachedPreviewToken,
        }),
      );
      final decoded = jsonDecode(_stringFromJavaScriptResult(result));
      return decoded is Map<String, dynamic> ? decoded : {};
    } on Object catch (error, stackTrace) {
      developer.log('Failed to read history markers',
          name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      return {};
    }
  }

  Future<Map<String, dynamic>> _syncHistoryState({int? revision}) async {
    final expectedRevision = revision ?? _navigationRevision;
    final markers = await _readHistoryMarkers();
    if (!mounted || expectedRevision != _navigationRevision) return {};
    final active = markers['active'];
    if (active is! String ||
        !const {'visible', 'hidden', 'none'}.contains(active)) {
      return {};
    }
    final activeToken = markers['activeToken'];
    final dialog = markers['dialog'];
    final preview = markers['preview'];
    _handlePreviewNavigationState(active);
    setState(() {
      _activePreviewToken = activeToken is String ? activeToken : null;
      _returnDialogMarker = dialog is String ? dialog : null;
      _virtualPreviewForward = active == 'none' && preview is String &&
          preview == _detachedPreviewToken;
    });
    return markers;
  }

  void _scheduleHistoryStateSync(int revision) {
    for (final delay in const [
      Duration(milliseconds: 400),
      Duration(milliseconds: 1500),
    ]) {
      unawaited(Future<void>.delayed(delay, () async {
        if (!mounted || revision != _navigationRevision) return;
        await _syncHistoryState(revision: revision);
        if (!mounted || revision != _navigationRevision) return;
        await _refreshNavigationState(revision: revision);
      }));
    }
  }

  Future<void> _navigateWebViewHistory({required bool forward}) async {
    _beginNavigation();
    final revision = _navigationRevision;
    if (forward) {
      await _controller.goForward();
    } else {
      await _controller.goBack();
    }
    _scheduleHistoryStateSync(revision);
    await _syncHistoryState(revision: revision);
    if (mounted && revision == _navigationRevision) {
      await _refreshNavigationState(revision: revision);
    }
  }

  Future<void> _finishHistoryMarkers(String url, int revision) async {
    final processing = _messageOpenProcessing;
    if (processing != null) await processing.future;
    if (!_isCurrentPageCallback(url, revision) || !_canRunPageScripts) return;
    final kind = _pendingReturnDialog;
    if (kind != null && _pendingMessageOpen == null &&
        _messageOpenProcessing == null) {
      try {
        await _controller.runJavaScript(
          gakujoHistoryMarkerJs({'action': 'stamp-dialog', 'kind': kind}),
        );
        if (_isCurrentPageCallback(url, revision) &&
            _pendingReturnDialog == kind) {
          _setPendingReturnDialog(null);
        }
      } on Object catch (error, stackTrace) {
        developer.log('Failed to stamp history dialog',
            name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      }
    }
    if (!_isCurrentPageCallback(url, revision)) return;
    await _syncHistoryState(revision: revision);
  }

  Widget _historyDialogInput({required bool returned, required Widget child}) {
    if (!returned) return child;
    return Listener(
      onPointerDown: (event) {
        final direction = mouseHistoryNavigation(event);
        if (direction != null) {
          unawaited(_closeReturnedDialog(
            back: direction == MouseHistoryNavigation.back,
          ));
        }
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          final back = key == LogicalKeyboardKey.browserBack ||
              (HardwareKeyboard.instance.isAltPressed &&
                  key == LogicalKeyboardKey.arrowLeft);
          final forward = key == LogicalKeyboardKey.browserForward ||
              (HardwareKeyboard.instance.isAltPressed &&
                  key == LogicalKeyboardKey.arrowRight);
          if (back || forward) {
            unawaited(_closeReturnedDialog(
              back: back,
            ));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }

  Widget _historyDialogTitle(String title, bool returned) {
    if (!returned) return Text(title);
    return Row(children: [
      Expanded(child: Text(title)),
      IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: '前のページへ戻る',
        onPressed: () => unawaited(_closeReturnedDialog(back: true)),
      ),
      IconButton(
        icon: const Icon(Icons.arrow_forward),
        tooltip: 'ページに戻る',
        onPressed: () => unawaited(_closeReturnedDialog(back: false)),
      ),
    ]);
  }

  Future<void> _closeReturnedDialog({required bool back}) async {
    final dialogContext = _returnedDialogContext;
    if (dialogContext == null) return;
    _setPendingReturnDialog(null);
    _returnedDialogContext = null;
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    if (back && await _controller.canGoBack()) {
      await _navigateWebViewHistory(forward: false);
    }
  }

  bool _isStaleDialogReturn(int? revision) =>
      revision != null && revision != _navigationRevision;

  Future<void> _showReturnedDialog(String kind, int revision) async {
    _returnedDialogRevision = revision;
    try {
      switch (kind) {
        case 'starred':
          await _showStarredMessagesDialog(returnRevision: revision);
        case 'favorites':
          await _showFavoritesDialog(returnRevision: revision);
        case 'cachedReports':
          await _showCachedReportsDialog(returnRevision: revision);
      }
    } finally {
      if (_returnedDialogRevision == revision) {
        _returnedDialogRevision = null;
        _returnedDialogContext = null;
      }
    }
  }

  Future<bool> _goBackIfPossible() async {
    if (_returnedDialogContext != null) {
      await _closeReturnedDialog(back: true);
      return true;
    }
    if (_returnedDialogOpening) return true;
    _setPendingReturnDialog(null);
    if (_calendarOperationGate.isRunning) {
      return false;
    }
    final revision = _navigationRevision;
    bool stillCurrent() => mounted && revision == _navigationRevision;
    final markers = _previewNavigationState == 'visible'
        ? <String, dynamic>{}
        : await _syncHistoryState(revision: revision);
    if (!stillCurrent()) return true;
    final dialog = markers['dialog'];
    final action = decideGakujoHistoryAction(
      forward: false,
      previewState: _previewNavigationState,
      hasDialog: dialog is String,
      activeToken: _activePreviewToken,
      markerToken:
          markers['preview'] is String ? markers['preview'] as String : null,
      detachedToken: _detachedPreviewToken,
      canGoForward: false,
      canGoBack: _previewNavigationState != 'visible' &&
          await _controller.canGoBack(),
    );
    if (!stillCurrent()) return true;
    if (action == GakujoHistoryAction.preview) {
      return _navigatePreview('back');
    }
    if (action == GakujoHistoryAction.dialog) {
      if (_returnedDialogOpening || _returnedDialogContext != null) return true;
      unawaited(_showReturnedDialog(dialog as String, revision));
      return true;
    }
    _setPendingMessageUrl(null);
    if (action != GakujoHistoryAction.webView) {
      await _refreshNavigationState();
      return false;
    }
    if (_previewNavigationState == 'hidden' && _activePreviewToken != null) {
      _detachedPreviewToken = _activePreviewToken;
    }
    await _navigateWebViewHistory(forward: false);
    return true;
  }

  Future<void> _goForward() async {
    if (_calendarOperationGate.isRunning) {
      _showSnackBar('カレンダー連携または再検出の完了後に進んでください');
      return;
    }
    await _goForwardIfPossible();
    await _refreshNavigationState();
  }

  Future<bool> _goForwardIfPossible() async {
    if (_returnedDialogContext != null) {
      await _closeReturnedDialog(back: false);
      return true;
    }
    if (_returnedDialogOpening) return true;
    _setPendingReturnDialog(null);
    if (_calendarOperationGate.isRunning) {
      return false;
    }
    final revision = _navigationRevision;
    bool stillCurrent() => mounted && revision == _navigationRevision;
    final markers = _previewNavigationState == 'visible'
        ? <String, dynamic>{}
        : await _syncHistoryState(revision: revision);
    if (!stillCurrent()) return true;
    final canGoForward = _previewNavigationState != 'visible' &&
        await _controller.canGoForward();
    if (!stillCurrent()) return true;
    final action = decideGakujoHistoryAction(
      forward: true,
      previewState: _previewNavigationState,
      hasDialog: false,
      activeToken: _activePreviewToken,
      markerToken:
          markers['preview'] is String ? markers['preview'] as String : null,
      detachedToken: _detachedPreviewToken,
      canGoForward: canGoForward,
      canGoBack: false,
    );
    if (action == GakujoHistoryAction.preview) {
      return _navigatePreview('forward');
    }
    if (action == GakujoHistoryAction.reopenPreview &&
        _detachedPreviewToken != null) {
      try {
        final result = await _controller.runJavaScriptReturningResult(
          gakujoHistoryMarkerJs({
            'action': 'reopen-preview',
            'token': _detachedPreviewToken,
          }),
        );
        if (!stillCurrent()) return true;
        if (_boolFromJavaScriptResult(result)) {
          _detachedPreviewToken = null;
          if (mounted) setState(() => _virtualPreviewForward = false);
          return true;
        }
      } on Object catch (error, stackTrace) {
        developer.log('Failed to reopen preview',
            name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      }
    }
    if (!stillCurrent()) return true;
    _setPendingMessageUrl(null);
    if (action != GakujoHistoryAction.webView &&
        !(action == GakujoHistoryAction.reopenPreview && canGoForward)) {
      await _refreshNavigationState();
      return false;
    }

    await _navigateWebViewHistory(forward: true);
    return true;
  }

  void _handlePreviewNavigationState(String state) {
    if (state.startsWith('token:')) {
      final token = state.substring(6);
      if (RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(token)) {
        _activePreviewToken = token;
      }
      return;
    }
    if (!mounted || !const {'visible', 'hidden', 'none'}.contains(state)) {
      return;
    }
    if (_previewNavigationState != state) {
      // Opening/hiding a preview changes gesture ownership. A partial scroll
      // or the remainder of its momentum must not become history navigation.
      _desktopHistorySwipe.suppress();
      _desktopPanZoomSuppressed = true;
      _desktopPanZoomInterrupted = _desktopPanZoomActive;
      _previewGestureRevision++;
      _resetTouchHistorySwipe();
      setState(() => _previewNavigationState = state);
    }
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(const MethodChannel('net.yoshida.morebettergakujo/pdf_preview')
          .invokeMethod<void>('setPreviewState', state)
          .catchError((Object error, StackTrace stackTrace) {
        developer.log('Failed to change PDF preview visibility',
            name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      }));
    }
  }

  Future<bool> _navigatePreview(String direction) async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        gakujoPreviewNavigateJs({'direction': direction}),
      );
      return _boolFromJavaScriptResult(result);
    } on Object catch (error, stackTrace) {
      developer.log('Failed to navigate preview',
          name: 'MoreBetterGakujo', error: error, stackTrace: stackTrace);
      // Do not navigate the underlying page when the preview could not be queried.
      return (direction == 'back' && _previewNavigationState == 'visible') ||
          (direction == 'forward' && _previewNavigationState == 'hidden');
    }
  }

  Future<void> _refreshNavigationState({int? revision}) async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    if (!mounted || (revision != null && revision != _navigationRevision)) {
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
    // Only a page that passed the authenticated DOM probe may replace the
    // restorable URL. Login, 2FA, logout and timeout screens often reuse the
    // same campusportal/campussmart paths as authenticated pages.
    await _saveLastPageUrl(_sessionRecoveryUrl);
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

    _status.value = gakujoUserFacingMessage(
      status,
      platform: defaultTargetPlatform,
    );
  }

  void _showSnackBar(
    String message, {
    SnackBarAction? action,
  }) {
    if (!mounted) {
      return;
    }
    message = gakujoUserFacingMessage(message, platform: defaultTargetPlatform);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (defaultTargetPlatform == TargetPlatform.linux) {
      // A closing menu still counts as covering the page, so the strip must be
      // set then too, or the message would end up behind the page.
      if (!_isSettingsDialogOpen) {
        setState(() {
          _linuxSnackBar = buildTransientGakujoSnackBar(message, action: action);
        });
        if (!(widget.linuxOverlayObscured?.value ?? false)) return;
      } else if (_linuxSnackBar != null) {
        setState(() => _linuxSnackBar = null);
      }
    }
    messenger.showSnackBar(
      buildTransientGakujoSnackBar(message, action: action),
    );
  }

  bool _tryStartPageNavigationOperation() {
    if (_messageOpenProcessing != null || !_calendarOperationGate.tryStart()) {
      return false;
    }
    _setPendingMessageUrl(null);
    if (mounted) {
      setState(() {});
    }
    return true;
  }

  Future<void> _finishPageNavigationOperation() async {
    String? previousRestoreTarget;
    try {
      while (true) {
        final notification = _deferredNotificationAfterPageOperationUrl;
        final url = notification ?? _deferredNavigationAfterPageOperationUrl;
        _deferredNotificationAfterPageOperationUrl = null;
        _deferredNavigationAfterPageOperationUrl = null;
        if (!mounted || url == null ||
            !AllowedWebOrigins.canLoad(url, debugAllowed: _debugAllowed)) {
          break;
        }
        // A failed or timed-out notification may still own the login restore.
        // Its replacement must also win when the next page authenticates.
        if (previousRestoreTarget != null) {
          _clearNavigationRestoreFor(previousRestoreTarget);
        }
        _setPendingMessageUrl(url);
        previousRestoreTarget = notification == null
            ? null
            : _reserveNotificationRestore(notification);
        final waiter = Completer<String>();
        final disposed = Completer<void>();
        final pageFinished = _waitForNextPageFinished(
          waiter: waiter,
          timeout: const Duration(seconds: 8),
        );
        try {
          _beginPendingMessageNavigation(url);
          _deferredPageNavigation =
              (url: url, revision: _navigationRevision, disposed: disposed);
          // Disposal can interrupt either the load reply or the scripts that
          // process a page-finished event after its timeout has been cancelled.
          final settled = Future.any<void>([pageFinished, disposed.future]);
          await Future.any<void>([_controller.loadUrl(url), settled]);
          await settled;
        } on Object catch (error, stackTrace) {
          developer.log(
            'Failed to open navigation deferred by a page operation',
            name: 'MoreBetterGakujo',
            error: error,
            stackTrace: stackTrace,
          );
          if (mounted) _showSnackBar('保留したページを開けませんでした');
        } finally {
          _deferredPageNavigation = null;
          if (!waiter.isCompleted) waiter.complete('');
        }
      }
    } finally {
      _calendarOperationGate.finish();
      if (mounted) {
        setState(() {});
        final url = _currentPageUrl;
        if (url != null &&
            _messageOpenReadyNavigationRevision == _navigationRevision) {
          // The finished callback may have deferred opening under this gate.
          await _openPendingMessageIfNeeded(
            url,
            navigationRevision: _navigationRevision,
          );
        }
      }
    }
  }

  bool get _canRunPageScripts => canRunGakujoPageScripts(
        currentUrl: _currentPageUrl,
        lastAllowedUrl: _lastAllowedPageUrl,
        debugAllowed: _debugAllowed,
      );

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
}

/// Whether [url] is Gakujo's shared downloads tab.
@visibleForTesting
bool isGakujoSharedDownloadsUrl(String? url) =>
    url != null && Uri.tryParse(url)?.queryParameters['tabId'] == 'sd';

/// Whether [value] can name a course folder. Page labels and the titles of
/// error or notice pages (expired flow, timeout, offline) are not courses;
/// caching one would file the next download under that name.
@visibleForTesting
bool isUsefulGakujoCourseName(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > DownloadFileNamePolicy.maxCourseFolderNameLength ||
      normalized == '未分類') {
    return false;
  }

  const genericPageLabels = {
    'ダウンロード',
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
  if (RegExp(
    r'有効期限|タイムアウト|インターネットに接続|接続できません|'
    r'ページを表示できません|webpage not available|ログイン|ログアウト|'
    r'^now loading|'
    r'^(?:エラー|error)',
  ).hasMatch(lower)) {
    return false;
  }
  return !lower.contains('campussquare') &&
      !lower.contains('more better gakujo') &&
      !normalized.contains('学務情報システム');
}
