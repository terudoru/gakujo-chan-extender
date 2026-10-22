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
}) =>
    runBackupStorageTransaction([
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
      if (backup.messageExcludeKeywords != null) {
        await settingsStore.saveMessageExcludeKeywords(
          backup.messageExcludeKeywords!,
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
      final downloadHistory = backup.downloadHistory;
      if (downloadHistory != null) {
        await historyStore.replaceHistory(downloadHistory);
      }
      final failedDownloads = backup.failedDownloads;
      if (failedDownloads != null) {
        await historyStore.replaceFailedDownloads(
          failedDownloads
              .where(
                (entry) => isAllowedUrl(entry.request.url),
              )
              .toList(),
        );
      }
      final favorites = backup.favorites;
      if (favorites != null) {
        await activityStore.replaceFavorites(
          favorites
              .where(
                (entry) => isAllowedNavigationUrl(entry.url),
              )
              .toList(),
        );
      }
      final starredMessages = backup.starredMessages;
      if (starredMessages != null) {
        await activityStore.replaceStarredMessages(starredMessages);
      }
      final deadlines = backup.deadlines;
      if (deadlines != null) {
        await activityStore.replaceDeadlines(
          deadlines.where((entry) => isAllowedUrl(entry.url)).toList(),
        );
      }
      final notifiedDeadlineKeys = backup.notifiedDeadlineKeys;
      if (notifiedDeadlineKeys != null) {
        await activityStore.replaceNotifiedDeadlineKeys(notifiedDeadlineKeys);
      }
      final changes = backup.changes;
      if (changes != null) {
        await activityStore.replaceChanges(
          changes.where((entry) => isAllowedUrl(entry.url)).toList(),
        );
      }
      final reportLists = backup.reportLists;
      if (reportLists != null) {
        await activityStore.replaceReportLists(
          reportLists.where((entry) => isAllowedUrl(entry.url)).toList(),
        );
      }
    });
