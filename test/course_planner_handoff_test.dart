import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/course_planner_handoff.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';

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
