import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/course_planner_handoff.dart';
import 'package:morebettergakujo_flutter/src/drive_planner_handoff.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

class _Drive implements StarSyncTransport {
  List<int>? bytes;
  final extra = <String, List<int>>{};
  int writes = 0;
  void Function()? onRead;
  @override
  Future<StarSyncRemoteObject?> get(
    String path, {
    int maxBytes = starSyncDefaultMaxBytes,
  }) async {
    onRead?.call();
    final value = path == drivePlannerHandoffName ? bytes : extra[path];
    return value == null ? null : StarSyncRemoteObject(bytes: value);
  }

  @override
  Future<void> put(
    String path,
    List<int> value, {
    bool createOnly = false,
  }) async {
    writes++;
    if (path == drivePlannerHandoffName) {
      if (createOnly) expect(bytes, isNull);
      bytes = value;
    } else {
      if (createOnly) expect(extra.containsKey(path), isFalse);
      extra[path] = value;
    }
  }

  @override
  Future<void> ensureDirectory(String path) async {}
  @override
  Future<List<StarSyncRemoteEntry>> list(String directory) async => [];
  @override
  Future<void> delete(String path) async {}
  @override
  void close() {}
}

Map<String, dynamic> _packetFromToken(String token) =>
    jsonDecode(utf8.decode(base64Url.decode(
      base64Url.normalize(token.substring('MBGPLAN1.'.length)),
    ))) as Map<String, dynamic>;

