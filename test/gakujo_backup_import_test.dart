import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
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
      expect(backup.changes, isNull);
      expect(backup.reportLists, isNull);
    });

    test('preserves an explicit empty collection as a replacement', () {
      final backup = parseGakujoBackup('{"version":2,"favorites":[]}');

      expect(backup.favorites, isEmpty);
      expect(backup.downloadHistory, isNull);
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
