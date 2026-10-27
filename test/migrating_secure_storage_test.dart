import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/bundled_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/migrating_secure_storage.dart';

void main() {
  test('read prefers primary values', () async {
    final primary = _MemorySecureStorage({'token': 'primary'});
    final fallback = _MemorySecureStorage({'token': 'fallback'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(await storage.read(key: 'token'), 'primary');
    expect(primary.values['token'], 'primary');
    expect(fallback.values['token'], 'fallback');
  });

  for (final operation in ['read', 'readKeys', 'readAll']) {
    testWidgets('$operation waits past three seconds with a longer timeout',
        (tester) async {
      final primary = _MemorySecureStorage({'token': 'primary'})
        ..readDelay = const Duration(seconds: 4)
        ..readAllDelay = const Duration(seconds: 4);
      final fallback = _MemorySecureStorage({'token': 'fallback'});
      final storage = MigratingSecureStorage(
        primary: primary,
        fallback: fallback,
        operationTimeout: const Duration(minutes: 2),
      );

      final read = switch (operation) {
        'read' => storage.read(key: 'token'),
        'readKeys' => storage.readKeys(['token']),
        _ => storage.readAll(),
      };
      final result = expectLater(
        read,
        completion(operation == 'read' ? 'primary' : {'token': 'primary'}),
      );
      await tester.pump(const Duration(seconds: 4));
      await result;

      expect(fallback.readKeys, isEmpty);
      expect(fallback.readAllCount, 0);
    });
  }

  test('read migrates fallback values into primary storage', () async {
    final primary = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({'token': 'fallback'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(await storage.read(key: 'token'), 'fallback');
    expect(primary.values['token'], 'fallback');
    expect(fallback.values.containsKey('token'), isFalse);
  });

  test('read migrates values through layered fallback stores', () async {
    final primary = _MemorySecureStorage();
    final middle = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({'token': 'legacy'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: MigratingSecureStorage(
        primary: middle,
        fallback: fallback,
      ),
    );

    expect(await storage.read(key: 'token'), 'legacy');
    expect(primary.values['token'], 'legacy');
    expect(middle.values.containsKey('token'), isFalse);
    expect(fallback.values.containsKey('token'), isFalse);
  });

  test('readKeys avoids fallback stores when primary has requested keys',
      () async {
    final primary = _MemorySecureStorage({
      'login': 'student',
      'password': 'secret',
    });
    final fallback = _MemorySecureStorage({
      'login': 'old',
      'password': 'old-secret',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    final values = await storage.readKeys(['login', 'password']);

    expect(values, {'login': 'student', 'password': 'secret'});
    expect(primary.readAllCount, 0);
    expect(primary.readKeys, ['login', 'password']);
    expect(fallback.readAllCount, 0);
    expect(fallback.readKeys, isEmpty);
  });

  test('readKeys does not depend on primary readAll', () async {
    final primary = _MemorySecureStorage({
      'login': 'student',
      'password': 'secret',
    })
      ..readAllError = StateError('readAll unavailable');
    final fallback = _MemorySecureStorage({
      'login': 'old',
      'password': 'old-secret',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    final values = await storage.readKeys(['login', 'password']);

    expect(values, {'login': 'student', 'password': 'secret'});
    expect(primary.readAllCount, 0);
    expect(fallback.readAllCount, 0);
    expect(fallback.readKeys, isEmpty);
  });

  test('readKeys treats missing keys as unset when primary has values',
      () async {
    final primary = _MemorySecureStorage({'login': 'student'});
    final fallback = _MemorySecureStorage({
      'login': 'old',
      'password': 'legacy-secret',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    final values = await storage.readKeys(['login', 'password']);

    expect(values, {'login': 'student', 'password': null});
    expect(primary.values, {'login': 'student'});
    expect(fallback.values, {'login': 'old', 'password': 'legacy-secret'});
    expect(fallback.readKeys, isEmpty);
  });

  test('readKeys migrates missing keys when primary is empty', () async {
    final primary = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({
      'login': 'old',
      'password': 'legacy-secret',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    final values = await storage.readKeys(['login', 'password']);

    expect(values, {'login': 'old', 'password': 'legacy-secret'});
    expect(primary.values, {'login': 'old', 'password': 'legacy-secret'});
    expect(fallback.values, isEmpty);
    expect(fallback.readKeys, ['login', 'password']);
  });

  test('readKeys falls back when the primary batch times out', () async {
    final primary = _MemorySecureStorage({'login': 'student'})
      ..readDelay = const Duration(seconds: 4);
    final fallback = _MemorySecureStorage({
      'login': 'legacy-student',
      'password': 'legacy-secret',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    final values = await storage.readKeys(['login', 'password']);

    expect(values, {'login': 'legacy-student', 'password': 'legacy-secret'});
    expect(fallback.readKeys, ['login', 'password']);
    expect(primary.values, {'login': 'student'});
  });

  test('readKeys rethrows timeout when fallback has no requested values',
      () async {
    final primary = _MemorySecureStorage()
      ..readDelay = const Duration(seconds: 4);
    final fallback = _MemorySecureStorage();
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(
      storage.readKeys(['login', 'password']),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('readKeys fails fast after a migration sweep times out', () async {
    final primary = _MemorySecureStorage({'login': 'student'})
      ..readDelay = const Duration(milliseconds: 300);
    final fallback = _MemorySecureStorage({'password': 'legacy-secret'})
      ..readDelay = const Duration(milliseconds: 300);
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: 'migration-completed',
      operationTimeout: const Duration(milliseconds: 100),
    );
    final watch = Stopwatch()..start();

    await expectLater(
      storage.readKeys(['login', 'password']),
      throwsA(isA<TimeoutException>()),
    );

    // One sweep timeout, not another wait for the primary and fallback reads.
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 250)));
    expect(fallback.readKeys, isEmpty);
  });

  test('readAll avoids fallback when primary has values', () async {
    final primary = _MemorySecureStorage({'token': 'primary'});
    final fallback = _MemorySecureStorage({
      'token': 'fallback',
      'legacy': 'migrated',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(await storage.readAll(), {'token': 'primary'});
    expect(primary.values, {'token': 'primary'});
    expect(fallback.values, {'token': 'fallback', 'legacy': 'migrated'});
    expect(fallback.readAllCount, 0);
  });

  test('readAll migrates fallback when primary is empty', () async {
    final primary = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({'legacy': 'migrated'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(await storage.readAll(), {'legacy': 'migrated'});
    expect(primary.values, {'legacy': 'migrated'});
    expect(fallback.values, isEmpty);
    expect(fallback.readAllCount, 1);
  });

  test('read avoids fallback for missing key when primary has values',
      () async {
    final primary = _MemorySecureStorage({'login': 'student'});
    final fallback = _MemorySecureStorage({'password': 'legacy-secret'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(await storage.read(key: 'password'), isNull);
    expect(fallback.readKeys, isEmpty);
    expect(fallback.readAllCount, 0);
  });

  test('migration marker sweeps missing fallback values into primary',
      () async {
    const markerKey = 'migration-completed';
    final primary = _MemorySecureStorage({'setting': 'configured'});
    final fallback = _MemorySecureStorage({
      'setting': 'legacy-setting',
      'two-factor-secret': 'legacy',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
    );

    expect(await storage.read(key: 'two-factor-secret'), 'legacy');
    expect(primary.values, {
      'setting': 'configured',
      'two-factor-secret': 'legacy',
      markerKey: '1',
    });
    expect(fallback.values, {'setting': 'legacy-setting'});
    expect(fallback.readAllCount, 1);
  });

  test('keyed sweep reads only missing keys and writes the marker last',
      () async {
    const markerKey = 'migration-completed';
    final primary = _MemorySecureStorage({'setting': 'configured'});
    final fallback = _MemorySecureStorage({
      'setting': 'stale',
      'two-factor-secret': 'legacy',
      'unrelated': 'other-app',
    });
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
      migrationKeys: ['setting', 'two-factor-secret', 'missing'],
    );

    expect(await storage.read(key: 'two-factor-secret'), 'legacy');
    expect(primary.values, {
      'setting': 'configured',
      'two-factor-secret': 'legacy',
      markerKey: '1',
    });
    expect(primary.readAllCount, 1);
    expect(primary.writeKeys, ['two-factor-secret', markerKey]);
    expect(fallback.readAllCount, 0);
    expect(fallback.readKeys, ['two-factor-secret', 'missing']);
    expect(fallback.values, {'setting': 'stale', 'unrelated': 'other-app'});

    expect(await storage.read(key: 'missing'), isNull);
    expect(fallback.readKeys, ['two-factor-secret', 'missing']);
  });

  test('keyed bundled sweep never enumerates either legacy service', () async {
    const markerKey = 'migration-completed';
    const bundleKey = 'secure-storage-bundle';
    const migrationKeys = [
      'setting',
      'download-history',
      'two-factor-secret',
      'missing',
    ];
    final backing = _MemorySecureStorage({
      bundleKey: jsonEncode({'setting': 'configured'}),
      'setting': 'stale',
      'download-history': 'recent',
      'stray': 'unrelated-v2-item',
    });
    final legacy = _MemorySecureStorage({
      'download-history': 'stale-history',
      'two-factor-secret': 'legacy',
      'other-app': 'unrelated-default-item',
    });
    final bundled = BundledSecureStorage(
      storage: backing,
      bundleKey: bundleKey,
    );
    final storage = MigratingSecureStorage(
      primary: bundled,
      fallback: MigratingSecureStorage(
        primary: backing,
        fallback: legacy,
        deleteFallbackAfterMigration: false,
        migrationKeys: migrationKeys,
      ),
      deleteFallbackAfterMigration: false,
      migrationMarkerKey: markerKey,
      migrationKeys: migrationKeys,
    );

    expect(await storage.readAll(), {
      'setting': 'configured',
      'download-history': 'recent',
      'two-factor-secret': 'legacy',
    });
    expect(await bundled.read(key: markerKey), '1');
    expect(backing.readAllCount, 0);
    expect(backing.readKeys.toSet(), {
      bundleKey,
      'download-history',
      'two-factor-secret',
      'missing',
    });
    expect(legacy.readAllCount, 0);
    expect(legacy.readKeys, ['two-factor-secret', 'missing']);
    expect(backing.values['stray'], 'unrelated-v2-item');
    expect(legacy.values['other-app'], 'unrelated-default-item');
  });

  for (final hasPrimaryValue in [false, true]) {
    test(
        'keyed readAll reads missing fallback keys (primary: $hasPrimaryValue)',
        () async {
      final primary = _MemorySecureStorage(
        hasPrimaryValue ? {'setting': 'configured'} : null,
      );
      final fallback = _MemorySecureStorage({
        'setting': 'stale',
        'two-factor-secret': 'legacy',
        'unrelated': 'other-app',
      });
      final storage = MigratingSecureStorage(
        primary: primary,
        fallback: fallback,
        migrationKeys: ['setting', 'two-factor-secret', 'missing'],
      );

      final expected = {
        'setting': hasPrimaryValue ? 'configured' : 'stale',
        'two-factor-secret': 'legacy',
      };
      expect(await storage.readAll(), expected);
      expect(primary.values, expected);
      expect(primary.readAllCount, 1);
      expect(fallback.readAllCount, 0);
      expect(fallback.readKeys, [
        if (!hasPrimaryValue) 'setting',
        'two-factor-secret',
        'missing',
      ]);
      expect(fallback.values['unrelated'], 'other-app');
    });
  }

  for (final operation in ['read', 'readKeys']) {
    test('keyed $operation avoids readAll when checking a missing key',
        () async {
      final primary = _MemorySecureStorage({'setting': 'configured'});
      final fallback = _MemorySecureStorage({'two-factor-secret': 'legacy'});
      final storage = MigratingSecureStorage(
        primary: primary,
        fallback: fallback,
        migrationKeys: ['setting', 'two-factor-secret'],
      );

      if (operation == 'read') {
        expect(await storage.read(key: 'two-factor-secret'), 'legacy');
      } else {
        expect(await storage.readKeys(['setting', 'two-factor-secret']), {
          'setting': 'configured',
          'two-factor-secret': 'legacy',
        });
      }
      expect(primary.values['two-factor-secret'], 'legacy');
      expect(primary.readAllCount, 0);
      expect(fallback.readAllCount, 0);
      expect(fallback.readKeys, ['two-factor-secret']);
    });
  }

  test('empty migration keys do not read fallback storage', () async {
    final primary = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({'unrelated': 'other-app'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: 'migration-completed',
      migrationKeys: const [],
    );

    expect(await storage.readAll(), isEmpty);
    expect(primary.values, {'migration-completed': '1'});
    expect(fallback.readAllCount, 0);
    expect(fallback.readKeys, isEmpty);
  });

  test('failed keyed sweep leaves no marker and retries the fallback chain',
      () async {
    const markerKey = 'migration-completed';
    const migrationKeys = ['setting', 'two-factor-secret'];
    final primary = _MemorySecureStorage({'setting': 'configured'});
    final middle = _MemorySecureStorage({'unrelated': 'v2-item'});
    final legacy = _MemorySecureStorage({'two-factor-secret': 'legacy'})
      ..readError = StateError('keychain unavailable');
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: MigratingSecureStorage(
        primary: middle,
        fallback: legacy,
        migrationKeys: migrationKeys,
      ),
      migrationMarkerKey: markerKey,
      migrationKeys: migrationKeys,
    );

    expect(await storage.readAll(), {'setting': 'configured'});
    expect(primary.values.containsKey(markerKey), isFalse);
    legacy.readError = null;

    expect(await storage.readAll(), {
      'setting': 'configured',
      'two-factor-secret': 'legacy',
    });
    expect(primary.values[markerKey], '1');
    expect(middle.readAllCount, 0);
    expect(legacy.readAllCount, 0);
  });

  test('existing migration marker prevents every fallback read', () async {
    const markerKey = 'migration-completed';
    final primary = _MemorySecureStorage({
      'setting': 'configured',
      markerKey: '1',
    });
    final fallback = _MemorySecureStorage({'two-factor-secret': 'legacy'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
    );

    expect(await storage.read(key: 'two-factor-secret'), isNull);
    expect(
      await storage.readKeys(['setting', 'two-factor-secret']),
      {'setting': 'configured', 'two-factor-secret': null},
    );
    expect(await storage.readAll(), {'setting': 'configured'});
    expect(fallback.readAllCount, 0);
    expect(fallback.readKeys, isEmpty);
  });

  test('failed migration sweep leaves no marker and is retried', () async {
    const markerKey = 'migration-completed';
    final primary = _MemorySecureStorage({'setting': 'configured'});
    final fallback = _MemorySecureStorage({'two-factor-secret': 'legacy'})
      ..readAllError = StateError('readAll unavailable');
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
    );

    expect(await storage.read(key: 'two-factor-secret'), 'legacy');
    expect(primary.values.containsKey(markerKey), isFalse);
    expect(fallback.readAllCount, 1);

    fallback.readAllError = null;

    expect(await storage.read(key: 'two-factor-secret'), 'legacy');
    expect(primary.values[markerKey], '1');
    expect(fallback.readAllCount, 2);
  });

  test('migration sweep reads through layered fallback stores', () async {
    const markerKey = 'migration-completed';
    final primary = _MemorySecureStorage({'setting': 'configured'});
    final middle = _MemorySecureStorage({'download-history': 'recent'});
    final legacy = _MemorySecureStorage({'two-factor-secret': 'legacy'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: MigratingSecureStorage(
        primary: middle,
        fallback: legacy,
        deleteFallbackAfterMigration: false,
      ),
      deleteFallbackAfterMigration: false,
      migrationMarkerKey: markerKey,
    );

    expect(await storage.read(key: 'two-factor-secret'), 'legacy');
    expect(primary.values, {
      'setting': 'configured',
      'download-history': 'recent',
      'two-factor-secret': 'legacy',
      markerKey: '1',
    });
    expect(middle.values, {'download-history': 'recent'});
    expect(legacy.values, {'two-factor-secret': 'legacy'});
  });

  testWidgets(
      'write waits for slow migration through bundled and legacy stores',
      (tester) async {
    const markerKey = 'migration-completed';
    final backing = _MemorySecureStorage()
      ..readDelay = const Duration(seconds: 4)
      ..readAllDelay = const Duration(seconds: 4);
    final legacy = _MemorySecureStorage({'two-factor-secret': 'legacy'})
      ..readAllDelay = const Duration(seconds: 4);
    final bundled = BundledSecureStorage(storage: backing, bundleKey: 'bundle');
    final storage = MigratingSecureStorage(
      primary: bundled,
      fallback: MigratingSecureStorage(
        primary: backing,
        fallback: legacy,
        deleteFallbackAfterMigration: false,
        operationTimeout: const Duration(minutes: 2),
      ),
      deleteFallbackAfterMigration: false,
      migrationMarkerKey: markerKey,
      operationTimeout: const Duration(minutes: 2),
    );

    final write = expectLater(
      storage.write(key: 'setting', value: 'configured'),
      completes,
    );
    await tester.pump();
    // Each physical keychain read can wait for a separate access prompt.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 4));
    }
    await write;

    expect(await bundled.readAll(), {
      'two-factor-secret': 'legacy',
      markerKey: '1',
      'setting': 'configured',
    });
    expect(legacy.values, {'two-factor-secret': 'legacy'});
  });

  test('concurrent marked reads share one migration sweep', () async {
    const markerKey = 'migration-completed';
    final primary = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({
      'two-factor-secret': 'legacy',
      'download-history': 'recent',
    })
      ..readAllDelay = const Duration(milliseconds: 20);
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
    );

    final values = await Future.wait([
      storage.read(key: 'two-factor-secret'),
      storage.read(key: 'download-history'),
    ]);

    expect(values, ['legacy', 'recent']);
    expect(fallback.readAllCount, 1);
  });

  test('primary read failure is rethrown when fallback is empty', () async {
    final primary = _MemorySecureStorage()..readError = StateError('denied');
    final fallback = _MemorySecureStorage();
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    expect(storage.read(key: 'token'), throwsA(isA<StateError>()));
  });

  test('write stores primary value and removes stale fallback value', () async {
    final primary = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({'token': 'old'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
    );

    await storage.write(key: 'token', value: 'new');

    expect(primary.values['token'], 'new');
    expect(fallback.values.containsKey('token'), isFalse);
  });

  test('deleteAll waits for an in-flight migration sweep', () async {
    const markerKey = 'migration-completed';
    final readAllStarted = Completer<void>();
    final releaseReadAll = Completer<void>();
    final primary = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({'token': 'legacy'})
      ..readAllStarted = readAllStarted
      ..releaseReadAll = releaseReadAll;
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
    );

    final read = storage.read(key: 'token');
    await readAllStarted.future;
    final deletion = storage.deleteAll();
    releaseReadAll.complete();

    await read;
    await deletion;

    expect(await storage.read(key: 'token'), isNull);
    expect(primary.values, {markerKey: '1'});
    expect(fallback.values, isEmpty);
  });

  test('failed fallback deleteAll leaves a durable deletion tombstone',
      () async {
    const markerKey = 'migration-completed';
    final primary = _MemorySecureStorage({'current': 'value'});
    final fallback = _MemorySecureStorage({'token': 'legacy'})
      ..deleteAllError = StateError('legacy keychain unavailable');
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
    );

    await expectLater(storage.deleteAll(), throwsA(isA<StateError>()));

    expect(primary.values, {markerKey: '1'});
    expect(fallback.values, {'token': 'legacy'});

    final restartedStorage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
    );
    expect(await restartedStorage.read(key: 'token'), isNull);
  });

  test('deleteAll writes its tombstone before legacy cleanup finishes',
      () async {
    const markerKey = 'migration-completed';
    final deleteAllStarted = Completer<void>();
    final releaseDeleteAll = Completer<void>();
    final primary = _MemorySecureStorage({'current': 'value'});
    final fallback = _MemorySecureStorage({'token': 'legacy'})
      ..deleteAllStarted = deleteAllStarted
      ..releaseDeleteAll = releaseDeleteAll;
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
    );

    final deletion = storage.deleteAll();
    await deleteAllStarted.future;

    expect(primary.values, {markerKey: '1'});
    final restartedStorage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
    );
    expect(await restartedStorage.read(key: 'token'), isNull);

    releaseDeleteAll.complete();
    await deletion;
    expect(fallback.values, isEmpty);
  });

  test('deleteAll restores a bundled marker erased by an aliased fallback',
      () async {
    const markerKey = 'migration-completed';
    const bundleKey = 'secure-storage-bundle';
    final sharedBacking = _MemorySecureStorage();
    final bundledPrimary = BundledSecureStorage(
      storage: sharedBacking,
      bundleKey: bundleKey,
    );
    final legacy = _MemorySecureStorage({'login': 'legacy-student'})
      ..deleteAllError = StateError('legacy keychain unavailable');
    final nestedFallback = MigratingSecureStorage(
      primary: sharedBacking,
      fallback: legacy,
      deleteFallbackAfterMigration: false,
    );
    final storage = MigratingSecureStorage(
      primary: bundledPrimary,
      fallback: nestedFallback,
      deleteFallbackAfterMigration: false,
      migrationMarkerKey: markerKey,
    );

    await bundledPrimary.write(key: 'current', value: 'value');
    await expectLater(storage.deleteAll(), throwsA(isA<StateError>()));

    final persistedBundle =
        jsonDecode(sharedBacking.values[bundleKey]!) as Map<String, dynamic>;
    expect(persistedBundle, {markerKey: '1'});
    expect(legacy.values, {'login': 'legacy-student'});

    final restartedStorage = MigratingSecureStorage(
      primary: BundledSecureStorage(
        storage: sharedBacking,
        bundleKey: bundleKey,
      ),
      fallback: MigratingSecureStorage(
        primary: sharedBacking,
        fallback: legacy,
        deleteFallbackAfterMigration: false,
      ),
      deleteFallbackAfterMigration: false,
      migrationMarkerKey: markerKey,
    );
    expect(await restartedStorage.read(key: 'login'), isNull);
  });

  test('failed fallback key delete cannot revive a deleted marked value',
      () async {
    const markerKey = 'migration-completed';
    final primary = _MemorySecureStorage();
    final fallback = _MemorySecureStorage({'token': 'legacy'});
    final storage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      deleteFallbackAfterMigration: false,
      migrationMarkerKey: markerKey,
    );

    expect(await storage.read(key: 'token'), 'legacy');
    fallback.deleteError = StateError('legacy key delete failed');

    await expectLater(storage.delete(key: 'token'), throwsA(isA<StateError>()));

    expect(primary.values, {markerKey: '1'});
    expect(fallback.values, {'token': 'legacy'});
    final restartedStorage = MigratingSecureStorage(
      primary: primary,
      fallback: fallback,
      migrationMarkerKey: markerKey,
    );
    expect(await restartedStorage.read(key: 'token'), isNull);
    fallback.deleteError = null;
    await restartedStorage.delete(key: 'token');
    expect(fallback.values, isEmpty);
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage([Map<String, String>? initial])
      : values = Map<String, String>.from(initial ?? const {});

  final Map<String, String> values;
  Object? readError;
  Object? readAllError;
  Object? deleteError;
  Object? deleteAllError;
  Completer<void>? readAllStarted;
  Completer<void>? releaseReadAll;
  Completer<void>? deleteAllStarted;
  Completer<void>? releaseDeleteAll;
  Duration readDelay = Duration.zero;
  Duration readAllDelay = Duration.zero;
  int readAllCount = 0;
  final List<String> readKeys = [];
  final List<String> writeKeys = [];

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
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    final error = readError;
    if (error != null) {
      throw error;
    }
    readKeys.add(key);
    return values[key];
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readAllCount += 1;
    final started = readAllStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final release = releaseReadAll;
    if (release != null) {
      await release.future;
    }
    if (readAllDelay > Duration.zero) {
      await Future<void>.delayed(readAllDelay);
    }
    final error = readAllError ?? readError;
    if (error != null) {
      throw error;
    }
    return Map<String, String>.from(values);
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writeKeys.add(key);
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    values.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final started = deleteAllStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final release = releaseDeleteAll;
    if (release != null) {
      await release.future;
    }
    final error = deleteAllError;
    if (error != null) {
      throw error;
    }
    values.clear();
  }
}
