import 'dart:convert';

import 'gakujo_activity_store.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_download_history_store.dart';

const supportedGakujoBackupVersions = {2};

class GakujoBackupImportException implements FormatException {
  const GakujoBackupImportException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => message;
}

class GakujoBackupImport {
  const GakujoBackupImport({
    required this.version,
    this.downloadSaveMode,
    this.pageMode,
    this.setupCompleted,
    this.calendarImportSettings,
    this.messageExcludeKeywords,
    this.notificationTopics,
    this.messageNotification,
    this.notificationPreferences,
    this.disabledFeatureFlags,
    this.downloadHistory,
    this.failedDownloads,
    this.favorites,
    this.starredMessages,
    this.deadlines,
    this.notifiedDeadlineKeys,
    this.changes,
    this.reportLists,
  });

  final int version;
  final DownloadSaveMode? downloadSaveMode;
  final GakujoPageMode? pageMode;
  final bool? setupCompleted;
  final GakujoCalendarImportSettings? calendarImportSettings;
  final List<String>? messageExcludeKeywords;
  final Set<GakujoNotificationTopic>? notificationTopics;
  final GakujoMessageNotificationSettings? messageNotification;
  final GakujoNotificationPreferences? notificationPreferences;
  final Set<GakujoFeatureFlag>? disabledFeatureFlags;
  final List<GakujoDownloadHistoryEntry>? downloadHistory;
  final List<GakujoFailedDownloadEntry>? failedDownloads;
  final List<GakujoFavoritePage>? favorites;
  final List<GakujoStarredMessage>? starredMessages;
  final List<GakujoDeadlineEntry>? deadlines;
  final List<String>? notifiedDeadlineKeys;
  final List<GakujoActivityChangeEntry>? changes;
  final List<GakujoCachedReportList>? reportLists;
}

GakujoBackupImport parseGakujoBackup(
  String text, {
  Set<GakujoReminderOffset> currentReminderOffsets =
      GakujoNotificationPreferences.defaultReminderOffsets,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const GakujoBackupImportException(
      'バックアップJSONの形式が正しくありません',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const GakujoBackupImportException(
      'バックアップJSONはオブジェクトである必要があります',
    );
  }

  if (!decoded.containsKey('version')) {
    throw const GakujoBackupImportException(
      'バックアップのバージョン情報がありません',
    );
  }
  final version = decoded['version'];
  if (version is! int || !supportedGakujoBackupVersions.contains(version)) {
    throw GakujoBackupImportException(
      'このバックアップのバージョン（$version）には対応していません',
    );
  }

  final Map<String, dynamic> settings = decoded;
  void validateSetting(String key, bool Function(Object?) accepts) {
    if (settings.containsKey(key) && !accepts(settings[key])) {
      throw GakujoBackupImportException('バックアップの「$key」に不正な値があります');
    }
  }

  validateSetting(
      'downloadSaveMode',
      (value) =>
          DownloadSaveMode.values.any((mode) => mode.storageValue == value));
  validateSetting(
      'pageMode',
      (value) =>
          GakujoPageMode.values.any((mode) => mode.storageValue == value));
  validateSetting('setupCompleted', (value) => value is bool);
  if (decoded['notificationTopics'] is List) {
    validateGakujoBackupCollection(
      'notificationTopics',
      _decodeList(decoded, 'notificationTopics', (value) {
        final name = value.toString().trim();
        return name == 'message'
            ? name
            : GakujoNotificationTopicLabels.fromStorageValue(name)
                ?.storageValue;
      }),
    );
  }

  return GakujoBackupImport(
    version: version,
    downloadSaveMode: decoded.containsKey('downloadSaveMode')
        ? DownloadSaveModeLabels.fromStorageValue(
            decoded['downloadSaveMode']?.toString(),
          )
        : null,
    pageMode: decoded.containsKey('pageMode')
        ? GakujoPageModeLabels.fromStorageValue(
            decoded['pageMode']?.toString(),
          )
        : null,
    setupCompleted: decoded['setupCompleted'] is bool
        ? decoded['setupCompleted'] as bool
        : null,
    calendarImportSettings: decoded.containsKey('calendarImportSettings')
        ? _decodeCalendarImportSettings(
            decoded['calendarImportSettings'],
          )
        : null,
    messageExcludeKeywords: decoded.containsKey('messageExcludeKeywords')
        ? normalizeMessageExcludeKeywords(
            validateGakujoBackupCollection(
              'messageExcludeKeywords',
              _decodeList(
                decoded,
                'messageExcludeKeywords',
                (value) => value.toString(),
              ),
            )!,
          )
        : null,
    notificationTopics: decoded['notificationTopics'] is List
        ? Set.unmodifiable(
            GakujoNotificationTopicLabels.decode(
              decoded['notificationTopics'],
            ),
          )
        : null,
    messageNotification: decoded['messageNotification'] is Map ||
            decoded['notificationTopics'] is List
        ? GakujoMessageNotificationSettings.fromJson(
            decoded['messageNotification'],
            legacyTopics: decoded['notificationTopics'],
          )
        : null,
    notificationPreferences: decoded['notificationPreferences'] is Map
        ? GakujoNotificationPreferences.fromJson(
            decoded['notificationPreferences'],
            fallbackReminderOffsets: currentReminderOffsets,
          )
        : null,
    disabledFeatureFlags: decoded.containsKey('disabledFeatureFlags')
        ? Set.unmodifiable(
            validateGakujoBackupCollection(
              'disabledFeatureFlags',
              _decodeList(
                decoded,
                'disabledFeatureFlags',
                (value) => GakujoFeatureFlagLabels.fromStorageValue(
                  value.toString(),
                ),
              ),
            )!
                .whereType<GakujoFeatureFlag>(),
          )
        : null,
    downloadHistory: _decodeMapList(
      decoded,
      'downloadHistory',
      GakujoDownloadHistoryEntry.fromJson,
    ),
    failedDownloads: _decodeMapList(
      decoded,
      'failedDownloads',
      GakujoFailedDownloadEntry.fromJson,
    ),
    favorites: _decodeMapList(
      decoded,
      'favorites',
      GakujoFavoritePage.fromJson,
    ),
    starredMessages: _decodeMapList(
      decoded,
      'starredMessages',
      GakujoStarredMessage.fromJson,
    ),
    deadlines: _decodeMapList(
      decoded,
      'deadlines',
      GakujoDeadlineEntry.fromJson,
    ),
    notifiedDeadlineKeys: decoded.containsKey('notifiedDeadlineKeys')
        ? validateGakujoBackupCollection(
            'notifiedDeadlineKeys',
            _decodeList(decoded, 'notifiedDeadlineKeys', (value) {
              if (value is! String) {
                throw const GakujoBackupImportException(
                  'バックアップの「notifiedDeadlineKeys」に不正な項目があります',
                );
              }
              return value;
            }),
          )
        : null,
    changes: _decodeMapList(
      decoded,
      'changes',
      GakujoActivityChangeEntry.fromJson,
    ),
    reportLists: _decodeMapList(
      decoded,
      'reportLists',
      GakujoCachedReportList.fromJson,
    ),
  );
}

GakujoCalendarImportSettings _decodeCalendarImportSettings(Object? raw) {
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } on FormatException {
      throw const GakujoBackupImportException(
        'バックアップの「calendarImportSettings」に不正な値があります',
      );
    }
  }
  if (raw is! Map<String, dynamic>) {
    throw const GakujoBackupImportException(
      'バックアップの「calendarImportSettings」はオブジェクトである必要があります',
    );
  }
  return GakujoCalendarImportSettings.fromJson(raw);
}

