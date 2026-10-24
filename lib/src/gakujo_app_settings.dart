import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'migrating_secure_storage.dart';
import 'secure_storage_factory.dart';
import 'secure_storage_transaction.dart';

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
  messageStars,
  sessionExtender,
  loginAutofill,
  twoFactorAutofill,
  activityScan,
  deadlineScan,
  deadlineNotifications,
  reportListCache,
  sessionRecoveryGuide,
  autoBackup,
  uploadCompression,
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
      GakujoCalendarTermTarget.current => '現在のターム（休業中は次のターム）',
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
    this.applyClassChanges = true,
    this.includeAssignmentDeadlines = true,
  });

  static const defaultCalendarTitle = 'More Better Gakujo 授業';
  static const validationCalendarTitle = 'More Better Gakujo 検証';

  final GakujoCalendarImportMethod method;
  final GakujoCalendarTermSource termSource;
  final GakujoCalendarTermTarget termTarget;
  final bool includeNoClassDates;
  final String calendarTitle;

  /// Reflect the 休講補講 page: drop cancelled classes, add make-ups and
  /// move room changes.
  final bool applyClassChanges;

  /// Also add each レポート・小テスト closing time as an event.
  final bool includeAssignmentDeadlines;

  String get effectiveCalendarTitle {
    final trimmed = calendarTitle.trim();
    return trimmed.isEmpty || trimmed == validationCalendarTitle
        ? defaultCalendarTitle
        : trimmed;
  }

  GakujoCalendarImportSettings copyWith({
    GakujoCalendarImportMethod? method,
    GakujoCalendarTermSource? termSource,
    GakujoCalendarTermTarget? termTarget,
    bool? includeNoClassDates,
    String? calendarTitle,
    bool? applyClassChanges,
    bool? includeAssignmentDeadlines,
  }) {
    return GakujoCalendarImportSettings(
      method: method ?? this.method,
      termSource: termSource ?? this.termSource,
      termTarget: termTarget ?? this.termTarget,
      includeNoClassDates: includeNoClassDates ?? this.includeNoClassDates,
      calendarTitle: calendarTitle ?? this.calendarTitle,
      applyClassChanges: applyClassChanges ?? this.applyClassChanges,
      includeAssignmentDeadlines:
          includeAssignmentDeadlines ?? this.includeAssignmentDeadlines,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'method': method.storageValue,
      'termSource': termSource.storageValue,
      'termTarget': termTarget.storageValue,
      'includeNoClassDates': includeNoClassDates,
      'calendarTitle': effectiveCalendarTitle,
      'applyClassChanges': applyClassChanges,
      'includeAssignmentDeadlines': includeAssignmentDeadlines,
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
      applyClassChanges: raw['applyClassChanges'] != false,
      includeAssignmentDeadlines: raw['includeAssignmentDeadlines'] != false,
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
      GakujoFeatureFlag.messageStars => '連絡通知のスター',
      GakujoFeatureFlag.sessionExtender => 'セッション自動延長',
      GakujoFeatureFlag.loginAutofill => 'ログイン補助',
      GakujoFeatureFlag.twoFactorAutofill => '2FA自動入力',
      GakujoFeatureFlag.activityScan => '更新検知',
      GakujoFeatureFlag.deadlineScan => '提出期限抽出',
      GakujoFeatureFlag.deadlineNotifications => '提出期限のOS通知',
      GakujoFeatureFlag.reportListCache => '課題一覧の保存',
      GakujoFeatureFlag.sessionRecoveryGuide => 'セッション復帰ガイド',
      GakujoFeatureFlag.autoBackup => '自動バックアップ',
      GakujoFeatureFlag.uploadCompression => '5MB超の添付ファイルを自動圧縮',
    };
  }

  String get storageValue {
    return switch (this) {
      GakujoFeatureFlag.downloadCapture => 'download_capture',
      GakujoFeatureFlag.gpaDisplay => 'gpa_display',
      GakujoFeatureFlag.reportTools => 'report_tools',
      GakujoFeatureFlag.messageTools => 'message_tools',
      GakujoFeatureFlag.messageStars => 'message_stars',
      GakujoFeatureFlag.sessionExtender => 'session_extender',
      GakujoFeatureFlag.loginAutofill => 'login_autofill',
      GakujoFeatureFlag.twoFactorAutofill => 'two_factor_autofill',
      GakujoFeatureFlag.activityScan => 'activity_scan',
      GakujoFeatureFlag.deadlineScan => 'deadline_scan',
      GakujoFeatureFlag.deadlineNotifications => 'deadline_notifications',
      GakujoFeatureFlag.reportListCache => 'report_list_cache',
      GakujoFeatureFlag.sessionRecoveryGuide => 'session_recovery_guide',
      GakujoFeatureFlag.autoBackup => 'auto_backup',
      GakujoFeatureFlag.uploadCompression => 'upload_compression',
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

/// What an OS notification about a deadline can be about. Students choose
/// which of these reach the notification center instead of being told about
/// every dated line the app finds. 連絡通知 have their own rule,
/// [GakujoMessageNotificationSettings].
enum GakujoNotificationTopic {
  coursework,
  survey,
  other,
}

extension GakujoNotificationTopicLabels on GakujoNotificationTopic {
  String get label {
    return switch (this) {
      GakujoNotificationTopic.coursework => 'レポート・小テストの期限',
      GakujoNotificationTopic.survey => 'アンケートの回答期限',
      GakujoNotificationTopic.other => 'その他の期限（学内の手続きなど）',
    };
  }

  String get storageValue {
    return switch (this) {
      GakujoNotificationTopic.coursework => 'coursework',
      GakujoNotificationTopic.survey => 'survey',
      GakujoNotificationTopic.other => 'other',
    };
  }

  static GakujoNotificationTopic? fromStorageValue(String? value) {
    for (final topic in GakujoNotificationTopic.values) {
      if (topic.storageValue == value) {
        return topic;
      }
    }
    // Reports and quizzes were separate choices before.
    if (value == 'report' || value == 'quiz') {
      return GakujoNotificationTopic.coursework;
    }
    return null;
  }

  /// Coursework only, until the student picks otherwise.
  static const defaults = {
    GakujoNotificationTopic.coursework,
    GakujoNotificationTopic.survey,
  };

  /// A missing value means the student never chose; an empty one means they
  /// turned every topic off.
  static Set<GakujoNotificationTopic> decode(Object? raw) {
    final Iterable<Object?> values = switch (raw) {
      null => defaults,
      final String text => text.split(','),
      final Iterable<Object?> list => list,
      _ => defaults,
    };
    return {
      for (final value in values)
        if (value is GakujoNotificationTopic)
          value
        else if (fromStorageValue(value?.toString().trim()) case final topic?)
          topic,
    };
  }
}

/// How 連絡通知 reach OS notifications. Most of them are university-wide
/// announcements whose display period reads like a deadline, so they are
/// off unless the student asks for them.
enum GakujoMessageNotificationMode {
  off,
  deadlines,
  keywords,
}

extension GakujoMessageNotificationModeLabels on GakujoMessageNotificationMode {
  String get label {
    return switch (this) {
      GakujoMessageNotificationMode.off => '通知しない',
      GakujoMessageNotificationMode.deadlines => '期限が書かれたものを通知',
      GakujoMessageNotificationMode.keywords => 'キーワードを含むものだけ通知',
    };
  }

  String get storageValue {
    return switch (this) {
      GakujoMessageNotificationMode.off => 'off',
      GakujoMessageNotificationMode.deadlines => 'deadlines',
      GakujoMessageNotificationMode.keywords => 'keywords',
    };
  }

  static GakujoMessageNotificationMode fromStorageValue(String? value) {
    for (final mode in GakujoMessageNotificationMode.values) {
      if (mode.storageValue == value) {
        return mode;
      }
    }
    return GakujoMessageNotificationMode.off;
  }
}

class GakujoMessageNotificationSettings {
  const GakujoMessageNotificationSettings({
    this.mode = GakujoMessageNotificationMode.off,
    this.keywords = const [],
    this.since,
  });

  final GakujoMessageNotificationMode mode;
  final List<String> keywords;

  /// When the student last changed this rule. Messages posted before then
  /// are not notified, so a new rule does not bring a backlog of the
  /// hundreds of announcements already in the list.
  final DateTime? since;

  /// Whether a 連絡通知 whose list row reads [text] should be notified. The
  /// row starts with its 掲載日時.
  bool allows({required String text, required bool isDeadline}) {
    final since = this.since;
    final posted = RegExp(
      r'([0-9]{4})/([0-9]{1,2})/([0-9]{1,2})\s+([0-9]{1,2}):([0-9]{2})',
    ).firstMatch(text);
    if (since != null && posted != null) {
      // 掲載日時 is Japan time whatever the device's time zone is.
      final postedAt = DateTime.utc(
        int.parse(posted.group(1)!),
        int.parse(posted.group(2)!),
        int.parse(posted.group(3)!),
        int.parse(posted.group(4)!),
        int.parse(posted.group(5)!),
      ).subtract(const Duration(hours: 9));
      if (postedAt.isBefore(
        since.toUtc().subtract(const Duration(minutes: 1)),
      )) {
        return false;
      }
    }
    return switch (mode) {
      GakujoMessageNotificationMode.off => false,
      GakujoMessageNotificationMode.deadlines => isDeadline,
      GakujoMessageNotificationMode.keywords =>
        keywords.any((keyword) => text.contains(keyword)),
    };
  }

  GakujoMessageNotificationSettings copyWith({
    GakujoMessageNotificationMode? mode,
    List<String>? keywords,
    DateTime? since,
  }) {
    return GakujoMessageNotificationSettings(
      mode: mode ?? this.mode,
      keywords: keywords ?? this.keywords,
      since: since ?? this.since,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'mode': mode.storageValue,
      'keywords': normalizeMessageExcludeKeywords(keywords),
      if (since != null) 'since': since!.toUtc().toIso8601String(),
    };
  }

  /// Reads the saved rule. Before it existed, choosing 連絡通知 among the
  /// topics meant notifying their deadlines, so [legacyTopics] keeps that.
  factory GakujoMessageNotificationSettings.fromJson(
    Object? raw, {
    Object? legacyTopics,
  }) {
    var decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        decoded = null;
      }
    }
    if (decoded is Map) {
      final keywords = decoded['keywords'];
      return GakujoMessageNotificationSettings(
        mode: GakujoMessageNotificationModeLabels.fromStorageValue(
          decoded['mode']?.toString(),
        ),
        keywords: keywords is List
            ? normalizeMessageExcludeKeywords(
                keywords.map((value) => value.toString()),
              )
            : const [],
        since: DateTime.tryParse(decoded['since']?.toString() ?? ''),
      );
    }
    final legacy = switch (legacyTopics) {
      final String text => text.split(','),
      final Iterable<Object?> list => list.map((value) => '$value'),
      _ => const <String>[],
    };
    return GakujoMessageNotificationSettings(
      mode: legacy.any((value) => value.trim() == 'message')
          ? GakujoMessageNotificationMode.deadlines
          : GakujoMessageNotificationMode.off,
    );
  }
}

