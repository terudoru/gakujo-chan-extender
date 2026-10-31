import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_crypto.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

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
  Future<StarSyncRemoteObject?> get(String path) async {
    gets[path] = (gets[path] ?? 0) + 1;
    if (simulateKeyringRace && path == 'stars/keyring.json') {
      simulateKeyringRace = false;
      _racePending = true;
      return null;
    }
    final bytes = files[path];
    return bytes == null ? null : StarSyncRemoteObject(bytes: bytes);
  }

  @override
  Future<void> put(
    String path,
    List<int> bytes, {
    bool createOnly = false,
  }) async {
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

  test(
    'pairing setup, reset and join retain settings after first sync fails',
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
        await first.setUpWithPairing(config),
        StarSyncPairingSetup.created,
      );
      expect(first.status.value.enabled, isTrue);
      expect(first.status.value.status, StarSyncStatus.error);
      expect(first.status.value.lastError, isNotNull);
      await first.syncNow();
      final second = make();
      remote.failDevicePutOnce = true;
      await second.joinWithPairingCode(config, await first.pairingCode());
      expect(second.status.value.enabled, isTrue);
      expect(second.status.value.status, StarSyncStatus.error);
      expect(second.status.value.lastError, isNotNull);
      final reset = make();
      remote.failDevicePutOnce = true;
      expect(
        await reset.setUpWithPairing(config, resetExisting: true),
        StarSyncPairingSetup.created,
      );
      expect(reset.status.value.enabled, isTrue);
      expect(reset.status.value.status, StarSyncStatus.error);
      expect(reset.status.value.lastError, isNotNull);
    },
  );

  test('pairing, two-way sync, reset and rejoin', () async {
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
    expect(await a.setUpWithPairing(config), StarSyncPairingSetup.created);
    expect(
      await b.setUpWithPairing(config),
      StarSyncPairingSetup.needsPairingCode,
    );
    expect(storageB.values, isEmpty);
    GakujoStarredMessage star(String id) => GakujoStarredMessage(
      keijitype: '1',
      genrecd: '2',
      seqNo: id,
      title: id,
      starredAt: DateTime.utc(2026),
    );
    await activityA.upsertStarredMessage(star('3'));
    await a.syncNow();
    await b.joinWithPairingCode(config, await a.pairingCode());
    expect((await activityB.loadStarredMessages()).single.id, '1|2|3');
    await activityB.upsertStarredMessage(star('4'));
    await b.syncNow();
    await a.syncNow();
    expect((await activityA.loadStarredMessages()).length, 2);
    final code = await a.resetRemoteWithPairing();
    await b.syncNow();
    expect(b.status.value.status, StarSyncStatus.needsPairingCode);
    await b.rejoinWithPairingCode(code);
    expect(b.status.value.status, StarSyncStatus.ok);
    expect((await activityB.loadStarredMessages()).length, 2);
  });

  test('wrong keys and malformed codes do not persist', () async {
    final remote = _Transport();
    final first = _Storage();
    final second = _Storage();
    final a = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      googleDriveTransport: () => remote,
    );
    final b = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: second),
      secureStorage: second,
      googleDriveTransport: () => remote,
    );
    await a.setUpWithPairing(config);
    final other = createStarSyncPairingKeyring();
    final wrongId = encodeStarSyncPairingCode(
      other.keyring.keyId,
      other.dataKey,
    );
    await expectLater(
      b.joinWithPairingCode(config, wrongId),
      throwsA(isA<StarSyncPairingMismatchException>()),
    );
    final actual = decodeStarSyncPairingCode(await a.pairingCode());
    final wrongKey = List<int>.of(actual.dataKey)..[0] ^= 1;
    await expectLater(
      b.joinWithPairingCode(
        config,
        encodeStarSyncPairingCode(actual.keyId, wrongKey),
      ),
      throwsA(isA<StarSyncPairingMismatchException>()),
    );
    await expectLater(
      b.joinWithPairingCode(config, 'garbage'),
      throwsA(isA<StarSyncFormatException>()),
    );
    expect(second.values, isEmpty);
  });

  test(
    'creation race requires pairing and missing Drive factory throws',
    () async {
      final remote = _Transport();
      final storage = _Storage();
      final a = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        googleDriveTransport: () => remote,
      );
      await a.setUpWithPairing(config);
      final second = _Storage();
      final b = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: second),
        secureStorage: second,
        googleDriveTransport: () => remote,
      );
      remote.simulateKeyringRace = true;
      expect(
        await b.setUpWithPairing(config),
        StarSyncPairingSetup.needsPairingCode,
      );
      expect(second.values, isEmpty);
      final absent = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: second),
        secureStorage: second,
      );
      await expectLater(absent.setUpWithPairing(config), throwsStateError);
    },
  );

  test('passphrase keyring can be joined with a code', () async {
    final remote = _Transport();
    final first = _Storage();
    final second = _Storage();
    final a = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      transportFactory: (_) => remote,
      kdfParams: const StarSyncKdfParams(memoryKiB: 8, iterations: 1),
    );
    final b = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: second),
      secureStorage: second,
      transportFactory: (_) => remote,
    );
    await a.setUp(config, 'passphrase');
    await b.joinWithPairingCode(config, await a.pairingCode());
    expect(b.status.value.status, StarSyncStatus.ok);
  });

  test('pairing keyring rejects passphrase changes', () async {
    final remote = _Transport();
    final storage = _Storage();
    final engine = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      googleDriveTransport: () => remote,
    );
    await engine.setUpWithPairing(config);
    await expectLater(engine.changePassphrase('old', 'new'), throwsStateError);
  });
  test(
    'disabled pairing reset replaces keyring and removes old devices',
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
      await engine.setUpWithPairing(config);
      final code = await engine.pairingCode();
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
        await engine.setUpWithPairing(
          config,
          resetExisting: true,
          clearLocalStars: true,
        ),
        StarSyncPairingSetup.created,
      );
      expect(await engine.pairingCode(), isNot(code));
      expect(await engine.localStarCount(), 0);
      expect(oldDevices.where(remote.files.containsKey), isEmpty);
      final state = StarSyncState.fromJson(
        jsonDecode(storage.values[starSyncStateKey]!),
      );
      expect(state.records, isEmpty);
    },
  );

  test(
    'pairing detects overwrite after create and reset reports race',
    () async {
      final remote = _Transport();
      final foreign = createStarSyncPairingKeyring();
      final bytes = utf8.encode(jsonEncode(foreign.keyring.toJson()));
      final storage = _Storage();
      final engine = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        googleDriveTransport: () => remote,
      );
      remote.overwriteKeyring = bytes;
      expect(
        await engine.setUpWithPairing(config),
        StarSyncPairingSetup.needsPairingCode,
      );
      expect(storage.values, isEmpty);
      remote.overwriteKeyring = bytes;
      await expectLater(
        engine.setUpWithPairing(config, resetExisting: true),
        throwsA(isA<StarSyncSetupRaceException>()),
      );
      expect(storage.values, isEmpty);
    },
  );

  test('pairing accepts a valid device after a stale device file', () async {
    final remote = _Transport();
    final first = _Storage();
    final a = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      googleDriveTransport: () => remote,
    );
    await a.setUpWithPairing(config);
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
    await b.joinWithPairingCode(
      config,
      await a.pairingCode(),
      clearLocalStars: true,
    );
    expect(b.status.value.enabled, isTrue);
  });
}