void main() {
  final fixture = File('test/fixtures/drive_planner_handoff_v1.json')
      .readAsBytesSync();
  final data = decodeDrivePlannerHandoff(fixture);
  final captured = [
    for (final packet in data['packets'] as List)
      (
        coursePlannerHandoffOrder.singleWhere((k) => k.name == packet['kind']),
        packet['token'] as String,
      ),
  ];
  final time = DateTime.utc(2026, 11, 24);
  test('timetable marker persists courses by term and rejects another student', () async {
    final drive = _Drive();
    final student = 'a' * 43;
    List<dynamic> terms() {
      final value = jsonDecode(utf8.decode(drive.extra[drivePlannerTimetableName]!));
      expect(value['student'], student);
      return value['terms'] as List;
    }
    Map<String, dynamic> term(String year, String semester, int day) => {
      'year': year,
      'semester': semester,
      'meetings': [
        {'code': '${year.substring(2)}0H1002', 'title': '心理・人間学入門',
          'status': '許可', 'day': day, 'period': 3},
      ],
    };
    Future<PlannerTimetableShare> shareTerms(
      List<Object?> captured, {String? owner, int days = 0}
    ) =>
        shareDrivePlannerTimetable(
          transport: drive,
          student: owner ?? student,
          captured: captured,
          allowed: () => true,
          capturedAt: time.add(Duration(days: days)),
        );
    expect(await shareTerms([]), PlannerTimetableShare.complete);
    expect(terms(), isEmpty);
    expect(await shareTerms([term('2025', 'second', 2), term('2026', 'first', 4)], days: 1),
      PlannerTimetableShare.complete);
    expect(await shareTerms([term('2026', 'first', 3)], days: 2), PlannerTimetableShare.complete);
    expect(await shareTerms([term('2026', 'first', 5)], days: 1), PlannerTimetableShare.complete);
    expect(terms().map((term) => term['meetings'][0]['day']), [2, 3]);
    expect(drive.writes, 3);
    await expectLater(shareTerms([], owner: 'b' * 43), throwsA(isA<PlannerTimetableStudentMismatch>()));
    expect(await shareTerms([term('2025', 'second', 8)], days: 3), PlannerTimetableShare.pending);
    expect(drive.writes, 3);

    final unreadable = {
      ...term('2024', 'first', 0), 'capturedAt': plannerTimestamp(time),
    };
    drive.extra[drivePlannerTimetableName] = utf8.encode(jsonEncode({
      'v': 1, 'kind': 'mbg-gakujo-timetable', 'student': student,
      'terms': [...terms(), unreadable, term('2024', 'second', 5)],
    }));
    expect(await shareTerms([]), PlannerTimetableShare.pending);
    expect(drive.writes, 3);
    expect(await shareTerms([term('2026', 'second', 7), term('2024', 'second', 9)], days: 3),
      PlannerTimetableShare.pending);
    expect(terms().map((term) => term['meetings'][0]['day']), [2, 3, 0, 5, 7]);
    expect(await shareTerms([term('2024', 'first', 4), term('2024', 'second', 5)], days: 4),
      PlannerTimetableShare.complete);
    expect(terms().map((term) => term['meetings'][0]['day']), [2, 3, 7, 4, 5]);
    expect(drive.writes, 5);
  });

  Future<bool> share(
    _Drive drive, {
    List<(CoursePlannerImportKind, String)>? packets,
    bool Function()? allowed,
    DateTime? at,
    bool preserveAcademicHistory = false,
    String? student,
  }) => shareDrivePlannerHandoffs(
    transport: drive,
    captured: packets ?? captured,
    allowed: allowed ?? () => true,
    capturedAt: at ?? time,
    preserveAcademicHistory: preserveAcademicHistory,
    student: student,
  );

  test('Drive body matches shared fixture byte for byte', () async {
    final drive = _Drive();
    expect(await share(drive), isTrue);
    expect(drive.bytes, fixture);
  });
  test('scoped academic reports keep matching inquiries and never claim the legacy copy', () async {
    final drive = _Drive();
    final student = 'a' * 43;
    final source = captured.take(2).toList();
    expect(await share(drive), isTrue);
    expect(await share(drive, student: student, packets: [source.first]), isTrue);
    final first = decodeDrivePlannerHandoff(drive.extra[driveScopedPlannerHandoffName]!, student: student);
    expect(first.keys.toList(), ['v', 'kind', 'student', 'updatedAt', 'packets']);
    expect(first, {
      'v': 2, 'kind': 'mbg-gakujo-handoff', 'student': student,
      'updatedAt': plannerTimestamp(time),
      'packets': [(data['packets'] as List).first],
    });
    expect(await share(drive, student: student, packets: [source.last]), isTrue);
    final saved = drive.extra[driveScopedPlannerHandoffName]!;
    expect(decodeDrivePlannerHandoff(saved, student: student)['packets'],
        (data['packets'] as List).take(2).toList());
    await expectLater(share(drive, student: 'b' * 43),
        throwsA(isA<PlannerTimetableStudentMismatch>()));
    expect(drive.extra[driveScopedPlannerHandoffName], same(saved));

    drive.extra[driveScopedPlannerHandoffName] = utf8.encode(jsonEncode({
      ...first, 'student': '',
    }));
    expect(await share(drive, student: student, packets: source), isTrue);
    expect(decodeDrivePlannerHandoff(drive.extra[driveScopedPlannerHandoffName]!,
        student: student)['packets'], (data['packets'] as List).take(2).toList());
    expect(drive.bytes, fixture);
  });
  for (final corruption in [
    'malformed JSON',
    'unsupported version',
    'invalid token',
    'invalid UTF-8',
  ]) {
    test('replaces existing handoff with $corruption', () async {
      final previous = jsonDecode(utf8.decode(fixture)) as Map<String, dynamic>;
      if (corruption == 'unsupported version') previous['v'] = 2;
      if (corruption == 'invalid token') {
        previous['packets'][0]['token'] = 'MBGPLAN1.invalid';
      }
      final drive = _Drive()
        ..bytes = switch (corruption) {
          'malformed JSON' => utf8.encode('{broken'),
          'invalid UTF-8' => [0xff],
          _ => utf8.encode(jsonEncode(previous)),
        };
      expect(await share(drive), isTrue);
      expect(drive.writes, 1);
      expect(drive.bytes, fixture);
      expect(decodeDrivePlannerHandoff(drive.bytes!), data);
    });
  }
  test('merge retains other kinds and unchanged capturedAt', () async {
    final drive = _Drive();
    await share(drive, packets: captured.take(2).toList());
    await share(
      drive,
      packets: captured.skip(1).toList(),
      at: time.add(const Duration(days: 1)),
    );
    final result = decodeDrivePlannerHandoff(drive.bytes!);
    expect((result['packets'] as List).length, 4);
    expect(result['packets'][0]['capturedAt'], plannerTimestamp(time));
    expect(result['packets'][1]['capturedAt'], plannerTimestamp(time));
    expect(
      result['packets'][2]['capturedAt'],
      plannerTimestamp(time.add(const Duration(days: 1))),
    );
  });
  test('a partial refresh preserves existing grades and registration while a profile is unreadable', () async {
    final previous = jsonDecode(utf8.decode(fixture)) as Map<String, dynamic>;
    final previousPackets = previous['packets'] as List;
    previousPackets.first['token'] = 'MBGPLAN2.e30';
    previousPackets.removeWhere((packet) => packet['kind'] == 'balances');
    final drive = _Drive()..bytes = utf8.encode(jsonEncode(previous));
    final balances = captured.singleWhere(
      (entry) => entry.$1 == CoursePlannerImportKind.balances,
    );
    final profileCapture = captured.singleWhere(
      (entry) => entry.$1 == CoursePlannerImportKind.profile,
    );
    final refreshed = time.add(const Duration(days: 1));
    expect(
      await share(drive, packets: [balances], at: refreshed,
        preserveAcademicHistory: true),
      isFalse,
    );
    final partial = jsonDecode(utf8.decode(drive.bytes!))['packets'] as List;
    expect(partial.where((packet) => packet['kind'] != 'balances'), previousPackets);
    expect(partial.singleWhere((packet) => packet['kind'] == 'balances'), {
      'kind': 'balances', 'capturedAt': plannerTimestamp(refreshed), 'token': balances.$2,
    });
    expect(
      await share(drive, packets: [profileCapture],
        at: time.subtract(const Duration(seconds: 1)), preserveAcademicHistory: true),
      isFalse,
    );
    expect(drive.writes, 1);
    expect(
      await share(drive, packets: [profileCapture], at: refreshed,
        preserveAcademicHistory: true),
      isTrue,
    );
    final repaired = decodeDrivePlannerHandoff(drive.bytes!)['packets'] as List;
    expect(repaired.first, {
      'kind': 'profile', 'capturedAt': plannerTimestamp(refreshed), 'token': profileCapture.$2,
    });
    expect(repaired.skip(1), partial.skip(1));
    expect(drive.writes, 2);
  });
  test('unchanged content performs no write', () async {
    final drive = _Drive()..bytes = fixture;
    await share(drive, at: time.add(const Duration(days: 1)));
    expect(drive.writes, 0);
    expect(drive.bytes, fixture);
  });

  test('grade refreshes retain absent years and only replace an exact result', () async {
    final drive = _Drive();
    const kind = CoursePlannerImportKind.grades;
    Future<bool> publish(int day, List<List<String>> rows, {String? year}) {
      final headers = [
        if (year == null) '年度', '開講番号', '科目名', '単位数', '評価',
      ];
      final token = encodeCoursePlannerHandoff({
        'v': 1, 'kind': kind.name,
        'tables': [{'heading': '単位修得状況照会', 'rows': [headers, ...rows]}],
        'year': ?year,
      }, kind)!;
      return share(drive, packets: [(kind, token)],
        preserveAcademicHistory: true, at: time.add(Duration(days: day)));
    }
    Map<String, List<String>> savedGrades() {
      final data = decodeDrivePlannerHandoff(drive.bytes!);
      final token = (data['packets'] as List).single['token'] as String;
      final packet = _packetFromToken(token);
      final byCode = <String, List<String>>{};
      for (final table in packet['tables'] as List) {
        final rows = table['rows'] as List;
        final headers = rows.first as List;
        for (final raw in rows.skip(1)) {
          final row = (raw as List).cast<String>();
          final code = row[headers.indexOf('開講番号')];
          expect(byCode.containsKey(code), isFalse);
          byCode[code] = [
            row[headers.indexOf('年度')], row[headers.indexOf('科目名')],
            row[headers.indexOf('単位数')], row[headers.indexOf('評価')],
          ];
        }
      }
      return byCode;
    }
    expect(await publish(0, [
      ['2024', '240H1001', '旧年度の科目', '2', '秀'],
      ['2026', '260H1002', '訂正対象の科目', '2', '良'],
    ]), isTrue);
    expect(await publish(2, [
      ['260H1002', '訂正対象の科目', '2', '不可'],
    ], year: '2026'), isTrue);
    expect(savedGrades(), {
      '240H1001': ['2024', '旧年度の科目', '2', '秀'],
      '260H1002': ['2026', '訂正対象の科目', '2', '不可'],
    });

    expect(await publish(1, [
      ['2026', '260H1002', '訂正対象の科目', '2', '良'],
      ['2025', '250H1003', '後から見つかった科目', '1', '良'],
    ]), isTrue);
    expect(savedGrades()['260H1002']?.last, '不可');
    expect(savedGrades()['250H1003'], ['2025', '後から見つかった科目', '1', '良']);

    expect(await publish(3, [
      ['2026', '260H1002', '訂正対象の科目', '2', '保留'],
      ['2025', '250H1004', '別の科目', '2', '優'],
    ]), isFalse);
    expect(savedGrades()['260H1002']?.last, '不可');
    expect(savedGrades()['250H1004']?.last, '優');
    expect(await publish(4, [
      ['2026', '260H1002', '訂正対象の科目', '2', '優'],
      ['2026', '260H1002', '訂正対象の科目', '2', '可'],
    ]), isFalse);
    expect(await publish(5, [
      ['2026', '260H1002', '別名の科目', '2', '優'],
    ]), isFalse);
    expect(savedGrades()['260H1002']?.last, '不可');
    expect(await publish(6, [
      ['2026', '260H1002', '訂正対象の科目', '2', '優'],
    ]), isTrue);
    expect(savedGrades()['260H1002']?.last, '優');
    expect(savedGrades().keys, containsAll(['240H1001', '250H1003', '250H1004']));
  });

  test('a flat inquiry cannot discard a previously captured split credit report', () async {
    const kind = CoursePlannerImportKind.balances;
    final split = encodeCoursePlannerHandoff({
      'v': 1, 'kind': kind.name, 'tables': [
        {'heading': '履修科目確認表', 'rows': [
          ['科目区分', '既修得単位(昼間)', '既修得単位(夜間)'],
          ['合成科目区分', '4.5', '1.5'],
        ]},
      ],
    }, kind)!;
    final flat = captured.singleWhere((entry) => entry.$1 == kind);
    final drive = _Drive();
    expect(await share(drive, packets: [(kind, split)], preserveAcademicHistory: true), isTrue);
    final published = drive.bytes;
    expect(await share(drive, packets: [flat], preserveAcademicHistory: true,
      at: time.add(const Duration(minutes: 1))), isTrue);
    expect(drive.bytes, published);
    expect(drive.writes, 1);
  });

  test('verified registration captures retain missing terms and refresh explicit outcomes', () async {
    const kind = CoursePlannerImportKind.registration;
    String token(List<Map<String, Object?>> tables, {String? year}) =>
        encodeCoursePlannerHandoff({
          'v': 1,
          'kind': kind.name,
          'tables': tables,
          'year': ?year,
        }, kind)!;
    final drive = _Drive();
    final prior = token([
      {'heading': '履修登録・登録状況照会', 'rows': [
        ['年度', '開講番号', '登録状況'],
        ['2025', '250H1002', '許可'],
        ['2026', '269G9001', '申請中'],
        ['2026', '269G9002', '許可'],
      ]},
      {'heading': '不許可となった科目', 'rows': [
        ['年度', '開講番号', '科目名'],
        ['2025', '250H1005', '合成不許可'],
      ]},
    ]);
    final recent = token([
      {'heading': '履修登録・登録状況照会', 'rows': [
        ['開講番号', '登録状況'],
        ['269G9001 (T1)', '許可'],
        ['269G9002', '要確認'],
        ['269G9003', '申請中'],
      ]},
      {'heading': '履修登録・登録状況照会', 'rows': [
        ['年度', '開講番号', '登録状況'],
        ['2024', '240H1003', '許可'],
      ]},
    ], year: '2026');
    List<String> rows() {
      final packet = decodeDrivePlannerHandoff(drive.bytes!)['packets'].single;
      final decoded = _packetFromToken(packet['token'] as String);
      expect(decoded['year'], isNull);
      return [
        for (final table in decoded['tables'])
          for (final row in table['rows'].skip(1))
            row.join('/'),
      ];
    }

    await share(drive, packets: [(kind, prior)], preserveAcademicHistory: true);
    final refreshAt = time.add(const Duration(minutes: 30));
    expect(await share(drive, packets: [(kind, recent)], at: refreshAt,
      preserveAcademicHistory: true), isTrue);
    expect(rows(), unorderedEquals([
      '2025/250H1002/許可',
      '2025/250H1005/合成不許可',
      '2026/269G9001 (T1)/許可',
      '2026/269G9002/許可',
      '2026/269G9003/申請中',
    ]));
    // Repeated current-only captures and a delayed older response cannot
    // erase previous semesters or roll the new permission back.
    await share(drive, packets: [(kind, recent)], at: refreshAt.add(const Duration(minutes: 1)),
      preserveAcademicHistory: true);
    await share(drive, packets: [(kind, prior)], at: time,
      preserveAcademicHistory: true);
    expect(drive.writes, 2);
  });

  test('verified profile refresh retains only a matching printed admission year', () async {
    const kind = CoursePlannerImportKind.profile;
    String token(String affiliation, String yearOfStudy, {String? admission}) =>
        encodeCoursePlannerHandoff({
          'v': 1, 'kind': kind.name, 'year': ?admission,
          'tables': [{'heading': '学生所属', 'rows': [
            ['所属', '学年'], [affiliation, yearOfStudy],
          ]}],
        }, kind)!;
    const affiliation = '理学部物理学科';
    final drive = _Drive();
    await share(drive, packets: [(kind, token(affiliation, '2', admission: '2024'))],
      preserveAcademicHistory: true);
    await share(drive, packets: [(kind, token(affiliation, '3'))],
      at: time.add(const Duration(days: 1)), preserveAcademicHistory: true);
    String published() =>
        decodeDrivePlannerHandoff(drive.bytes!)['packets'].single['token'] as String;
    expect(_packetFromToken(published()),
      _packetFromToken(token(affiliation, '3', admission: '2024')));
    final changedAffiliation = token('工学部工学科', '3');
    await share(drive, packets: [(kind, changedAffiliation)],
      at: time.add(const Duration(days: 2)), preserveAcademicHistory: true);
    expect(published(), changedAffiliation);
  });
  for (final reason in ['signed out', 'switch OFF', 'account changed']) {
    test('$reason prevents write including during read', () async {
      final drive = _Drive();
      expect(await share(drive, allowed: () => false), isFalse);
      var allowed = true;
      drive.onRead = () => allowed = false;
      expect(await share(drive, allowed: () => allowed), isFalse);
      expect(drive.writes, 0);
    });
  }
  test('12 hour throttle persists and boundary is inclusive', () {
    expect(plannerCaptureDue(null, time), isTrue);
    expect(
      plannerCaptureDue(
        plannerTimestamp(time),
        time.add(const Duration(hours: 11, minutes: 59)),
      ),
      isFalse,
    );
    expect(
      plannerCaptureDue(
        plannerTimestamp(time),
        time.add(const Duration(hours: 12)),
      ),
      isTrue,
    );
    expect(
      plannerCaptureDue(
        plannerTimestamp(time),
        time.subtract(const Duration(hours: 1)),
      ),
      isFalse,
    );
  });
  test('rejects duplicate kinds, unknown keys and invalid token', () {
    for (final mutation in [
      (Map<String, dynamic> d) => (d['packets'] as List).add(d['packets'][0]),
      (Map<String, dynamic> d) => d['extra'] = true,
      (Map<String, dynamic> d) => d['packets'][0]['token'] = 'MBGPLAN1.invalid',
    ]) {
      final d = jsonDecode(utf8.decode(fixture)) as Map<String, dynamic>;
      mutation(d);
      expect(
        () => decodeDrivePlannerHandoff(utf8.encode(jsonEncode(d))),
        throwsFormatException,
      );
    }
  });
}
