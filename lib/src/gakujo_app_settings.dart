import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'migrating_secure_storage.dart';
import 'secure_storage_factory.dart';

enum DownloadSaveMode {
  autoSortToConfiguredFolder,
  flatToConfiguredFolder,
  flatWithPickerEachTime,
}

extension DownloadSaveModeLabels on DownloadSaveMode {
  String get label {
    return switch (this) {
      DownloadSaveMode.autoSortToConfiguredFolder => '自動仕分け+指定場所保存',
      DownloadSaveMode.flatToConfiguredFolder => '自動仕分けなし+指定場所保存',
      DownloadSaveMode.flatWithPickerEachTime => '自動仕分けなし+適宜保存場所指定',
    };
  }

  String get storageValue {
    return switch (this) {
      DownloadSaveMode.autoSortToConfiguredFolder => 'auto_sort_configured',
      DownloadSaveMode.flatToConfiguredFolder => 'flat_configured',
      DownloadSaveMode.flatWithPickerEachTime => 'flat_picker_each_time',
    };
  }

  bool get needsConfiguredRoot {
    return switch (this) {
      DownloadSaveMode.autoSortToConfiguredFolder ||
      DownloadSaveMode.flatToConfiguredFolder =>
        true,
      DownloadSaveMode.flatWithPickerEachTime => false,
    };
  }

  bool get autoSortByCourse {
    return this == DownloadSaveMode.autoSortToConfiguredFolder;
  }

  static DownloadSaveMode fromStorageValue(String? value) {
    return DownloadSaveMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => DownloadSaveMode.autoSortToConfiguredFolder,
    );
  }
}

enum GakujoPageMode {
  mobile,
  desktop,
}

extension GakujoPageModeLabels on GakujoPageMode {
  String get label {
    return switch (this) {
      GakujoPageMode.mobile => 'モバイル版',
      GakujoPageMode.desktop => 'デスクトップ版',
    };
  }

  String get storageValue {
    return switch (this) {
      GakujoPageMode.mobile => 'mobile',
      GakujoPageMode.desktop => 'desktop',
    };
  }

  String get startUrl {
    return switch (this) {
      GakujoPageMode.mobile =>
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do',
      GakujoPageMode.desktop =>
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
    };
  }

  static GakujoPageMode fromStorageValue(String? value) {
    return GakujoPageMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => GakujoPageMode.desktop,
    );
  }
}

enum GakujoFeatureFlag {
  downloadCapture,
  gpaDisplay,
  reportTools,
  messageTools,
  sessionExtender,
  loginAutofill,
  twoFactorAutofill,
  activityScan,
  deadlineScan,
  deadlineNotifications,
  reportListCache,
  sessionRecoveryGuide,
  autoBackup,
}

enum GakujoCalendarImportMethod {
  automatic,
  deviceCalendar,
  officialGoogle,
  icsFile,
}

extension GakujoCalendarImportMethodLabels on GakujoCalendarImportMethod {
  String get label {
    return switch (this) {
      GakujoCalendarImportMethod.automatic => '自動で選ぶ',
      GakujoCalendarImportMethod.deviceCalendar => 'OSカレンダーへ直接追加',
      GakujoCalendarImportMethod.officialGoogle => '本家Google連携を開く',
      GakujoCalendarImportMethod.icsFile => 'iCalendarファイルを書き出す',
    };
  }

  String get storageValue {
    return switch (this) {
      GakujoCalendarImportMethod.automatic => 'automatic',
      GakujoCalendarImportMethod.deviceCalendar => 'device_calendar',
      GakujoCalendarImportMethod.officialGoogle => 'official_google',
      GakujoCalendarImportMethod.icsFile => 'ics_file',
    };
  }

  static GakujoCalendarImportMethod fromStorageValue(String? value) {
    return GakujoCalendarImportMethod.values.firstWhere(
      (method) => method.storageValue == value,
      orElse: () => GakujoCalendarImportMethod.automatic,
    );
  }
}