/// When to be reminded of an assignment that has not been handed in yet.
enum GakujoReminderOffset {
  threeDays,
  oneDay,
  threeHours,
  oneHour,
}

extension GakujoReminderOffsetLabels on GakujoReminderOffset {
  String get label {
    return switch (this) {
      GakujoReminderOffset.threeDays => '3日前',
      GakujoReminderOffset.oneDay => '1日前',
      GakujoReminderOffset.threeHours => '3時間前',
      GakujoReminderOffset.oneHour => '1時間前',
    };
  }

  Duration get before {
    return switch (this) {
      GakujoReminderOffset.threeDays => const Duration(days: 3),
      GakujoReminderOffset.oneDay => const Duration(days: 1),
      GakujoReminderOffset.threeHours => const Duration(hours: 3),
      GakujoReminderOffset.oneHour => const Duration(hours: 1),
    };
  }

  String get storageValue {
    return switch (this) {
      GakujoReminderOffset.threeDays => 'three_days',
      GakujoReminderOffset.oneDay => 'one_day',
      GakujoReminderOffset.threeHours => 'three_hours',
      GakujoReminderOffset.oneHour => 'one_hour',
    };
  }

  static GakujoReminderOffset? fromStorageValue(String? value) {
    for (final offset in GakujoReminderOffset.values) {
      if (offset.storageValue == value) {
        return offset;
      }
    }
    return null;
  }
}

