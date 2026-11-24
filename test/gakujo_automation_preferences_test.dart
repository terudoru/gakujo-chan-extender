import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_local_prefs_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_restore.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_auto_backup_schedule.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  String? failOnce;
  @override
  Future<Map<String, String>> readAll({
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic wOptions,
    dynamic mOptions,
    dynamic webOptions,
  }) async => {...values};
  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic wOptions,
    dynamic mOptions,
    dynamic webOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic wOptions,
    dynamic mOptions,
    dynamic webOptions,
  }) async {
    if (failOnce == key) {
      failOnce = null;
      throw StateError('Synthetic write failure');
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
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic wOptions,
    dynamic mOptions,
    dynamic webOptions,
  }) async {
    values.remove(key);
  }
}

Map<String, Object?> payload(GakujoAppSettings settings) =>
    buildGakujoBackupPayload(
      appSettings: settings,
      downloadHistory: [],
      failedDownloads: [],
      favorites: [],
      deadlines: [],
      reportLists: [],
    );

void main() {
  test(
    'missing and unknown automation preferences use current defaults',
    () async {
      for (final raw in [
        null,
        'broken',
        [],
        {},
        {'intervalHours': 2, 'generations': 20},
        {'intervalHours': 24.0, 'generations': '100'},
      ]) {
        expect(
          GakujoAutoBackupSettings.fromJson(raw).toJson(),
          const GakujoAutoBackupSettings().toJson(),
        );
      }
      expect(
        GakujoReportInitialSort.fromJson('unknown'),
        GakujoReportInitialSort.deadline,
      );
      final storage = _Storage();
      var loaded = await GakujoAppSettingsStore(secureStorage: storage).load();
      expect(
        loaded.autoBackupSettings.toJson(),
        const GakujoAutoBackupSettings().toJson(),
      );
      expect(loaded.reportInitialSort, GakujoReportInitialSort.deadline);
      storage.values['more_better_gakujo_auto_backup_settings'] = 'broken';
      storage.values['more_better_gakujo_report_initial_sort'] = 'future-order';
      loaded = await GakujoAppSettingsStore(secureStorage: storage).load();
      expect(
        loaded.autoBackupSettings.toJson(),
        const GakujoAutoBackupSettings().toJson(),
      );
      expect(loaded.reportInitialSort, GakujoReportInitialSort.deadline);
      for (final data in [
        {'version': 2},
        {
          'version': 2,
          'autoBackupSettings': false,
          'reportInitialSort': 'future-order',
        },
      ]) {
        final backup = parseGakujoBackup(jsonEncode(data));
        expect(
          backup.autoBackupSettings!.toJson(),
          const GakujoAutoBackupSettings().toJson(),
        );
        expect(backup.reportInitialSort, GakujoReportInitialSort.deadline);
      }
    },
  );

  test(
    'each interval, generation count, and initial sort persists and exports',
    () async {
      final storage = _Storage();
      final store = GakujoAppSettingsStore(secureStorage: storage);
      for (final hours in GakujoAutoBackupSettings.intervals) {
        for (final count in GakujoAutoBackupSettings.generationCounts) {
          for (final sort in GakujoReportInitialSort.values) {
            final settings = GakujoAutoBackupSettings(
              intervalHours: hours,
              generations: count,
            );
            await store.saveAutoBackupSettings(settings);
            await store.saveReportInitialSort(sort);
            final loaded = await GakujoAppSettingsStore(secureStorage: storage)
                .load();
            expect(loaded.autoBackupSettings.toJson(), settings.toJson());
            expect(loaded.reportInitialSort, sort);
            final backup = parseGakujoBackup(
              encodeGakujoBackupPayload(payload(loaded)),
            );
            expect(backup.autoBackupSettings!.toJson(), settings.toJson());
            expect(backup.reportInitialSort, sort);
          }
        }
      }
    },
  );

  test('local mirror and transactional backup restore preserve automation preferences', () async {
    const source = GakujoAppSettings(
      autoBackupSettings: GakujoAutoBackupSettings(
        intervalHours: 24,
        generations: 100,
      ),
      reportInitialSort: GakujoReportInitialSort.original,
    );
    final directory = await Directory.systemTemp.createTemp(
      'automation-prefs-',
    );
    try {
      final mirror = GakujoLocalPrefsStore(directory: directory);
      await mirror.saveAppSettings(source);
      final local = await mirror.load();
      final merged = mergeMacosLocalMessageFiltersWithSecureSettings(
        secureSettings: const GakujoAppSettings(),
        localPrefs: local,
      );
      expect(
        merged.autoBackupSettings.toJson(),
        source.autoBackupSettings.toJson(),
      );
      expect(merged.reportInitialSort, source.reportInitialSort);
      final storage = _Storage();
      final store = GakujoAppSettingsStore(secureStorage: storage);
      var runtime = const GakujoAppSettings();
      final backup = parseGakujoBackup(
        encodeGakujoBackupPayload(payload(merged)),
      );
      Future<void> restore() => restoreGakujoBackup(
        backup: backup,
        settingsStore: store,
        historyStore: GakujoDownloadHistoryStore(secureStorage: storage),
        activityStore: GakujoActivityStore(secureStorage: storage),
        isAllowedUrl: (_) => true,
        isAllowedNavigationUrl: (_) => true,
      );
      await restoreGakujoSettingsLocally(
        operations: StorageOperationQueue(),
        backup: backup,
        currentSettings: () => runtime,
        restore: restore,
        publish: (value, _) => runtime = value,
        mirror: (_) async {},
      );
      expect(
        runtime.autoBackupSettings.toJson(),
        source.autoBackupSettings.toJson(),
      );
      expect(runtime.reportInitialSort, source.reportInitialSort);
      expect(
        (await store.load()).autoBackupSettings.toJson(),
        source.autoBackupSettings.toJson(),
      );
      expect((await store.load()).reportInitialSort, source.reportInitialSort);
      await store.saveAutoBackupSettings(const GakujoAutoBackupSettings());
      await store.saveReportInitialSort(GakujoReportInitialSort.title);
      final before = {...storage.values};
      storage.failOnce = 'more_better_gakujo_report_initial_sort';
      await expectLater(restore(), throwsStateError);
      expect(storage.values, before);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  for (final hours in GakujoAutoBackupSettings.intervals) {
    testWidgets('automatic backup interval ${hours}h fires on schedule', (
      tester,
    ) async {
      var writes = 0;
      final schedule = GakujoAutoBackupSchedule(onBackup: () => writes++);
      addTearDown(schedule.dispose);
      schedule.schedule(
        enabled: true,
        settings: GakujoAutoBackupSettings(intervalHours: hours),
      );
      expect(writes, 1);
      await tester.pump(
        Duration(hours: hours) - const Duration(milliseconds: 1),
      );
      expect(writes, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(writes, 2);
      schedule.dispose();
    });
  }

  testWidgets(
    'interval changes replace next timer and retain launch/debounce policy',
    (tester) async {
      var writes = 0;
      final schedule = GakujoAutoBackupSchedule(onBackup: () => writes++);
      addTearDown(schedule.dispose);
      schedule.schedule(
        enabled: true,
        settings: const GakujoAutoBackupSettings(),
      );
      await tester.pump(const Duration(hours: 2));
      expect(writes, 1);
      schedule.schedule(
        enabled: true,
        settings: const GakujoAutoBackupSettings(intervalHours: 1),
      );
      await tester.pump(const Duration(minutes: 1));
      expect(writes, 2);
      await tester.pump(const Duration(minutes: 58, seconds: 59));
      expect(writes, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(writes, 3);
      await tester.pump(const Duration(hours: 3));
      expect(writes, 6); // The old six-hour timer must have been cancelled.
      schedule.schedule(
        enabled: false,
        settings: const GakujoAutoBackupSettings(),
      );
      await tester.pump(const Duration(hours: 24));
      expect(writes, 6);
      schedule.dispose();
      schedule.schedule(
        enabled: true,
        settings: const GakujoAutoBackupSettings(),
      );
      await tester.pump(const Duration(hours: 24));
      expect(writes, 6);
    },
  );

  for (final count in GakujoAutoBackupSettings.generationCounts) {
    test(
      'automatic retention $count preserves manual/legacy files and current write',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'auto-generations-',
        );
        try {
          final time = DateTime(2026, 1, 1);
          for (final name in [
            'manual-backup-old.json',
            'legacy-backup.json',
            'other.json',
            'auto-backup-note.txt',
          ]) {
            final file = File.fromUri(directory.uri.resolve(name));
            await file.writeAsString('{}');
            await file.setLastModified(
              time.subtract(const Duration(days: 100)),
            );
          }
          for (var i = 0; i < count + 2; i++) {
            final file = File.fromUri(
              directory.uri.resolve('auto-backup-$i.json'),
            );
            await file.writeAsString('{}');
            await file.setLastModified(time.add(Duration(minutes: i)));
          }
          final current = File.fromUri(
            directory.uri.resolve('auto-backup-current.json'),
          );
          await current.writeAsString('{}');
          await current.setLastModified(time.subtract(const Duration(days: 1)));
          await pruneAutomaticBackupFiles(
            directory,
            settings: GakujoAutoBackupSettings(generations: count),
            protectedFile: current,
          );
          final names = (await directory.list().toList())
              .map((file) => file.uri.pathSegments.last)
              .toSet();
          expect(
            names.where(
              (name) =>
                  name.startsWith('auto-backup-') && name.endsWith('.json'),
            ),
            hasLength(count),
          );
          expect(await current.exists(), isTrue);
          expect(
            names,
            containsAll([
              'manual-backup-old.json',
              'legacy-backup.json',
              'other.json',
              'auto-backup-note.txt',
            ]),
          );
          expect(names, isNot(contains('auto-backup-0.json')));
          expect(names, isNot(contains('auto-backup-1.json')));
          expect(names, isNot(contains('auto-backup-2.json')));
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );
  }

  testWidgets('settings sections change automatic backup and report defaults', (
    tester,
  ) async {
    var settings = const GakujoAutoBackupSettings();
    var sort = GakujoReportInitialSort.deadline;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (_, setState) => Column(
                children: [
                  GakujoAutoBackupSection(
                    settings: settings,
                    onIntervalChanged: (value) => setState(
                      () => settings = settings.copyWith(intervalHours: value),
                    ),
                    onGenerationsChanged: (value) => setState(
                      () => settings = settings.copyWith(generations: value),
                    ),
                  ),
                  GakujoReportInitialSortSection(
                    sort: sort,
                    onChanged: (value) => setState(() => sort = value!),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (final label in ['1時間', '100世代', '学務の元の順']) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(settings.intervalHours, 1);
    expect(settings.generations, 100);
    expect(sort, GakujoReportInitialSort.original);
  });
}
