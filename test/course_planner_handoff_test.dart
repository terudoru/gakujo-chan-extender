import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/course_planner_handoff.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';

import 'support/planner_multikind_fixture.dart';

class _View extends Fake implements GakujoWebViewController {
  late GakujoNavigationDelegate delegate;
  String? url;
  Future<Object?> Function(String)? evaluate;
  @override
  Future<void> setJavaScriptModeUnrestricted() async {}
  @override
  Future<String?> currentUrl() async => url;
  @override
  Future<void> addJavaScriptChannel(
    String name, {
    required FutureOr<void> Function(String) onMessageReceived,
  }) => Completer<void>().future;
  @override
  Future<void> setNavigationDelegate(GakujoNavigationDelegate value) async {
    delegate = value;
  }

  @override
  Future<void> loadUrl(String value) async {
    url = value;
  }

  @override
  Future<void> runJavaScript(String script) async {}
  @override
  Future<Object?> runJavaScriptReturningResult(String script) =>
      evaluate!(script);
  @override
  Future<void> dispose() async {}
}

void main() {
  test('displayed affiliation keeps the admission year from the same inquiry', () {
    String profile(String affiliation, String grade, [String? year]) =>
        encodeCoursePlannerHandoff({
          'v': 1,
          'kind': 'profile',
          'tables': [
            {
              'heading': '学生所属',
              'rows': [
                ['所属', '学年'],
                [affiliation, grade],
              ],
            },
          ],
          'year': ?year,
        }, CoursePlannerImportKind.profile)!;
    final displayed = profile('理学部', '3');
    final inquiry = profile('理学部', '2', '2024');
    expect(
      reuseCoursePlannerEnrollmentFacts(displayed, inquiry),
      profile('理学部', '3', '2024'),
    );
    expect(
      reuseCoursePlannerEnrollmentFacts(displayed, profile('工学部', '2', '2024')),
      displayed,
    );
    final explicit = profile('理学部', '3', '2023');
    expect(reuseCoursePlannerEnrollmentFacts(explicit, inquiry), explicit);
  });

  test('verified enrollment facts survive a partial profile refresh', () {
    const kind = CoursePlannerImportKind.profile;
    String? token(String grade, Map<String, String> facts, {String year = '2024'}) =>
        encodeCoursePlannerHandoff({
          'v': 1, 'kind': kind.name,
          'tables': [
            {'heading': '学生所属', 'rows': [
              ['所属', '学年', ...facts.keys],
              ['理学部', grade, ...facts.values],
            ]},
          ],
          'year': year,
        }, kind);
    const entry = {'入学区分': '編入', '入学年次': '3', '適用便覧年度': '2022'};
    final prior = token('3', entry)!;
    expect(reuseCoursePlannerEnrollmentFacts(token('4', {})!, prior), token('4', entry));
    final differentYear = token('2', {}, year: '2026')!;
    expect(reuseCoursePlannerEnrollmentFacts(differentYear, prior), differentYear);
    final differentType = token('2', {'入学区分': '1年次入学'})!;
    expect(reuseCoursePlannerEnrollmentFacts(differentType, prior), differentType);
    expect(token('2', {'入学区分': '不明'}), isNull);
    expect(token('2', {'適用便覧年度': '令和4年度'}), isNull);
    expect(token('2', {'入学年次': '5'}), isNull);
  });

  test('the registration encoder matches the shared MBGPLAN1 vector', () {
    const packet = {
      'v': 1,
      'kind': 'registration',
      'year': '2026',
      'tables': [
        {
          'heading': '履修登録・登録状況照会',
          'rows': [
            ['開講番号', '登録状況'],
            ['269G9001', '申請中'],
            ['269G9002', '許可'],
          ],
        },
      ],
    };
    expect(
      encodeCoursePlannerHandoff(packet, CoursePlannerImportKind.registration),
      File('test/support/planner_handoff.txt').readAsStringSync().trim(),
    );
  });

  test('multi-kind fetch decoding matches the shared multi-token vector', () {
    final expectedVector = File(
      'test/support/planner_handoff_multi.txt',
    ).readAsStringSync().trim();
    for (final raw in [
      jsonEncode(plannerMultiFetchPayload),
      jsonEncode(jsonEncode(plannerMultiFetchPayload)),
    ]) {
      final handoffs = decodeCoursePlannerFetch(raw);
      expect(
        handoffs.map((h) => h.$1).toList(),
        coursePlannerHandoffOrder,
      );
      expect(joinCoursePlannerHandoffs(handoffs), expectedVector);
    }
    expect(expectedVector.split('\n'), hasLength(4));
  });

  test('decodeCoursePlannerFetch rejects invalid replies and skips bad packets', () {
    expect(decodeCoursePlannerFetch(null), isEmpty);
    expect(decodeCoursePlannerFetch('null'), isEmpty);
    expect(decodeCoursePlannerFetch('{bad json'), isEmpty);
    expect(decodeCoursePlannerFetch('{"v":2,"packets":{}}'), isEmpty);
    expect(decodeCoursePlannerFetch('{"v":1,"packets":[]}'), isEmpty);
    final mixed = decodeCoursePlannerFetch(
      jsonEncode({
        'v': 1,
        'packets': {
          'profile': {
            'v': 1,
            'kind': 'profile',
            'tables': [
              {
                'heading': '学生所属',
                'rows': [
                  ['所属', '学年'],
                  ['fixture@example.invalid', '2'],
                ],
              },
            ],
          },
          'grades': {
            'v': 1,
            'kind': 'grades',
            'tables': [
              {
                'heading': '単位修得状況照会',
                'rows': [
                  ['評価'],
                  ['良'],
                ],
              },
            ],
          },
        },
      }),
    );
    expect(mixed.map((h) => h.$1).toList(), [CoursePlannerImportKind.grades]);
  });

  test('fetchCoursePlannerHandoffs drops results when identity changes', () async {
    var evaluated = false;
    var current = false;
    final portal = _View()
      ..evaluate = (_) async {
        evaluated = true;
        return jsonEncode({
          'v': 1,
          'packets': {
            'grades': {
              'v': 1,
              'kind': 'grades',
              'tables': [
                {
                  'heading': '単位修得状況照会',
                  'rows': [
                    ['評価'],
                    ['良'],
                  ],
                },
              ],
            },
          },
        });
      };
    expect(await fetchCoursePlannerHandoffs(portal, () => current), isEmpty);
    expect(evaluated, isFalse);

    current = true;
    portal.evaluate = (_) async {
      evaluated = true;
      current = false;
      return jsonEncode({
        'v': 1,
        'packets': {
          'grades': {
            'v': 1,
            'kind': 'grades',
            'tables': [
              {
                'heading': '単位修得状況照会',
                'rows': [
                  ['評価'],
                  ['良'],
                ],
              },
            ],
          },
        },
      });
    };
    expect(await fetchCoursePlannerHandoffs(portal, () => current), isEmpty);
    expect(evaluated, isTrue);
  });

  test('background capture polls the WebView and clears its own attempt', () async {
    final scripts = <String>[];
    final portal = _View()
      ..evaluate = (script) async {
        scripts.add(script);
        if (!script.contains('__mbgPlannerFetch?.take(')) return jsonEncode('pending');
        return jsonEncode(jsonEncode({
          'v': 1,
          'packets': <String, dynamic>{},
          'timetable': [{'year': '2025', 'semester': 'second', 'meetings': []}],
          'complete': false,
        }));
      };
    final (packets, timetable, complete) = await fetchCoursePlannerCapture(portal, () => true);
    expect(packets, isEmpty);
    expect(timetable.single, containsPair('year', '2025'));
    expect(complete, isFalse);
    final owner = RegExp(r'"attempt":"([A-Za-z0-9_-]+)"').firstMatch(scripts.first)!.group(1)!;
    expect(scripts[1], contains('take("$owner")'));
    expect(scripts[2], contains('cancel("$owner")'));
  });

  test('supplementCoursePlannerHandoffs merges displayed kinds in order and preserves fetched on error', () async {
    const regPacket = {
      'v': 1,
      'kind': 'registration',
      'tables': [
        {
          'heading': '履修登録・登録状況照会',
          'rows': [
            ['開講番号', '登録状況'],
            ['269G9001', '申請中'],
          ],
        },
      ],
      'year': '2026',
    };
    const gradePacket = {
      'v': 1,
      'kind': 'grades',
      'tables': [
        {
          'heading': '単位修得状況照会',
          'rows': [
            ['開講番号', '科目名', '単位数', '評価', '年度'],
            ['269G9001', '合成力学', '2', '優', '2026'],
          ],
        },
      ],
    };
    const profilePacket = {
      'v': 1,
      'kind': 'profile',
      'tables': [
        {
          'heading': '学生所属',
          'rows': [
            ['所属', '学年'],
            ['理学部物理学科', '2'],
          ],
        },
      ],
    };
    final regToken = encodeCoursePlannerHandoff(
      regPacket,
      CoursePlannerImportKind.registration,
    )!;
    final gradeToken = encodeCoursePlannerHandoff(
      gradePacket,
      CoursePlannerImportKind.grades,
    )!;
    final profileToken = encodeCoursePlannerHandoff(
      profilePacket,
      CoursePlannerImportKind.profile,
    )!;

    final fetched = [(CoursePlannerImportKind.registration, regToken)];
    final portal = _View()
      ..evaluate = (script) async {
        if (script.contains('"kind":"grades"')) return jsonEncode(gradePacket);
        if (script.contains('"kind":"profile"')) {
          return jsonEncode(profilePacket);
        }
        return '["registration","grades","profile"]';
      };
    final merged = await supplementCoursePlannerHandoffs(
      portal,
      () => true,
      fetched,
    );
    expect(merged, [
      (CoursePlannerImportKind.profile, profileToken),
      (CoursePlannerImportKind.grades, gradeToken),
      (CoursePlannerImportKind.registration, regToken),
    ]);

    // Displayed-page failures must not lose the fetched kinds.
    portal.evaluate = (_) async => throw StateError('capture failed');
    expect(
      await supplementCoursePlannerHandoffs(portal, () => true, fetched),
      fetched,
    );

    // Identity change during supplementation aborts and returns empty.
    var current = true;
    portal.evaluate = (_) async {
      current = false;
      return '["grades"]';
    };
    expect(
      await supplementCoursePlannerHandoffs(portal, () => current, fetched),
      isEmpty,
    );
  });

  test('MBGPLAN1 encodes the existing packets and the exact profile shape', () {
    for (final (kind, heading, headers, values) in [
      (CoursePlannerImportKind.grades, '単位修得状況照会', ['評価'], ['良']),
      (
        CoursePlannerImportKind.registration,
        '履修登録・登録状況照会',
        ['開講番号', '登録状況'],
        ['171G0057', '申請中'],
      ),
      (
        CoursePlannerImportKind.balances,
        '履修科目確認表',
        ['科目区分', '既修得単位数'],
        ['教養', '2'],
      ),
      (CoursePlannerImportKind.profile, '学生所属', ['所属', '学年'], ['理学部物理学科', '']),
      (CoursePlannerImportKind.profile, '学生所属', ['所属', '学年'], ['理学部物理学科', '2']),
    ]) {
      final packet = {
        'v': 1,
        'kind': kind.name,
        if (kind == CoursePlannerImportKind.registration) 'year': '2026',
        'tables': [
          {
            'heading': heading,
            'rows': [headers, values],
          },
        ],
      };
      final token = encodeCoursePlannerHandoff(packet, kind)!;
      expect(token, matches(RegExp(r'^MBGPLAN1\.[A-Za-z0-9_-]+$')));
      final json = utf8.decode(
        base64Url.decode(
          base64Url.normalize(token.substring('MBGPLAN1.'.length)),
        ),
      );
      expect(jsonDecode(json), packet);
    }
  });

  test('MBGPLAN1 rejects invalid profiles and oversized encoded packets', () {
    const kind = CoursePlannerImportKind.profile;
    for (final rows in [
      [
        ['所属', '学年'],
        ['理学部物理学科', '7'],
      ],
      [
        ['所属', '学年'],
        ['学籍番号 12A0000B', '2'],
      ],
      [
        ['所属', '学年'],
        ['fixture@example.invalid', '2'],
      ],
      [
        ['所属', '学年'],
        ['', '2'],
      ],
      [
        ['所属', '学年', '氏名'],
        ['理学部物理学科', '2', '合成氏名'],
      ],
      [
        ['所属', '学年'],
        ['理学部物理学科', '2'],
        ['理学部物理学科', '3'],
      ],
      [
        ['学年', '所属'],
        ['2', '理学部物理学科'],
      ],
    ]) {
      expect(
        encodeCoursePlannerHandoff({
          'v': 1,
          'kind': kind.name,
          'tables': [
            {'heading': '学生所属', 'rows': rows},
          ],
        }, kind),
        isNull,
      );
    }
    final longRow = [List.filled(140, '科').join()];
    expect(
      encodeCoursePlannerHandoff({
        'v': 1,
        'kind': 'grades',
        'tables': [
          {
            'heading': '単位修得状況照会',
            'rows': [
              ['科目名'],
              ...List.filled(4000, longRow),
            ],
          },
        ],
      }, CoursePlannerImportKind.grades),
      isNull,
    );
  });

  test('profile is offered only for the clipboard chooser', () async {
    final portal = _View()..evaluate = (_) async => '["grades","profile"]';
    final source = CoursePlannerSource(portal, () => true);
    expect(await source.choices(), [CoursePlannerImportKind.grades]);
    expect(await source.choices(includeProfile: true), [
      CoursePlannerImportKind.grades,
      CoursePlannerImportKind.profile,
    ]);
  });

  test('grade packets retain zero and separate credit columns', () async {
    final portal = _View();
    final source = CoursePlannerSource(portal, () => true);
    for (final (headers, values) in [
      (['修得単位数'], ['0']),
      (['単位数', '修得単位数'], ['2', '0']),
      (['修得単位数', '単位数'], ['1', '2']),
    ]) {
      final packet = {
        'v': 1,
        'kind': 'grades',
        'tables': [
          {
            'heading': '単位修得状況照会',
            'rows': [
              ['開講番号', '評価', ...headers],
              ['260K0363', '不可', ...values],
            ],
          },
        ],
      };
      portal.evaluate = (_) async => jsonEncode(packet);
      expect(await source.capture(CoursePlannerImportKind.grades), packet);
    }
  });
  test(
    'grade packets admit course offering and exclude student affiliation',
    () async {
      final portal = _View();
      final source = CoursePlannerSource(portal, () => true);
      for (final header in ['開講所属', '学生所属', '所属学部', '学部', '所属', '氏名']) {
        portal.evaluate = (_) async => jsonEncode({
          'v': 1,
          'kind': 'grades',
          'tables': [
            {
              'heading': '単位修得状況照会',
              'rows': [
                ['科目名', '単位数', '評価', header, 'クラス', '学期'],
                ['情報通信技術教育論I', '1', '優', '人文学部', 'A', '第1ターム'],
              ],
            },
          ],
        });
        expect(
          await source.capture(CoursePlannerImportKind.grades),
          header == '開講所属' ? isNotNull : isNull,
          reason: header,
        );
      }
    },
  );
}