List<T>? _decodeMapList<T>(
  Map<String, dynamic> decoded,
  String key,
  T Function(Map<dynamic, dynamic>) fromJson,
) {
  if (!decoded.containsKey(key)) {
    return null;
  }
  return validateGakujoBackupCollection(
    key,
    _decodeList(decoded, key, (value) {
      if (value is! Map<dynamic, dynamic>) {
        throw GakujoBackupImportException(
          'バックアップの「$key」に不正な項目があります',
        );
      }
      try {
        return fromJson(value);
      } on FormatException catch (error) {
        throw GakujoBackupImportException('バックアップの「$key」: ${error.message}');
      } on Object {
        throw GakujoBackupImportException(
          'バックアップの「$key」に不正な項目があります',
        );
      }
    }),
  );
}

/// A non-empty unreadable collection must never become a request to clear it.
List<T>? validateGakujoBackupCollection<T>(
  String key,
  List<T>? entries, {
  bool Function(T)? retain,
}) {
  if (entries == null) {
    return null;
  }
  final valid = entries.where((entry) {
    final readable = switch (entry) {
      null => false,
      final GakujoFavoritePage value =>
        value.title.trim().isNotEmpty && value.url.trim().isNotEmpty,
      final GakujoStarredMessage value =>
        value.isValid && value.title.trim().isNotEmpty,
      final GakujoDownloadHistoryEntry value =>
        value.fileName.trim().isNotEmpty,
      final GakujoFailedDownloadEntry value =>
        value.id.trim().isNotEmpty && value.request.url.trim().isNotEmpty,
      final GakujoDeadlineEntry value => value.title.trim().isNotEmpty &&
          value.url.trim().isNotEmpty &&
          value.dueText.trim().isNotEmpty,
      final GakujoActivityChangeEntry value => value.title.trim().isNotEmpty &&
          value.url.trim().isNotEmpty &&
          value.previousHash.trim().isNotEmpty &&
          value.nextHash.trim().isNotEmpty,
      final GakujoCachedReportList value => value.title.trim().isNotEmpty &&
          value.url.trim().isNotEmpty &&
          value.items.any((item) => item.trim().isNotEmpty),
      final String value => value.trim().isNotEmpty,
      _ => true,
    };
    return readable && (retain == null || retain(entry));
  }).toList();
  if (entries.isNotEmpty && valid.isEmpty) {
    const kinds = {
      'downloadHistory': 'ダウンロード履歴',
      'failedDownloads': '失敗したダウンロード',
      'favorites': 'お気に入り',
      'starredMessages': 'スター付き連絡通知',
      'deadlines': '締切',
      'notifiedDeadlineKeys': '通知済みキー',
      'changes': '変更履歴',
      'reportLists': '課題一覧',
      'messageExcludeKeywords': '除外キーワード',
      'notificationTopics': '通知対象',
      'disabledFeatureFlags': '無効な機能',
    };
    throw GakujoBackupImportException(
      'バックアップの${kinds[key] ?? key}を読み取れませんでした',
    );
  }
  return List.unmodifiable(valid);
}

List<T> _decodeList<T>(
  Map<String, dynamic> decoded,
  String key,
  T Function(Object value) fromJson,
) {
  final value = decoded[key];
  if (value is! List<dynamic>) {
    throw GakujoBackupImportException(
      'バックアップの「$key」は配列である必要があります',
    );
  }
  final entries = <T>[];
  for (final item in value) {
    if (item == null) {
      throw GakujoBackupImportException(
        'バックアップの「$key」に不正な項目があります',
      );
    }
    entries.add(fromJson(item));
  }
  return entries;
}
