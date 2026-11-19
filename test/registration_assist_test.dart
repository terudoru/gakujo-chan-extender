import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/registration_handoff.dart';
import 'package:morebettergakujo_flutter/src/widgets/registration_assist_panel.dart';

void main() {
  final vector = File('test/support/registration_handoff.txt')
      .readAsStringSync()
      .trim();
  final expected = jsonDecode('''
{"v":1,"kind":"gakujo-registration-plan","year":2026,"courses":[
 {"code":"171G0057","title":"アカデミック英語R1","semester":1,"quarters":[1],"slots":["月1"],"credits":0.5},
 {"code":"174G5512","title":"物理学基礎B Ⅱ","semester":2,"quarters":[4],"slots":["火1","金1"],"credits":2},
 {"code":"260A0003","title":"基礎農林学実習","semester":1,"quarters":[1,2],"slots":[],"credits":1}]}
''') as Map<String, dynamic>;

  String token(Object json) =>
      'MBGREG1.${base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '')}';
  final courses = (expected['courses'] as List).cast<Map<String, dynamic>>();

  test(
    'fixed handoff decodes to the documented JSON, including embedded paste',
    () {
      expect(
        RegistrationHandoff.decode('  履修手帖から\n$vector\n  ').toJson(),
        expected,
      );
    },
  );

  test('rejects invalid tokens and fields with localized errors', () {
    final invalid = [
      vector.replaceFirst('MBGREG1', 'MBGREG2'),
      'MBGREG1.A',
      'MBGREG1.%%%%',
      '$vector=',
      'MBGREG1.${List.filled(65536, 'A').join()}',
      token({...expected, 'unexpected': false}),
      token({...expected, 'year': '2026'}),
      token({...expected, 'year': 2026.0}),
      token({
        ...expected,
        'courses': [courses.first, courses.first],
      }),
      token({
        ...expected,
        'courses': [
          for (var index = 0; index < 61; index++)
            {
              ...courses.first,
              'code': '171G${index.toString().padLeft(4, '0')}',
            },
        ],
      }),
      for (final extra in [
        {'code': '171g0057'},
        {
          'slots': ['月8'],
        },
        {
          'slots': ['火1', '火1'],
        },
        {'semester': 1.0},
        {
          'quarters': [1, 1],
        },
        {
          'quarters': [5],
        },
        {'credits': 31},
        {'title': ''},
        {'unexpected': false},
      ])
        token({
          ...expected,
          'courses': [
            {...courses.first, ...extra},
          ],
        }),
    ];
    for (final input in invalid) {
      expect(
        () => RegistrationHandoff.decode(input),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            matches(RegExp(r'[ぁ-ん]')),
          ),
        ),
      );
    }
  });

  test(
    'registered, first slot, other semester and manual courses are classified',
    () {
      final [first, second, intensive] = RegistrationHandoff.decode(vector)
          .courses;
      final slots = {
        1: {'月1'},
        2: {'火1'},
      };
      expect(
        classifyRegistrationCourse(first, {first.code}, slots),
        RegistrationDisposition.registered,
      );
      expect(
        classifyRegistrationCourse(first, {}, slots),
        RegistrationDisposition.guided,
      );
      expect(
        classifyRegistrationCourse(second, {}, {
          2: {'金1'},
        }),
        RegistrationDisposition.manual,
      );
      expect(
        classifyRegistrationCourse(second, {}, {
          1: {'月1'},
        }),
        RegistrationDisposition.checkOtherSemester,
      );
      expect(
        classifyRegistrationCourse(intensive, {}, slots),
        RegistrationDisposition.manual,
      );
      expect(
        classifyRegistrationCourse(first, {}, {1: {}}),
        RegistrationDisposition.manual,
      );
      final noSemester = RegistrationHandoff.decode(
        token({
          ...expected,
          'courses': [
            {...courses.first, 'semester': null},
          ],
        }),
      ).courses.single;
      expect(
        classifyRegistrationCourse(noSemester, {}, slots),
        RegistrationDisposition.manual,
      );
    },
  );

  test('account or identity revision change terminates the in-memory run', () {
    final plan = RegistrationHandoff.decode(vector);
    for (final (account, revision, confirmed) in [
      ('other', 3, true),
      ('fixture', 4, true),
      ('fixture', 3, false),
    ]) {
      final run = RegistrationRun('fixture', 3, plan, {});
      expect(run.checkIdentity('fixture', 3, confirmed: true), isTrue);
      expect(run.next?.code, '171G0057');
      expect(
        run.checkIdentity(account, revision, confirmed: confirmed),
        isFalse,
      );
      expect(run.checkIdentity('fixture', 3, confirmed: true), isFalse);
      expect(run.next, isNull);
      expect(run.summary, contains('残り 3件'));
    }
  });

  testWidgets('bottom panel retains safety text while the student chooses', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: RegistrationAssistPanel(
            status: '171G0057 を確認してください',
            onCancel: () {},
            onSkip: () {},
          ),
        ),
      ),
    );
    expect(find.text(registrationSafetyText), findsOneWidget);
    expect(find.text('この科目を飛ばす'), findsOneWidget);
    expect(find.text('中止'), findsOneWidget);
    expect(find.text('次の科目へ'), findsNothing);
  });
}