enum GakujoCalendarTermSource {
  officialAcademicCalendar,
  pageOrManual,
}

extension GakujoCalendarTermSourceLabels on GakujoCalendarTermSource {
  String get label {
    return switch (this) {
      GakujoCalendarTermSource.officialAcademicCalendar => '公式授業暦から自動判定',
      GakujoCalendarTermSource.pageOrManual => 'ページから読み取り、必要なら手入力',
    };
  }

  String get storageValue {
    return switch (this) {
      GakujoCalendarTermSource.officialAcademicCalendar => 'official',
      GakujoCalendarTermSource.pageOrManual => 'page_or_manual',
    };
  }

  static GakujoCalendarTermSource fromStorageValue(String? value) {
    return GakujoCalendarTermSource.values.firstWhere(
      (source) => source.storageValue == value,
      orElse: () => GakujoCalendarTermSource.officialAcademicCalendar,
    );
  }
}

enum GakujoCalendarTermTarget {
  current,
  first,
  second,
  third,
  fourth,
}

extension GakujoCalendarTermTargetLabels on GakujoCalendarTermTarget {
  String get label {
    return switch (this) {
      GakujoCalendarTermTarget.current => '現在のタームを自動判定',
      GakujoCalendarTermTarget.first => '第1ターム',
      GakujoCalendarTermTarget.second => '第2ターム',
      GakujoCalendarTermTarget.third => '第3ターム',
      GakujoCalendarTermTarget.fourth => '第4ターム',
    };
  }

  String get storageValue {
    return switch (this) {
      GakujoCalendarTermTarget.current => 'current',
      GakujoCalendarTermTarget.first => 'first',
      GakujoCalendarTermTarget.second => 'second',
      GakujoCalendarTermTarget.third => 'third',
      GakujoCalendarTermTarget.fourth => 'fourth',
    };
  }

  String? get termName {
    return switch (this) {
      GakujoCalendarTermTarget.current => null,
      GakujoCalendarTermTarget.first => '第1ターム',
      GakujoCalendarTermTarget.second => '第2ターム',
      GakujoCalendarTermTarget.third => '第3ターム',
      GakujoCalendarTermTarget.fourth => '第4ターム',
    };
  }

  static GakujoCalendarTermTarget fromStorageValue(String? value) {
    return GakujoCalendarTermTarget.values.firstWhere(
      (target) => target.storageValue == value,
      orElse: () => GakujoCalendarTermTarget.current,
    );
  }
}

class GakujoCalendarImportSettings {
  const GakujoCalendarImportSettings({
    this.method = GakujoCalendarImportMethod.automatic,
    this.termSource = GakujoCalendarTermSource.officialAcademicCalendar,
    this.termTarget = GakujoCalendarTermTarget.current,
    this.includeNoClassDates = true,
    this.calendarTitle = defaultCalendarTitle,
  });

  static const defaultCalendarTitle = 'More Better Gakujo 授業';

  final GakujoCalendarImportMethod method;
  final GakujoCalendarTermSource termSource;
  final GakujoCalendarTermTarget termTarget;
  final bool includeNoClassDates;
  final String calendarTitle;

  String get effectiveCalendarTitle {
    final trimmed = calendarTitle.trim();
    return trimmed.isEmpty ? defaultCalendarTitle : trimmed;
  }

  GakujoCalendarImportSettings copyWith({
    GakujoCalendarImportMethod? method,
    GakujoCalendarTermSource? termSource,
    GakujoCalendarTermTarget? termTarget,
    bool? includeNoClassDates,
    String? calendarTitle,
  }) {
    return GakujoCalendarImportSettings(
      method: method ?? this.method,
      termSource: termSource ?? this.termSource,
      termTarget: termTarget ?? this.termTarget,
      includeNoClassDates: includeNoClassDates ?? this.includeNoClassDates,
      calendarTitle: calendarTitle ?? this.calendarTitle,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'method': method.storageValue,
      'termSource': termSource.storageValue,
      'termTarget': termTarget.storageValue,
      'includeNoClassDates': includeNoClassDates,
      'calendarTitle': effectiveCalendarTitle,
    };
  }

