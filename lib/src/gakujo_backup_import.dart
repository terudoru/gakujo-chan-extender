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
    this.disabledFeatureFlags,
    this.downloadHistory,
    this.failedDownloads,
    this.favorites,
    this.deadlines,
    this.changes,
    this.reportLists,
  });

  final int version;
  final DownloadSaveMode? downloadSaveMode;
  final GakujoPageMode? pageMode;
  final bool? setupCompleted;
  final GakujoCalendarImportSettings? calendarImportSettings;
  final List<String>? messageExcludeKeywords;
  final Set<GakujoFeatureFlag>? disabledFeatureFlags;
  final List<GakujoDownloadHistoryEntry>? downloadHistory;
  final List<GakujoFailedDownloadEntry>? failedDownloads;
  final List<GakujoFavoritePage>? favorites;
  final List<GakujoDeadlineEntry>? deadlines;
  final List<GakujoActivityChangeEntry>? changes;
  final List<GakujoCachedReportList>? reportLists;
}

GakujoBackupImport parseGakujoBackup(String text) {
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
        ? GakujoCalendarImportSettings.fromJson(
            decoded['calendarImportSettings'],
          )
        : null,
    messageExcludeKeywords: decoded.containsKey('messageExcludeKeywords')
        ? normalizeMessageExcludeKeywords(
            _decodeList(
              decoded,
              'messageExcludeKeywords',
              (value) => value.toString(),
            ),
          )
        : null,
    disabledFeatureFlags: decoded.containsKey('disabledFeatureFlags')
        ? Set.unmodifiable(
            _decodeList(
              decoded,
              'disabledFeatureFlags',
              (value) => GakujoFeatureFlagLabels.fromStorageValue(
                value.toString(),
              ),
            ).whereType<GakujoFeatureFlag>(),
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
    deadlines: _decodeMapList(
      decoded,
      'deadlines',
      GakujoDeadlineEntry.fromJson,
    ),
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

List<T>? _decodeMapList<T>(
  Map<String, dynamic> decoded,
  String key,
  T Function(Map<dynamic, dynamic>) fromJson,
) {
  if (!decoded.containsKey(key)) {
    return null;
  }
  return List.unmodifiable(
    _decodeList(decoded, key, (value) {
      if (value is! Map<dynamic, dynamic>) {
        throw GakujoBackupImportException(
          'バックアップの「$key」に不正な項目があります',
        );
      }
      try {
        return fromJson(value);
      } on Object {
        throw GakujoBackupImportException(
          'バックアップの「$key」に不正な項目があります',
        );
      }
    }),
  );
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
      continue;
    }
    entries.add(fromJson(item));
  }
  return entries;
}
