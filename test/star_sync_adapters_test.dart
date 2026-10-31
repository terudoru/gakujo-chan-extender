import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_adapters.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('portable settings ignore credentials and non-portable fields', () {
    final current = GakujoAppSettings(
      loginCredentials: const GakujoLoginCredentials(
        loginId: 'id',
        password: 'secret',
      ),
      disabledFeatureFlags: {GakujoFeatureFlag.messageStars},
    );
    final exported = exportStarSyncPortableSettings(current);
    expect(exported.keys, isNot(contains('loginCredentials')));
    expect(
      exported['disabledFeatureFlags'],
      isNot(contains(GakujoFeatureFlag.messageStars.storageValue)),
    );
    final imported = importStarSyncPortableSettings(current, {
      'loginCredentials': {'loginId': 'other', 'password': 'other'},
      'downloadSaveMode': 'other',
      'pageMode': 'other',
      'disabledFeatureFlags': [],
      'messageExcludeKeywords': ['exam'],
    });
    expect(imported.downloadSaveMode, isNull);
    expect(imported.pageMode, isNull);
    expect(imported.disabledFeatureFlags, isNull);
    expect(imported.messageExcludeKeywords, ['exam']);
    expect(current.loginCredentials!.password, 'secret');
  });

  test('favorites round trip and retain the store limit', () async {
    final store = GakujoActivityStore();
    final collection = StarSyncFavoritesCollection(store);
    final entries = <String, Object?>{
      for (var i = 0; i < 35; i++)
        'https://example.com/$i': {
          'title': 'Page $i',
          'addedAt': DateTime.utc(2026, 1, 1, 0, i).toIso8601String(),
        },
    };
    await collection.applyLocal(
      entries,
      basedOn: await collection.readLocal(),
    );
    final result = await collection.readLocal();
    expect(collection.name, 'favorites');
    expect(collection.growOnly, isFalse);
    expect(result, hasLength(30));
    expect(result['https://example.com/34'], entries['https://example.com/34']);
    expect(result.containsKey('https://example.com/0'), isFalse);
    await collection.applyLocal(result, basedOn: result);
    expect(await collection.readLocal(), result);
  });

  test('notified keys retain newer incoming entries at capacity', () async {
    final store = GakujoActivityStore();
    final collection = StarSyncNotifiedDeadlinesCollection(store);
    final base = DateTime.utc(2026);
    await store.mergeNotifiedDeadlineKeysWithTimes({
      for (var i = 0; i < 1000; i++) 'local-$i': base.add(Duration(seconds: i)),
    });
    await store.mergeNotifiedDeadlineKeysWithTimes({
      'remote': base.add(const Duration(seconds: 2000)),
      'older': base.subtract(const Duration(seconds: 1)),
    });
    final result = await collection.readLocal();
    expect(result, hasLength(1000));
    expect(result, contains('remote'));
    expect(result, isNot(contains('older')));
    expect(result, isNot(contains('local-0')));
    final snapshot = Map<String, Object?>.of(result);
    await store.addNotifiedDeadlineKeys(['concurrent']);
    expect(await collection.applyLocal(snapshot, basedOn: snapshot), isFalse);
  });

  test('favorites reject a stale snapshot', () async {
    final store = GakujoActivityStore();
    final collection = StarSyncFavoritesCollection(store);
    final snapshot = await collection.readLocal();
    await store.addFavorite(GakujoFavoritePage(
      title: 'Concurrent', url: 'https://example.com/new', addedAt: DateTime.utc(2026),
    ));
    expect(await collection.applyLocal({}, basedOn: snapshot), isFalse);
    expect((await collection.readLocal()).keys, contains('https://example.com/new'));
  });

  test('settings forwards portable keys and ignores unknown imports', () async {
    Map<String, Object?>? applied;
    final collection = StarSyncSettingsCollection(
      read: () async => {
        'notificationTopics': ['report'],
      },
      apply: (entries, {required basedOn}) async { applied = entries; return true; },
    );
    expect(collection.name, 'settings');
    expect(collection.growOnly, isFalse);
    expect(await collection.readLocal(), {
      'notificationTopics': ['report'],
    });
    await collection.applyLocal({
      'notificationTopics': ['report'],
      'password': 'secret',
      'unknown': true,
    }, basedOn: const {});
    expect(applied, {
      'notificationTopics': ['report'],
    });
  });

  test('report drafts passes null and entries through', () async {
    Map<String, Object?>? applied;
    final collection = StarSyncReportDraftsCollection(
      read: () async => null,
      apply: (entries, {required basedOn}) async { applied = entries; return true; },
    );
    expect(collection.name, 'report-drafts');
    expect(collection.growOnly, isFalse);
    expect(await collection.readLocal(), isNull);
    final entries = <String, Object?>{
      'key': {'savedAt': 1, 'fields': []},
    };
    await collection.applyLocal(entries, basedOn: await collection.readLocal() ?? {});
    expect(applied, entries);
  });
}
