import 'dart:convert';

import 'course_planner_handoff.dart';
import 'star_sync/star_sync_transport.dart';

const drivePlannerHandoffName = 'mbg-gakujo-handoff.v1.json';
const driveScopedPlannerHandoffName = 'mbg-gakujo-handoff.v2.json';
const drivePlannerTimetableName = 'mbg-gakujo-timetable.v1.json';
const plannerTimetableCapability = 'gakujo-timetable';
const plannerScopedHandoffCapability = 'gakujo-handoff-scoped';
const drivePlannerMaxBytes = 8 * 1024 * 1024;
const _plannerTimetableMaxBytes = 4 * 1024 * 1024;
const _plannerBindingName = 'mbg-planner-student-binding-v1';

bool isPlannerInquiryName(String name) =>
    name == drivePlannerHandoffName || name == driveScopedPlannerHandoffName ||
    name == drivePlannerTimetableName;

class PlannerDriveConflict implements Exception {
  const PlannerDriveConflict();
}

Future<T> retryPlannerDriveConflict<T>(Future<T> Function() update) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await update();
    } on PlannerDriveConflict {
      if (attempt == 2) rethrow;
    }
  }
}

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
  String? student,
}) {
  if (bytes.length > drivePlannerMaxBytes) throw const FormatException();
  final data = jsonDecode(utf8.decode(bytes));
  final savedStudent = data is Map ? data['student'] : null;
  if (student != null && data is Map && data['v'] == 2 &&
      data['kind'] == 'mbg-gakujo-handoff' && savedStudent is String &&
      _studentScope.hasMatch(savedStudent) && savedStudent != student) {
    throw const PlannerTimetableStudentMismatch();
  }
  if (data is! Map<String, dynamic> ||
      data.length != (student == null ? 4 : 5) ||
      data['v'] != (student == null ? 1 : 2) ||
      (student != null && (!_studentScope.hasMatch(student) || savedStudent != student)) ||
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
  String? student,
}) async {
  if (!allowed() || captured.isEmpty) return false;
  if (student != null && !_studentScope.hasMatch(student)) throw const FormatException();
  final path = student == null ? drivePlannerHandoffName : driveScopedPlannerHandoffName;
  final preserveHistory = preserveAcademicHistory || student != null;
  final remote = await transport.get(
    path,
    maxBytes: drivePlannerMaxBytes,
  );
  if (!allowed()) return false;
  Map<String, dynamic>? previous;
  if (remote != null) {
    try {
      previous = decodeDrivePlannerHandoff(
        remote.bytes,
        allowUnreadableTokens: preserveHistory,
        student: student,
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
    } else if (preserveHistory && saved != null) {
      final savedAt = saved['capturedAt'] as String;
      final prior = saved['token'] as String;
      final supersedes = timestamp.compareTo(savedAt) > 0;
      final newer = supersedes ? token : prior;
      final older = supersedes ? prior : token;
      at = supersedes ? timestamp : savedAt;
      if (kind == CoursePlannerImportKind.grades) {
        final combined = mergeCoursePlannerGrades(token, prior, refreshExisting: supersedes);
        if (combined == null) {
          complete = false;
          continue;
        }
        next = combined.token;
        complete &= !combined.pending;
      } else if (kind == CoursePlannerImportKind.registration) {
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
      'v': student == null ? 1 : 2,
      'kind': 'mbg-gakujo-handoff',
      'student': ?student,
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
    path,
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
String? _termKey(Object? term) {
  if (term is! Map<String, dynamic> ||
      term['year'] is! String ||
      !_academicYear.hasMatch(term['year'] as String) ||
      !const {'first', 'second'}.contains(term['semester'])) {
    return null;
  }
  return '${term['year']}/${term['semester']}';
}

bool _validMeetings(List<dynamic> meetings, String year) {
  final slots = <String>{};
  final yearSuffix = year.substring(2);
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
        !slots.add('${meeting['code']}/${meeting['day']}/${meeting['period']}')) {
      return false;
    }
  }
  return slots.isNotEmpty;
}

({Map<String, Map<String, dynamic>?> terms, bool pending})? _readTimetableTerms(
  List<Object?> values, {
  String? capturedAt,
}) {
  if (values.length > 60) return null;
  final terms = <String, Map<String, dynamic>?>{};
  var pending = false;
  var meetingCount = 0;
  for (final value in values) {
    final meetings = value is Map<String, dynamic> ? value['meetings'] : null;
    if (meetings is List && (meetingCount += meetings.length) > 12000) {
      return null;
    }
    final key = _termKey(value);
    if (key == null) {
      pending = true;
      continue;
    }
    final term = value as Map<String, dynamic>;
    final readable = !terms.containsKey(key) &&
        term.length == (capturedAt == null ? 4 : 3) &&
        _timestamp(capturedAt ?? term['capturedAt']) &&
        meetings is List && _validMeetings(meetings, term['year'] as String);
    terms[key] = readable ? {...term, 'capturedAt': ?capturedAt} : null;
    pending |= !readable;
  }
  return (terms: terms, pending: pending);
}

class PlannerTimetableStudentMismatch implements Exception {
  const PlannerTimetableStudentMismatch();
}

enum PlannerTimetableShare {
  cancelled,
  pending,
  // A matching binding permits scoped reports. The timetable owner still needs verification.
  unverified,
  complete,
}

bool _retryableTimetableFailure(StarSyncTransportException error) => const {
  StarSyncTransportErrorKind.network,
  StarSyncTransportErrorKind.tls,
  StarSyncTransportErrorKind.server,
  StarSyncTransportErrorKind.invalidResponse,
  StarSyncTransportErrorKind.notFound,
  StarSyncTransportErrorKind.storageFull,
}.contains(error.kind);

/// A timetable can start empty so a browser can recognize an MBG account
/// before the first inquiry capture. Update only terms observed in this session.
Future<PlannerTimetableShare> shareDrivePlannerTimetable({
  required StarSyncTransport transport,
  required String student,
  required List<Object?> captured,
  required bool Function() allowed,
  required DateTime capturedAt,
}) async {
  if (!allowed()) return PlannerTimetableShare.cancelled;
  if (!_studentScope.hasMatch(student)) throw const FormatException();
  final binding = await transport.get(_plannerBindingName, maxBytes: 4096);
  if (!allowed()) return PlannerTimetableShare.cancelled;
  if (binding != null) {
    final value = jsonDecode(utf8.decode(binding.bytes));
    if (value is! Map || value['v'] != 1 || value['scope'] != student) {
      throw const PlannerTimetableStudentMismatch();
    }
  }

  Future<bool> confirmedByOtherFile() async {
    if (binding != null) return true;
    final report = await transport.get(driveScopedPlannerHandoffName, maxBytes: drivePlannerMaxBytes);
    if (!allowed() || report == null) return false;
    try {
      decodeDrivePlannerHandoff(report.bytes, allowUnreadableTokens: true, student: student);
      return true;
    } on FormatException {
      return false;
    }
  }

  final StarSyncRemoteObject? remote;
  try {
    remote = await transport.get(drivePlannerTimetableName, maxBytes: _plannerTimetableMaxBytes);
  } on StarSyncTransportException catch (error) {
    if (!_retryableTimetableFailure(error)) rethrow;
    final verified = await confirmedByOtherFile();
    if (!allowed()) return PlannerTimetableShare.cancelled;
    if (!verified) rethrow;
    return PlannerTimetableShare.unverified;
  }
  if (!allowed()) return PlannerTimetableShare.cancelled;
  var stored = const <Object?>[];
  var unreadableBody = false;
  var repair = false;
  if (remote != null) {
    Object? value;
    try {
      value = jsonDecode(utf8.decode(remote.bytes));
    } on FormatException {
      final verified = await confirmedByOtherFile();
      if (!allowed()) return PlannerTimetableShare.cancelled;
      if (!verified) rethrow;
      unreadableBody = true;
      repair = true;
    }
    if (!unreadableBody) {
      final owner = value is Map ? value['student'] : null;
      if (value is! Map || value['kind'] != 'mbg-gakujo-timetable' ||
          owner is! String || !_studentScope.hasMatch(owner)) {
        final verified = await confirmedByOtherFile();
        if (!allowed()) return PlannerTimetableShare.cancelled;
        if (!verified) throw const FormatException();
        return PlannerTimetableShare.unverified;
      }
      if (owner != student) throw const PlannerTimetableStudentMismatch();
      if (value.length != 4 || value['v'] != 1) return PlannerTimetableShare.pending;
      if (value['terms'] case final List<Object?> terms) {
        stored = terms;
      } else {
        repair = true;
      }
    }
  }
  final incomplete = unreadableBody ? PlannerTimetableShare.unverified : PlannerTimetableShare.pending;
  final observed = _readTimetableTerms(captured, capturedAt: plannerTimestamp(capturedAt));
  final existing = _readTimetableTerms(stored);
  if (observed == null || existing == null) return incomplete;
  final updates = <String, Map<String, dynamic>>{};
  for (final MapEntry(:key, value: term) in observed.terms.entries) {
    if (term == null) continue;
    final previous = existing.terms[key];
    if (previous != null &&
        ((previous['capturedAt'] as String).compareTo(term['capturedAt'] as String) >= 0 ||
            jsonEncode(previous['meetings']) == jsonEncode(term['meetings']))) {
      continue;
    }
    updates[key] = term;
  }
  if (updates.isEmpty && remote != null) {
    return repair || observed.pending || existing.pending
        ? incomplete
        : PlannerTimetableShare.complete;
  }
  final merged = <Object?>[
    for (final term in stored)
      if (!updates.containsKey(_termKey(term))) term,
    ...updates.values,
  ];
  final result = _readTimetableTerms(merged);
  if (result == null) return incomplete;
  final bytes = utf8.encode(jsonEncode({
    'v': 1,
    'kind': 'mbg-gakujo-timetable',
    'student': student,
    'terms': merged,
  }));
  if (bytes.length > _plannerTimetableMaxBytes) return incomplete;
  if (!allowed()) return PlannerTimetableShare.cancelled;
  try {
    await transport.put(drivePlannerTimetableName, bytes, createOnly: remote == null);
  } on StarSyncTransportException catch (error) {
    if (!_retryableTimetableFailure(error)) rethrow;
    return allowed() ? incomplete : PlannerTimetableShare.cancelled;
  }
  if (!allowed()) return PlannerTimetableShare.cancelled;
  return observed.pending || result.pending
      ? PlannerTimetableShare.pending
      : PlannerTimetableShare.complete;
}