  factory GakujoCalendarImportSettings.fromJson(Object? raw) {
    if (raw is String) {
      try {
        return GakujoCalendarImportSettings.fromJson(jsonDecode(raw));
      } on FormatException {
        return const GakujoCalendarImportSettings();
      }
    }
    if (raw is! Map<dynamic, dynamic>) {
      return const GakujoCalendarImportSettings();
    }
    return GakujoCalendarImportSettings(
      method: GakujoCalendarImportMethodLabels.fromStorageValue(
        raw['method']?.toString(),
      ),
      termSource: GakujoCalendarTermSourceLabels.fromStorageValue(
        raw['termSource']?.toString(),
      ),
      termTarget: GakujoCalendarTermTargetLabels.fromStorageValue(
        raw['termTarget']?.toString(),
      ),
      includeNoClassDates: raw['includeNoClassDates'] is bool
          ? raw['includeNoClassDates'] as bool
          : raw['includeNoClassDates']?.toString().toLowerCase() != 'false',
      calendarTitle:
          (raw['calendarTitle']?.toString().trim().isNotEmpty == true)
              ? raw['calendarTitle'].toString().trim()
              : defaultCalendarTitle,
    );
  }
}

extension GakujoFeatureFlagLabels on GakujoFeatureFlag {
  String get label {
    return switch (this) {
      GakujoFeatureFlag.downloadCapture => '資料ダウンロード捕捉',
      GakujoFeatureFlag.gpaDisplay => 'GPA表示',
      GakujoFeatureFlag.reportTools => 'レポート並び替え',
      GakujoFeatureFlag.messageTools => '連絡通知一括既読',
      GakujoFeatureFlag.sessionExtender => 'セッション自動延長',
      GakujoFeatureFlag.loginAutofill => 'ログイン補助',
      GakujoFeatureFlag.twoFactorAutofill => '2FA自動入力',
      GakujoFeatureFlag.activityScan => '更新検知',
      GakujoFeatureFlag.deadlineScan => '提出期限抽出',
      GakujoFeatureFlag.deadlineNotifications => '提出期限のOS通知',
      GakujoFeatureFlag.reportListCache => '課題一覧の保存',
      GakujoFeatureFlag.sessionRecoveryGuide => 'セッション復帰ガイド',
      GakujoFeatureFlag.autoBackup => '自動バックアップ',
    };
  }

  String get storageValue {
    return switch (this) {
      GakujoFeatureFlag.downloadCapture => 'download_capture',
      GakujoFeatureFlag.gpaDisplay => 'gpa_display',
      GakujoFeatureFlag.reportTools => 'report_tools',
      GakujoFeatureFlag.messageTools => 'message_tools',
      GakujoFeatureFlag.sessionExtender => 'session_extender',
      GakujoFeatureFlag.loginAutofill => 'login_autofill',
      GakujoFeatureFlag.twoFactorAutofill => 'two_factor_autofill',
      GakujoFeatureFlag.activityScan => 'activity_scan',
      GakujoFeatureFlag.deadlineScan => 'deadline_scan',
      GakujoFeatureFlag.deadlineNotifications => 'deadline_notifications',
      GakujoFeatureFlag.reportListCache => 'report_list_cache',
      GakujoFeatureFlag.sessionRecoveryGuide => 'session_recovery_guide',
      GakujoFeatureFlag.autoBackup => 'auto_backup',
    };
  }

  static GakujoFeatureFlag? fromStorageValue(String? value) {
    for (final flag in GakujoFeatureFlag.values) {
      if (flag.storageValue == value) {
        return flag;
      }
    }
    return null;
  }
}

class GakujoAppSettings {
  const GakujoAppSettings({
    this.downloadSaveMode = DownloadSaveMode.autoSortToConfiguredFolder,
    this.pageMode = GakujoPageMode.desktop,
    this.loginCredentials,
    this.disabledFeatureFlags = const {},
    this.setupCompleted = false,
    this.calendarImportSettings = const GakujoCalendarImportSettings(),
    this.messageExcludeKeywords = const [],
  });

