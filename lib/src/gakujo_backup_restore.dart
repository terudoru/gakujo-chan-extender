import 'gakujo_activity_store.dart';
import 'gakujo_app_settings.dart';
import 'gakujo_backup_import.dart';
import 'gakujo_download_history_store.dart';
import 'secure_storage_transaction.dart';

Future<void> restoreGakujoBackup({
  required GakujoBackupImport backup,
  required GakujoAppSettingsStore settingsStore,
  required GakujoDownloadHistoryStore historyStore,
  required GakujoActivityStore activityStore,
  required bool Function(String) isAllowedUrl,
  required bool Function(String) isAllowedNavigationUrl,
}) async {
  // Validate every replacement before starting the transaction: even rollback
  // writes are unnecessary when the backup cannot be read.
  final messageExcludeKeywords = validateGakujoBackupCollection(
    'messageExcludeKeywords',
    backup.messageExcludeKeywords,
  );
  final downloadHistory = validateGakujoBackupCollection(
    'downloadHistory',
    backup.downloadHistory,
    retain: historyStore.retainsBackupEntry,
  );
  final failedDownloads = validateGakujoBackupCollection(
    'failedDownloads',
    backup.failedDownloads,
    retain: (entry) =>
        historyStore.retainsBackupEntry(entry) &&
        isAllowedUrl(entry.request.url),
  );
  final favorites = validateGakujoBackupCollection(
    'favorites',
    backup.favorites,
    retain: (entry) =>
        activityStore.retainsBackupEntry(entry) &&
        isAllowedNavigationUrl(entry.url),
  );
  final starredMessages = validateGakujoBackupCollection(
    'starredMessages',
    backup.starredMessages,
    retain: activityStore.retainsBackupEntry,
  );
  final deadlines = validateGakujoBackupCollection(
    'deadlines',
    backup.deadlines,
    retain: (entry) =>
        activityStore.retainsBackupEntry(entry) && isAllowedUrl(entry.url),
  );
  final notifiedDeadlineKeys = validateGakujoBackupCollection(
    'notifiedDeadlineKeys',
    backup.notifiedDeadlineKeys,
  );
  final changes = validateGakujoBackupCollection(
    'changes',
    backup.changes,
    retain: (entry) =>
        activityStore.retainsBackupEntry(entry) && isAllowedUrl(entry.url),
  );
  final reportLists = validateGakujoBackupCollection(
    'reportLists',
    backup.reportLists,
    retain: (entry) =>
        activityStore.retainsBackupEntry(entry) && isAllowedUrl(entry.url),
  );
  await runBackupStorageTransaction([
    settingsStore.backupStorage,
    historyStore.backupStorage,
    activityStore.backupStorage,
  ], () async {
    if (backup.downloadSaveMode != null) {
      await settingsStore.saveDownloadSaveMode(backup.downloadSaveMode!);
    }
    if (backup.pageMode != null) {
      await settingsStore.savePageMode(backup.pageMode!);
    }
    if (backup.disabledFeatureFlags != null) {
      await settingsStore
          .saveDisabledFeatureFlags(backup.disabledFeatureFlags!);
    }
    if (backup.setupCompleted != null) {
      await settingsStore.saveSetupCompleted(backup.setupCompleted!);
    }
    if (backup.calendarImportSettings != null) {
      await settingsStore.saveCalendarImportSettings(
        backup.calendarImportSettings!,
      );
    }
    if (messageExcludeKeywords != null) {
      await settingsStore.saveMessageExcludeKeywords(
        messageExcludeKeywords,
      );
    }
    if (backup.notificationTopics != null) {
      await settingsStore.saveNotificationTopics(backup.notificationTopics!);
    }
    if (backup.notificationPreferences != null) {
      await settingsStore.saveNotificationPreferences(
        backup.notificationPreferences!,
      );
    }
    if (backup.messageNotification != null) {
      await settingsStore.saveMessageNotification(
        backup.messageNotification!,
      );
    }
    if (downloadHistory != null) {
      await historyStore.replaceHistory(downloadHistory);
    }
    if (failedDownloads != null) {
      await historyStore.replaceFailedDownloads(failedDownloads);
    }
    if (favorites != null) {
      await activityStore.replaceFavorites(favorites);
    }
    if (starredMessages != null) {
      await activityStore.replaceStarredMessages(starredMessages);
    }
    if (deadlines != null) {
      await activityStore.replaceDeadlines(deadlines);
    }
    if (notifiedDeadlineKeys != null) {
      await activityStore.replaceNotifiedDeadlineKeys(notifiedDeadlineKeys);
    }
    if (changes != null) {
      await activityStore.replaceChanges(changes);
    }
    if (reportLists != null) {
      await activityStore.replaceReportLists(reportLists);
    }
  });
}
