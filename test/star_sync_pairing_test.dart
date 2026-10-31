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

  test('pairing, two-way sync, reset and rejoin', () async {
    final remote = _Transport();
    final storageA = _Storage();
    final storageB = _Storage();
    final activityA = GakujoActivityStore(secureStorage: storageA);
    final activityB = GakujoActivityStore(secureStorage: storageB);
    final a = StarSyncEngine(
      activityStore: activityA,
      secureStorage: storageA,
      googleDriveTransport: () => remote,
    );
    final b = StarSyncEngine(
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
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      googleDriveTransport: () => remote,
    );
    final b = StarSyncEngine(
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
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        googleDriveTransport: () => remote,
      );
      await a.setUpWithPairing(config);
      final second = _Storage();
      final b = StarSyncEngine(
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
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      transportFactory: (_) => remote,
      kdfParams: const StarSyncKdfParams(memoryKiB: 8, iterations: 1),
    );
    final b = StarSyncEngine(
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
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      googleDriveTransport: () => remote,
    );
    await engine.setUpWithPairing(config);
    await expectLater(engine.changePassphrase('old', 'new'), throwsStateError);
  });
}
