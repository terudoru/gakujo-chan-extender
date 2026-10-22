import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:test/test.dart';

void main() {
  test(
      'smartphone groups without a count or paging report the rows read as total',
      () async {
    final result = await _evaluate();
    final rows = result['rows'] as List;
    expect(result['total'], rows.length);
    expect(rows.map((row) => row['kind']).toSet().toList(), [
      'レポート',
      '小テスト',
      '授業アンケート',
      '一般アンケート',
      '授業評価アンケート',
    ]);
  });

  for (final (name, control) in [
    (
      '次へ link',
      {
        'tag': 'a',
        'textContent': '次へ進む',
        'attributes': {'href': '#next'},
      },
    ),
    ('前へ button', {'tag': 'button', 'textContent': '前へ戻る'}),
    (
      'paging onclick',
      {
        'tag': 'a',
        'attributes': {'onclick': 'paging(2)'},
      },
    ),
    (
      'paging href',
      {
        'tag': 'a',
        'attributes': {'href': '?_eventId=paging'},
      },
    ),
    (
      '_displayCount select',
      {
        'tag': 'select',
        'attributes': {'name': '_displayCount'},
      },
    ),
    (
      '_displayCount input',
      {
        'tag': 'input',
        'attributes': {'name': '_displayCount'},
      },
    ),
  ]) {
    test('smartphone list with $name keeps total unknown', () async {
      final result = await _evaluate(controls: [control]);
      expect(result['total'], -1);
    });
  }

  test('desktop list keeps its explicit 1～12/12件 total', () async {
    final result = await _evaluate(smartphone: false, count: '1～12/12件');
    expect(result['total'], 12);
  });

  test('desktop list without a count keeps total unknown', () async {
    final result = await _evaluate(smartphone: false);
    expect(result['total'], -1);
  });

  test('smartphone list with paging preserves an explicit count', () async {
    final result = await _evaluate(
      count: '1～12/24件',
      controls: [
        {'tag': 'a', 'textContent': '次へ'},
      ],
    );
    expect(result['total'], 24);
  });
}

Future<Map<String, dynamic>> _evaluate({
  bool smartphone = true,
  String count = '',
  List<Map<String, Object?>> controls = const [],
}) async {
  final directory =
      Directory.systemTemp.createTempSync('gakujo_assignment_list_');
  try {
    final harness = File.fromUri(directory.uri.resolve('harness.cjs'))
      ..writeAsStringSync(
          File('test/support/gakujo_assignment_list_fetch_harness.cjs')
              .readAsStringSync(),
          encoding: utf8);
    final input = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
          jsonEncode({
            'script': gakujoAssignmentListFetchScript,
            'smartphone': smartphone,
            'count': count,
            'controls': controls,
          }),
          encoding: utf8);
    final result = await Process.run('node', [harness.path, input.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: 'Node failed: ${result.stderr}');
    final output = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(output['status'], 'ok');
    expect(output['rows'], hasLength(12));
    return output;
  } finally {
    directory.deleteSync(recursive: true);
  }
}
