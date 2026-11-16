import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/download_destination_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
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