/// The rest of the student's notification choices: what to leave out and
/// when to be reminded.
class GakujoNotificationPreferences {
  const GakujoNotificationPreferences({
    this.skipSubmitted = true,
    this.mutedCourses = const {},
    this.reminderOffsets = defaultReminderOffsets,
  });

  static const defaultReminderOffsets = {
    GakujoReminderOffset.oneDay,
    GakujoReminderOffset.oneHour,
  };

  /// Leave out assignments the レポート・小テスト list shows as handed in.
  final bool skipSubmitted;

  /// Courses whose deadlines and reminders are not notified.
  final Set<String> mutedCourses;

  /// Empty when reminders are off.
  final Set<GakujoReminderOffset> reminderOffsets;

  bool isMuted(String course) {
    final compact = course.replaceAll(RegExp(r'\s+'), '');
    return compact.isNotEmpty &&
        mutedCourses.any(
          (muted) => muted.replaceAll(RegExp(r'\s+'), '') == compact,
        );
  }

  GakujoNotificationPreferences copyWith({
    bool? skipSubmitted,
    Set<String>? mutedCourses,
    Set<GakujoReminderOffset>? reminderOffsets,
  }) {
    return GakujoNotificationPreferences(
      skipSubmitted: skipSubmitted ?? this.skipSubmitted,
      mutedCourses: mutedCourses ?? this.mutedCourses,
      reminderOffsets: reminderOffsets ?? this.reminderOffsets,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'skipSubmitted': skipSubmitted,
      'mutedCourses': mutedCourses.toList()..sort(),
      'reminderOffsets': [
        for (final offset in GakujoReminderOffset.values)
          if (reminderOffsets.contains(offset)) offset.storageValue,
      ],
    };
  }

