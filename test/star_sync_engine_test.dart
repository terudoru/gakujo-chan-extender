import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_crypto.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_document.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failStarWriteOnce = false;
  void Function()? onStarRead;

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
    if (key == 'more_better_gakujo_starred_messages') onStarRead?.call();
    return values[key];
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
  int lists = 0;
  int serverFailures = 0;
  final gets = <String, int>{};
  Completer<void>? listStarted;
  Completer<void>? listRelease;
  bool failDevicePutOnce = false;
  bool simulateKeyringRace = false;
  bool _racePending = false;
  List<int>? overwriteKeyring;
  bool revoked = false;
  Completer<void>? devicePut;

  @override
  void close() {}

  @override
  Future<void> ensureDirectory(String path) async {}

  @override
  Future<List<StarSyncRemoteEntry>> list(String directory) async {
    lists++;
    if (revoked) {
      throw const StarSyncGoogleAuthException(
        StarSyncGoogleAuthErrorKind.revoked,
      );
    }
    if (serverFailures > 0) {
      serverFailures--;
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.server,
        'busy',
        statusCode: 503,
      );
    }
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
    if (path.startsWith('stars/devices/')) devicePut?.complete();
  }

  @override
  Future<void> delete(String path) async {
    deletes++;
    files.remove(path);
  }
}

class _TestTimer implements Timer {
  _TestTimer(this.callback);
  final void Function() callback;
  bool active = true;
  @override
  bool get isActive => active;
  @override
  int get tick => active ? 0 : 1;
  @override
  void cancel() => active = false;
  void fire() {
    if (!active) return;
    active = false;
    callback();
  }
}

