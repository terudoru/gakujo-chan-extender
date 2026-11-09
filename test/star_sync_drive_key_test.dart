import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_collections.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_crypto.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

class _Favorites extends StarSyncCollection {
  @override
  String get name => 'favorites';
  @override
  bool get growOnly => false;
  @override
  int? get maxLive => null;
  @override
  Comparable Function(Object?)? get order => null;
  @override
  Future<Map<String, Object?>?> readLocal() async => {};
  @override
  Future<bool> applyLocal(Map<String, Object?> entries, {
    required Map<String, Object?> basedOn,
    bool Function()? stillCurrent,
  }) async => true;
}

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failStarWriteOnce = false;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

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
    if (failStarWriteOnce && key == 'more_better_gakujo_starred_messages') {
      failStarWriteOnce = false;
      throw StateError('star write failed');
    }
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
    values.remove(key);
  }
}

class _Transport implements StarSyncTransport {
  final files = <String, List<int>>{};
  int puts = 0;
  int deletes = 0;
  final gets = <String, int>{};
  Completer<void>? listStarted;
  Completer<void>? listRelease;
  bool failDevicePutOnce = false;
  bool failUpgradeOnce = false;
  bool simulateKeyringRace = false;
  bool _racePending = false;
  List<int>? overwriteKeyring;

  @override
  void close() {}

  @override
  Future<void> ensureDirectory(String path) async {}

  @override
  Future<List<StarSyncRemoteEntry>> list(String directory) async {
    final started = listStarted;
    final release = listRelease;
    if (started != null && release != null) {
      listStarted = null;
      listRelease = null;
      started.complete();
      await release.future;
    }
    return [
      for (final entry in files.entries)
        if (entry.key.startsWith('$directory/'))
          StarSyncRemoteEntry(path: entry.key, etag: base64Encode(entry.value)),
    ];
  }

  @override
  Future<StarSyncRemoteObject?> get(
    String path, {
    int maxBytes = starSyncDefaultMaxBytes,
  }) async {
    gets[path] = (gets[path] ?? 0) + 1;
    if (simulateKeyringRace && path == 'stars/keyring.json') {
      simulateKeyringRace = false;
      _racePending = true;
      return null;
    }
    final bytes = files[path];
    if (bytes != null && bytes.length > maxBytes) {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.invalidResponse,
        'Response is too large',
      );
    }
    return bytes == null ? null : StarSyncRemoteObject(bytes: bytes);
  }

  @override
  Future<void> put(
    String path,
    List<int> bytes, {
    bool createOnly = false,
  }) async {
    if (failUpgradeOnce && path == 'stars/keyring.json' && !createOnly) {
      failUpgradeOnce = false;
      throw StateError('upgrade failed');
    }
    if (failDevicePutOnce && path.startsWith('stars/devices/')) {
      failDevicePutOnce = false;
      throw StateError('device upload failed');
    }
    if (_racePending && createOnly && path == 'stars/keyring.json') {
      _racePending = false;
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.alreadyExists,
        'exists',
      );
    }
    if (createOnly && files.containsKey(path)) {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.alreadyExists,
        'exists',
      );
    }
    files[path] = List.of(bytes);
    if (createOnly &&
        path == 'stars/keyring.json' &&
        overwriteKeyring != null) {
      files[path] = overwriteKeyring!;
      overwriteKeyring = null;
    }
    puts++;
  }

  @override
  Future<void> delete(String path) async {
    deletes++;
    files.remove(path);
  }
}

