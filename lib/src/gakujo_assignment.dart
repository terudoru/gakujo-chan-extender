import 'generated/assignment_list_fetch.g.dart';

import 'gakujo_dated_activity.dart';

/// One row of Gakujo's レポート・小テスト・アンケート提出 list: the single
/// place that tells a submission's exact closing time and whether it has
/// been handed in.
class GakujoAssignment {
  const GakujoAssignment({
    required this.kind,
    required this.title,
    required this.status,
    required this.course,
    required this.dueAt,
    required this.capturedAt,
    this.courseCode = '',
    this.url = '',
  });

  /// レポート, 小テスト or an アンケート kind, as the list's 種別 says.
  final String kind;
  final String title;

  /// 未提出, 提出済 and the like.
  final String status;
  final String course;
  final String courseCode;

  /// The closing moment. Gakujo writes it in Japan time; see [dueInJapan].
  final DateTime dueAt;
  final DateTime capturedAt;
  final String url;

  bool get isSubmitted =>
      status.contains('提出済') ||
      status.contains('回答済') ||
      status.contains('解答済') ||
      (status.toLowerCase().contains('submitted') &&
          !RegExp(r'not\s+submitted', caseSensitive: false).hasMatch(status));

  bool get isSurvey => kind.contains('アンケート');

  /// [dueAt] as Japan wall-clock time, the way Gakujo shows it, whatever
  /// time zone the device is in.
  DateTime get dueInJapan => japanWallClock(dueAt);

  /// Reports and quizzes can share a title in the same course.
  String get id => '$notificationId|${kind.replaceAll(RegExp(r'\s+'), '')}';

  /// Keep the existing notification and reminder keys across upgrades.
  String get notificationId => assignmentId(
        course: course,
        courseCode: courseCode,
        title: title,
      );

  Map<String, Object?> toJson() {
    return {
      'kind': kind,
      'title': title,
      'status': status,
      'course': course,
      'courseCode': courseCode,
      'dueAt': dueAt.toIso8601String(),
      'capturedAt': capturedAt.toIso8601String(),
      'url': url,
    };
  }

  static GakujoAssignment? fromJson(Map<dynamic, dynamic> json) {
    final dueAt = DateTime.tryParse(json['dueAt']?.toString() ?? '');
    final title = json['title']?.toString().trim() ?? '';
    if (dueAt == null || title.isEmpty) {
      return null;
    }
    return GakujoAssignment(
      kind: json['kind']?.toString() ?? '',
      title: title,
      status: json['status']?.toString() ?? '',
      course: json['course']?.toString() ?? '',
      courseCode: json['courseCode']?.toString() ?? '',
      dueAt: dueAt,
      capturedAt: DateTime.tryParse(json['capturedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      url: json['url']?.toString() ?? '',
    );
  }

  /// Reads a row the page scan sent: 種別, タイトル, 状態, 開講番号, 科目名
  /// and 提出期間 such as "2026/10/21 17:01 ～2026/10/28 16:31".
  static GakujoAssignment? fromReportRow(
    Map<dynamic, dynamic> row, {
    required DateTime capturedAt,
    String url = '',
  }) {
    String field(String name) =>
        (row[name]?.toString() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final title = field('title');
    final dueAt = _closingTime(field('period'));
    if (title.isEmpty || dueAt == null) {
      return null;
    }
    return GakujoAssignment(
      kind: field('kind'),
      title: title,
      status: field('status'),
      course: field('course'),
      courseCode: field('code'),
      dueAt: dueAt,
      capturedAt: capturedAt,
      url: url,
    );
  }

  static DateTime? _closingTime(String period) {
    final normalized = GakujoDatedActivity.normalizeDateText(period);
    final parts = normalized.split(RegExp(r'[～〜~]'));
    final times = RegExp(
      r'(?:([0-9]{4})/)?([0-9]{1,2})/([0-9]{1,2})(?:\s+([0-9]{1,2}):([0-9]{2}))?',
    ).allMatches(parts.last).toList();
    if (times.isEmpty) {
      return null;
    }
    final last = times.last;
    final opening =
        RegExp(r'([0-9]{4})/([0-9]{1,2})/[0-9]{1,2}').firstMatch(normalized);
    var year = int.tryParse(last.group(1) ?? '');
    final month = int.parse(last.group(2)!);
    final day = int.parse(last.group(3)!);
    if (year == null) {
      if (opening == null) {
        return null;
      }
      year = int.parse(opening.group(1)!);
      if (month < int.parse(opening.group(2)!)) {
        year += 1;
      }
    }
    final date = DateTime.utc(year, month, day);
    final hour = int.tryParse(last.group(4) ?? '') ?? 23;
    final minute = int.tryParse(last.group(5) ?? '') ?? 59;
    if (date.year != year ||
        date.month != month ||
        date.day != day ||
        hour > 24 ||
        minute > 59 ||
        (hour == 24 && minute != 0)) {
      return null;
    }
    return date
        .add(Duration(hours: hour, minutes: minute))
        .subtract(_japanOffset);
  }
}

const _japanOffset = Duration(hours: 9);

/// [moment] as Japan wall-clock time (fields read as JST, flagged UTC).
DateTime japanWallClock(DateTime moment) => moment.toUtc().add(_japanOffset);

/// Fetches the レポート・小テスト・アンケート提出 list without leaving the
/// current page, so assignments stay current without opening the list.
/// Status is "missing" when Gakujo answers with something else, such as its
/// login page.
const gakujoAssignmentListFetchScript = gakujoAssignmentListFetchJs;

/// Legacy course/title key for notifications, reminders and cross-page
/// matching. Stored assignment identities also include their kind.
String assignmentId({
  required String course,
  required String courseCode,
  required String title,
}) {
  String compact(String value) => value.replaceAll(RegExp(r'\s+'), '');
  final owner = courseCode.isNotEmpty ? courseCode : compact(course);
  return '$owner|${compact(title)}';
}

/// The assignment [title] from [course]/[courseCode] refers to, if known. A
/// title alone matches only when exactly one assignment has it.
GakujoAssignment? findAssignment(
  Iterable<GakujoAssignment> assignments, {
  required String title,
  String course = '',
  String courseCode = '',
  String kind = '',
}) {
  if (title.trim().isEmpty) {
    return null;
  }
  final candidates = assignments.where((assignment) =>
      kind.isEmpty ||
      assignment.kind == kind ||
      (kind == 'アンケート' && assignment.isSurvey));
  if (course.isNotEmpty || courseCode.isNotEmpty) {
    final id = assignmentId(
      course: course,
      courseCode: courseCode,
      title: title,
    );
    final matches = <GakujoAssignment>[];
    for (final assignment in candidates) {
      if (assignment.notificationId == id ||
          (courseCode.isEmpty &&
              assignmentId(
                    course: assignment.course,
                    courseCode: '',
                    title: assignment.title,
                  ) ==
                  id)) {
        matches.add(assignment);
      }
    }
    return matches.length == 1 ? matches.single : null;
  }
  final compact = title.replaceAll(RegExp(r'\s+'), '');
  final matches = [
    for (final assignment in candidates)
      if (assignment.title.replaceAll(RegExp(r'\s+'), '') == compact)
        assignment,
  ];
  return matches.length == 1 ? matches.single : null;
}