void main() {
  const config = StarSyncConfig(backend: StarSyncBackend.webDav);
  const kdf = StarSyncKdfParams(memoryKiB: 8, iterations: 1);

  test('account change waits for the complete sync', () async {
    final remote = _Transport();
    final storage = _Storage();
    var account = 'student';
    final engine = StarSyncEngine(
      loginId: () => account,
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await engine.setUp(config, 'pass');
    remote.listStarted = Completer<void>();
    remote.listRelease = Completer<void>();
    final started = remote.listStarted!;
    final release = remote.listRelease!;
    final syncing = engine.syncNow();
    await started.future;
    var changed = false;
    final change = engine.runAccountChange(() async {
      account = 'other';
      changed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(changed, isFalse);
    release.complete();
    await syncing;
    await change;
    final puts = remote.puts;
    await engine.syncNow();
    expect(remote.puts, puts);
    expect(engine.status.value.status, StarSyncStatus.accountMismatch);
  });

  test('setup rechecks account before clearing or installing', () async {
    for (final pairing in [false, true]) {
      final remote = _Transport();
      final storage = _Storage();
      final activity = GakujoActivityStore(secureStorage: storage);
      var account = 'student';
      final engine = StarSyncEngine(
        loginId: () => account,
        activityStore: activity,
        secureStorage: storage,
        transportFactory: (_) => remote,
        kdfParams: kdf,
      );
      await activity.upsertStarredMessage(
        GakujoStarredMessage(
          keijitype: '1',
          genrecd: '2',
          seqNo: '3',
          title: 'kept',
          starredAt: DateTime.utc(2026),
        ),
      );
      remote.listStarted = Completer<void>();
      remote.listRelease = Completer<void>();
      final started = remote.listStarted!;
      final release = remote.listRelease!;
      final setup = pairing
          ? engine.setUpWithPairing(
              config,
              resetExisting: true,
              clearLocalStars: true,
            )
          : engine.setUp(
              config,
              'pass',
              resetExisting: true,
              clearLocalStars: true,
            );
      await started.future;
      await engine.runAccountChange(() async {
        account = 'other';
      });
      release.complete();
      await expectLater(
        setup,
        throwsA(isA<StarSyncAccountMismatchException>()),
      );
      expect((await activity.loadStarredMessages()).single.title, 'kept');
      expect(engine.status.value.enabled, isFalse);
      expect(storage.values.containsKey(starSyncStateKey), isFalse);
    }
  });

  test('pairing join rechecks the account before installation', () async {
    final remote = _Transport();
    final first = _Storage();
    final second = _Storage();
    final a = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      transportFactory: (_) => remote,
    );
    await a.setUpWithPairing(config);
    final code = await a.pairingCode();
    var account = 'student';
    final activity = GakujoActivityStore(secureStorage: second);
    await activity.upsertStarredMessage(
      GakujoStarredMessage(
        keijitype: '1',
        genrecd: '2',
        seqNo: '3',
        title: 'kept',
        starredAt: DateTime.utc(2026),
      ),
    );
    final b = StarSyncEngine(
      loginId: () => account,
      activityStore: activity,
      secureStorage: second,
      transportFactory: (_) => remote,
    );
    remote.listStarted = Completer<void>();
    remote.listRelease = Completer<void>();
    final started = remote.listStarted!;
    final release = remote.listRelease!;
    final joining = b.joinWithPairingCode(config, code, clearLocalStars: true);
    await started.future;
    await b.runAccountChange(() async {
      account = 'other';
    });
    release.complete();
    await expectLater(
      joining,
      throwsA(isA<StarSyncAccountMismatchException>()),
    );
    expect((await activity.loadStarredMessages()).single.title, 'kept');
    expect(b.status.value.enabled, isFalse);
  });

  test('reset in memory cancels timers without writing storage', () async {
    final remote = _Transport();
    final storage = _Storage();
    _TestTimer? timer;
    final engine = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
      timerFactory: (_, callback) => timer = _TestTimer(callback),
    );
    await engine.setUp(config, 'pass');
    engine.scheduleSync();
    await engine.resetInMemory();
    expect(timer!.isActive, isFalse);
    expect(engine.status.value.enabled, isFalse);
    expect(storage.values.containsKey(starSyncConfigKey), isTrue);
  });

  test(
    'feature gate prevents cooldown retry and preserves pending change',
    () async {
      final remote = _Transport();
      final storage = _Storage();
      var allowed = true;
      var now = DateTime.utc(2026);
      _TestTimer? timer;
      final engine = StarSyncEngine(
        loginId: () => 'student',
        canSync: () => allowed,
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        transportFactory: (_) => remote,
        kdfParams: kdf,
        now: () => now,
        timerFactory: (_, callback) => timer = _TestTimer(callback),
      );
      await engine.setUp(config, 'pass');
      remote.serverFailures = 1;
      await expectLater(
        engine.syncNow(trigger: StarSyncTrigger.localChange),
        throwsA(isA<StarSyncTransportException>()),
      );
      final lists = remote.lists;
      allowed = false;
      now = now.add(const Duration(minutes: 3));
      timer!.fire();
      await Future<void>.delayed(Duration.zero);
      expect(remote.lists, lists);
      final state = StarSyncState.fromJson(
        jsonDecode(storage.values[starSyncStateKey]!),
      );
      expect(state.pendingLocalChange, isTrue);
    },
  );

  test('cap eviction stays deleted when an old device returns', () async {
    final remote = _Transport();
    final first = _Storage();
    final second = _Storage();
    StarSyncEngine make(_Storage storage) => StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    GakujoStarredMessage star(int id) => GakujoStarredMessage(
      keijitype: '1',
      genrecd: '2',
      seqNo: '$id',
      title: 'star',
      starredAt: DateTime.utc(2026).add(Duration(seconds: id)),
    );
    final a = make(first);
    final b = make(second);
    await a.setUp(config, 'pass');
    await a.activityStore.upsertStarredMessage(star(0));
    await a.syncNow();
    await b.setUp(config, 'pass');
    await b.activityStore.replaceStarredMessages(
      List.generate(300, (i) => star(i + 1)),
    );
    await b.syncNow();
    final state = StarSyncState.fromJson(
      jsonDecode(second.values[starSyncStateKey]!),
    );
    expect(state.records['1|2|0']!.starred, isFalse);
    expect(state.records['1|2|0']!.title, isEmpty);
    await b.activityStore.removeStarredMessage('1|2|300');
    await b.syncNow();
    expect(
      (await b.activityStore.loadStarredMessages()).any((s) => s.id == '1|2|0'),
      isFalse,
    );
  });

  test('all setup paths require an account before any work', () async {
    for (final id in <String?>[null, '', '   ']) {
      final storage = _Storage();
      var transports = 0;
      final engine = StarSyncEngine(
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        loginId: () => id,
        transportFactory: (_) {
          transports++;
          return _Transport();
        },
      );
      await expectLater(
        engine.setUp(config, 'passphrase'),
        throwsA(isA<StarSyncAccountRequiredException>()),
      );
      await expectLater(
        engine.setUpWithPairing(config),
        throwsA(isA<StarSyncAccountRequiredException>()),
      );
      await expectLater(
        engine.joinWithPairingCode(config, 'invalid'),
        throwsA(isA<StarSyncAccountRequiredException>()),
      );
      expect(storage.values, isEmpty);
      expect(transports, 0);
    }
  });

  test(
    'account changes stop all sync work until the account returns',
    () async {
      final remote = _Transport();
      final storage = _Storage();
      final activity = GakujoActivityStore(secureStorage: storage);
      String? id = 'student';
      var transports = 0;
      final engine = StarSyncEngine(
        activityStore: activity,
        secureStorage: storage,
        loginId: () => id,
        transportFactory: (_) {
          transports++;
          return remote;
        },
        kdfParams: kdf,
      );
      await engine.setUp(config, 'correct horse');
      await activity.upsertStarredMessage(
        GakujoStarredMessage(
          keijitype: '1',
          genrecd: '2',
          seqNo: '3',
          title: 'Local',
          starredAt: DateTime.utc(2026),
        ),
      );
      final before = jsonEncode(
        (await activity.loadStarredMessages()).map((e) => e.toJson()).toList(),
      );
      final calls = transports;
      final puts = remote.puts;
      for (final changedId in <String?>['other', null, '']) {
        id = changedId;
        await engine.syncNow();
        expect(engine.status.value.status, StarSyncStatus.accountMismatch);
        expect(transports, calls);
        expect(remote.puts, puts);
        expect(
          jsonEncode(
            (await activity.loadStarredMessages())
                .map((e) => e.toJson())
                .toList(),
          ),
          before,
        );
        await expectLater(
          engine.pairingCode(),
          throwsA(isA<StarSyncAccountMismatchException>()),
        );
        await expectLater(
          engine.rejoinWithPairingCode('invalid'),
          throwsA(isA<StarSyncAccountMismatchException>()),
        );
        await expectLater(
          engine.rejoin('passphrase'),
          throwsA(isA<StarSyncAccountMismatchException>()),
        );
        await expectLater(
          engine.changePassphrase('old', 'new'),
          throwsA(isA<StarSyncAccountMismatchException>()),
        );
        await expectLater(
          engine.resetRemote('passphrase'),
          throwsA(isA<StarSyncAccountMismatchException>()),
        );
        await expectLater(
          engine.resetRemoteWithPairing(),
          throwsA(isA<StarSyncAccountMismatchException>()),
        );
      }
      expect(transports, calls);
      id = 'student';
      await engine.syncNow();
      expect(engine.status.value.status, StarSyncStatus.ok);
      expect(transports, greaterThan(calls));
      expect(remote.puts, greaterThan(puts));
    },
  );

  test('old state without a bound account stops before transport', () async {
    final remote = _Transport();
    final storage = _Storage();
    var transports = 0;
    StarSyncEngine make() => StarSyncEngine(
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      loginId: () => 'student',
      transportFactory: (_) {
        transports++;
        return remote;
      },
      kdfParams: kdf,
    );
    await make().setUp(config, 'correct horse');
    final state =
        jsonDecode(storage.values[starSyncStateKey]!) as Map<String, dynamic>;
    state.remove('boundAccount');
    storage.values[starSyncStateKey] = jsonEncode(state);
    final engine = make();
    await engine.load();
    final calls = transports;
    await engine.syncNow();
    expect(engine.status.value.status, StarSyncStatus.accountMismatch);
    expect(transports, calls);
  });

  test('a document without an account is skipped', () async {
    final remote = _Transport();
    final storage = _Storage();
    final activity = GakujoActivityStore(secureStorage: storage);
    final engine = StarSyncEngine(
      activityStore: activity,
      secureStorage: storage,
      loginId: () => 'student',
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await engine.setUp(config, 'correct horse');
    final state =
        jsonDecode(storage.values[starSyncStateKey]!) as Map<String, dynamic>;
    final document = StarSyncDocument(
      deviceId: 'other',
      writtenAt: DateTime.utc(2026),
      clock: 0,
      records: {},
    );
    remote.files['stars/devices/other'] = await encryptStarSyncFile(
      dataKey: starSyncKeyFromBytes(base64Decode(state['dataKey'] as String)),
      keyId: state['keyId'] as String,
      deviceId: 'other',
      plaintext: document.toBytes(),
    );
    expect((await engine.syncNow()).skippedFiles, 1);
    expect(await activity.loadStarredMessages(), isEmpty);
  });

  test('idle sync skips downloads and upload until keyring changes', () async {
    final remote = _Transport();
    final storage = _Storage();
    final engine = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await engine.setUp(config, 'correct horse');
    final gets = Map<String, int>.from(remote.gets);
    final puts = remote.puts;
    await engine.syncNow();
    expect(remote.gets, gets);
    expect(remote.puts, puts);
    remote.files['stars/keyring.json'] = [
      ...remote.files['stars/keyring.json']!,
      32,
    ];
    await engine.syncNow();
    expect(remote.gets['stars/keyring.json'], gets['stars/keyring.json']! + 1);
  });

  test('resume is throttled, daily cap does not block manual sync', () async {
    final remote = _Transport();
    final storage = _Storage();
    var now = DateTime(2026, 11, 1, 12);
    final delays = <Duration>[];
    StarSyncEngine make() => StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
      now: () => now,
      random: Random(4),
      delay: (duration) async => delays.add(duration),
    );
    var engine = make();
    await engine.setUp(config, 'correct horse');
    var lists = remote.lists;
    await engine.syncNow(trigger: StarSyncTrigger.resume);
    expect(remote.lists, lists);
    now = now.add(const Duration(minutes: 2));
    await engine.syncNow(trigger: StarSyncTrigger.resume);
    expect(remote.lists, lists + 2);
    expect(delays.single.inMilliseconds, inInclusiveRange(0, 20000));
    final saved =
        jsonDecode(storage.values[starSyncStateKey]!) as Map<String, dynamic>;
    saved['backgroundDate'] = '2026-11-1';
    saved['backgroundCount'] = 120;
    storage.values[starSyncStateKey] = jsonEncode(saved);
    engine = make();
    await engine.load();
    now = now.add(const Duration(minutes: 2));
    lists = remote.lists;
    await engine.syncNow(trigger: StarSyncTrigger.startup);
    expect(remote.lists, lists);
    await engine.syncNow(trigger: StarSyncTrigger.manual);
    expect(remote.lists, lists + 2);
  });

  test(
    'server cooldown doubles, preserves local work and resets on success',
    () async {
      final remote = _Transport();
      final storage = _Storage();
      var now = DateTime(2026, 11, 1, 12);
      final engine = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        transportFactory: (_) => remote,
        kdfParams: kdf,
        now: () => now,
        delay: (_) async {},
      );
      await engine.setUp(config, 'correct horse');
      remote.serverFailures = 2;
      await expectLater(
        engine.syncNow(),
        throwsA(isA<StarSyncTransportException>()),
      );
      expect(
        engine.status.value.cooldownUntil,
        now.add(const Duration(minutes: 1)),
      );
      await engine.syncNow(trigger: StarSyncTrigger.localChange);
      var saved =
          jsonDecode(storage.values[starSyncStateKey]!) as Map<String, dynamic>;
      expect(saved['pendingLocalChange'], isTrue);
      await expectLater(
        engine.syncNow(),
        throwsA(isA<StarSyncTransportException>()),
      );
      expect(
        engine.status.value.cooldownUntil,
        now.add(const Duration(minutes: 2)),
      );
      now = now.add(const Duration(minutes: 2));
      await engine.syncNow(trigger: StarSyncTrigger.resume);
      saved =
          jsonDecode(storage.values[starSyncStateKey]!) as Map<String, dynamic>;
      expect(saved['pendingLocalChange'], isFalse);
      expect(saved['serverFailures'], 0);
      expect(engine.status.value.cooldownUntil, isNull);
    },
  );

  test('local change wakes a delayed startup sync', () async {
    final remote = _Transport();
    final storage = _Storage();
    var now = DateTime(2026, 11, 1, 12);
    final waiting = Completer<void>();
    final entered = Completer<Duration>();
    final engine = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
      now: () => now,
      random: Random(3),
      delay: (duration) {
        entered.complete(duration);
        return waiting.future;
      },
    );
    await engine.setUp(config, 'correct horse');
    now = now.add(const Duration(minutes: 2));
    final startup = engine.syncNow(trigger: StarSyncTrigger.startup);
    expect((await entered.future).inMilliseconds, inInclusiveRange(0, 20000));
    final local = engine.syncNow(trigger: StarSyncTrigger.localChange);
    await Future.wait([startup, local]);
    expect(engine.status.value.lastSyncAt, now.toUtc());
  });

  test('two devices share stars and propagate deletion', () async {
    final remote = _Transport();
    final storageA = _Storage();
    final storageB = _Storage();
    final activityA = GakujoActivityStore(secureStorage: storageA);
    final activityB = GakujoActivityStore(secureStorage: storageB);
    final a = StarSyncEngine(
      loginId: () => 'student',
      activityStore: activityA,
      secureStorage: storageA,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      loginId: () => 'student',
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
      loginId: () => 'student',
      activityStore: activityA,
      secureStorage: storageA,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      loginId: () => 'student',
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
      loginId: () => 'student',
      activityStore: activityA,
      secureStorage: storageA,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      loginId: () => 'student',
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
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    ).setUp(config, 'correct horse');
    final engine = StarSyncEngine(
      loginId: () => 'student',
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
      loginId: () => 'student',
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
      loginId: () => 'student',
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
        loginId: () => 'student',
        activityStore: activity,
        secureStorage: first,
        transportFactory: (_) => remote,
        kdfParams: kdf,
      );
      final b = StarSyncEngine(
        loginId: () => 'student',
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
        loginId: () => 'student',
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
      loginId: () => 'student',
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
      loginId: () => 'student',
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
        loginId: () => 'student',
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
      loginId: () => 'student',
      activityStore: activityA,
      secureStorage: first,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      loginId: () => 'student',
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
      loginId: () => 'student',
      activityStore: activityA,
      secureStorage: first,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    final b = StarSyncEngine(
      loginId: () => 'student',
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
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await engine.setUp(config, 'correct horse');
    await engine.disable(deleteOwnRemoteFile: true);
    expect(remote.deletes, 1);
  });
  test(
    'disabled setup reset removes old files and clears local stars',
    () async {
      final remote = _Transport();
      final storage = _Storage();
      final activity = GakujoActivityStore(secureStorage: storage);
      final engine = StarSyncEngine(
        loginId: () => 'student',
        activityStore: activity,
        secureStorage: storage,
        transportFactory: (_) => remote,
        kdfParams: kdf,
      );
      await engine.setUp(config, 'old');
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
      expect(await engine.localStarCount(), 1);
      await engine.setUp(
        config,
        'new',
        resetExisting: true,
        clearLocalStars: true,
      );
      expect(await engine.localStarCount(), 0);
      expect(remote.files['stars/keyring.json'], isNot(oldKeyring));
      expect(oldDevices.where(remote.files.containsKey), isEmpty);
      final state = StarSyncState.fromJson(
        jsonDecode(storage.values[starSyncStateKey]!),
      );
      expect(state.records, isEmpty);
    },
  );

  test('setup uses keyring overwritten after a successful create', () async {
    final remote = _Transport();
    final first = _Storage();
    final a = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: first),
      secureStorage: first,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await a.setUp(config, 'same');
    final keyring = List<int>.of(remote.files['stars/keyring.json']!);
    remote.files.clear();
    remote.overwriteKeyring = keyring;
    final second = _Storage();
    final b = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: second),
      secureStorage: second,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await b.setUp(config, 'same');
    expect(await b.pairingCode(), await a.pairingCode());
  });

  test(
    'overwritten keyring with another passphrase is not installed',
    () async {
      final remote = _Transport();
      final first = _Storage();
      final a = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: first),
        secureStorage: first,
        transportFactory: (_) => remote,
        kdfParams: kdf,
      );
      await a.setUp(config, 'other');
      final keyring = List<int>.of(remote.files['stars/keyring.json']!);
      remote.files.clear();
      remote.overwriteKeyring = keyring;
      final second = _Storage();
      final b = StarSyncEngine(
        loginId: () => 'student',
        activityStore: GakujoActivityStore(secureStorage: second),
        secureStorage: second,
        transportFactory: (_) => remote,
        kdfParams: kdf,
      );
      await expectLater(
        b.setUp(config, 'pass'),
        throwsA(isA<StarSyncWrongPassphraseException>()),
      );
      expect(second.values, isEmpty);
    },
  );

  test('disable does not wait for background jitter', () async {
    final remote = _Transport();
    final storage = _Storage();
    final delayStarted = Completer<void>();
    final release = Completer<void>();
    final engine = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
      now: () => DateTime.utc(2026).add(const Duration(minutes: 3)),
      delay: (_) {
        delayStarted.complete();
        return release.future;
      },
    );
    await engine.setUp(config, 'pass');
    final state = StarSyncState.fromJson(
      jsonDecode(storage.values[starSyncStateKey]!),
    );
    state.lastSyncAt = DateTime.utc(2026);
    storage.values[starSyncStateKey] = jsonEncode(state.toJson());
    await engine.load();
    final background = engine.syncNow(trigger: StarSyncTrigger.resume);
    await delayStarted.future;
    await engine.disable().timeout(const Duration(seconds: 1));
    release.complete();
    await background;
    expect(engine.status.value.enabled, isFalse);
  });

  test('failed restore preserves the previous bulk flag', () async {
    final remote = _Transport();
    final storage = _Storage();
    final engine = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await engine.setUp(config, 'pass');
    for (final previous in [false, true]) {
      if (previous) await engine.markBulkReplace();
      await expectLater(
        engine.withBulkReplace(() async => throw StateError('failed')),
        throwsStateError,
      );
      final state = StarSyncState.fromJson(
        jsonDecode(storage.values[starSyncStateKey]!),
      );
      expect(state.pendingBulkReplace, previous);
    }
  });

  test('cooldown timer sends pending local change', () async {
    final remote = _Transport();
    final storage = _Storage();
    var now = DateTime.utc(2026);
    _TestTimer? timer;
    final engine = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
      now: () => now,
      timerFactory: (_, callback) => timer = _TestTimer(callback),
    );
    await engine.setUp(config, 'pass');
    await engine.activityStore.upsertStarredMessage(
      GakujoStarredMessage(
        keijitype: '1',
        genrecd: '2',
        seqNo: '3',
        title: 'pending',
        starredAt: DateTime.utc(2026),
      ),
    );
    remote.serverFailures = 1;
    await expectLater(
      engine.syncNow(trigger: StarSyncTrigger.localChange),
      throwsA(isA<StarSyncTransportException>()),
    );
    expect(timer, isNotNull);
    final sent = Completer<void>();
    remote.devicePut = sent;
    now = now.add(const Duration(minutes: 2));
    timer!.fire();
    await sent.future.timeout(const Duration(seconds: 2));
    expect(remote.puts, greaterThan(1));
    engine.dispose();
  });

  test(
    'account change inside local transform aborts without star writes',
    () async {
      final remote = _Transport();
      final storage = _Storage();
      var account = 'student';
      final engine = StarSyncEngine(
        loginId: () => account,
        activityStore: GakujoActivityStore(secureStorage: storage),
        secureStorage: storage,
        transportFactory: (_) => remote,
        kdfParams: kdf,
      );
      await engine.setUp(config, 'pass');
      final puts = remote.puts;
      final before = storage.values['more_better_gakujo_starred_messages'];
      storage.onStarRead = () {
        account = 'another';
      };
      await engine.syncNow();
      expect(engine.status.value.status, StarSyncStatus.accountMismatch);
      expect(storage.values['more_better_gakujo_starred_messages'], before);
      expect(remote.puts, puts);
    },
  );

  test('revoked Google credentials request sign in without cooldown', () async {
    final remote = _Transport();
    final storage = _Storage();
    final engine = StarSyncEngine(
      loginId: () => 'student',
      activityStore: GakujoActivityStore(secureStorage: storage),
      secureStorage: storage,
      transportFactory: (_) => remote,
      kdfParams: kdf,
    );
    await engine.setUp(config, 'pass');
    remote.revoked = true;
    await engine.syncNow();
    expect(engine.status.value.status, StarSyncStatus.needsGoogleSignIn);
    expect(engine.status.value.lastError, 'Google へのログインが必要です');
    expect(engine.status.value.cooldownUntil, isNull);
  });
}
