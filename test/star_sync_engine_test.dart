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
  const config = StarSyncConfig(backend: StarSyncBackend.webDav);
  const kdf = StarSyncKdfParams(memoryKiB: 8, iterations: 1);

  test('two devices share stars and propagate deletion', () async {
    final remote = _Transport();
    final storageA = _Storage();
    final storageB = _Storage();
    final activityA = GakujoActivityStore(secureStorage: storageA);
    final activityB = GakujoActivityStore(secureStorage: storageB);
    final a = StarSyncEngine(
      activityStore: activityA,
      secureStorage: storageA,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      activityStore: activityB,
      secureStorage: storageB,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await a.setUp(config, 'correct horse');
    await activityA.upsertStarredMessage(
      GakujoStarredMessage(
        keijitype: '1',
        genrecd: '2',
        seqNo: '3',
        title: 'Title',
        starredAt: DateTime.utc(2026),
      ),
    );
    await a.syncNow();
    await b.setUp(config, 'correct horse');
    expect((await activityB.loadStarredMessages()).single.title, 'Title');
    await activityA.removeStarredMessage('1|2|3');
    await a.syncNow();
    await b.syncNow();
    expect(await activityB.loadStarredMessages(), isEmpty);
  });

  test('failed star write preserves the baseline for a later import', () async {
    final remote = _Transport();
    final storageA = _Storage();
    final storageB = _Storage();
    final activityA = GakujoActivityStore(secureStorage: storageA);
    final activityB = GakujoActivityStore(secureStorage: storageB);
    final a = StarSyncEngine(
      activityStore: activityA,
      secureStorage: storageA,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      activityStore: activityB,
      secureStorage: storageB,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await a.setUp(config, 'correct horse');
    await b.setUp(config, 'correct horse');
    await activityA.upsertStarredMessage(
      GakujoStarredMessage(
        keijitype: '1',
        genrecd: '2',
        seqNo: '3',
        title: 'Title',
        starredAt: DateTime.utc(2026),
      ),
    );
    await a.syncNow();
    storageB.failStarWriteOnce = true;
    await expectLater(b.syncNow(), throwsStateError);
    expect(await activityB.loadStarredMessages(), isEmpty);
    final persisted = jsonDecode(storageB.values[starSyncStateKey]!) as Map;
    expect(persisted['records'], isEmpty);
    expect((await b.syncNow()).localChanged, isTrue);
    expect((await activityB.loadStarredMessages()).single.title, 'Title');
    await a.syncNow();
    expect((await activityA.loadStarredMessages()).single.title, 'Title');
  });

  test('local change callback runs once even when upload fails', () async {
    final remote = _Transport();
    final storageA = _Storage();
    final storageB = _Storage();
    final activityA = GakujoActivityStore(secureStorage: storageA);
    final activityB = GakujoActivityStore(secureStorage: storageB);
    var callbacks = 0;
    final a = StarSyncEngine(
      activityStore: activityA,
      secureStorage: storageA,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      activityStore: activityB,
      secureStorage: storageB,
      transportFactory: (_) => remote,
      onLocalStarsChanged: () => callbacks++,
      kdfParams: kdf,
    );
    await a.setUp(config, 'correct horse');
    await b.setUp(config, 'correct horse');
    await activityA.upsertStarredMessage(
      GakujoStarredMessage(
        keijitype: '1',
        genrecd: '2',
        seqNo: '3',
        title: 'Title',
        starredAt: DateTime.utc(2026),
      ),
    );
    await a.syncNow();
    remote.failDevicePutOnce = true;
    await expectLater(b.syncNow(), throwsStateError);
    expect((await activityB.loadStarredMessages()).single.title, 'Title');
    expect(callbacks, 1);
  });

  test('wrong passphrase does not persist configuration or state', () async {
    final remote = _Transport();
    final first = _Storage();
    final second = _Storage();
    await StarSyncEngine(
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    ).setUp(config, 'correct horse');
    final engine = StarSyncEngine(
      activityStore: GakujoActivityStore(secureStorage: second),
      secureStorage: second,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await expectLater(
      engine.setUp(config, 'wrong password'),
      throwsA(isA<StarSyncWrongPassphraseException>()),
    );
    expect(second.values, isEmpty);
  });
  test('corrupt stored state is removed and reported', () async {
    final storage = _Storage();
    storage.values[starSyncConfigKey] = '{}';
    storage.values[starSyncStateKey] = '{broken';
    final engine = StarSyncEngine(
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => _Transport(),
      kdfParams: kdf,
    );
    await engine.load();
    expect(storage.values, isEmpty);
    expect(engine.status.value.enabled, isFalse);
    expect(engine.status.value.lastError, '同期設定を読み込めませんでした');
  });

  test('unchanged documents are cached and are not uploaded again', () async {
    final remote = _Transport();
    final first = _Storage();
    final second = _Storage();
    StarSyncEngine make(_Storage storage) => StarSyncEngine(
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final a = make(first);
    final b = make(second);
    await a.setUp(config, 'correct horse');
    await b.setUp(config, 'correct horse');
    final deviceA =
        (jsonDecode(first.values[starSyncStateKey]!) as Map)['deviceId'];
    final path = 'stars/devices/$deviceA';
    final gets = remote.gets[path];
    final puts = remote.puts;
    await b.syncNow();
    expect(remote.gets[path], gets);
    expect(remote.puts, puts);
  });

  test(
    'disable deletes the local state without propagating an empty list',
    () async {
      final remote = _Transport();
      final first = _Storage();
      final second = _Storage();
      final activity = GakujoActivityStore(secureStorage: first);
      final a = StarSyncEngine(
        activityStore: activity,
        secureStorage: first,
        transportFactory: (_) => remote,
        kdfParams: kdf,
      );
      final b = StarSyncEngine(
        activityStore: GakujoActivityStore(secureStorage: second),
        secureStorage: second,
        transportFactory: (_) => remote,
        kdfParams: kdf,
      );
      await a.setUp(config, 'correct horse');
      await activity.upsertStarredMessage(
        GakujoStarredMessage(
          keijitype: '1',
          genrecd: '2',
          seqNo: '3',
          title: 'Title',
          starredAt: DateTime.utc(2026),
        ),
      );
      await a.syncNow();
      await b.setUp(config, 'correct horse');
      await a.disable();
      await activity.replaceStarredMessages(const []);
      await b.syncNow();
      expect(
        (await GakujoActivityStore(
          secureStorage: second,
        ).loadStarredMessages()).single.title,
        'Title',
      );
      expect(first.values.containsKey(starSyncConfigKey), isFalse);
      expect(first.values.containsKey(starSyncStateKey), isFalse);
    },
  );

  test('reset requires the other device to rejoin', () async {
    final remote = _Transport();
    StarSyncEngine make() {
      final storage = _Storage();
      return StarSyncEngine(
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        transportFactory: (_) => remote,
        kdfParams: kdf,
      );
    }

    final a = make();
    final b = make();
    await a.setUp(config, 'correct horse');
    await b.setUp(config, 'correct horse');
    await a.resetRemote('new passphrase');
    await b.syncNow();
    expect(b.status.value.status, StarSyncStatus.needsPassphrase);
    await b.rejoin('new passphrase');
    expect(b.status.value.status, StarSyncStatus.ok);
  });

  test('corrupt remote files are skipped', () async {
    final remote = _Transport();
    final storage = _Storage();
    final engine = StarSyncEngine(
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await engine.setUp(config, 'correct horse');
    remote.files['stars/devices/other'] = [1, 2, 3];
    expect((await engine.syncNow()).skippedFiles, 1);
  });

  test('different nonempty accounts are skipped', () async {
    final remote = _Transport();
    final first = _Storage();
    final second = _Storage();
    final a = StarSyncEngine(
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      transportFactory: (_) => remote,
      loginId: () => 'first',
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      activityStore: GakujoActivityStore(secureStorage: second),
      secureStorage: second,
      transportFactory: (_) => remote,
      loginId: () => 'second',
      kdfParams: kdf,
    );
    await a.setUp(config, 'correct horse');
    await b.setUp(config, 'correct horse');
    expect((await b.syncNow()).skippedFiles, 1);
  });

  test('a star toggled during network listing is retained', () async {
    final remote = _Transport();
    final storage = _Storage();
    final activity = GakujoActivityStore(secureStorage: storage);
    final engine = StarSyncEngine(
      activityStore: activity,
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await engine.setUp(config, 'correct horse');
    final started = Completer<void>();
    final release = Completer<void>();
    remote.listStarted = started;
    remote.listRelease = release;
    final syncing = engine.syncNow();
    await started.future;
    await activity.toggleStarredMessage(
      GakujoStarredMessage(
        keijitype: '1',
        genrecd: '2',
        seqNo: '3',
        title: 'Title',
        starredAt: DateTime.utc(2026),
      ),
    );
    release.complete();
    await syncing;
    expect((await activity.loadStarredMessages()).single.title, 'Title');
  });

  test('a keyring creation race adopts the winning keyring', () async {
    final remote = _Transport();
    StarSyncEngine make() {
      final storage = _Storage();
      return StarSyncEngine(
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        transportFactory: (_) => remote,
        kdfParams: kdf,
      );
    }

    await make().setUp(config, 'correct horse');
    remote.simulateKeyringRace = true;
    final b = make();
    await b.setUp(config, 'correct horse');
    expect(b.status.value.status, StarSyncStatus.ok);
    expect((await b.listDevices()).length, 2);
  });

  test('bulk replacement preserves remote stars', () async {
    final remote = _Transport();
    final first = _Storage();
    final second = _Storage();
    final activityA = GakujoActivityStore(secureStorage: first);
    final activityB = GakujoActivityStore(secureStorage: second);
    final a = StarSyncEngine(
      activityStore: activityA,
      secureStorage: first,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      activityStore: activityB,
      secureStorage: second,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await a.setUp(config, 'correct horse');
    await activityA.upsertStarredMessage(
      GakujoStarredMessage(
        keijitype: '1',
        genrecd: '2',
        seqNo: '3',
        title: 'Title',
        starredAt: DateTime.utc(2026),
      ),
    );
    await a.syncNow();
    await b.setUp(config, 'correct horse');
    await b.markBulkReplace();
    await activityB.replaceStarredMessages(const []);
    await b.syncNow();
    expect((await activityB.loadStarredMessages()).single.title, 'Title');
  });

  test('concurrent changes converge after two rounds', () async {
    final remote = _Transport();
    final first = _Storage();
    final second = _Storage();
    final activityA = GakujoActivityStore(secureStorage: first);
    final activityB = GakujoActivityStore(secureStorage: second);
    final a = StarSyncEngine(
      activityStore: activityA,
      secureStorage: first,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      activityStore: activityB,
      secureStorage: second,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    GakujoStarredMessage star(String id) => GakujoStarredMessage(
      keijitype: '1',
      genrecd: '2',
      seqNo: id,
      title: id,
      starredAt: DateTime.utc(2026),
    );
    await a.setUp(config, 'correct horse');
    await activityA.upsertStarredMessage(star('3'));
    await a.syncNow();
    await b.setUp(config, 'correct horse');
    await activityA.removeStarredMessage('1|2|3');
    await activityB.upsertStarredMessage(star('4'));
    await a.syncNow();
    await b.syncNow();
    await a.syncNow();
    await b.syncNow();
    final idsA = (await activityA.loadStarredMessages())
        .map((e) => e.id)
        .toSet();
    final idsB = (await activityB.loadStarredMessages())
        .map((e) => e.id)
        .toSet();
    expect(idsA, {'1|2|4'});
    expect(idsB, idsA);
  });

  test('disable deletes this device file once when requested', () async {
    final remote = _Transport();
    final storage = _Storage();
    final engine = StarSyncEngine(
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await engine.setUp(config, 'correct horse');
    await engine.disable(deleteOwnRemoteFile: true);
    expect(remote.deletes, 1);
  });
}
