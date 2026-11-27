import 'dart:convert';

import 'course_planner_handoff.dart';
import 'star_sync/star_sync_transport.dart';

const drivePlannerHandoffName = 'mbg-gakujo-handoff.v1.json';
const drivePlannerTimetableName = 'mbg-gakujo-timetable.v1.json';
const plannerTimetableCapability = 'gakujo-timetable';
const drivePlannerMaxBytes = 8 * 1024 * 1024;
const _plannerTimetableMaxBytes = 4 * 1024 * 1024;
const _plannerBindingName = 'mbg-planner-student-binding-v1';

bool isPlannerInquiryName(String name) =>
    name == drivePlannerHandoffName || name == drivePlannerTimetableName;

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

Map<String, dynamic> decodeDrivePlannerHandoff(
  List<int> bytes, {
  bool allowUnreadableTokens = false,
}) {
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
        !packet.containsKey('token') ||
        !seen.add('${packet['kind']}')) {
      throw const FormatException();
    }
    final kinds = coursePlannerHandoffOrder.where(
      (k) => k.name == packet['kind'],
    );
    if (kinds.isEmpty ||
        (!allowUnreadableTokens &&
            !_readablePlannerToken(packet['token'], kinds.single))) {
      throw const FormatException();
    }
  }
  return data;
}

bool _readablePlannerToken(Object? token, CoursePlannerImportKind kind) =>
    token is String && validCoursePlannerToken(token, kind);

/// Reads before merging; guards are checked again by the HTTP transport at send.
Future<bool> shareDrivePlannerHandoffs({
  required StarSyncTransport transport,
  required List<(CoursePlannerImportKind, String)> captured,
  required bool Function() allowed,
  required DateTime capturedAt,
  bool preserveAcademicHistory = false,
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
      previous = decodeDrivePlannerHandoff(
        remote.bytes,
        allowUnreadableTokens: preserveAcademicHistory,
      );
    } on FormatException {
      // The saved envelope does not establish which inquiries it contains.
    }
  }
  final packets = <String, Map<String, dynamic>>{};
  final unreadable = <CoursePlannerImportKind>{};
  if (previous != null) {
    for (final packet in previous['packets'] as List) {
      final kind = coursePlannerHandoffOrder.singleWhere(
        (kind) => kind.name == packet['kind'],
      );
      final token = packet['token'];
      if (!_readablePlannerToken(token, kind)) unreadable.add(kind);
      packets[kind.name] = {
        'kind': kind.name,
        'capturedAt': packet['capturedAt'],
        // Keep bounded tokens until their inquiry is captured again.
        'token': token is String && token.length <= 2 * 1024 * 1024 ? token : null,
      };
    }
  }
  final timestamp = plannerTimestamp(capturedAt);
  var changed = false;
  var complete = true;
  for (final (kind, token) in captured) {
    if (!validCoursePlannerToken(token, kind)) throw const FormatException();
    final saved = packets[kind.name];
    if (saved?['token'] == token) continue;
    var next = token;
    var at = timestamp;
    if (saved != null && unreadable.contains(kind)) {
      if (timestamp.compareTo(saved['capturedAt'] as String) < 0) continue;
      unreadable.remove(kind);
    } else if (preserveAcademicHistory && saved != null) {
      final savedAt = saved['capturedAt'] as String;
      final prior = saved['token'] as String;
      final supersedes = timestamp.compareTo(savedAt) > 0;
      final newer = supersedes ? token : prior;
      final older = supersedes ? prior : token;
      at = supersedes ? timestamp : savedAt;
      if (kind == CoursePlannerImportKind.registration) {
        final combined = mergeCoursePlannerRegistration(newer, older);
        if (combined == null) {
          complete = false;
          continue;
        }
        next = combined;
      } else if (kind == CoursePlannerImportKind.profile) {
        next = reuseCoursePlannerEnrollmentFacts(newer, older);
      } else if (kind == CoursePlannerImportKind.balances &&
          hasCoursePlannerSplitBalances(prior) &&
          !hasCoursePlannerSplitBalances(token)) {
        // A later summary page can lack the report's earned-credit columns.
        next = prior;
      } else {
        next = newer;
      }
    }
    if (saved?['token'] == next) continue;
    packets[kind.name] = {
      'kind': kind.name,
      'capturedAt': at,
      'token': next,
    };
    changed = true;
  }
  complete = complete && unreadable.isEmpty;
  if (!changed) return complete;
  final previousUpdate = previous?['updatedAt'] as String?;
  final bytes = utf8.encode(
    jsonEncode({
      'v': 1,
      'kind': 'mbg-gakujo-handoff',
      'updatedAt': previousUpdate != null &&
              previousUpdate.compareTo(timestamp) > 0
          ? previousUpdate
          : timestamp,
      'packets': [
        for (final kind in coursePlannerHandoffOrder) ?packets[kind.name],
      ],
    }),
  );
  if (bytes.length > drivePlannerMaxBytes) throw const FormatException();
  if (!allowed()) return false;
  await transport.put(
    drivePlannerHandoffName,
    bytes,
    createOnly: remote == null,
  );
  return complete && allowed();
}

bool plannerCaptureDue(String? lastSuccess, DateTime now) {
  final last = DateTime.tryParse(lastSuccess ?? '');
  return last == null ||
      now.toUtc().difference(last.toUtc()) >= const Duration(hours: 12);
}

