import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';

void main() {
  group('parseGakujoBackup', () {
    test('rejects missing and unknown versions with explicit errors', () {
      expect(
        () => parseGakujoBackup('{"pageMode":"mobile"}'),
        throwsA(
          isA<GakujoBackupImportException>().having(
            (error) => error.message,
            'message',
            contains('バージョン情報がありません'),
          ),
        ),
      );
      expect(
        () => parseGakujoBackup('{"version":999}'),
        throwsA(
          isA<GakujoBackupImportException>().having(
            (error) => error.message,
            'message',
            allOf(contains('999'), contains('対応していません')),
          ),
        ),
      );
    });

    test('treats missing collection keys as unchanged', () {
      final backup = parseGakujoBackup(
        '{"version":2,"pageMode":"mobile"}',
      );

      expect(backup.pageMode, GakujoPageMode.mobile);
      expect(backup.downloadHistory, isNull);
      expect(backup.failedDownloads, isNull);
      expect(backup.favorites, isNull);
      expect(backup.deadlines, isNull);
      expect(backup.notifiedDeadlineKeys, isNull);
      expect(backup.changes, isNull);
      expect(backup.reportLists, isNull);
    });

    test('preserves an explicit empty collection as a replacement', () {
      final backup = parseGakujoBackup(
        '{"version":2,"favorites":[],"notifiedDeadlineKeys":[]}',
      );

      expect(backup.favorites, isEmpty);
      expect(backup.notifiedDeadlineKeys, isEmpty);
      expect(backup.downloadHistory, isNull);
    });

    for (final key in [
      'favorites',
      'starredMessages',
      'downloadHistory',
      'failedDownloads',
      'deadlines',
      'changes',
      'reportLists',
      'notifiedDeadlineKeys',
    ]) {
      test('rejects a non-empty unreadable $key collection', () {
        expect(
          () => parseGakujoBackup(jsonEncode({
            'version': 2,
            key: key == 'notifiedDeadlineKeys' ? [' ', ''] : [{}],
          })),
          throwsA(isA<GakujoBackupImportException>().having(
            (error) => error.message,
            'message',
            allOf(startsWith('バックアップの'), endsWith('を読み取れませんでした')),
          )),
        );
        expect(
          () => parseGakujoBackup(jsonEncode({'version': 2, key: []})),
          returnsNormally,
        );
      });
    }

    test('keeps useful favorites when some records have empty required fields',
        () {
      final backup = parseGakujoBackup(jsonEncode({
        'version': 2,
        'favorites': [
          {},
          {'title': ' ', 'url': 'https://example.com'},
          {'title': 'Missing URL', 'url': ' '},
          {'title': 'Kept', 'url': 'https://example.com'},
        ],
      }));
      expect(backup.favorites!.single.title, 'Kept');
    });

    test('rejects non-empty settings lists with no recognized values', () {
      for (final entry in {
        'messageExcludeKeywords': [' ', ''],
        'disabledFeatureFlags': ['unknown-feature'],
        'notificationTopics': ['unknown-topic'],
      }.entries) {
        expect(
          () => parseGakujoBackup(jsonEncode({
            'version': 2,
            entry.key: entry.value,
          })),
          throwsA(isA<GakujoBackupImportException>()),
        );
        expect(
          () => parseGakujoBackup(jsonEncode({'version': 2, entry.key: []})),
          returnsNormally,
        );
      }
      // The legacy message-only choice intentionally has no coursework topic.
      final messages = parseGakujoBackup(
        '{"version":2,"notificationTopics":["message"]}',
      );
      expect(messages.notificationTopics, isEmpty);
      expect(messages.messageNotification!.mode,
          GakujoMessageNotificationMode.deadlines);
    });

    test(
        'unknown reminder offsets preserve local choices unless explicitly empty',
        () {
      const local = {GakujoReminderOffset.threeDays};
      for (final (offsets, expected) in [
        (['future_offset'], local),
        (['future_offset', 'one_hour'], {GakujoReminderOffset.oneHour}),
        (<String>[], <GakujoReminderOffset>{}),
      ]) {
        final backup = parseGakujoBackup(
          jsonEncode({
            'version': 2,
            'notificationPreferences': {
              'skipSubmitted': false,
              'mutedCourses': ['科目A'],
              'reminderOffsets': offsets,
            },
          }),
          currentReminderOffsets: local,
        );
        expect(backup.notificationPreferences!.reminderOffsets, expected);
        expect(backup.notificationPreferences!.skipSubmitted, isFalse);
        expect(backup.notificationPreferences!.mutedCourses, {'科目A'});
      }
    });

    test('migrates legacy message topics using the settings loader rule', () {
      for (final topics in [
        ['message', 'report'],
        ['report'],
        <String>[],
      ]) {
        final backup = parseGakujoBackup(jsonEncode({
          'version': 2,
          'notificationTopics': topics,
        }));
        final migrated = GakujoMessageNotificationSettings.fromJson(
          null,
          legacyTopics: topics,
        );
        expect(backup.messageNotification!.toJson(), migrated.toJson());
        expect(
            backup.messageNotification!.mode,
            topics.contains('message')
                ? GakujoMessageNotificationMode.deadlines
                : GakujoMessageNotificationMode.off);
      }
      expect(parseGakujoBackup('{"version":2}').messageNotification, isNull);
    });

    test('an explicit message rule takes precedence over legacy topics', () {
      final backup = parseGakujoBackup(jsonEncode({
        'version': 2,
        'notificationTopics': ['message', 'report'],
        'messageNotification': {'mode': 'off'},
      }));
      expect(
          backup.messageNotification!.mode, GakujoMessageNotificationMode.off);
    });

    test(
        'rejects null records instead of treating them as an empty replacement',
        () {
      for (final key in [
        'favorites',
        'downloadHistory',
        'deadlines',
        'notifiedDeadlineKeys',
        'failedDownloads',
        'changes',
        'reportLists',
        'messageExcludeKeywords'
      ]) {
        expect(
          () => parseGakujoBackup(jsonEncode({
            'version': 2,
            key: [null]
          })),
          throwsA(isA<GakujoBackupImportException>()),
          reason: key,
        );
      }
    });

    test('rejects invalid settings instead of overwriting with defaults', () {
      for (final entry in {
        'downloadSaveMode': 'invalid-mode',
        'pageMode': 123,
        'setupCompleted': 'true',
        'calendarImportSettings': null,
      }.entries) {
        expect(
          () => parseGakujoBackup(
              jsonEncode({'version': 2, entry.key: entry.value})),
          throwsA(isA<GakujoBackupImportException>()),
          reason: entry.key,
        );
      }
    });

    test('rejects invalid notified deadline key collections', () {
      for (final value in [
        null,
        'deadline|report',
        [42],
        [true],
        [{}],
      ]) {
        expect(
          () => parseGakujoBackup(jsonEncode({
            'version': 2,
            'notifiedDeadlineKeys': value,
          })),
          throwsA(isA<GakujoBackupImportException>()),
        );
      }
    });

    test('accepts a complete version 2 backup', () {
      final backup = parseGakujoBackup(
        jsonEncode({
          'version': 2,
          'createdAt': '2026-07-16T12:00:00.000',
          'downloadSaveMode': 'flat_configured',
          'pageMode': 'mobile',
          'setupCompleted': true,
          'calendarImportSettings': {
            'method': 'ics_file',
            'termSource': 'page_or_manual',
            'termTarget': 'second',
            'includeNoClassDates': false,
            'calendarTitle': '授業カレンダー',
          },
          'messageExcludeKeywords': ['広告', '重要'],
          'disabledFeatureFlags': ['gpa_display'],
          'downloadHistory': [
            {
              'fileName': 'report.pdf',
              'courseName': 'テスト科目',
              'savedAt': '2026-07-16T11:00:00.000',
              'location': '/tmp/report.pdf',
            },
          ],
          'failedDownloads': [
            {
              'id': 'failed-1',
              'request': {
                'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/file.pdf',
                'method': 'GET',
                'courseName': 'テスト科目',
                'fileName': 'file.pdf',
              },
              'failedAt': '2026-07-16T11:10:00.000',
              'errorMessage': 'timeout',
            },
          ],
          'favorites': [
            {
              'title': 'お気に入り',
              'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/favorite',
              'addedAt': '2026-07-16T10:00:00.000',
            },
          ],
          'deadlines': [
            {
              'title': '課題',
              'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/deadline',
              'dueText': '2026/07/31',
              'detectedAt': '2026-07-16T09:00:00.000',
              'kind': 'deadline',
            },
          ],
          'changes': [
            {
              'category': 'レポート',
              'title': '変更',
              'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/change',
              'changedAt': '2026-07-16T08:00:00.000',
              'previousHash': 'before',
              'nextHash': 'after',
              'previousPreview': '前',
              'nextPreview': '後',
            },
          ],
          'reportLists': [
            {
              'title': '課題一覧',
              'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/reports',
              'capturedAt': '2026-07-16T07:00:00.000',
              'items': ['課題A'],
            },
          ],
        }),
      );

      expect(backup.version, 2);
      expect(backup.downloadSaveMode, DownloadSaveMode.flatToConfiguredFolder);
      expect(backup.pageMode, GakujoPageMode.mobile);
      expect(backup.setupCompleted, isTrue);
      expect(
        backup.calendarImportSettings?.method,
        GakujoCalendarImportMethod.icsFile,
      );
      expect(backup.messageExcludeKeywords, ['広告', '重要']);
      expect(backup.disabledFeatureFlags, {GakujoFeatureFlag.gpaDisplay});
      expect(backup.downloadHistory, hasLength(1));
      expect(backup.failedDownloads, hasLength(1));
      expect(backup.failedDownloads?.single.request.formFields, isEmpty);
      expect(backup.favorites, hasLength(1));
      expect(backup.deadlines, hasLength(1));
      expect(backup.changes, hasLength(1));
      expect(backup.reportLists, hasLength(1));
    });

    test('imports exported settings for every supported page and save mode',
        () {
      for (final saveMode in DownloadSaveMode.values) {
        for (final pageMode in GakujoPageMode.values) {
          final payload = buildGakujoBackupPayload(
            appSettings: GakujoAppSettings(
              downloadSaveMode: saveMode,
              pageMode: pageMode,
              disabledFeatureFlags: GakujoFeatureFlag.values.toSet(),
            ),
            downloadHistory: const [],
            failedDownloads: const [],
            favorites: const [],
            deadlines: const [],
            changes: const [],
            reportLists: const [],
          );
          final imported = parseGakujoBackup(jsonEncode(payload));
          expect(imported.downloadSaveMode, saveMode);
          expect(imported.pageMode, pageMode);
          expect(
              imported.disabledFeatureFlags, GakujoFeatureFlag.values.toSet());
        }
      }
    });

    test('keeps support for calendar settings encoded as a JSON string', () {
      final backup = parseGakujoBackup(jsonEncode({
        'version': 2,
        'calendarImportSettings': jsonEncode({'calendarTitle': '授業'}),
      }));
      expect(backup.calendarImportSettings?.calendarTitle, '授業');
    });

    test('rejects an invalid collection before returning import data', () {
      expect(
        () => parseGakujoBackup(
          '{"version":2,"favorites":[],"reportLists":"invalid"}',
        ),
        throwsA(
          isA<GakujoBackupImportException>().having(
            (error) => error.message,
            'message',
            contains('reportLists'),
          ),
        ),
      );
    });
  });
}
