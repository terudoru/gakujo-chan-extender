import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/course_planner_link.dart';
import 'package:morebettergakujo_flutter/src/course_planner_page.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
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

class _Service extends Fake implements GakujoWebViewService {
  _Service({this.portal});
  _View? portal;
  final view = _View();
  @override
  GakujoWebViewController createController() {
    final first = portal;
    portal = null;
    return first ?? view;
  }

  @override
  Future<void> configureController(
    GakujoWebViewController controller, {
    required bool debugAllowed,
    bool downloadInterceptionEnabled = true,
  }) async {}
  @override
  Widget buildWidget(
    GakujoWebViewController controller, {
    ValueChanged<String>? onError,
  }) => const Text('Planner WebView');
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
  testWidgets(
    'app menu opens a separate planner from unrelated and syllabus pages',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
      final portal = _View()..url = 'https://www.niigata-u.ac.jp/';
      final service = _Service(portal: portal);
      await tester.pumpWidget(
        MaterialApp(home: GakujoWebApp(webViewService: service)),
      );
      for (final expected in [
        coursePlannerUrl,
        '$coursePlannerUrl#course=2026-261G7011',
      ]) {
        await tester.tap(find.byTooltip('メニュー'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('履修プランナー'));
        await tester.tap(find.text('履修プランナー'));
        await tester.pumpAndSettle();
        expect(find.byType(CoursePlannerPage), findsOneWidget);
        expect(service.view.url, expected);
        await tester.pageBack();
        await tester.pumpAndSettle();
        portal.url = 'https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/84/84_261G7011_ja_JP.html?private=omitted';
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('only the configured loopback origin is usable for debug previews', () {
    expect(
      coursePlannerBase('http://127.0.0.1:8350', debug: true),
      'http://127.0.0.1:8350/',
    );
    for (final url in [
      'https://elsewhere.test/',
      'http://user@localhost/',
      'http://localhost/?target=other',
    ]) {
      expect(coursePlannerBase(url, debug: true), coursePlannerUrl);
    }
    expect(
      coursePlannerBase('http://localhost:8000/', debug: false),
      coursePlannerUrl,
    );
    expect(
      coursePlannerLink(
        'https://syllabus.niigata-u.ac.jp:8443/syllabusHtml/2026/84/84_261G7011_ja_JP.html',
      ).toString(),
      coursePlannerUrl,
    );
    final official = Uri.parse(coursePlannerUrl);
    for (final target in [
      'https://user@gakujo.terudoru.com/planner/',
      'https://gakujo.terudoru.com/planner/new',
      'https://gakujo.terudoru.com/planner/?private=1',
    ]) {
      expect(isCoursePlannerDocument(Uri.parse(target), official), isFalse);
    }
  });
  for (final stale in [false, true]) {
    testWidgets(
      'dedicated planner receives only the confirmed current capture, stale=$stale',
      (tester) async {
        final portal = _View(), service = _Service();
        final capture = Completer<String>();
        var valid = true, reads = 0, probes = 0, delivered = 0;
        portal.evaluate = (_) {
          reads++;
          return capture.future;
        };
        service.view.evaluate = (script) async {
          if (script.contains('"phase":"bind"')) return 'bound';
          if (script.contains('"phase":"probe"')) {
            return ++probes == 1 ? 'waiting' : '"ready"';
          }
          if (script.contains('"phase":"deliver"')) {
            expect(script, contains('"kind":"grades","tables"'));
            delivered++;
            return 'sent';
          }
          fail('Unexpected phase');
        };
        final source = CoursePlannerSource(portal, () => valid);
        await tester.pumpWidget(
          MaterialApp(
            home: CoursePlannerPage(
              service: service,
              url: Uri.parse(coursePlannerUrl),
              onExternalLink: (_) {},
              source: source,
              kind: CoursePlannerImportKind.grades,
            ),
          ),
        );
        await tester.pump();
        expect(service.view.url, coursePlannerUrl);
        final finished = Future.sync(
          () => service.view.delegate.onPageFinished!(coursePlannerUrl),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 201));
        expect(reads, 1);
        valid = !stale;
        capture.complete(
          jsonEncode({
            'v': 1,
            'kind': 'grades',
            'tables': [
              {
                'heading': '単位修得状況照会',
                'rows': [
                  ['科目名', '単位数', '評価'],
                  ['合成科目', '1', '認定'],
                ],
              },
            ],
          }),
        );
        await finished;
        await tester.pump();
        expect(delivered, stale ? 0 : 1);
        if (!stale) {
          await service.view.delegate.onPageFinished!(coursePlannerUrl);
          expect(delivered, 1);
        } else {
          expect(find.textContaining('学務の照会画面からやり直してください'), findsOneWidget);
        }
      },
    );
  }
}
