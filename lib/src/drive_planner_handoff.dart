import 'dart:convert';

import 'course_planner_handoff.dart';
import 'star_sync/star_sync_transport.dart';

const drivePlannerHandoffName = 'mbg-gakujo-handoff.v1.json';
const drivePlannerMaxBytes = 8 * 1024 * 1024;

String plannerTimestamp(DateTime time) => DateTime.fromMillisecondsSinceEpoch(
  time.toUtc().millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

bool _timestamp(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$').hasMatch(value)) {
    return false;
  }
  final time = DateTime.tryParse(value);
  return time != null && plannerTimestamp(time) == value;
}

Map<String, dynamic> decodeDrivePlannerHandoff(List<int> bytes) {
  if (bytes.length > drivePlannerMaxBytes) throw const FormatException();
  final data = jsonDecode(utf8.decode(bytes));
  if (data is! Map<String, dynamic> ||
      data.length != 4 ||
      data['v'] != 1 ||
      data['kind'] != 'mbg-gakujo-handoff' ||
      !_timestamp(data['updatedAt'])) {
    throw const FormatException();
  }
  final packets = data['packets'];
  if (packets is! List || packets.isEmpty || packets.length > 4) {
    throw const FormatException();
  }
  final seen = <String>{};
  for (final packet in packets) {
    if (packet is! Map<String, dynamic> ||
        packet.length != 3 ||
        !_timestamp(packet['capturedAt']) ||
        packet['token'] is! String ||
        !seen.add('${packet['kind']}')) {
      throw const FormatException();
    }
    final kinds = coursePlannerHandoffOrder.where(
      (k) => k.name == packet['kind'],
    );
    if (kinds.isEmpty ||
        !validCoursePlannerToken(packet['token'] as String, kinds.single)) {
      throw const FormatException();
    }
  }
  return data;
}

/// Reads before merging; guards are checked again by the HTTP transport at send.
Future<bool> shareDrivePlannerHandoffs({
  required StarSyncTransport transport,
  required List<(CoursePlannerImportKind, String)> captured,
  required bool Function() allowed,
  required DateTime capturedAt,
}) async {
  if (!allowed() || captured.isEmpty) return false;
  final remote = await transport.get(
    drivePlannerHandoffName,
    maxBytes: drivePlannerMaxBytes,
  );
  if (!allowed()) return false;
  Map<String, dynamic>? previous;
  if (remote != null) {
    try {
      previous = decodeDrivePlannerHandoff(remote.bytes);
    } on FormatException {
      // Replace unreadable or unsupported handoffs with the captured kinds.
    }
  }
  final packets = <String, Map<String, dynamic>>{
    if (previous != null)
      for (final packet in previous['packets'] as List)
        (packet as Map<String, dynamic>)['kind'] as String: {
          'kind': packet['kind'],
          'capturedAt': packet['capturedAt'],
          'token': packet['token'],
        },
  };
  var changed = false;
  for (final (kind, token) in captured) {
    if (!validCoursePlannerToken(token, kind)) throw const FormatException();
    if (packets[kind.name]?['token'] == token) continue;
    packets[kind.name] = {
      'kind': kind.name,
      'capturedAt': plannerTimestamp(capturedAt),
      'token': token,
    };
    changed = true;
  }
  if (!changed) return true;
  final bytes = utf8.encode(
    jsonEncode({
      'v': 1,
      'kind': 'mbg-gakujo-handoff',
      'updatedAt': plannerTimestamp(capturedAt),
      'packets': [
        for (final kind in coursePlannerHandoffOrder) ?packets[kind.name],
      ],
    }),
  );
  if (bytes.length > drivePlannerMaxBytes) throw const FormatException();
  if (!allowed()) return false;
  await transport.put(drivePlannerHandoffName, bytes);
  return allowed();
}

bool plannerCaptureDue(String? lastSuccess, DateTime now) {
  final last = DateTime.tryParse(lastSuccess ?? '');
  return last == null ||
      now.toUtc().difference(last.toUtc()) >= const Duration(hours: 12);
}
