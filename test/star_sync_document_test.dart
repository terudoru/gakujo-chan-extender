import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_document.dart';

final now = DateTime.utc(2026, 10, 31);

StarSyncRecord record(
  int id, {
  int clock = 1,
  String device = 'a',
  String title = 'title',
  bool starred = true,
  DateTime? at,
  DateTime? updated,
}) => StarSyncRecord(
  id: '1|2|$id',
  title: title,
  starred: starred,
  starredAt: at ?? now,
  clock: clock,
  deviceId: device,
  updatedAt: updated ?? now,
);

GakujoStarredMessage local(
  int id, {
  String title = 'title',
  DateTime? at,
  String body = '',
}) => GakujoStarredMessage(
  keijitype: '1',
  genrecd: '2',
  seqNo: '$id',
  title: title,
  body: body,
  starredAt: at ?? now,
);

Map<String, Object?> jsonRecords(Map<String, StarSyncRecord> records) =>
    records.map((key, value) => MapEntry(key, value.toJson()));

void main() {
  test('winner uses clock and device, with title fallback', () {
    final a = record(1, clock: 3, title: 'old');
    final b = record(1, clock: 4, title: '', starred: false);
    expect(StarSyncRecord.pick(a, b).starred, false);
    expect(StarSyncRecord.pick(a, b).title, isEmpty);
    expect(
      StarSyncRecord.pick(b, record(1, clock: 4, device: 'z')).deviceId,
      'z',
    );
    expect(StarSyncRecord.pick(b, record(1, clock: 5)).starred, true);
  });

  test('document round trip skips bad records and rejects unknown schema', () {
    final doc = StarSyncDocument(
      deviceId: 'd',
      writtenAt: now,
      clock: 2,
      records: {'1|2|1': record(1, title: 'x' * 301)},
    );
    final decoded = StarSyncDocument.fromBytes(doc.toBytes());
    expect(decoded.records.values.single.title.length, 300);
    final json = doc.toJson();
    (json['stars'] as Map)['bad'] = {'title': 1};
    expect(StarSyncDocument.fromJson(json).records.length, 1);
    json['schema'] = 2;
    expect(
      () => StarSyncDocument.fromJson(json),
      throwsA(isA<StarSyncFormatException>()),
    );
    expect(
      () => StarSyncDocument.fromBytes(utf8.encode('[]')),
      throwsA(isA<StarSyncFormatException>()),
    );
    expect(StarSyncRecord.fromJson({'id': 'bad'}), isNull);
  });

  test(
    'merge is order independent and idempotent, including title fallback',
    () {
      final sources = [
        {'1|2|1': record(1, clock: 1, title: 'first')},
        {'1|2|1': record(1, clock: 2, title: 'second')},
        {'1|2|1': record(1, clock: 3, title: '')},
      ];
      final expected = jsonRecords(mergeStarSyncRecords(sources, now: now));
      for (var seed = 0; seed < 20; seed++) {
        final shuffled = [...sources]..shuffle(Random(seed));
        final merged = mergeStarSyncRecords(shuffled, now: now);
        expect(jsonRecords(merged), expected);
        expect(
          jsonRecords(mergeStarSyncRecords([merged, merged], now: now)),
          expected,
        );
      }
      expect(expected['1|2|1'], containsPair('title', 'second'));
    },
  );

  test('tombstones retain no title and GC uses logical order', () {
    final deleted = record(1, clock: 2, starred: false);
    final old = record(1, clock: 1, title: 'old');
    final merged = mergeStarSyncRecords([
      {old.id: old},
      {deleted.id: deleted},
    ], now: now.add(const Duration(days: 365)));
    expect(merged[old.id]!.starred, isFalse);
    expect(merged[old.id]!.title, isEmpty);
    final records = {
      for (var i = 0; i < 1005; i++)
        record(i, clock: i, starred: false).id: record(
          i,
          clock: i,
          starred: false,
        ),
    };
    final kept = mergeStarSyncRecords([records], now: now);
    expect(kept.length, 1000);
    expect(kept.containsKey('1|2|4'), isFalse);
    expect(kept.containsKey('1|2|5'), isTrue);
    expect(kept.values.every((r) => r.title.isEmpty), isTrue);
    expect(
      jsonRecords(kept),
      jsonRecords(
        mergeStarSyncRecords([
          Map.fromEntries(records.entries.toList().reversed),
        ], now: now.add(const Duration(days: 180))),
      ),
    );
  });

  test('merge preserves all live records for causal cap eviction', () {
    final a = {
      for (var i = 0; i < 320; i++)
        record(i, at: now.add(Duration(seconds: i))).id: record(
          i,
          at: now.add(Duration(seconds: i)),
        ),
    };
    final b = {
      for (var i = 320; i < 640; i++)
        record(i, at: now.add(Duration(seconds: i))).id: record(
          i,
          at: now.add(Duration(seconds: i)),
        ),
    };
    final first = mergeStarSyncRecords([a, b], now: now);
    final second = mergeStarSyncRecords([b, a], now: now);
    expect(first.length, 640);
    expect(jsonRecords(first), jsonRecords(second));
  });

  test('reconcile detects additions, restars, removals and title updates', () {
    final state = {
      for (final r in [
        record(1, starred: false, at: now.subtract(const Duration(seconds: 1))),
        record(2),
        record(3),
        record(4),
        record(5, starred: false),
      ])
        r.id: r,
    };
    final result = reconcileLocalStars(
      local: [
        local(1),
        local(2, at: now.add(const Duration(seconds: 1))),
        local(3, title: 'changed'),
        local(6),
      ],
      state: state,
      clock: 10,
      deviceId: 'new',
      now: now,
    );
    expect(result.clock, 14);
    expect(result.state['1|2|1']!.clock, 11);
    expect(result.state['1|2|2']!.clock, 12);
    expect(result.state['1|2|3']!.title, 'changed');
    expect(result.state['1|2|3']!.clock, 1);
    expect(result.state['1|2|4']!.starred, false);
    expect(result.state['1|2|5']!.clock, 1);
    expect(result.state['1|2|6']!.clock, 14);
    final bulk = reconcileLocalStars(
      local: [],
      state: state,
      clock: 10,
      deviceId: 'new',
      now: now,
      bulkReplace: true,
    );
    expect(bulk.clock, 10);
    expect(bulk.state['1|2|4']!.starred, true);
  });

  test('known star instances do not create local edits', () {
    final live = record(1, clock: 5);
    final deleted = record(2, clock: 6, starred: false);
    final previous = record(3, clock: 2, starred: false);
    final remote = record(3, clock: 7, at: now.add(const Duration(days: 1)));
    final result = reconcileLocalStars(
      local: [local(1), local(2), local(3)],
      state: {previous.id: previous},
      known: {live.id: live, deleted.id: deleted, remote.id: remote},
      clock: 7,
      deviceId: 'local',
      now: now,
    );
    expect(result.clock, 7);
    expect(result.state.keys, [previous.id]);
    expect(result.state[previous.id]!.starred, isFalse);
    final merged = mergeStarSyncRecords([
      result.state,
      {live.id: live, deleted.id: deleted, remote.id: remote},
    ], now: now);
    expect(merged[deleted.id]!.starred, isFalse);
    expect(merged[previous.id]!.clock, 7);
  });

  test('bulk restore revives matching tombstones in state or known', () {
    final inState = record(1, clock: 4, starred: false);
    final inKnown = record(2, clock: 5, starred: false);
    final live = record(3, clock: 6);
    final absent = record(4, clock: 7);
    final result = reconcileLocalStars(
      local: [local(1, title: 'restored'), local(2), local(3)],
      state: {inState.id: inState, live.id: live, absent.id: absent},
      known: {inKnown.id: inKnown},
      clock: 7,
      deviceId: 'local',
      now: now,
      bulkReplace: true,
    );
    expect(result.clock, 9);
    for (final id in [inState.id, inKnown.id]) {
      final revived = result.state[id]!;
      expect(revived.starred, isTrue);
      expect(revived.starredAt, now);
      expect(revived.deviceId, 'local');
    }
    expect(result.state[inState.id]!.clock, 8);
    expect(result.state[inState.id]!.title, 'restored');
    expect(result.state[inKnown.id]!.clock, 9);
    expect(result.state[live.id]!.clock, 6);
    expect(result.state[absent.id]!.starred, isTrue);
  });

  test('matching tombstones remove local copies without bulk restore', () {
    final inState = record(1, clock: 4, starred: false);
    final inKnown = record(2, clock: 5, starred: false);
    final result = reconcileLocalStars(
      local: [local(1), local(2)],
      state: {inState.id: inState},
      known: {inKnown.id: inKnown},
      clock: 5,
      deviceId: 'local',
      now: now,
    );
    expect(result.clock, 5);
    final merged = mergeStarSyncRecords([
      result.state,
      {inKnown.id: inKnown},
    ], now: now);
    expect(
      applyStarSyncStateToLocal(state: merged, local: [local(1), local(2)]),
      isEmpty,
    );
  });

  test('a different starredAt creates a new edit even for a tombstone', () {
    final deleted = record(1, clock: 4, starred: false);
    final later = now.add(const Duration(seconds: 1));
    final result = reconcileLocalStars(
      local: [local(1, at: later)],
      state: {deleted.id: deleted},
      known: {deleted.id: deleted},
      clock: 4,
      deviceId: 'local',
      now: later,
    );
    expect(result.clock, 5);
    expect(result.state[deleted.id]!.starred, isTrue);
    expect(result.state[deleted.id]!.starredAt, later);
  });

  test('cap trimmed absences are retained, newer absences are deleted', () {
    final items = List.generate(300, (i) => local(i, at: now));
    final old = record(900, at: now.subtract(const Duration(seconds: 1)));
    final newer = record(901, at: now.add(const Duration(seconds: 1)));
    final result = reconcileLocalStars(
      local: items,
      state: {old.id: old, newer.id: newer},
      clock: 1,
      deviceId: 'd',
      now: now,
    );
    expect(result.state[old.id]!.starred, true);
    expect(result.state[newer.id]!.starred, false);
  });

  test('equal timestamps use id ordering to identify cap trimming', () {
    final items = List.generate(301, (i) => local(i, at: now))
      ..sort((a, b) => a.id.compareTo(b.id));
    final removedByUser = items.removeAt(0);
    final trimmed = items.removeLast();
    items.add(local(-1, at: now));
    final deletedRecord = record(int.parse(removedByUser.seqNo));
    final trimmedRecord = record(int.parse(trimmed.seqNo));
    final result = reconcileLocalStars(
      local: items,
      state: {deletedRecord.id: deletedRecord, trimmedRecord.id: trimmedRecord},
      clock: 1,
      deviceId: 'd',
      now: now,
    );
    expect(result.state[deletedRecord.id]!.starred, isFalse);
    expect(result.state[trimmedRecord.id]!.starred, isTrue);
  });

  test('applying state preserves local details and takes remote timestamp', () {
    final r = record(1, title: 'remote', at: now.add(const Duration(days: 1)));
    final newRecord = record(2);
    final result = applyStarSyncStateToLocal(
      state: {r.id: r, newRecord.id: newRecord},
      local: [local(1, title: '', body: 'private')],
    );
    expect(result.first.body, 'private');
    expect(result.first.title, 'remote');
    expect(result.first.starredAt, r.starredAt);
    expect(result.last.body, '');
  });
}