  final DownloadSaveMode downloadSaveMode;
  final GakujoPageMode pageMode;
  final GakujoLoginCredentials? loginCredentials;
  final Set<GakujoFeatureFlag> disabledFeatureFlags;
  final bool setupCompleted;
  final GakujoCalendarImportSettings calendarImportSettings;
  final List<String> messageExcludeKeywords;

  bool get hasLoginCredentials => loginCredentials?.isComplete ?? false;

  bool isFeatureEnabled(GakujoFeatureFlag flag) {
    return !disabledFeatureFlags.contains(flag);
  }

  GakujoAppSettings copyWith({
    DownloadSaveMode? downloadSaveMode,
    GakujoPageMode? pageMode,
    Object? loginCredentials = _unchanged,
    Set<GakujoFeatureFlag>? disabledFeatureFlags,
    bool? setupCompleted,
    GakujoCalendarImportSettings? calendarImportSettings,
    List<String>? messageExcludeKeywords,
  }) {
    return GakujoAppSettings(
      downloadSaveMode: downloadSaveMode ?? this.downloadSaveMode,
      pageMode: pageMode ?? this.pageMode,
      loginCredentials: loginCredentials == _unchanged
          ? this.loginCredentials
          : loginCredentials as GakujoLoginCredentials?,
      disabledFeatureFlags: disabledFeatureFlags ?? this.disabledFeatureFlags,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      calendarImportSettings:
          calendarImportSettings ?? this.calendarImportSettings,
      messageExcludeKeywords:
          messageExcludeKeywords ?? this.messageExcludeKeywords,
    );
  }
}

class GakujoLoginCredentials {
  const GakujoLoginCredentials({
    required this.loginId,
    required this.password,
  });

  final String loginId;
  final String password;

  bool get isComplete => loginId.trim().isNotEmpty && password.isNotEmpty;
}

const _unchanged = Object();

class GakujoAppSettingsStore {
  GakujoAppSettingsStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? SecureStorageFactory.create();

  static const _downloadSaveModeKey = 'more_better_gakujo_download_save_mode';
  static const _pageModeKey = 'more_better_gakujo_page_mode';
  static const _loginIdKey = 'more_better_gakujo_login_id';
  static const _loginPasswordKey = 'more_better_gakujo_login_password';
  static const _disabledFeatureFlagsKey =
      'more_better_gakujo_disabled_feature_flags';
  static const _setupCompletedKey = 'more_better_gakujo_setup_completed';
  static const _calendarImportSettingsKey =
      'more_better_gakujo_calendar_import_settings';
  static const _messageExcludeKeywordsKey =
      'more_better_gakujo_message_exclude_keywords';
  static const _settingsKeys = [
    _downloadSaveModeKey,
    _pageModeKey,
    _loginIdKey,
    _loginPasswordKey,
    _disabledFeatureFlagsKey,
    _setupCompletedKey,
    _calendarImportSettingsKey,
    _messageExcludeKeywordsKey,
  ];

  final FlutterSecureStorage _secureStorage;

  Future<GakujoAppSettings> load() async {
    final values = await _loadSettingsValues();
    final loginId = values[_loginIdKey]?.trim() ?? '';
    final password = values[_loginPasswordKey] ?? '';
    final disabledFeatureFlags = (values[_disabledFeatureFlagsKey] ?? '')
        .split(',')
        .map((value) => GakujoFeatureFlagLabels.fromStorageValue(value))
        .whereType<GakujoFeatureFlag>()
        .toSet();
    return GakujoAppSettings(
      downloadSaveMode: DownloadSaveModeLabels.fromStorageValue(
        values[_downloadSaveModeKey],
      ),
      pageMode: GakujoPageModeLabels.fromStorageValue(values[_pageModeKey]),
      loginCredentials: loginId.isNotEmpty && password.isNotEmpty
          ? GakujoLoginCredentials(loginId: loginId, password: password)
          : null,
      disabledFeatureFlags: disabledFeatureFlags,
      setupCompleted: values[_setupCompletedKey] == 'true',
      calendarImportSettings: GakujoCalendarImportSettings.fromJson(
        values[_calendarImportSettingsKey],
      ),
      messageExcludeKeywords: _decodeMessageExcludeKeywords(
        values[_messageExcludeKeywordsKey],
      ),
    );
  }

