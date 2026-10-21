import 'gakujo_activity_store.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_download_history_store.dart';
import 'secure_storage_transaction.dart';

Future<Map<String, Object?>> readGakujoBackupPayload({
  required GakujoAppSettings Function() currentSettings,
  required GakujoAppSettingsStore settingsStore,
  required GakujoDownloadHistoryStore historyStore,
  required GakujoActivityStore activityStore,
}) =>
    runWithBackupStorageLocks([
      settingsStore.backupStorage,
      historyStore.backupStorage,
      activityStore.backupStorage,
    ], () async {
      final history = await historyStore.load();
      final failedDownloads = await historyStore.loadFailedDownloads();
      final favorites = await activityStore.loadFavoritesForBackup();
      final deadlines = await activityStore.loadDeadlinesForBackup();
      final changes = await activityStore.loadChangesForBackup();
      final reportLists = await activityStore.loadReportListsForBackup();
      return buildGakujoBackupPayload(
        appSettings: currentSettings(),
        downloadHistory: history,
        failedDownloads: failedDownloads,
        favorites: favorites,
        deadlines: deadlines,
        changes: changes,
        reportLists: reportLists,
      );
    });

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
    'notificationTopics':
        encodeNotificationTopics(appSettings.notificationTopics),
    'messageNotification': appSettings.messageNotification.toJson(),
    'notificationPreferences': appSettings.notificationPreferences.toJson(),
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
