import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/download_destination_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  test('diagnostic backup replaces private starred messages with their count',
      () {
    const starredMessages = [
      {
        'title': 'Private message title one',
        'body': 'Private message body one',
        'sender': 'Private sender one',
        'period': 'Private period one',
      },
      {
        'title': 'Private message title two',
        'body': 'Private message body two',
        'sender': 'Private sender two',
        'period': 'Private period two',
      },
    ];
    final otherFields = <String, Object?>{
      'version': 2,
      'createdAt': '2026-10-22T00:00:00.000Z',
      'pageMode': 'desktop',
      'downloadHistory': [
        {'fileName': 'lecture.pdf'},
      ],
      'failedDownloads': [
        {'errorMessage': 'timeout'},
      ],
      'favorites': [
        {'title': 'Favorite course'},
      ],
      'deadlines': [
        {'title': 'Assignment'},
      ],
      'changes': [],
      'reportLists': [
        {'courseName': 'Course'},
      ],
    };
    final backup = Map<String, Object?>.unmodifiable({
      ...otherFields,
      'starredMessages': starredMessages,
    });
    final originalJson = jsonEncode(backup);

    final redacted = redactGakujoDiagnosticBackup(backup);

    expect(redacted, {...otherFields, 'starredMessageCount': 2});
    expect(redacted, isNot(contains('starredMessages')));
    final reportJson = jsonEncode({'backup': redacted});
    for (final message in starredMessages) {
      for (final value in message.values) {
        expect(reportJson, isNot(contains(value)));
      }
    }
    expect(jsonEncode(backup), originalJson);
    expect(backup['starredMessages'], starredMessages);
  });

  test('diagnostic backup counts an empty starred message list as zero', () {
    expect(
      redactGakujoDiagnosticBackup({'starredMessages': []}),
      {'starredMessageCount': 0},
    );
  });

  test('diagnostic backup counts missing or null starred messages as zero', () {
    for (final backup in <Map<String, Object?>>[
      {},
      {'starredMessages': null},
    ]) {
      expect(
        redactGakujoDiagnosticBackup(backup),
        {'starredMessageCount': 0},
      );
    }
  });

  test('diagnostic backup removes deadline message bodies without mutating input',
      () {
    const deadlines = [
      {
        'title': 'Assignment',
        'messageText': 'Private student name and student ID',
        'url': 'https://example.com/assignment',
      },
      {'title': 'Another assignment', 'messageText': 'Another private body'},
      {'title': 'Deadline without a message'},
    ];
    final backup = Map<String, Object?>.unmodifiable({'deadlines': deadlines});
    final originalJson = jsonEncode(backup);

    final redacted = redactGakujoDiagnosticBackup(backup);

    expect(redacted['deadlines'], [
      {'title': 'Assignment', 'url': 'https://example.com/assignment'},
      {'title': 'Another assignment'},
      {'title': 'Deadline without a message'},
    ]);
    final reportJson = jsonEncode({'backup': redacted});
    expect(reportJson, isNot(contains('messageText')));
    expect(reportJson, isNot(contains('Private student name and student ID')));
    expect(reportJson, isNot(contains('Another private body')));
    expect(jsonEncode(backup), originalJson);
  });

  test('diagnostic backup handles malformed deadline entries defensively', () {
    expect(
      redactGakujoDiagnosticBackup({
        'deadlines': [
          null,
          'legacy entry',
          42,
          {'title': 'Assignment', 'messageText': null},
        ],
      })['deadlines'],
      [null, 'legacy entry', 42, {'title': 'Assignment'}],
    );
    for (final deadlines in <Object?>[null, 'invalid', 42, <String, Object?>{}]) {
      expect(
        redactGakujoDiagnosticBackup({'deadlines': deadlines})['deadlines'],
        deadlines,
      );
    }
  });

  test('diagnostic backup keeps only dates from message deadline previews', () {
    const privateText = '山田太郎 学籍番号12345678 個別の提出指示';
    final deadlines = [
      GakujoDeadlineEntry(
        title: '課題のお知らせ',
        url: 'https://gakujo.example/message',
        dueText: '$privateText 2026/11/20 午後5:00まで',
        detectedAt: DateTime.utc(2026, 11, 1),
        source: '連絡通知',
        messageText: '$privateText 2026/11/20 午後5:00まで',
      ),
      GakujoDeadlineEntry(
        title: '本文が未保存の連絡',
        url: 'https://gakujo.example/message',
        dueText: '$privateText 2026/11/21 09:00～17:00',
        detectedAt: DateTime.utc(2026, 11, 1),
        kind: 'schedule',
        source: '連絡通知',
      ),
      GakujoDeadlineEntry(
        title: '出典が未保存の連絡',
        url: 'https://gakujo.example/message',
        dueText: '$privateText 日付なし',
        detectedAt: DateTime.utc(2026, 11, 1),
        kind: 'notice',
        messageText: privateText,
      ),
      GakujoDeadlineEntry(
        title: '通常の課題',
        url: 'https://gakujo.example/report',
        dueText: '提出期限 2026/11/22 17:00まで',
        detectedAt: DateTime.utc(2026, 11, 1),
        source: 'レポート・小テスト',
      ),
    ];
    final backup = buildGakujoBackupPayload(
      appSettings: const GakujoAppSettings(),
      downloadHistory: const [],
      failedDownloads: const [],
      favorites: const [],
      deadlines: deadlines,
      notifiedDeadlineKeys: [
        for (final deadline in deadlines) deadline.key,
        'deadline|https://gakujo.example/portal|削除済みの連絡|'
            '$privateText | 2026/11/23 17:00まで',
      ],
      reportLists: const [],
    );
    final originalJson = jsonEncode(backup);

    final redacted = redactGakujoDiagnosticBackup(backup);
    final entries = (redacted['deadlines']! as List).cast<Map>();

    expect(entries[0]['dueText'], '2026/11/20 午後5:00');
    expect(entries[1]['dueText'], '2026/11/21 09:00～17:00');
    expect(entries[2]['dueText'], isEmpty);
    expect(entries[3], deadlines[3].toJson());
    expect(redacted['notifiedDeadlineKeys'], [
      'deadline|https://gakujo.example/message|課題のお知らせ|2026/11/20 午後5:00',
      'schedule|https://gakujo.example/message|本文が未保存の連絡|2026/11/21 09:00～17:00',
      'notice|https://gakujo.example/message|出典が未保存の連絡|',
      'deadline|https://gakujo.example/report|通常の課題|2026/11/22 17:00',
      'deadline|https://gakujo.example/portal|削除済みの連絡|2026/11/23 17:00',
    ]);
    final reportJson = jsonEncode({'backup': redacted});
    for (final value in ['山田太郎', '12345678', '個別の提出指示', 'messageText']) {
      expect(reportJson, isNot(contains(value)));
    }
    expect(jsonEncode(backup), originalJson);
  });

  test('diagnostic backup handles malformed notification keys defensively', () {
    expect(
      redactGakujoDiagnosticBackup({
        'notifiedDeadlineKeys': [null, 42, 'legacy-key', 'kind|url|title'],
      })['notifiedDeadlineKeys'],
      [null, 42, 'legacy-key', 'kind|url|title'],
    );
    for (final keys in <Object?>[null, 'invalid', 42, <String, Object?>{}]) {
      expect(
        redactGakujoDiagnosticBackup({
          'notifiedDeadlineKeys': keys,
        })['notifiedDeadlineKeys'],
        keys,
      );
    }
  });

  const downloadRoot = DownloadDestinationSettings(
    isConfigured: true,
    displayName: 'Private student folder',
    path: '/Users/student/Documents/Gakujo',
  );
  const settings = GakujoAppSettings(
    calendarImportSettings: GakujoCalendarImportSettings(
      calendarTitle: 'Private student calendar',
    ),
  );

  test('lightweight diagnostics omit calendar titles and download root labels',
      () {
    final payload = gakujoDiagnosticSettingsPayload(
      settings: settings,
      downloadRoot: downloadRoot,
      includeStoredData: false,
    );
    final calendarSettings =
        payload['calendarImportSettings']! as Map<String, Object?>;

    expect(payload, isNot(contains('downloadRootLabel')));
    expect(payload['downloadRootConfigured'], isTrue);
    expect(calendarSettings, isNot(contains('calendarTitle')));
    expect(calendarSettings, {
      'method': 'automatic',
      'termSource': 'official',
      'termTarget': 'current',
      'includeNoClassDates': true,
      'applyClassChanges': true,
    });
    final reportJson = jsonEncode(payload);
    expect(reportJson, isNot(contains(downloadRoot.displayName!)));
    expect(reportJson, isNot(contains(downloadRoot.path!)));
    expect(reportJson,
        isNot(contains(settings.calendarImportSettings.calendarTitle)));
  });

  test('detailed diagnostics retain calendar titles and download root labels', () {
    final payload = gakujoDiagnosticSettingsPayload(
      settings: settings,
      downloadRoot: downloadRoot,
      includeStoredData: true,
    );

    expect(payload['downloadRootConfigured'], isTrue);
    expect(payload['downloadRootLabel'],
        'Private student folder\n/Users/student/Documents/Gakujo');
    expect(payload['calendarImportSettings'],
        settings.calendarImportSettings.toJson());
  });
}
