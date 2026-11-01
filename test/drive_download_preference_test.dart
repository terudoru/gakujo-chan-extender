import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/drive_download_preference.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';

import 'support/memory_secure_storage.dart';

void main() {
  late Directory directory;
  late File legacy;
  late MemorySecureStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('drive_preference_test');
    legacy = File('${directory.path}/drive_downloads_enabled');
    storage = MemorySecureStorage();
  });

  tearDown(() async => directory.delete(recursive: true));

  test('migrates the old toggle without trusting an unknown account', () async {
    await legacy.writeAsString('true');
    final preference = DriveDownloadPreference(storage: storage);
    await preference.load(legacy);
    expect(preference.enabled, isTrue);
    expect(preference.matches(starSyncAccountHash('student')), isFalse);
    expect(await legacy.exists(), isFalse);
    final reloaded = DriveDownloadPreference(storage: storage);
    await reloaded.load(legacy);
    expect(reloaded.enabled, isTrue);
    expect(reloaded.boundAccount, isNull);
  });

  test('binding survives restart and matches only the original login', () async {
    final preference = DriveDownloadPreference(storage: storage);
    final account = starSyncAccountHash(' student ');
    await preference.save(true, account, 'a@example.com');
    final reloaded = DriveDownloadPreference(storage: storage);
    await reloaded.load(legacy);
    expect(reloaded.matches(starSyncAccountHash('student'), 'a@example.com'), isTrue);
    expect(reloaded.matches(starSyncAccountHash('other'), 'a@example.com'), isFalse);
    expect(reloaded.matches(null, 'a@example.com'), isFalse);
    expect(reloaded.matches(account, 'b@example.com'), isFalse);
    expect(reloaded.boundGoogleEmail, 'a@example.com');
    expect(reloaded.matches(starSyncAccountHash('student'), 'a@example.com'), isTrue);
    await reloaded.save(false, null);
    expect(reloaded.matches(account), isFalse);
  });

  test('download origin must match the current binding', () async {
    final preference = DriveDownloadPreference(storage: storage);
    await preference.save(true, 'A', 'a@example.com');
    expect(preference.matchesUpload(null, 'a@example.com', 'A', 'a@example.com'), isFalse);
    expect(preference.matchesUpload('A', 'a@example.com', null, 'a@example.com'), isFalse);
    expect(preference.matchesUpload('A', 'a@example.com', 'B', 'a@example.com'), isFalse);
    expect(preference.matchesUpload('A', 'a@example.com', 'A', 'b@example.com'), isFalse);
    expect(preference.matchesUpload('A', 'a@example.com', 'A', 'a@example.com'), isTrue);
  });

  test('clear removes stored notification times', () async {
    const key = 'more_better_gakujo_notified_deadline_times';
    await storage.write(key: key, value: '{"old":"2026-01-01T00:00:00Z"}');
    await GakujoActivityStore(secureStorage: storage).clearNotifiedDeadlineTimes();
    expect(storage.values, isNot(contains(key)));
  });

  test('clear removes the toggle and account binding', () async {
    final preference = DriveDownloadPreference(storage: storage);
    await preference.save(true, starSyncAccountHash('student'));
    await preference.clear();
    expect(storage.values, isNot(contains(DriveDownloadPreference.key)));
    expect(preference.enabled, isFalse);
    expect(preference.boundAccount, isNull);
  });

  test('cancellation drops waiting jobs and invalidates the active job', () async {
    final queue = DriveDownloadQueue();
    final started = Completer<void>();
    final resume = Completer<void>();
    final finished = Completer<void>();
    final calls = <String>[];
    queue.add((generation) async {
      calls.add('started');
      started.complete();
      await resume.future;
      if (queue.isCurrent(generation)) calls.add('request');
      finished.complete();
    });
    await started.future;
    queue.add((_) async => calls.add('queued'));
    queue.cancel();
    resume.complete();
    await finished.future;
    expect(calls, ['started']);
  });
}
