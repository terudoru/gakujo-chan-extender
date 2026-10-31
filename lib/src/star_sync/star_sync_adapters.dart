import '../gakujo_activity_store.dart';
import 'star_sync_collections.dart';

// The exporter must exclude messageStars from disabledFeatureFlags. Credentials,
// 2FA secrets, download paths and save mode, and page mode are not portable.
const starSyncPortableSettingKeys = <String>[
  'disabledFeatureFlags',
  'calendarImportSettings',
  'messageExcludeKeywords',
  'notificationTopics',
  'messageNotification',
  'notificationPreferences',
];

class StarSyncFavoritesCollection implements StarSyncCollection {
  StarSyncFavoritesCollection(this.store);

  final GakujoActivityStore store;

  @override
  String get name => 'favorites';
  @override
  bool get growOnly => false;

  @override
  Future<Map<String, Object?>> readLocal() async => {
    for (final page in await store.loadFavoritesForBackup())
      page.durableUrl: {
        'title': page.title,
        'addedAt': page.addedAt.toIso8601String(),
      },
  };

  @override
  Future<void> applyLocal(Map<String, Object?> entries) {
    return store.replaceFavorites([
      for (final entry in entries.entries)
        if (entry.value is Map)
          GakujoFavoritePage.fromJson({
            ...(entry.value as Map),
            'url': entry.key,
          }),
    ]);
  }
}

class StarSyncNotifiedDeadlinesCollection implements StarSyncCollection {
  StarSyncNotifiedDeadlinesCollection(this.store);

  final GakujoActivityStore store;

  @override
  String get name => 'notified-deadlines';
  @override
  bool get growOnly => true;

  @override
  Future<Map<String, Object?>> readLocal() async => {
    for (final key in await store.loadNotifiedDeadlineKeysForBackup())
      key: true,
  };

  @override
  Future<void> applyLocal(Map<String, Object?> entries) async {
    final local = await store.loadNotifiedDeadlineKeysForBackup();
    await store.replaceNotifiedDeadlineKeys({
      ...entries.keys.where((key) => !local.contains(key)),
      ...local,
    });
  }
}

class StarSyncSettingsCollection implements StarSyncCollection {
  StarSyncSettingsCollection({required this.read, required this.apply});

  final Future<Map<String, Object?>> Function() read;
  final Future<void> Function(Map<String, Object?>) apply;

  @override
  String get name => 'settings';
  @override
  bool get growOnly => false;

  @override
  Future<Map<String, Object?>> readLocal() => read();

  @override
  Future<void> applyLocal(Map<String, Object?> entries) => apply({
    for (final key in starSyncPortableSettingKeys)
      if (entries.containsKey(key)) key: entries[key],
  });
}

class StarSyncReportDraftsCollection implements StarSyncCollection {
  StarSyncReportDraftsCollection({required this.read, required this.apply});

  final Future<Map<String, Object?>?> Function() read;
  final Future<void> Function(Map<String, Object?>) apply;

  @override
  String get name => 'report-drafts';
  @override
  bool get growOnly => false;

  @override
  Future<Map<String, Object?>?> readLocal() => read();

  @override
  Future<void> applyLocal(Map<String, Object?> entries) => apply(entries);
}
