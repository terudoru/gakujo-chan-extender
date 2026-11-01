import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_quota_meter.dart';

import 'support/memory_secure_storage.dart';

void main() {
  test('clear removes persisted and in-memory quota data', () async {
    final storage = MemorySecureStorage();
    final meter = StarSyncQuotaMeter(storage: storage);
    await meter.charge(100);
    await meter.claimSaveNotice();
    await meter.clear();
    expect(storage.values, isNot(contains(starSyncGoogleQuotaKey)));
    expect(meter.usage.value, 0);
    expect(await meter.currentUsage(), 0);
    expect(await meter.claimSaveNotice(), isTrue);
  });

  test('persists usage and notices over a rolling 24 hours', () async {
    var now = DateTime(2026, 11, 1, 23, 59);
    final storage = MemorySecureStorage();
    StarSyncQuotaMeter make() =>
        StarSyncQuotaMeter(storage: storage, now: () => now);
    final first = make();
    await first.charge(14900);
    expect(await first.allowsAutomatic(100), isTrue);
    expect(await first.allowsAutomatic(101), isFalse);
    expect(await first.claimSaveNotice(), isTrue);
    final restored = make();
    expect(await restored.currentUsage(), 14900);
    expect(await restored.claimSaveNotice(), isFalse);
    // A local midnight does not reset anything: Google's accounting day is
    // a different 24 hours, and only a rolling window bounds every one.
    now = DateTime(2026, 11, 2);
    expect(await restored.currentUsage(), 14900);
    expect(await restored.claimSaveNotice(), isFalse);
    // The 23:00 hour leaves the window two days later at 00:00.
    now = DateTime(2026, 11, 3, 0, 1);
    expect(await restored.currentUsage(), 0);
    expect(await restored.claimSaveNotice(), isTrue);
    await restored.charge(50);
    expect(await make().currentUsage(), 50);
  });

  test('serializes charges and refuses crossing the hard limit', () async {
    final meter = StarSyncQuotaMeter(storage: MemorySecureStorage());
    await meter.charge(24900);
    await Future.wait([meter.charge(50), meter.charge(50)]);
    await expectLater(meter.charge(5), throwsA(isA<StarSyncQuotaExceeded>()));
    expect(await meter.currentUsage(), 25000);
  });

  test('enforces the soft limit on each automatic charge', () async {
    final meter = StarSyncQuotaMeter(storage: MemorySecureStorage());
    await meter.charge(14950);
    await meter.charge(50, automatic: true);
    await expectLater(
      meter.charge(1, automatic: true),
      throwsA(isA<StarSyncQuotaExceeded>()),
    );
    await meter.charge(50);
    expect(await meter.currentUsage(), 15050);
  });

  test('retains buckets after a forward and backward clock jump', () async {
    final storage = MemorySecureStorage();
    var now = DateTime.utc(2026, 1, 1, 12);
    StarSyncQuotaMeter make() =>
        StarSyncQuotaMeter(storage: storage, now: () => now);
    await make().charge(100);
    now = now.add(const Duration(hours: 30));
    expect(await make().currentUsage(), 0);
    now = now.subtract(const Duration(hours: 30));
    expect(await make().currentUsage(), 100);
    await make().charge(50);
    expect(await make().currentUsage(), 150);
    expect(
      jsonDecode(storage.values[starSyncGoogleQuotaKey]!)['lastSeen'],
      DateTime.utc(2026, 1, 2, 18).millisecondsSinceEpoch,
    );
  });

  test('migrates a day-based record into the current hour', () async {
    final storage = MemorySecureStorage();
    storage.values[starSyncGoogleQuotaKey] = jsonEncode({
      'date': '2026-01-01',
      'units': 14950,
    });
    final meter = StarSyncQuotaMeter(storage: storage);
    expect(await meter.currentUsage(), 14950);
    await expectLater(
      meter.charge(51, automatic: true),
      throwsA(isA<StarSyncQuotaExceeded>()),
    );
    expect(await StarSyncQuotaMeter(storage: storage).currentUsage(), 14950);
  });
}
