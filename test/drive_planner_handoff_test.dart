import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/course_planner_handoff.dart';
import 'package:morebettergakujo_flutter/src/drive_planner_handoff.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

class _Drive implements StarSyncTransport {
  List<int>? bytes;
  int writes = 0;
  void Function()? onRead;
  @override
  Future<StarSyncRemoteObject?> get(
    String path, {
    int maxBytes = starSyncDefaultMaxBytes,
  }) async {
    expect(path, drivePlannerHandoffName);
    onRead?.call();
    return bytes == null ? null : StarSyncRemoteObject(bytes: bytes!);
  }

  @override
  Future<void> put(
    String path,
    List<int> value, {
    bool createOnly = false,
  }) async {
    writes++;
    bytes = value;
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