final _studentScope = RegExp(r'^[A-Za-z0-9_-]{43}$');
final _academicYear = RegExp(r'^(19|20)\d{2}$');
final _openingNumber = RegExp(r'^\d{3}[A-Z][A-Z0-9]{4,5}$');
final _privateTitle = RegExp(
  r'https?:|[@<>]|学籍番号|在籍番号|学生番号|氏名|メールアドレス|電話番号|\b\d{2}[A-Za-z]\d{4}[A-Za-z]\b|\d{7,}',
  caseSensitive: false,
);
bool _gridPosition(Object? value) => value is int && value >= 1 && value <= 7;
String _termKey(Map<String, dynamic> term) =>
    '${term['year']}/${term['semester']}';

List<Map<String, dynamic>> _validateTimetableTerms(
  Object? terms, {
  String? capturedAt,
}) {
  if (terms is! List || terms.length > 60) throw const FormatException();
  final result = <Map<String, dynamic>>[];
  final seenTerms = <String>{};
  var meetingCount = 0;
  for (final term in terms) {
    if (term is! Map<String, dynamic> ||
        term.length != (capturedAt == null ? 4 : 3) ||
        !_timestamp(capturedAt ?? term['capturedAt']) ||
        term['year'] is! String ||
        !_academicYear.hasMatch(term['year'] as String) ||
        !const {'first', 'second'}.contains(term['semester']) ||
        term['meetings'] is! List ||
        !seenTerms.add(_termKey(term))) {
      throw const FormatException();
    }
    final meetings = term['meetings'] as List;
    meetingCount += meetings.length;
    if (meetings.isEmpty || meetingCount > 12000) throw const FormatException();
    final seenMeetings = <String>{};
    final yearSuffix = (term['year'] as String).substring(2);
    for (final meeting in meetings) {
      if (meeting is! Map<String, dynamic> ||
          meeting.length != 5 ||
          meeting['code'] is! String ||
          !_openingNumber.hasMatch(meeting['code'] as String) ||
          !(meeting['code'] as String).startsWith(yearSuffix) ||
          meeting['title'] is! String ||
          (meeting['title'] as String).length > 140 ||
          _privateTitle.hasMatch(meeting['title'] as String) ||
          !const {'許可', '申請中', '要確認'}.contains(meeting['status']) ||
          !_gridPosition(meeting['day']) ||
          !_gridPosition(meeting['period']) ||
          !seenMeetings.add('${meeting['code']}/${meeting['day']}/${meeting['period']}')) {
        throw const FormatException();
      }
    }
    result.add({...term, 'capturedAt': ?capturedAt});
  }
  return result;
}

class PlannerTimetableStudentMismatch implements Exception {
  const PlannerTimetableStudentMismatch();
}

/// A timetable can start empty so a browser can recognize an MBG account
/// before the first inquiry capture. Update only terms observed in this session.
Future<bool> shareDrivePlannerTimetable({
  required StarSyncTransport transport,
  required String student,
  required List<Object?> captured,
  required bool Function() allowed,
  required DateTime capturedAt,
}) async {
  if (!allowed()) return false;
  if (!_studentScope.hasMatch(student)) throw const FormatException();
  final observed = _validateTimetableTerms(
    captured,
    capturedAt: plannerTimestamp(capturedAt),
  );
  final binding = await transport.get(_plannerBindingName, maxBytes: 4096);
  if (!allowed()) return false;
  if (binding != null) {
    final value = jsonDecode(utf8.decode(binding.bytes));
    if (value is! Map || value['v'] != 1 || value['scope'] != student) {
      throw const PlannerTimetableStudentMismatch();
    }
  }
  final remote = await transport.get(
    drivePlannerTimetableName,
    maxBytes: _plannerTimetableMaxBytes,
  );
  if (!allowed()) return false;
  final terms = <String, Map<String, dynamic>>{};
  if (remote != null) {
    final value = jsonDecode(utf8.decode(remote.bytes));
    if (value is! Map || value.length != 4 || value['v'] != 1 ||
        value['kind'] != 'mbg-gakujo-timetable') {
      throw const FormatException();
    }
    if (value['student'] != student) throw const PlannerTimetableStudentMismatch();
    for (final term in _validateTimetableTerms(value['terms'])) {
      terms[_termKey(term)] = term;
    }
  }
  var changed = remote == null;
  for (final term in observed) {
    final key = _termKey(term);
    final previous = terms[key];
    if (previous != null &&
        ((previous['capturedAt'] as String).compareTo(term['capturedAt'] as String) >= 0 ||
            jsonEncode(previous['meetings']) == jsonEncode(term['meetings']))) {
      continue;
    }
    terms[key] = term;
    changed = true;
  }
  if (!changed) return true;
  final bytes = utf8.encode(jsonEncode({
    'v': 1,
    'kind': 'mbg-gakujo-timetable',
    'student': student,
    'terms': _validateTimetableTerms(terms.values.toList()),
  }));
  if (bytes.length > _plannerTimetableMaxBytes) throw const FormatException();
  if (!allowed()) return false;
  await transport.put(drivePlannerTimetableName, bytes, createOnly: remote == null);
  return allowed();
}
