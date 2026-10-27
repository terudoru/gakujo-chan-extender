import 'gakujo_activity_store.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_download_history_store.dart';
import 'gakujo_external_url.dart';
import 'secure_storage_transaction.dart';

Future<Map<String, Object?>> readGakujoBackupPayload({
  required GakujoAppSettings Function() currentSettings,
  required GakujoAppSettingsStore settingsStore,
  required GakujoDownloadHistoryStore historyStore,
  required GakujoActivityStore activityStore,
  bool includeStarredMessages = true,
}) =>
    runWithBackupStorageLocks([
      settingsStore.backupStorage,
      historyStore.backupStorage,
      activityStore.backupStorage,
    ], () async {
      final history = await historyStore.load();
      final failedDownloads = await historyStore.loadFailedDownloads();
      final favorites = await activityStore.loadFavoritesForBackup();
      final starredMessages = includeStarredMessages
          ? await activityStore.loadStarredMessagesForBackup()
          : const <GakujoStarredMessage>[];
      final deadlines = await activityStore.loadDeadlinesForBackup();
      final notifiedDeadlineKeys =
          await activityStore.loadNotifiedDeadlineKeysForBackup();
      final changes = await activityStore.loadChangesForBackup();
      final reportLists = await activityStore.loadReportListsForBackup();
      return buildGakujoBackupPayload(
        appSettings: currentSettings(),
        downloadHistory: history,
        failedDownloads: failedDownloads,
        favorites: favorites,
        starredMessages: starredMessages,
        includeStarredMessages: includeStarredMessages,
        deadlines: deadlines,
        notifiedDeadlineKeys: notifiedDeadlineKeys,
        changes: changes,
        reportLists: reportLists,
      );
    });

Map<String, Object?> buildGakujoBackupPayload({
  required GakujoAppSettings appSettings,
  required Iterable<GakujoDownloadHistoryEntry> downloadHistory,
  required Iterable<GakujoFailedDownloadEntry> failedDownloads,
  required Iterable<GakujoFavoritePage> favorites,
  Iterable<GakujoStarredMessage> starredMessages = const [],
  bool includeStarredMessages = true,
  required Iterable<GakujoDeadlineEntry> deadlines,
  Iterable<String> notifiedDeadlineKeys = const [],
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
    'favorites': favorites.map((entry) => sanitizeGakujoExternalEntry(entry.toJson())).toList(),
    if (includeStarredMessages)
      'starredMessages': starredMessages.map((entry) => entry.toJson()).toList(),
    'deadlines': deadlines.map((entry) => sanitizeGakujoExternalEntry(entry.toJson())).toList(),
    'notifiedDeadlineKeys': notifiedDeadlineKeys.map(sanitizeGakujoNotificationKey).toList(),
    'changes': changes.map((entry) => sanitizeGakujoExternalEntry(entry.toJson())).toList(),
    'reportLists': reportLists.map((entry) => sanitizeGakujoExternalEntry(entry.toJson())).toList(),
  };
}
