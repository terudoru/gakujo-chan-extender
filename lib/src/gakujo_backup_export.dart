import 'gakujo_activity_store.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_download_history_store.dart';

Map<String, Object?> buildGakujoBackupPayload({
  required GakujoAppSettings appSettings,
  required Iterable<GakujoDownloadHistoryEntry> downloadHistory,
  required Iterable<GakujoFailedDownloadEntry> failedDownloads,
  required Iterable<GakujoFavoritePage> favorites,
  required Iterable<GakujoDeadlineEntry> deadlines,
  required Iterable<GakujoActivityChangeEntry> changes,
  required Iterable<GakujoCachedReportList> reportLists,
  DateTime? createdAt,
}) {
  return {
    'version': 2,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
    'downloadSaveMode': appSettings.downloadSaveMode.storageValue,
    'pageMode': appSettings.pageMode.storageValue,
    'setupCompleted': appSettings.setupCompleted,
    'calendarImportSettings': appSettings.calendarImportSettings.toJson(),
    'messageExcludeKeywords': appSettings.messageExcludeKeywords,
    'disabledFeatureFlags': appSettings.disabledFeatureFlags
        .map((flag) => flag.storageValue)
        .toList(),
    'downloadHistory': downloadHistory.map((entry) => entry.toJson()).toList(),
    'failedDownloads':
        failedDownloads.map((entry) => entry.toExternalJson()).toList(),
    'favorites': favorites.map((entry) => entry.toJson()).toList(),
    'deadlines': deadlines.map((entry) => entry.toJson()).toList(),
    'changes': changes.map((entry) => entry.toJson()).toList(),
    'reportLists': reportLists.map((entry) => entry.toJson()).toList(),
  };
}
