import 'dart:convert';

import '../gakujo_activity_store.dart';
import '../gakujo_app_settings.dart';
import '../gakujo_backup_import.dart';
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

Map<String, Object?> exportStarSyncPortableSettings(
  GakujoAppSettings settings,
) => {
  'disabledFeatureFlags':
      settings.disabledFeatureFlags
          .where((flag) => flag != GakujoFeatureFlag.messageStars)
          .map((flag) => flag.storageValue)
          .toList()
        ..sort(),
  'calendarImportSettings': settings.calendarImportSettings.toJson(),
  'messageExcludeKeywords': settings.messageExcludeKeywords,
  'notificationTopics': encodeNotificationTopics(settings.notificationTopics),
  'messageNotification': settings.messageNotification.toJson(),
  'notificationPreferences': settings.notificationPreferences.toJson(),
};

GakujoBackupImport importStarSyncPortableSettings(
  GakujoAppSettings current,
  Map<String, Object?> incoming,
) {
  final before = exportStarSyncPortableSettings(current);
  final changed = <String, Object?>{
    for (final key in starSyncPortableSettingKeys)
      if (incoming.containsKey(key) &&
          starSyncCanonicalJson(incoming[key]) !=
              starSyncCanonicalJson(before[key]))
        key: incoming[key],
  };
  if (changed.containsKey('disabledFeatureFlags')) {
    final flags = changed['disabledFeatureFlags'];
    if (flags is! List) throw const FormatException('Invalid feature flags');
    final portableFlags = flags
        .where((value) => value != GakujoFeatureFlag.messageStars.storageValue)
        .toList();
    if (starSyncCanonicalJson(portableFlags) ==
        starSyncCanonicalJson(before['disabledFeatureFlags'])) {
      changed.remove('disabledFeatureFlags');
    } else {
      changed['disabledFeatureFlags'] = [
        ...portableFlags,
        if (current.disabledFeatureFlags.contains(
          GakujoFeatureFlag.messageStars,
        ))
          GakujoFeatureFlag.messageStars.storageValue,
      ];
    }
  }
  final parsed = parseGakujoBackup(
    jsonEncode({'version': 2, ...changed}),
    currentReminderOffsets: current.notificationPreferences.reminderOffsets,
  );
  return GakujoBackupImport(
    version: 2,
    disabledFeatureFlags: parsed.disabledFeatureFlags,
    calendarImportSettings: parsed.calendarImportSettings,
    messageExcludeKeywords: parsed.messageExcludeKeywords,
    notificationTopics: parsed.notificationTopics,
    messageNotification: changed.containsKey('messageNotification')
        ? parsed.messageNotification
        : null,
    notificationPreferences: parsed.notificationPreferences,
  );
}

class StarSyncFavoritesCollection implements StarSyncCollection {
  StarSyncFavoritesCollection(this.store, {this.onChanged});

  final GakujoActivityStore store;
  final Future<void> Function()? onChanged;

  @override
  String get name => 'favorites';
  @override
  bool get growOnly => false;
  @override
  int? get maxLive => 30;
  @override
  Comparable Function(Object?)? get order => (value) =>
      DateTime.tryParse((value as Map)['addedAt']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  @override
  Future<Map<String, Object?>> readLocal() async => {
    for (final page in await store.loadFavoritesForBackup())
      page.durableUrl: {
        'title': page.title,
        'addedAt': page.addedAt.toIso8601String(),
      },
  };

  @override
  Future<bool> applyLocal(
    Map<String, Object?> entries, {
    required Map<String, Object?> basedOn,
  }) async {
    final applied = await store.compareAndReplaceFavorites(
      [
        for (final entry in entries.entries)
          if (entry.value is Map)
            GakujoFavoritePage.fromJson({
              ...(entry.value as Map),
              'url': entry.key,
            }),
      ],
      basedOn: basedOn,
    );
    if (applied &&
        starSyncCanonicalJson(entries) != starSyncCanonicalJson(basedOn)) {
      await onChanged?.call();
    }
    return applied;
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
  int? get maxLive => 1000;
  @override
  Comparable Function(Object?)? get order => (value) =>
      DateTime.parse(value as String);

  @override
  Future<Map<String, Object?>> readLocal() async => {
    for (final entry in (await store.loadNotifiedDeadlineKeysWithTimes()).entries)
      entry.key: entry.value.toUtc().toIso8601String(),
  };

  @override
  Future<bool> applyLocal(
    Map<String, Object?> entries, {
    required Map<String, Object?> basedOn,
  }) => store.compareAndReplaceNotifiedDeadlineKeysWithTimes(
    {
      for (final entry in entries.entries)
        entry.key: DateTime.parse(entry.value as String),
    },
    basedOn: basedOn,
  );
}

class StarSyncSettingsCollection implements StarSyncCollection {
  StarSyncSettingsCollection({required this.read, required this.apply});

  final Future<Map<String, Object?>> Function() read;
  final Future<bool> Function(
    Map<String, Object?>, {
    required Map<String, Object?> basedOn,
  }) apply;

  @override
  String get name => 'settings';
  @override
  bool get growOnly => false;
  @override
  int? get maxLive => null;
  @override
  Comparable Function(Object?)? get order => null;

  @override
  Future<Map<String, Object?>> readLocal() => read();

  @override
  Future<bool> applyLocal(
    Map<String, Object?> entries, {
    required Map<String, Object?> basedOn,
  }) => apply({
    for (final key in starSyncPortableSettingKeys)
      if (entries.containsKey(key)) key: entries[key],
  }, basedOn: basedOn);
}

class StarSyncReportDraftsCollection implements StarSyncCollection {
  StarSyncReportDraftsCollection({required this.read, required this.apply});

  final Future<Map<String, Object?>?> Function() read;
  final Future<bool> Function(
    Map<String, Object?>, {
    required Map<String, Object?> basedOn,
  }) apply;

  @override
  String get name => 'report-drafts';
  @override
  bool get growOnly => false;
  @override
  int? get maxLive => null;
  @override
  Comparable Function(Object?)? get order => null;

  @override
  Future<Map<String, Object?>?> readLocal() => read();

  @override
  Future<bool> applyLocal(
    Map<String, Object?> entries, {
    required Map<String, Object?> basedOn,
  }) => apply(entries, basedOn: basedOn);
}
