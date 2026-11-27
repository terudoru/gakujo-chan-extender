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
    Future<bool> shareTerms(List<Object?> captured, {String? owner, int days = 0}) =>
        shareDrivePlannerTimetable(
          transport: drive,
          student: owner ?? student,
          captured: captured,
          allowed: () => true,
          capturedAt: time.add(Duration(days: days)),
        );
    expect(await shareTerms([]), isTrue);
    expect(terms(), isEmpty);
    expect(await shareTerms([term('2025', 'second', 2), term('2026', 'first', 4)], days: 1), isTrue);
    expect(await shareTerms([term('2026', 'first', 3)], days: 2), isTrue);
    expect(await shareTerms([term('2026', 'first', 5)], days: 1), isTrue);
    expect(terms().map((term) => term['meetings'][0]['day']), [2, 3]);
    expect(drive.writes, 3);
    await expectLater(shareTerms([], owner: 'b' * 43), throwsA(isA<PlannerTimetableStudentMismatch>()));
    await expectLater(shareTerms([term('2025', 'second', 8)], days: 3), throwsFormatException);
    expect(drive.writes, 3);
  });

  Future<bool> share(
    _Drive drive, {
    List<(CoursePlannerImportKind, String)>? packets,
    bool Function()? allowed,
    DateTime? at,
  }) => shareDrivePlannerHandoffs(
    transport: drive,
    captured: packets ?? captured,
    allowed: allowed ?? () => true,
    capturedAt: at ?? time,
  );

  test('Drive body matches shared fixture byte for byte', () async {
    final drive = _Drive();
    expect(await share(drive), isTrue);
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
  test('unchanged content performs no write', () async {
    final drive = _Drive()..bytes = fixture;
    await share(drive, at: time.add(const Duration(days: 1)));
    expect(drive.writes, 0);
    expect(drive.bytes, fixture);
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