  factory GakujoNotificationPreferences.fromJson(
    Object? raw, {
    Set<GakujoReminderOffset>? fallbackForUnrecognizedReminderOffsets,
  }) {
    var decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        decoded = null;
      }
    }
    if (decoded is! Map) {
      return const GakujoNotificationPreferences();
    }
    final muted = decoded['mutedCourses'];
    final offsets = decoded['reminderOffsets'];
    final recognizedOffsets = offsets is List
        ? {
            for (final value in offsets)
              if (GakujoReminderOffsetLabels.fromStorageValue(value.toString())
                  case final offset?)
                offset,
          }
        : defaultReminderOffsets;
    return GakujoNotificationPreferences(
      skipSubmitted: decoded['skipSubmitted'] != false,
      mutedCourses: muted is List
          ? {
              for (final value in muted)
                if (value.toString().trim().isNotEmpty) value.toString().trim(),
            }
          : const {},
      reminderOffsets:
          offsets is List && offsets.isNotEmpty && recognizedOffsets.isEmpty
              ? fallbackForUnrecognizedReminderOffsets ?? recognizedOffsets
              : recognizedOffsets,
    );
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
    this.notificationTopics = GakujoNotificationTopicLabels.defaults,
    this.messageNotification = const GakujoMessageNotificationSettings(),
    this.notificationPreferences = const GakujoNotificationPreferences(),
  });

  final DownloadSaveMode downloadSaveMode;
  final GakujoPageMode pageMode;
  final GakujoLoginCredentials? loginCredentials;
  final Set<GakujoFeatureFlag> disabledFeatureFlags;
  final bool setupCompleted;
  final GakujoCalendarImportSettings calendarImportSettings;
  final List<String> messageExcludeKeywords;
  final Set<GakujoNotificationTopic> notificationTopics;
  final GakujoMessageNotificationSettings messageNotification;
  final GakujoNotificationPreferences notificationPreferences;

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
    Set<GakujoNotificationTopic>? notificationTopics,
    GakujoMessageNotificationSettings? messageNotification,
    GakujoNotificationPreferences? notificationPreferences,
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
      notificationTopics: notificationTopics ?? this.notificationTopics,
      messageNotification: messageNotification ?? this.messageNotification,
      notificationPreferences:
          notificationPreferences ?? this.notificationPreferences,
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
  static const _loginCredentialsKey = 'more_better_gakujo_login_credentials_v2';
  static const _disabledFeatureFlagsKey =
      'more_better_gakujo_disabled_feature_flags';
  static const _setupCompletedKey = 'more_better_gakujo_setup_completed';
  static const _calendarImportSettingsKey =
      'more_better_gakujo_calendar_import_settings';
  static const _messageExcludeKeywordsKey =
      'more_better_gakujo_message_exclude_keywords';
  static const _notificationTopicsKey =
      'more_better_gakujo_notification_topics';
  static const _messageNotificationKey =
      'more_better_gakujo_message_notification';
  static const _notificationPreferencesKey =
      'more_better_gakujo_notification_preferences';
  static const _settingsKeys = [
    _downloadSaveModeKey,
    _pageModeKey,
    _loginIdKey,
    _loginPasswordKey,
    _loginCredentialsKey,
    _disabledFeatureFlagsKey,
    _setupCompletedKey,
    _calendarImportSettingsKey,
    _messageExcludeKeywordsKey,
    _notificationTopicsKey,
    _messageNotificationKey,
    _notificationPreferencesKey,
  ];

  final FlutterSecureStorage _secureStorage;
  final _operations = StorageOperationQueue();

  BackupStorageParticipant get backupStorage => BackupStorageParticipant(
        _operations,
        _secureStorage,
        const [
          _downloadSaveModeKey,
          _pageModeKey,
          _disabledFeatureFlagsKey,
          _setupCompletedKey,
          _calendarImportSettingsKey,
          _messageExcludeKeywordsKey,
          _notificationTopicsKey,
          _messageNotificationKey,
          _notificationPreferencesKey,
        ],
      );

  Future<GakujoAppSettings> load() {
    return _enqueue(() => _load(migrateLegacyCredentials: true));
  }

  Future<GakujoAppSettings> _load({
    bool migrateLegacyCredentials = false,
  }) async {
    final values = await _loadSettingsValues();
    final loginCredentials = await _loadLoginCredentials(
      values,
      migrateLegacyCredentials: migrateLegacyCredentials,
    );
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
      loginCredentials: loginCredentials,
      disabledFeatureFlags: disabledFeatureFlags,
      setupCompleted: values[_setupCompletedKey] == 'true',
      calendarImportSettings: GakujoCalendarImportSettings.fromJson(
        values[_calendarImportSettingsKey],
      ),
      messageExcludeKeywords: _decodeMessageExcludeKeywords(
        values[_messageExcludeKeywordsKey],
      ),
      notificationTopics: GakujoNotificationTopicLabels.decode(
        values[_notificationTopicsKey],
      ),
      messageNotification: GakujoMessageNotificationSettings.fromJson(
        values[_messageNotificationKey],
        legacyTopics: values[_notificationTopicsKey],
      ),
      notificationPreferences: GakujoNotificationPreferences.fromJson(
        values[_notificationPreferencesKey],
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
    return _enqueue(
      () => _secureStorage.write(
        key: _downloadSaveModeKey,
        value: mode.storageValue,
      ),
    );
  }

  Future<void> savePageMode(GakujoPageMode mode) {
    return _enqueue(
      () => _secureStorage.write(
        key: _pageModeKey,
        value: mode.storageValue,
      ),
    );
  }

  Future<void> saveFeatureEnabled(
    GakujoFeatureFlag flag, {
    required bool enabled,
  }) {
    return _enqueue(() async {
      final settings = await _load();
      final disabled = {...settings.disabledFeatureFlags};
      if (enabled) {
        disabled.remove(flag);
      } else {
        disabled.add(flag);
      }
      await _writeDisabledFeatureFlags(disabled);
    });
  }

  Future<void> saveDisabledFeatureFlags(Set<GakujoFeatureFlag> flags) {
    return _enqueue(() => _writeDisabledFeatureFlags(flags));
  }

  Future<void> _writeDisabledFeatureFlags(Set<GakujoFeatureFlag> flags) {
    return _secureStorage.write(
      key: _disabledFeatureFlagsKey,
      value: flags.map((flag) => flag.storageValue).join(','),
    );
  }

  Future<void> saveSetupCompleted(bool completed) {
    return _enqueue(
      () => _secureStorage.write(
        key: _setupCompletedKey,
        value: completed ? 'true' : 'false',
      ),
    );
  }

  Future<void> saveCalendarImportSettings(
    GakujoCalendarImportSettings settings,
  ) {
    return _enqueue(
      () => _secureStorage.write(
        key: _calendarImportSettingsKey,
        value: jsonEncode(settings.toJson()),
      ),
    );
  }

  Future<void> saveMessageExcludeKeywords(List<String> keywords) {
    return _enqueue(
      () => _secureStorage.write(
        key: _messageExcludeKeywordsKey,
        value: jsonEncode(normalizeMessageExcludeKeywords(keywords)),
      ),
    );
  }

  Future<void> saveNotificationTopics(Set<GakujoNotificationTopic> topics) {
    return _enqueue(
      () => _secureStorage.write(
        key: _notificationTopicsKey,
        value: encodeNotificationTopics(topics).join(','),
      ),
    );
  }

  Future<void> saveMessageNotification(
    GakujoMessageNotificationSettings settings,
  ) {
    return _enqueue(
      () => _secureStorage.write(
        key: _messageNotificationKey,
        value: jsonEncode(settings.toJson()),
      ),
    );
  }

  Future<void> saveNotificationPreferences(
    GakujoNotificationPreferences preferences,
  ) {
    return _enqueue(
      () => _secureStorage.write(
        key: _notificationPreferencesKey,
        value: jsonEncode(preferences.toJson()),
      ),
    );
  }

  Future<void> saveLoginCredentials({
    required String loginId,
    required String password,
  }) {
    return _enqueue(() async {
      final trimmedLoginId = loginId.trim();
      if (trimmedLoginId.isEmpty || password.isEmpty) {
        await _clearLoginCredentials();
        return;
      }

      await _secureStorage.write(
        key: _loginCredentialsKey,
        value: jsonEncode({
          'version': 1,
          'loginId': trimmedLoginId,
          'password': password,
        }),
      );
      await _deleteLegacyLoginCredentialsBestEffort();
    });
  }

  Future<void> clearLoginCredentials() {
    return _enqueue(_clearLoginCredentials);
  }

  Future<void> _clearLoginCredentials() async {
    // Keep an authoritative tombstone instead of deleting the v2 record. If a
    // legacy-key cleanup fails, subsequent loads must not reconstruct a mixed
    // or previously deleted credential pair from the remaining old key.
    await _secureStorage.write(
      key: _loginCredentialsKey,
      value: jsonEncode(const {
        'version': 1,
        'cleared': true,
      }),
    );
    await _deleteLegacyLoginCredentialsBestEffort();
  }

  Future<GakujoLoginCredentials?> _loadLoginCredentials(
    Map<String, String?> values, {
    required bool migrateLegacyCredentials,
  }) async {
    final storedRecord = values[_loginCredentialsKey];
    if (storedRecord != null) {
      return _decodeLoginCredentialsRecord(storedRecord);
    }

    final loginId = values[_loginIdKey]?.trim() ?? '';
    final password = values[_loginPasswordKey] ?? '';
    final legacyCredentials = loginId.isNotEmpty && password.isNotEmpty
        ? GakujoLoginCredentials(loginId: loginId, password: password)
        : null;
    final hasLegacyRemainder = loginId.isNotEmpty || password.isNotEmpty;

    if (migrateLegacyCredentials &&
        (legacyCredentials != null || hasLegacyRemainder)) {
      try {
        if (legacyCredentials == null) {
          await _secureStorage.write(
            key: _loginCredentialsKey,
            value: jsonEncode(const {
              'version': 1,
              'cleared': true,
            }),
          );
        } else {
          await _secureStorage.write(
            key: _loginCredentialsKey,
            value: jsonEncode({
              'version': 1,
              'loginId': legacyCredentials.loginId,
              'password': legacyCredentials.password,
            }),
          );
        }
        await _deleteLegacyLoginCredentialsBestEffort();
      } on Object {
        // The complete legacy pair remains authoritative until a later load
        // can persist the single-record format successfully.
      }
    }

    return legacyCredentials;
  }

  GakujoLoginCredentials? _decodeLoginCredentialsRecord(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      return null;
    }
    if (decoded['cleared'] == true) {
      return null;
    }

    final loginId = decoded['loginId'] is String
        ? (decoded['loginId'] as String).trim()
        : '';
    final password =
        decoded['password'] is String ? decoded['password'] as String : '';
    if (loginId.isEmpty || password.isEmpty) {
      return null;
    }
    return GakujoLoginCredentials(loginId: loginId, password: password);
  }

  Future<void> _deleteLegacyLoginCredentialsBestEffort() async {
    for (final key in const [_loginIdKey, _loginPasswordKey]) {
      try {
        await _secureStorage.delete(key: key);
      } on Object {
        // The v2 record/tombstone is authoritative, so a stale legacy key can
        // never be combined with it. Retry cleanup on a future save or clear.
      }
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    return _operations.run(operation);
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

/// Storage form of [GakujoNotificationTopic]s, in a stable order.
List<String> encodeNotificationTopics(
    Iterable<GakujoNotificationTopic> topics) {
  final chosen = topics.toSet();
  return [
    for (final topic in GakujoNotificationTopic.values)
      if (chosen.contains(topic)) topic.storageValue,
  ];
}
