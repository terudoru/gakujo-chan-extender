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

  test('an unread page keeps the total unknown', () async {
    final result = await _evaluate(
      count: '1～12/24件',
      controls: [
        {'tag': 'a', 'textContent': '次へ'},
      ],
    );
    expect(result['total'], -1);
  });

  test('1～1/2件 follows 次へ with the next flow key and event', () async {
    const next = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
        'campussquare.do?_flowExecutionKey=page2&_eventId=paging&_page=2';
    final result = await _evaluate(expectedRows: 2, pages: [
      {
        'count': '1～1/2件',
        'rows': [
          {'title': '第1回'}
        ],
        'controls': [
          {
            'tag': 'a',
            'textContent': '次へ',
            'attributes': {'href': next}
          },
        ],
      },
      {
        'url': next,
        'count': '2～2/2件',
        'rows': [
          {'title': '第2回'}
        ],
      },
    ]);
    expect(result['total'], 2);
    expect((result['rows'] as List).map((row) => row['title']), ['第1回', '第2回']);
    expect((result['requests'] as List).last, next);
  });

  test('a supported display count uses the form flow key and paging event',
      () async {
    final result = await _evaluate(expectedRows: 2, pages: [
      {
        'count': '1～1/2件',
        'rows': [
          {'title': '第1回'}
        ],
        'controls': [
          {
            'tag': 'input',
            'value': 'list key',
            'attributes': {'type': 'hidden', 'name': '_flowExecutionKey'}
          },
          {
            'tag': 'select',
            'attributes': {'name': '_displayCount'},
            'options': [
              {'value': '1'},
              {'value': '50'}
            ]
          },
        ],
      },
      {
        'count': '1～2/2件',
        'rows': [
          {'title': '第1回'},
          {'title': '第2回'}
        ],
      },
    ]);
    expect(result['total'], 2);
    expect(
        Uri.parse((result['requests'] as List).last as String).queryParameters,
        containsPair('_displayCount', '50'));
    expect(
        Uri.parse((result['requests'] as List).last as String).queryParameters,
        containsPair('_eventId', 'paging'));
  });

  test('paging stops at ten pages without claiming a complete list', () async {
    final result = await _evaluate(expectedRows: 10, pages: [
      for (var page = 1; page <= 11; page += 1)
        {
          'count': '$page～$page/11件',
          'rows': [
            {'title': '課題 $page'}
          ],
          'controls': [
            {
              'tag': 'a',
              'textContent': '次へ',
              'attributes': {
                'href':
                    '?_flowExecutionKey=page$page&_eventId=paging&_page=${page + 1}',
              }
            },
          ],
        },
    ]);
    expect(result['requests'], hasLength(10));
    expect(result['total'], -1);
  });

  test('a repeated page keeps the total unknown', () async {
    final result = await _evaluate(expectedRows: 1, pages: [
      {
        'count': '1～1/2件',
        'rows': [
          {'title': '第1回'}
        ],
        'controls': [
          {
            'tag': 'a',
            'textContent': '次へ',
            'attributes': {
              'href': '?_flowExecutionKey=page2&_eventId=paging',
            }
          },
        ],
      },
    ]);
    expect(result['requests'], hasLength(2));
    expect(result['total'], -1);
  });

  test('a 次へ onclick URL follows the page event', () async {
    const next = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
        'campussquare.do?_flowExecutionKey=page2&_eventId=paging';
    final result = await _evaluate(expectedRows: 2, pages: [
      {
        'count': '1～1/2件',
        'rows': [
          {'title': '第1回'}
        ],
        'controls': [
          {
            'tag': 'a',
            'textContent': '次へ',
            'attributes': {
              'onclick': "location.href='$next'",
            }
          },
        ],
      },
      {
        'url': next,
        'count': '2～2/2件',
        'rows': [
          {'title': '第2回'}
        ],
      },
    ]);
    expect(result['total'], 2);
  });

  test('a failed next page keeps rows without claiming a complete list',
      () async {
    final result = await _evaluate(expectedRows: 1, pages: [
      {
        'count': '1～1/2件',
        'rows': [
          {'title': '第1回'}
        ],
        'controls': [
          {
            'tag': 'a',
            'textContent': '次へ',
            'attributes': {
              'href': '?_flowExecutionKey=page2&_eventId=paging',
            }
          },
        ],
      },
      {'status': 500},
    ]);
    expect(result['requests'], hasLength(2));
    expect(result['total'], -1);
  });

  test('smartphone course uses the last course / teacher group', () async {
    final result = await _evaluate(expectedRows: 1, pages: [
      {
        'rows': [
          {
            'title': '第1回 (前半)',
            'text': '第1回 (前半) (物理学 / 教員) '
                '実施期間：2026/10/24 8:45 ～10/30 17:00 状態：未提出'
          },
        ]
      },
    ]);
    expect((result['rows'] as List).single['course'], '物理学');
  });
}

Future<Map<String, dynamic>> _evaluate({
  bool smartphone = true,
  String count = '',
  List<Map<String, Object?>> controls = const [],
  List<Map<String, Object?>>? pages,
  int expectedRows = 12,
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
            'pages': ?pages,
          }),
          encoding: utf8);
    final result = await Process.run('node', [harness.path, input.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: 'Node failed: ${result.stderr}');
    final output = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(output['status'], 'ok');
    expect(output['rows'], hasLength(expectedRows));
    return output;
  } finally {
    directory.deleteSync(recursive: true);
  }
}
