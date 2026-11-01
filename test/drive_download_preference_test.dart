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
    await preference.save(true, account);
    final reloaded = DriveDownloadPreference(storage: storage);
    await reloaded.load(legacy);
    expect(reloaded.matches(starSyncAccountHash('student')), isTrue);
    expect(reloaded.matches(starSyncAccountHash('other')), isFalse);
    expect(reloaded.matches(null), isFalse);
    expect(reloaded.matches(starSyncAccountHash('student')), isTrue);
    await reloaded.save(false, null);
    expect(reloaded.matches(account), isFalse);
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
