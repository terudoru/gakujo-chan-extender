import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';

void main() {
  final strictReadCases = <({
    String key,
    Future<Object?> Function(GakujoActivityStore) loadBestEffort,
    Future<Object?> Function(GakujoActivityStore) loadForBackup,
  })>[
    (
      key: 'more_better_gakujo_deadlines',
      loadBestEffort: (store) => store.loadDeadlines(),
      loadForBackup: (store) => store.loadDeadlinesForBackup(),
    ),
    (
      key: 'more_better_gakujo_favorites',
      loadBestEffort: (store) => store.loadFavorites(),
      loadForBackup: (store) => store.loadFavoritesForBackup(),
    ),
    (
      key: 'more_better_gakujo_activity_changes',
      loadBestEffort: (store) => store.loadChanges(),
      loadForBackup: (store) => store.loadChangesForBackup(),
    ),
    (
      key: 'more_better_gakujo_cached_report_lists',
      loadBestEffort: (store) => store.loadReportLists(),
      loadForBackup: (store) => store.loadReportListsForBackup(),
    ),
  ];

  for (final readCase in strictReadCases) {
    test('backup read throws for ${readCase.key} while normal load is tolerant',
        () async {
      final storage = _MemorySecureStorage(failingReadKey: readCase.key);
      final store = GakujoActivityStore(secureStorage: storage);

      expect(await readCase.loadBestEffort(store), isEmpty);
      await expectLater(
        readCase.loadForBackup(store),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains(readCase.key),
          ),
        ),
      );
    });
  }

  test('backup reads match normal loads and re-enter the storage queue',
      () async {
    final now = DateTime.now();
    final storage = _MemorySecureStorage(values: {
      'more_better_gakujo_deadlines': jsonEncode([
        {
          'title': 'Report',
          'url': 'https://example.test/report',
          'dueText': '2099/07/01 17:00',
          'detectedAt': now.toIso8601String(),
          'kind': 'deadline',
        },
      ]),
      'more_better_gakujo_favorites': jsonEncode([
        {
          'title': 'Favorite',
          'url': 'https://example.test/favorite',
          'addedAt': now.toIso8601String(),
        },
      ]),
      'more_better_gakujo_activity_changes': jsonEncode([
        {
          'category': 'Notices',
          'title': 'Changed notice',
          'url': 'https://example.test/change',
          'changedAt': now.toIso8601String(),
          'previousHash': 'before',
          'nextHash': 'after',
        },
      ]),
      'more_better_gakujo_cached_report_lists': jsonEncode([
        {
          'title': 'Reports',
          'url': 'https://example.test/reports',
          'capturedAt': now.toIso8601String(),
          'items': ['Report 1'],
        },
      ]),
    });
    final store = GakujoActivityStore(secureStorage: storage);
    final expectedDeadlines = await store.loadDeadlines();
    final expectedFavorites = await store.loadFavorites();
    final expectedChanges = await store.loadChanges();
    final expectedReportLists = await store.loadReportLists();

    final actual = await store.backupStorage.queue.runExclusive(() async {
      return (
        deadlines: await store.loadDeadlinesForBackup(),
        favorites: await store.loadFavoritesForBackup(),
        changes: await store.loadChangesForBackup(),
        reportLists: await store.loadReportListsForBackup(),
      );
    }).timeout(const Duration(seconds: 1));

    expect(
      actual.deadlines.map((entry) => entry.toJson()).toList(),
      expectedDeadlines.map((entry) => entry.toJson()).toList(),
    );
    expect(
      actual.favorites.map((entry) => entry.toJson()).toList(),
      expectedFavorites.map((entry) => entry.toJson()).toList(),
    );
    expect(
      actual.changes.map((entry) => entry.toJson()).toList(),
      expectedChanges.map((entry) => entry.toJson()).toList(),
    );
    expect(
      actual.reportLists.map((entry) => entry.toJson()).toList(),
      expectedReportLists.map((entry) => entry.toJson()).toList(),
    );
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage({
    Map<String, String>? values,
    this.failingReadKey,
  }) : values = Map<String, String>.from(values ?? const {});

  final Map<String, String> values;
  final String? failingReadKey;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key == failingReadKey) {
      throw StateError('read failed for $key');
    }
    return values[key];
  }
}