  Future<Map<String, String?>> _loadSettingsValues() async {
    final secureStorage = _secureStorage;
    if (secureStorage is MigratingSecureStorage) {
      return secureStorage.readKeys(_settingsKeys);
    }

    try {
      final allValues = await secureStorage.readAll();
      return {
        for (final key in _settingsKeys) key: allValues[key],
      };
    } on Object {
      final values = <String, String?>{};
      for (final key in _settingsKeys) {
        values[key] = await secureStorage.read(key: key);
      }
      return values;
    }
  }

  Future<void> saveDownloadSaveMode(DownloadSaveMode mode) {
    return _secureStorage.write(
      key: _downloadSaveModeKey,
      value: mode.storageValue,
    );
  }

  Future<void> savePageMode(GakujoPageMode mode) {
    return _secureStorage.write(
      key: _pageModeKey,
      value: mode.storageValue,
    );
  }

  Future<void> saveFeatureEnabled(
    GakujoFeatureFlag flag, {
    required bool enabled,
  }) async {
    final settings = await load();
    final disabled = {...settings.disabledFeatureFlags};
    if (enabled) {
      disabled.remove(flag);
    } else {
      disabled.add(flag);
    }
    await saveDisabledFeatureFlags(disabled);
  }

  Future<void> saveDisabledFeatureFlags(Set<GakujoFeatureFlag> flags) {
    return _secureStorage.write(
      key: _disabledFeatureFlagsKey,
      value: flags.map((flag) => flag.storageValue).join(','),
    );
  }

  Future<void> saveSetupCompleted(bool completed) {
    return _secureStorage.write(
      key: _setupCompletedKey,
      value: completed ? 'true' : 'false',
    );
  }

  Future<void> saveCalendarImportSettings(
    GakujoCalendarImportSettings settings,
  ) {
    return _secureStorage.write(
      key: _calendarImportSettingsKey,
      value: jsonEncode(settings.toJson()),
    );
  }

  Future<void> saveMessageExcludeKeywords(List<String> keywords) {
    return _secureStorage.write(
      key: _messageExcludeKeywordsKey,
      value: jsonEncode(normalizeMessageExcludeKeywords(keywords)),
    );
  }

  Future<void> saveLoginCredentials({
    required String loginId,
    required String password,
  }) async {
    final trimmedLoginId = loginId.trim();
    if (trimmedLoginId.isEmpty || password.isEmpty) {
      await clearLoginCredentials();
      return;
    }

    await Future.wait([
      _secureStorage.write(key: _loginIdKey, value: trimmedLoginId),
      _secureStorage.write(key: _loginPasswordKey, value: password),
    ]);
  }

  Future<void> clearLoginCredentials() {
    return Future.wait([
      _secureStorage.delete(key: _loginIdKey),
      _secureStorage.delete(key: _loginPasswordKey),
    ]);
  }

  static List<String> _decodeMessageExcludeKeywords(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) {
        return normalizeMessageExcludeKeywords(
          decoded.map((value) => value.toString()),
        );
      }
    } on Object {
      // Fall back to a human-editable line/comma separated format.
    }
    return normalizeMessageExcludeKeywords(raw.split(RegExp(r'[\r\n,]+')));
  }
}

List<String> normalizeMessageExcludeKeywords(Iterable<String> keywords) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final keyword in keywords) {
    final trimmed = keyword.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final key = trimmed.toLowerCase();
    if (seen.add(key)) {
      normalized.add(trimmed);
    }
  }
  return List.unmodifiable(normalized);
}
