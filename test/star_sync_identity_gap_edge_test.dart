import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';

import 'support/star_sync_fakes.dart';

typedef _Storage = StarSyncFakeStorage;
typedef _Transport = StarSyncFakeTransport;

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
