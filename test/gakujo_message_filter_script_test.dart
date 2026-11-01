import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_message_filter_script.dart';
import 'package:test/test.dart';

void main() {
  test('builds keyword-based message row filter', () {
    final script = GakujoMessageFilterScript.build(
      keywords: ['アンケート', ' 集中  講義 ', 'アンケート'],
    );

    expect(script, contains('__MBG_MESSAGE_FILTER_VERSION'));
    expect(script, contains('__MBG_MESSAGE_FILTER_SIGNATURE'));
    expect(script, contains('document.getElementById("main-frame-if")'));
    expect(script, contains('doc.querySelector("table.normal:nth-child(9)")'));
    expect(script, contains('"アンケート"'));
    expect(script, contains('"集中 講義"'));
    expect(script, contains('data-mbg-message-filtered'));
    expect(script, contains('除外中: '));
  });

  test('filters rows and restores them when the keywords change', () async {
    final result = await _evaluateMessageFilterScripts([
      GakujoMessageFilterScript.build(keywords: const ['アンケート']),
      GakujoMessageFilterScript.build(keywords: const ['重要']),
      GakujoMessageFilterScript.build(keywords: const []),
    ]);

    final first = result[0] as Map<String, dynamic>;
    expect(first['rowDisplays'], ['none', '']);
    expect(first['statusText'], '除外中: 1件');
    expect(first['activeIntervalCount'], 1);

    final changed = result[1] as Map<String, dynamic>;
    expect(changed['rowDisplays'], ['', 'none']);
    expect(changed['statusText'], '除外中: 1件');
    expect(changed['activeIntervalCount'], 1);

    final cleared = result[2] as Map<String, dynamic>;
    expect(cleared['rowDisplays'], ['', '']);
    expect(cleared['statusText'], isNull);
    expect(cleared['activeIntervalCount'], 1);
  });

  for (final directTable in [true, false]) {
    test(
        'desktop frame status stays in the top document '
        '(direct table: $directTable)', () async {
      final survey = GakujoMessageFilterScript.build(
        keywords: const ['アンケート'],
      );
      final empty = GakujoMessageFilterScript.build(keywords: const []);
      final result = await _evaluateMessageFilterScripts(
        [
          survey,
          survey,
          GakujoMessageFilterScript.build(keywords: const ['アンケート', '重要']),
          GakujoMessageFilterScript.build(keywords: const ['該当なし']),
          survey,
          empty,
          empty,
        ],
        frame: 'list',
        directTable: directTable,
        initialStatusCount: 2,
        intervalPasses: 3,
      );

      final labels = [
        '除外中: 1件',
        '除外中: 1件',
        '除外中: 2件',
        null,
        '除外中: 1件',
        null,
        null,
      ];
      for (var index = 0; index < result.length; index += 1) {
        final snapshot = result[index] as Map;
        final documents = (snapshot['documents'] as List).cast<Map>();
        final top = documents[0];
        final frame = documents[1];
        expect(top['hasTabMenu'], isTrue);
        expect(top['rowDisplays'], isEmpty);
        expect(top['statusText'], labels[index]);
        expect(top['statusCount'], labels[index] == null ? 0 : 1);
        expect(top['statusInTabMenu'], labels[index] != null);
        expect(frame['hasTabMenu'], isFalse);
        expect(frame['statusCount'], 0);
        expect(snapshot['activeIntervalCount'], 1);
      }
      expect((result[0] as Map)['rowDisplays'], ['none', '']);
      expect((result[2] as Map)['rowDisplays'], ['none', 'none']);
      for (final index in [3, 5, 6]) {
        expect((result[index] as Map)['rowDisplays'], ['', '']);
      }
      for (final index in [1, 6]) {
        final documents =
            ((result[index] as Map)['documents'] as List).cast<Map>();
        for (final doc in documents) {
          expect(doc['statusWrites'], 0);
        }
      }
    });
  }

  test('empty keywords remove stale statuses from the top and frame documents',
      () async {
    final empty = GakujoMessageFilterScript.build(keywords: const []);
    final result = await _evaluateMessageFilterScripts(
      [empty, empty],
      frame: 'list',
      initialStatusCount: 2,
    );

    for (final snapshot in result.cast<Map>()) {
      for (final doc in (snapshot['documents'] as List).cast<Map>()) {
        expect(doc['statusCount'], 0);
        expect(doc['rowTextReads'], 0);
        expect(doc['tableTextReads'], 0);
        expect(doc['attributeWrites'], 0);
        expect(doc['displayWrites'], 0);
      }
    }
  });

  test('desktop teardown restores frame rows and removes the top status',
      () async {
    final survey = GakujoMessageFilterScript.build(
      keywords: const ['アンケート'],
    );
    final teardown = GakujoMessageFilterScript.buildTeardown();
    final result = await _evaluateMessageFilterScripts(
      [survey, teardown, teardown, survey],
      frame: 'list',
      initialDisplays: ['table-row', 'none'],
      initialStatusCount: 2,
      intervalPasses: 3,
    );

    for (final index in [1, 2]) {
      final snapshot = result[index] as Map;
      expect(snapshot['rowDisplays'], ['table-row', 'none']);
      expect(snapshot['activeIntervalCount'], 0);
      for (final doc in (snapshot['documents'] as List).cast<Map>()) {
        expect(doc['statusCount'], 0);
        expect(doc['rowTextReads'], 0);
        expect(doc['tableTextReads'], 0);
      }
    }
    for (final index in [0, 3]) {
      final snapshot = result[index] as Map;
      final documents = (snapshot['documents'] as List).cast<Map>();
      expect(snapshot['rowDisplays'], ['none', 'none']);
      expect(documents[0]['statusText'], '除外中: 1件');
      expect(documents[0]['statusInTabMenu'], isTrue);
      expect(documents[0]['statusCount'], 1);
      expect(documents[1]['statusCount'], 0);
      expect(snapshot['activeIntervalCount'], 1);
    }
  });

  test('preserves page-owned hidden rows and explicit display styles',
      () async {
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['アンケート']),
        GakujoMessageFilterScript.build(keywords: const []),
      ],
      initialDisplays: ['table-row', 'none'],
    );
    expect((result[0] as Map)['rowDisplays'], ['none', 'none']);
    expect((result[1] as Map)['rowDisplays'], ['table-row', 'none']);
  });

  test('does not count rows that were already hidden by the page', () async {
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['重要'])
      ],
      initialDisplays: ['', 'none'],
    );
    expect((result.single as Map)['statusText'], isNull);
    expect((result.single as Map)['rowDisplays'], ['', 'none']);
    expect((result.single as Map)['displayWrites'], 0);
  });

  for (final directTable in [true, false]) {
    test('empty keywords leave rows untouched (direct table: $directTable)',
        () async {
      final script = GakujoMessageFilterScript.build(keywords: const []);
      final result = await _evaluateMessageFilterScripts(
        [script, script],
        initialDisplays: ['table-row', 'none'],
        directTable: directTable,
        intervalPasses: 3,
      );

      for (final snapshot in result.cast<Map<String, dynamic>>()) {
        expect(snapshot['rowTextReads'], 0);
        expect(snapshot['tableTextReads'], 0);
        expect(snapshot['attributeWrites'], 0);
        expect(snapshot['displayWrites'], 0);
        expect(snapshot['rowAttributes'], [{}, {}]);
        expect(snapshot['rowDisplays'], ['table-row', 'none']);
        expect(snapshot['statusText'], isNull);
        expect(snapshot['activeIntervalCount'], 1);
      }
    });
  }

  test('clearing keywords restores only owned rows without reading text',
      () async {
    final empty = GakujoMessageFilterScript.build(keywords: const []);
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['アンケート']),
        empty,
        empty,
      ],
      initialDisplays: ['table-row', 'none'],
      directTable: false,
      intervalPasses: 3,
    );

    final filtered = result[0] as Map<String, dynamic>;
    expect(filtered['rowDisplays'], ['none', 'none']);
    expect(filtered['statusText'], '除外中: 1件');

    final cleared = result[1] as Map<String, dynamic>;
    expect(cleared['rowDisplays'], ['table-row', 'none']);
    expect(cleared['rowAttributes'], [
      {'data-mbg-message-filtered': 'false'},
      {'data-mbg-message-filtered': 'false'},
    ]);
    expect(cleared['rowTextReads'], 0);
    expect(cleared['tableTextReads'], 0);
    expect(cleared['attributeWrites'], 2);
    expect(cleared['displayWrites'], 1);
    expect(cleared['statusText'], isNull);

    final repeated = result[2] as Map<String, dynamic>;
    expect(repeated['rowTextReads'], 0);
    expect(repeated['tableTextReads'], 0);
    expect(repeated['attributeWrites'], 0);
    expect(repeated['displayWrites'], 0);
  });

  test('keyword passes write only changed row attributes and display styles',
      () async {
    final survey = GakujoMessageFilterScript.build(keywords: const ['アンケート']);
    final important = GakujoMessageFilterScript.build(keywords: const ['重要']);
    final result = await _evaluateMessageFilterScripts(
      [survey, survey, important, important],
      intervalPasses: 3,
    );

    final first = result[0] as Map<String, dynamic>;
    expect(first['rowDisplays'], ['none', '']);
    expect(first['attributeWrites'], 3);
    expect(first['displayWrites'], 1);
    expect(first['statusText'], '除外中: 1件');

    final changed = result[2] as Map<String, dynamic>;
    expect(changed['rowDisplays'], ['', 'none']);
    expect(changed['attributeWrites'], 4);
    expect(changed['displayWrites'], 2);
    expect(changed['statusText'], '除外中: 1件');

    for (final index in [1, 3]) {
      final repeated = result[index] as Map<String, dynamic>;
      expect(repeated['attributeWrites'], 0);
      expect(repeated['displayWrites'], 0);
      expect(repeated['statusText'], '除外中: 1件');
      expect(repeated['activeIntervalCount'], 1);
    }
  });

  for (final frame in [
    'none',
    'empty',
    'list',
    'sameDocument',
    'inaccessible',
    'both',
  ]) {
    test('filters smartphone message units in every document (frame: $frame)',
        () async {
      final result = await _evaluateMessageFilterScripts(
        [
          GakujoMessageFilterScript.build(keywords: const ['セキュリティ'])
        ],
        smartphone: true,
        smartphoneMessageCount: 159,
        frame: frame,
        intervalPasses: 3,
      );

      final snapshot = result.single as Map<String, dynamic>;
      final documents = (snapshot['documents'] as List)
          .cast<Map<String, dynamic>>()
          .where((doc) => (doc['rowDisplays'] as List).isNotEmpty)
          .toList();
      expect(documents.length, frame == 'both' ? 2 : 1);
      for (final doc in documents) {
        expect(doc['rowDisplays'], ['none', 'none', ...List.filled(157, '')]);
        expect(doc['statusText'], '除外中: 2件');
        expect(doc['statusBeforeList'], isTrue);
        expect(doc['onlyMessageUnitsTouched'], isTrue);
      }
      for (final doc in (snapshot['documents'] as List).cast<Map>()) {
        expect(doc['navigationRowDisplays'], ['', '', '']);
        expect(doc['navigationUntouched'], isTrue);
      }
      expect(snapshot['activeIntervalCount'], 1);
    });
  }

  test('ignores smartphone navigation tables without message links', () async {
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['授業'])
      ],
      smartphone: true,
      smartphoneMessageCount: 0,
      intervalPasses: 3,
    );

    final snapshot = result.single as Map;
    expect(snapshot['rowDisplays'], isEmpty);
    expect(snapshot['navigationRowDisplays'], ['', '', '']);
    expect(snapshot['navigationUntouched'], isTrue);
    expect(snapshot['statusText'], isNull);
  });

  test('prefers smartphone message units over a matching fallback table',
      () async {
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['セキュリティ'])
      ],
      smartphone: true,
      fallbackTable: true,
      intervalPasses: 3,
    );

    final snapshot = result.single as Map;
    expect(snapshot['rowDisplays'], ['none', 'none', '']);
    expect(snapshot['statusText'], '除外中: 2件');
    expect(snapshot['statusBeforeList'], isTrue);
    expect(snapshot['onlyMessageUnitsTouched'], isTrue);
    expect(snapshot['navigationRowDisplays'], ['', '', '']);
    expect(snapshot['navigationUntouched'], isTrue);
  });

  for (final frame in ['empty', 'list', 'both']) {
    test('empty keywords leave smartphone lists untouched (frame: $frame)',
        () async {
      final empty = GakujoMessageFilterScript.build(keywords: const []);
      final result = await _evaluateMessageFilterScripts(
        [empty, empty],
        smartphone: true,
        frame: frame,
        initialDisplays: ['table-row', 'none', ''],
        intervalPasses: 3,
      );

      for (final snapshot in result.cast<Map<String, dynamic>>()) {
        for (final doc in (snapshot['documents'] as List).cast<Map>()) {
          expect(doc['rowTextReads'], 0);
          expect(doc['tableTextReads'], 0);
          expect(doc['attributeWrites'], 0);
          expect(doc['displayWrites'], 0);
          expect(doc['statusText'], isNull);
          if ((doc['rowDisplays'] as List).isNotEmpty) {
            expect(doc['rowAttributes'], [{}, {}, {}]);
            expect(doc['rowDisplays'], ['table-row', 'none', '']);
          }
        }
        expect(snapshot['activeIntervalCount'], 1);
      }
    });
  }

  test('smartphone keyword changes restore styles and avoid repeated writes',
      () async {
    final security = GakujoMessageFilterScript.build(
      keywords: const ['セキュリティ'],
    );
    final survey = GakujoMessageFilterScript.build(keywords: const ['アンケート']);
    final empty = GakujoMessageFilterScript.build(keywords: const []);
    final result = await _evaluateMessageFilterScripts(
      [security, security, survey, survey, empty, empty],
      smartphone: true,
      initialDisplays: ['table-row', 'none', ''],
      intervalPasses: 3,
    );

    expect((result[0] as Map)['rowDisplays'], ['none', 'none', '']);
    expect((result[0] as Map)['statusText'], '除外中: 1件');
    expect((result[2] as Map)['rowDisplays'], ['table-row', 'none', 'none']);
    expect((result[2] as Map)['statusText'], '除外中: 1件');
    expect((result[4] as Map)['rowDisplays'], ['table-row', 'none', '']);
    expect((result[4] as Map)['rowAttributes'], [
      {'data-mbg-message-filtered': 'false'},
      {'data-mbg-message-filtered': 'false'},
      {'data-mbg-message-filtered': 'false'},
    ]);
    expect((result[4] as Map)['rowTextReads'], 0);
    expect((result[4] as Map)['tableTextReads'], 0);
    expect((result[4] as Map)['statusText'], isNull);
    for (final index in [1, 3, 5]) {
      final repeated = result[index] as Map;
      expect(repeated['attributeWrites'], 0);
      expect(repeated['displayWrites'], 0);
      expect(repeated['statusWrites'], 0);
      expect(repeated['activeIntervalCount'], 1);
    }
  });

  test('smartphone page-owned hidden matches are excluded from the count',
      () async {
    final result = await _evaluateMessageFilterScripts(
      [
        GakujoMessageFilterScript.build(keywords: const ['セキュリティ'])
      ],
      smartphone: true,
      initialDisplays: ['none', 'none', ''],
    );
    expect((result.single as Map)['rowDisplays'], ['none', 'none', '']);
    expect((result.single as Map)['statusText'], isNull);
    expect((result.single as Map)['displayWrites'], 0);
  });

  test('smartphone teardown restores rows and removes both statuses', () async {
    final security = GakujoMessageFilterScript.build(
      keywords: const ['セキュリティ'],
    );
    final teardown = GakujoMessageFilterScript.buildTeardown();
    final result = await _evaluateMessageFilterScripts(
      [security, teardown, teardown, security],
      smartphone: true,
      frame: 'both',
      initialDisplays: ['table-row', 'none', ''],
      intervalPasses: 3,
    );

    for (final index in [1, 2]) {
      final snapshot = result[index] as Map;
      for (final doc in (snapshot['documents'] as List).cast<Map>()) {
        expect(doc['rowDisplays'], ['table-row', 'none', '']);
        expect(doc['statusText'], isNull);
        expect(doc['rowTextReads'], 0);
        expect(doc['tableTextReads'], 0);
      }
      expect(snapshot['activeIntervalCount'], 0);
    }
    for (final doc in ((result[3] as Map)['documents'] as List).cast<Map>()) {
      expect(doc['rowDisplays'], ['none', 'none', '']);
      expect(doc['statusText'], '除外中: 1件');
      expect(doc['statusBeforeList'], isTrue);
    }
    expect((result[3] as Map)['activeIntervalCount'], 1);
  });
}

Future<List<dynamic>> _evaluateMessageFilterScripts(
  List<String> scripts, {
  List<String> initialDisplays = const ['', ''],
  bool directTable = true,
  int intervalPasses = 0,
  bool smartphone = false,
  int smartphoneMessageCount = 3,
  String frame = 'none',
  bool fallbackTable = false,
  int initialStatusCount = 0,
}) async {
  final directory =
      Directory.systemTemp.createTempSync('gakujo_message_filter_');
  try {
    final input = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
        jsonEncode({
          'scripts': scripts,
          'initialDisplays': initialDisplays,
          'directTable': directTable,
          'intervalPasses': intervalPasses,
          'smartphone': smartphone,
          'smartphoneMessageCount': smartphoneMessageCount,
          'frame': frame,
          'fallbackTable': fallbackTable,
          'initialStatusCount': initialStatusCount,
        }),
        encoding: utf8,
      );
    final result = await Process.run(
        'node', ['test/support/message_filter_dom_harness.cts', input.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);

    expect(
      result.exitCode,
      0,
      reason: 'Node JavaScript evaluation failed: ${result.stderr}',
    );
    return jsonDecode(result.stdout as String) as List<dynamic>;
  } finally {
    directory.deleteSync(recursive: true);
  }
}
