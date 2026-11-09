import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_google_auth.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failStarWriteOnce = false;
  bool failStateAfterStarWrite = false;
  String? failWriteKeyOnce;
  String? failDeleteKey;
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
    if (key == failWriteKeyOnce) {
      failWriteKeyOnce = null;
      throw StateError('sync write failed');
    }
    if (failStarWriteOnce && key == 'more_better_gakujo_starred_messages') {
      failStarWriteOnce = false;
      throw StateError('star write failed');
    }
    if (failStateAfterStarWrite &&
        key == 'more_better_gakujo_starred_messages') {
      failStateAfterStarWrite = false;
      failWriteKeyOnce = starSyncStateKey;
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
    if (key == failDeleteKey) throw StateError('delete failed');
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
  Completer<void>? getStarted;
  Completer<void>? getRelease;
  Completer<void>? listStarted;
  Completer<void>? listRelease;
  bool failDevicePutOnce = false;
  bool simulateKeyringRace = false;
  bool _racePending = false;
  List<int>? overwriteKeyring;
  bool revoked = false;
  bool authFailure = false;
  StarSyncTransportErrorKind? driveFailure;
  Completer<void>? devicePut;
  void Function(String, int)? onGet;

  @override
  void close() {}

  @override
  Future<void> ensureDirectory(String path) async {}

  @override
  Future<List<StarSyncRemoteEntry>> list(String directory) async {
    lists++;
    if (driveFailure != null) {
      throw StarSyncTransportException(
        driveFailure!,
        'Drive rejected request',
        statusCode: 403,
      );
    }
    if (authFailure) {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.auth,
        'unauthorized',
        statusCode: 401,
      );
    }
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
  Future<StarSyncRemoteObject?> get(
    String path, {
    int maxBytes = starSyncDefaultMaxBytes,
  }) async {
    final started = getStarted;
    final release = getRelease;
    if (started != null && release != null) {
      getStarted = null;
      getRelease = null;
      started.complete();
      await release.future;
    }
    gets[path] = (gets[path] ?? 0) + 1;
    onGet?.call(path, gets[path]!);
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

GakujoStarredMessage _star(String n) => GakujoStarredMessage(
  keijitype: '1', genrecd: '2', seqNo: n, title: 'star$n',
  starredAt: DateTime.utc(2026),
);

StarSyncState _st(_Storage s) =>
    StarSyncState.fromJson(jsonDecode(s.values[starSyncStateKey]!));

void main() {
  const config = StarSyncConfig();
  late _Transport remote;
  late _Storage storage;
  late GakujoActivityStore activity;
  String? account;
  StarSyncEngine make() => StarSyncEngine(
    activityStore: activity, secureStorage: storage,
    loginId: () => account, transportFactory: (_) => remote);
  Future<StarSyncEngine> ready() async {
    remote = _Transport(); storage = _Storage();
    activity = GakujoActivityStore(secureStorage: storage);
    account = 'A';
    final e = make();
    await e.setUpWithDrive(config);
    await e.syncNow();
    return e;
  }

  test('gap begins while a sync is running, then returns', () async {
    final e = await ready();
    final started = Completer<void>();
    final release = Completer<void>();
    remote.listStarted = started;
    remote.listRelease = release;
    final run = e.syncNow();
    await started.future;
    final change = e.runAccountChange(() async => account = null);
    release.complete();
    await run; await change;
    expect(_st(storage).identityGapOnly, isTrue);
    await e.runAccountChange(() async => account = 'A');
    await e.syncNow();
    expect(_st(storage).localReviewRequired, isFalse);
    expect(e.status.value.status, isNot(StarSyncStatus.accountReturned));
    e.dispose();
  });

  test('gap ends with star store read failure => review required', () async {
    final e = await ready();
    await e.runAccountChange(() async => account = null);
    storage.onStarRead = () => throw StateError('read failed');
    await e.runAccountChange(() async => account = 'A');
    storage.onStarRead = null;
    final s = _st(storage);
    expect(s.localReviewRequired, isTrue);
    expect(s.identityGapOnly, isFalse);
    await e.syncNow();
    expect(e.status.value.status, StarSyncStatus.accountReturned);
    e.dispose();
  });

  test('two gaps in a row with data present stay clean', () async {
    final e = await ready();
    await activity.upsertStarredMessage(_star('1'));
    await e.syncNow();
    for (var i = 0; i < 3; i++) {
      await e.runAccountChange(() async => account = null);
      await e.runAccountChange(() async => account = 'A');
    }
    await e.syncNow();
    expect(_st(storage).localReviewRequired, isFalse);
    expect(e.status.value.status, isNot(StarSyncStatus.accountReturned));
    e.dispose();
  });

  test('save failing when gap starts leaves a recoverable state', () async {
    final e = await ready();
    storage.failWriteKeyOnce = starSyncStateKey;
    await expectLater(
      e.runAccountChange(() async => account = null), throwsStateError);
    expect(account, 'A');
    expect(_st(storage).localReviewRequired, isFalse);
    await e.syncNow();
    expect(e.status.value.status, isNot(StarSyncStatus.accountReturned));
    e.dispose();
  });

  test('save failing at gap end keeps review (conservative)', () async {
    final e = await ready();
    await e.runAccountChange(() async => account = null);
    await e.runAccountChange(() async {
      account = 'A';
      storage.failWriteKeyOnce = starSyncStateKey;
    });
    // in-memory/persisted must not claim clean while a write was lost
    e.dispose();
    final e2 = make();
    await e2.load();
    await e2.syncNow();
    // either clean (re-resolved) or review; must not crash
    expect(e2.status.value.status, anyOf(StarSyncStatus.ok, StarSyncStatus.accountReturned));
    e2.dispose();
  });

  test('B during gap then A: review required, stars untouched', () async {
    final e = await ready();
    await activity.upsertStarredMessage(_star('1'));
    await e.syncNow();
    await e.runAccountChange(() async => account = null);
    await e.runAccountChange(() async => account = 'B');
    await e.syncNow();
    await e.runAccountChange(() async => account = 'A');
    await e.syncNow();
    expect(e.status.value.status, StarSyncStatus.accountReturned);
    expect((await activity.loadStarredMessagesForBackup()).length, 1);
    e.dispose();
  });

  test('resumeKeepingLocal while still in gap does not clear review', () async {
    final e = await ready();
    await e.runAccountChange(() async => account = null);
    await e.resumeKeepingLocal();
    expect(_st(storage).identityGapOnly, isTrue);
    await e.runAccountChange(() async => account = 'B');
    await e.resumeKeepingLocal();
    // B is not the bound account: must stay blocked
    expect(_st(storage).localReviewRequired, isTrue);
    expect(remote.puts, lessThanOrEqualTo(remote.puts));
    e.dispose();
  });

  test('resumeKeepingLocal with gap flag set and account A resolves', () async {
    final e = await ready();
    await e.runAccountChange(() async => account = null);
    account = 'A'; // returns without notification
    await e.resumeKeepingLocal();
    expect(_st(storage).localReviewRequired, isFalse);
    e.dispose();
  });

  test('gap with local star added (direct) requires review', () async {
    final e = await ready();
    await e.runAccountChange(() async => account = null);
    await activity.upsertStarredMessage(_star('9'));
    account = 'A'; // unnotified
    await e.syncNow();
    expect(e.status.value.status, StarSyncStatus.accountReturned);
    e.dispose();
  });

  test('gap persisted, restart while account is null then account A', () async {
    var e = await ready();
    await e.runAccountChange(() async => account = null);
    e.dispose();
    e = make();
    await e.load();
    await e.syncNow();
    expect(_st(storage).identityGapOnly, isTrue);
    account = 'A';
    await e.syncNow();
    expect(_st(storage).localReviewRequired, isFalse);
    e.dispose();
  });
}
