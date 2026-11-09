import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_adapters.dart';

GakujoBackupImport parse(Map<String, Object?> m) =>
    parseGakujoBackup(jsonEncode({'version': 2, ...m}));

void main() {
  group('backup import: disabledFeatureFlags', () {
    test('retired + current + unknown flag values', () {
      final b = parse({'disabledFeatureFlags': ['activity_scan', 'auto_backup', 'gpa_display']});
      expect(b.disabledFeatureFlags, {GakujoFeatureFlag.autoBackup});
    });
    test('unknown flag alone does not reject the whole backup', () {
      final b = parse({'disabledFeatureFlags': ['activity_scan']});
      expect(b.disabledFeatureFlags, isEmpty);
    });
    for (final v in ['auto_backup', 5, {'a': 1}, true]) {
      test('non-list disabledFeatureFlags $v is rejected cleanly', () {
        expect(() => parse({'disabledFeatureFlags': v}),
            throwsA(isA<GakujoBackupImportException>()));
      });
    }
    test('null disabledFeatureFlags', () {
      expect(() => parse({'disabledFeatureFlags': null}),
          throwsA(isA<GakujoBackupImportException>()));
    });
    test('list with null / numeric items', () {
      GakujoBackupImport r() => parse({'disabledFeatureFlags': ['auto_backup', 'session_recovery_guide']});
      expect(r().disabledFeatureFlags, {GakujoFeatureFlag.autoBackup});
    });
  });
  group('mutedCourses', () {
    for (final v in ['math', 5, null, ['a'], {'a': true}]) {
      test('notificationPreferences.mutedCourses=$v is ignored', () {
        final b = parse({'notificationPreferences': {'mutedCourses': v}});
        expect(b.notificationPreferences, isNotNull);
      });
    }
    test('notificationPreferences itself a string', () {
      final b = parse({'notificationPreferences': 'mutedCourses'});
      expect(b.notificationPreferences, isNull);
    });
    test('mutedCourses at top level ignored', () {
      parse({'mutedCourses': 'x'});
      parse({'mutedCourses': ['x']});
    });
    test('prefs fromJson tolerates mutedCourses string', () {
      final p = GakujoNotificationPreferences.fromJson({'mutedCourses': 'math'});
      expect(p.toJson().containsKey('mutedCourses'), isFalse);
    });
  });
  group('synced settings import', () {
    test('retired flags and odd types in synced settings', () {
      final cur = GakujoAppSettings();
      final out = importStarSyncPortableSettings(cur, {
        'disabledFeatureFlags': ['report_tools', 'auto_backup', 'activity_scan'],
        'notificationPreferences': {'mutedCourses': 'x', 'reminderOffsets': 'bad'},
      });
      expect(out.disabledFeatureFlags, {GakujoFeatureFlag.autoBackup});
    });
    test('synced disabledFeatureFlags non-list throws typed exception only', () {
      expect(() => importStarSyncPortableSettings(GakujoAppSettings(),
          {'disabledFeatureFlags': 'auto_backup'}),
          throwsA(isA<GakujoBackupImportException>()));
    });
    test('portable payload keeps only the 4 retired names filtered', () {
      final out = portableSyncBackupPayload({
        'version': 2, 'disabledFeatureFlags': ['gpa_display', 'auto_backup'],
      });
      expect(out['disabledFeatureFlags'], ['auto_backup']);
    });
    test('portable payload non-list flags', () {
      final out = portableSyncBackupPayload({'version': 2, 'disabledFeatureFlags': 'x',
        'notificationPreferences': 'mutedCourses'});
      expect(out, isA<Map>());
    });
  });
}