void main() {
  const config = StarSyncConfig(backend: StarSyncBackend.googleDrive);

  test('simultaneous first setups use the winning key', () async {
    final remote = _Transport();
    final first = _Storage();
    final second = _Storage();
    StarSyncEngine make(_Storage storage) => StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      googleDriveTransport: () => remote,
    );
    final a = make(first);
    final b = make(second);
    final results = await Future.wait([
      a.setUpWithDrive(config), b.setUpWithDrive(config),
    ]);
    expect(results, everyElement(StarSyncDriveSetup.created));
    final firstState = StarSyncState.fromJson(jsonDecode(first.values[starSyncStateKey]!));
    final secondState = StarSyncState.fromJson(jsonDecode(second.values[starSyncStateKey]!));
    expect(firstState.keyId, secondState.keyId);
    expect(firstState.dataKey, secondState.dataKey);
    a.dispose();
    b.dispose();
  });

  test(
    'drive setup, reset and join retain settings after first sync fails',
    () async {
      final remote = _Transport();
      StarSyncEngine make() {
        final storage = _Storage();
        return StarSyncEngine(
          loginId: () => 'student',
          activityStore: GakujoActivityStore(secureStorage: storage),
          secureStorage: storage,
          transportFactory: (_) => remote,
        );
      }

      final first = make();
      remote.failDevicePutOnce = true;
      expect(
        await first.setUpWithDrive(config),
        StarSyncDriveSetup.created,
      );
      expect(first.status.value.enabled, isTrue);
      expect(first.status.value.status, StarSyncStatus.error);
      expect(first.status.value.lastError, isNotNull);
      await first.syncNow();
      final second = make();
      remote.failDevicePutOnce = true;
      await second.setUpWithDrive(config);
      expect(second.status.value.enabled, isTrue);
      expect(second.status.value.status, StarSyncStatus.error);
      expect(second.status.value.lastError, isNotNull);
      final reset = make();
      remote.failDevicePutOnce = true;
      expect(
        await reset.setUpWithDrive(config, resetExisting: true),
        StarSyncDriveSetup.created,
      );
      expect(reset.status.value.enabled, isTrue);
      expect(reset.status.value.status, StarSyncStatus.error);
      expect(reset.status.value.lastError, isNotNull);
    },
  );

  test('drive, two-way sync, reset and rejoin', () async {
    final remote = _Transport();
    final storageA = _Storage();
    final storageB = _Storage();
    final activityA = GakujoActivityStore(secureStorage: storageA);
    final activityB = GakujoActivityStore(secureStorage: storageB);
    final a = StarSyncEngine(
      loginId: () => 'student',
      activityStore: activityA,
      secureStorage: storageA,
      googleDriveTransport: () => remote,
    );
    final b = StarSyncEngine(
      loginId: () => 'student',
      activityStore: activityB,
      secureStorage: storageB,
      googleDriveTransport: () => remote,
    );
    expect(await a.setUpWithDrive(config), StarSyncDriveSetup.created);
    GakujoStarredMessage star(String id) => GakujoStarredMessage(
      keijitype: '1',
      genrecd: '2',
      seqNo: id,
      title: id,
      starredAt: DateTime.utc(2026),
    );
    await activityA.upsertStarredMessage(star('3'));
    await a.syncNow();
    await b.setUpWithDrive(config);
    expect((await activityB.loadStarredMessages()).single.id, '1|2|3');
    await activityB.upsertStarredMessage(star('4'));
    await b.syncNow();
    await a.syncNow();
    expect((await activityA.loadStarredMessages()).length, 2);
    await a.resetRemoteWithDrive();
    await b.syncNow();
    expect(b.status.value.status, StarSyncStatus.ok);
    expect((await activityB.loadStarredMessages()).length, 2);
  });

  test('corrupted Drive key cannot overwrite existing device files', () async {
    final remote = _Transport();
    final first = _Storage();
    final a = StarSyncEngine(loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first, googleDriveTransport: () => remote);
    await a.setUpWithDrive(config);
    final ring = StarSyncKeyring.fromJson(jsonDecode(utf8.decode(remote.files['stars/keyring.json']!)));
    final wrong = List<int>.of(ring.dataKey)..[0] ^= 1;
    remote.files['stars/keyring.json'] = utf8.encode(jsonEncode(
      StarSyncKeyring.drive(keyId: ring.keyId, dataKey: wrong).toJson()));
    final before = {for (final entry in remote.files.entries) entry.key: List<int>.of(entry.value)};
    final second = _Storage();
    final b = StarSyncEngine(loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: second),
      secureStorage: second, googleDriveTransport: () => remote);
    await expectLater(b.setUpWithDrive(config), throwsA(isA<StarSyncKeyringMismatchException>()));
    expect(remote.files, before);
    expect(b.status.value.enabled, isFalse);
  });

  test('legacy key holder upgrades and a new device joins', () async {
    final remote = _Transport();
    final first = _Storage();
    final a = StarSyncEngine(loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first, googleDriveTransport: () => remote);
    await a.setUpWithDrive(config);
    final ring = StarSyncKeyring.fromJson(jsonDecode(utf8.decode(remote.files['stars/keyring.json']!)));
    remote.files['stars/keyring.json'] = utf8.encode(jsonEncode(StarSyncKeyring.pairing(keyId: ring.keyId).toJson()));
    await a.syncNow();
    expect(StarSyncKeyring.fromJson(jsonDecode(utf8.decode(remote.files['stars/keyring.json']!))).mode, 'drive');
    final second = _Storage();
    final b = StarSyncEngine(loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: second),
      secureStorage: second, googleDriveTransport: () => remote);
    expect(await b.setUpWithDrive(config), StarSyncDriveSetup.created);
    expect(StarSyncState.fromJson(jsonDecode(second.values[starSyncStateKey]!)).dataKey,
      StarSyncState.fromJson(jsonDecode(first.values[starSyncStateKey]!)).dataKey);
  });

  test('legacy data requires confirmation before recreation', () async {
    final remote = _Transport();
    final legacy = createStarSyncDriveKeyring();
    remote.files['stars/keyring.json'] = utf8.encode(jsonEncode(StarSyncKeyring.pairing(keyId: legacy.keyring.keyId).toJson()));
    remote.files['stars/devices/old'] = [1, 2, 3];
    remote.files['backups/old'] = [4, 5, 6];
    remote.files['sync/favorites/old'] = [7, 8, 9];
    final storage = _Storage();
    final activity = GakujoActivityStore(secureStorage: storage);
    await activity.upsertStarredMessage(GakujoStarredMessage(
      keijitype: '1', genrecd: '2', seqNo: '3', title: 'kept',
      starredAt: DateTime.utc(2026),
    ));
    final engine = StarSyncEngine(loginId: () => 'student',
      activityStore: activity,
      secureStorage: storage, googleDriveTransport: () => remote,
      collections: [_Favorites()]);
    expect(await engine.setUpWithDrive(config), StarSyncDriveSetup.needsLegacyReset);
    expect(engine.status.value.enabled, isFalse);
    expect(await engine.setUpWithDrive(config, resetExisting: true), StarSyncDriveSetup.created);
    final recreated = StarSyncKeyring.fromJson(jsonDecode(utf8.decode(remote.files['stars/keyring.json']!)));
    expect(recreated.mode, 'drive');
    expect(recreated.keyId, isNot(legacy.keyring.keyId));
    expect(remote.files.containsKey('stars/devices/old'), isFalse);
    expect(remote.files.containsKey('backups/old'), isFalse);
    expect(remote.files.containsKey('sync/favorites/old'), isFalse);
    expect((await activity.loadStarredMessages()).single.title, 'kept');
  });

  test('legacy upgrade retries after a write failure', () async {
    final remote = _Transport();
    final storage = _Storage();
    final engine = StarSyncEngine(loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage, googleDriveTransport: () => remote);
    await engine.setUpWithDrive(config);
    final ring = StarSyncKeyring.fromJson(jsonDecode(utf8.decode(remote.files['stars/keyring.json']!)));
    remote.files['stars/keyring.json'] = utf8.encode(jsonEncode(StarSyncKeyring.pairing(keyId: ring.keyId).toJson()));
    remote.failUpgradeOnce = true;
    await engine.syncNow();
    expect(StarSyncKeyring.fromJson(jsonDecode(utf8.decode(remote.files['stars/keyring.json']!))).mode, 'pairing');
    await engine.syncNow();
    expect(StarSyncKeyring.fromJson(jsonDecode(utf8.decode(remote.files['stars/keyring.json']!))).mode, 'drive');
  });

  test(
    'creation race joins the winning key and missing Drive factory throws',
    () async {
      final remote = _Transport();
      final storage = _Storage();
      final a = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        googleDriveTransport: () => remote,
      );
      await a.setUpWithDrive(config);
      final second = _Storage();
      final b = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: second),
        secureStorage: second,
        googleDriveTransport: () => remote,
      );
      remote.simulateKeyringRace = true;
      expect(
        await b.setUpWithDrive(config),
        StarSyncDriveSetup.created,
      );
      expect(StarSyncState.fromJson(jsonDecode(second.values[starSyncStateKey]!)).dataKey,
          StarSyncState.fromJson(jsonDecode(storage.values[starSyncStateKey]!)).dataKey);
      final absent = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: second),
        secureStorage: second,
      );
      await expectLater(absent.setUpWithDrive(config), throwsStateError);
    },
  );

  test('drive keyring rejects passphrase changes', () async {
    final remote = _Transport();
    final storage = _Storage();
    final engine = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      googleDriveTransport: () => remote,
    );
    await engine.setUpWithDrive(config);
    await expectLater(engine.changePassphrase('old', 'new'), throwsStateError);
  });
  test(
    'disabled drive reset replaces keyring and removes old devices',
    () async {
      final remote = _Transport();
      final storage = _Storage();
      final activity = GakujoActivityStore(secureStorage: storage);
      final engine = StarSyncEngine(
        loginId: () => 'student',
        activityStore: activity,
        secureStorage: storage,
        googleDriveTransport: () => remote,
      );
      await engine.setUpWithDrive(config);
      final oldKeyring = List<int>.of(remote.files['stars/keyring.json']!);
      final oldDevices = remote.files.keys
          .where((p) => p.startsWith('stars/devices/'))
          .toList();
      await engine.disable();
      await activity.upsertStarredMessage(
        GakujoStarredMessage(
          keijitype: '1',
          genrecd: '2',
          seqNo: '3',
          title: 'old',
          starredAt: DateTime.utc(2026),
        ),
      );
      expect(
        await engine.setUpWithDrive(
          config,
          resetExisting: true,
          clearLocalStars: await engine.snapshotLocalStars(),
        ),
        StarSyncDriveSetup.created,
      );
      expect(remote.files['stars/keyring.json'], isNot(oldKeyring));
      expect(await engine.localStarCount(), 0);
      expect(oldDevices.where(remote.files.containsKey), isEmpty);
      final state = StarSyncState.fromJson(
        jsonDecode(storage.values[starSyncStateKey]!),
      );
      expect(state.records, isEmpty);
    },
  );

  test(
    'drive detects overwrite after create and reset reports race',
    () async {
      final remote = _Transport();
      final foreign = createStarSyncDriveKeyring();
      final bytes = utf8.encode(jsonEncode(StarSyncKeyring.pairing(keyId: foreign.keyring.keyId).toJson()));
      final storage = _Storage();
      final engine = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        googleDriveTransport: () => remote,
      );
      remote.overwriteKeyring = bytes;
      expect(
        await engine.setUpWithDrive(config),
        StarSyncDriveSetup.needsLegacyReset,
      );
      expect(storage.values, isEmpty);
      remote.overwriteKeyring = bytes;
      await expectLater(
        engine.setUpWithDrive(config, resetExisting: true),
        throwsA(isA<StarSyncSetupRaceException>()),
      );
      expect(storage.values, isEmpty);
    },
  );

  test('drive accepts a valid device after a stale device file', () async {
    final remote = _Transport();
    final first = _Storage();
    final a = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      googleDriveTransport: () => remote,
    );
    await a.setUpWithDrive(config);
    final own = Map<String, List<int>>.of(remote.files);
    remote.files.clear();
    remote.files['stars/devices/stale'] = [1, 2, 3];
    remote.files.addAll(own);
    final second = _Storage();
    final b = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: second),
      secureStorage: second,
      googleDriveTransport: () => remote,
    );
    await b.setUpWithDrive(
      config, clearLocalStars: await b.snapshotLocalStars(),
    );
    expect(b.status.value.enabled, isTrue);
  });
}
