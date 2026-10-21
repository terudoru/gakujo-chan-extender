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
      status.contains('解答済');

  bool get isSurvey => kind.contains('アンケート');

  /// [dueAt] as Japan wall-clock time, the way Gakujo shows it, whatever
  /// time zone the device is in.
  DateTime get dueInJapan => japanWallClock(dueAt);

  /// The same assignment as found on other pages, such as the schedule.
  String get id => assignmentId(
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
    final times = RegExp(
      r'([0-9]{4})/([0-9]{1,2})/([0-9]{1,2})\s+([0-9]{1,2}):([0-9]{2})',
    ).allMatches(period).toList();
    if (times.isEmpty) {
      return null;
    }
    final last = times.last;
    final values = [for (var i = 1; i <= 5; i += 1) int.parse(last.group(i)!)];
    final wallClock = DateTime.utc(
      values[0],
      values[1],
      values[2],
      values[3],
      values[4],
    );
    if (wallClock.month != values[1] || wallClock.day != values[2]) {
      return null;
    }
    return wallClock.subtract(_japanOffset);
  }
}

const _japanOffset = Duration(hours: 9);

/// [moment] as Japan wall-clock time (fields read as JST, flagged UTC).
DateTime japanWallClock(DateTime moment) => moment.toUtc().add(_japanOffset);

/// Identity of an assignment across Gakujo's pages. The course code is the
/// stable part when a page has it; the schedule page and the list both do.
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
}) {
  if (title.trim().isEmpty) {
    return null;
  }
  if (course.isNotEmpty || courseCode.isNotEmpty) {
    final id = assignmentId(
      course: course,
      courseCode: courseCode,
      title: title,
    );
    for (final assignment in assignments) {
      if (assignment.id == id ||
          (courseCode.isEmpty &&
              assignmentId(
                    course: assignment.course,
                    courseCode: '',
                    title: assignment.title,
                  ) ==
                  id)) {
        return assignment;
      }
    }
    return null;
  }
  final compact = title.replaceAll(RegExp(r'\s+'), '');
  final matches = [
    for (final assignment in assignments)
      if (assignment.title.replaceAll(RegExp(r'\s+'), '') == compact)
        assignment,
  ];
  return matches.length == 1 ? matches.single : null;
}
