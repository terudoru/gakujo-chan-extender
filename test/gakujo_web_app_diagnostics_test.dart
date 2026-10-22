import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
}
