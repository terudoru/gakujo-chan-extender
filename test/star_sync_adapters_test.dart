import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_adapters.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
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
    await collection.applyLocal(entries);
    final result = await collection.readLocal();
    expect(collection.name, 'favorites');
    expect(collection.growOnly, isFalse);
    expect(result, hasLength(30));
    expect(result['https://example.com/34'], entries['https://example.com/34']);
    expect(result.containsKey('https://example.com/0'), isFalse);
    await collection.applyLocal(result);
    expect(await collection.readLocal(), result);
  });

  test(
    'notified deadline merge preserves local keys at the store limit',
    () async {
      final store = GakujoActivityStore();
      final collection = StarSyncNotifiedDeadlinesCollection(store);
      await store.replaceNotifiedDeadlineKeys(
        List.generate(1000, (index) => 'local-$index'),
      );
      await collection.applyLocal({'remote': true, 'local-1': true});
      final result = await collection.readLocal();
      expect(collection.name, 'notified-deadlines');
      expect(collection.growOnly, isTrue);
      expect(result, hasLength(1000));
      expect(result.keys, containsAll(List.generate(1000, (i) => 'local-$i')));
      await store.replaceNotifiedDeadlineKeys(['local']);
      await collection.applyLocal({'remote': true});
      expect(await collection.readLocal(), {'local': true, 'remote': true});
    },
  );

  test('settings forwards portable keys and ignores unknown imports', () async {
    Map<String, Object?>? applied;
    final collection = StarSyncSettingsCollection(
      read: () async => {
        'notificationTopics': ['report'],
      },
      apply: (entries) async => applied = entries,
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
    });
    expect(applied, {
      'notificationTopics': ['report'],
    });
  });

  test('report drafts passes null and entries through', () async {
    Map<String, Object?>? applied;
    final collection = StarSyncReportDraftsCollection(
      read: () async => null,
      apply: (entries) async => applied = entries,
    );
    expect(collection.name, 'report-drafts');
    expect(collection.growOnly, isFalse);
    expect(await collection.readLocal(), isNull);
    final entries = <String, Object?>{
      'key': {'savedAt': 1, 'fields': []},
    };
    await collection.applyLocal(entries);
    expect(applied, entries);
  });
}
