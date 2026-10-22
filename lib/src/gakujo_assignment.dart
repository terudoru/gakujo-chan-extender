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

/// JavaScript defining `readAssignmentRows(doc)`, which reads the
/// レポート・小テスト・アンケート提出 list into rows for
/// [GakujoAssignment.fromReportRow]. Gakujo serves the list as a table in the
/// PC portal and as `ul.campussmart-list` groups for smartphones and for a
/// page fetched on its own.
const gakujoAssignmentRowsScript = r'''
function readAssignmentRows(doc) {
  function text(node) {
    return String(node && (node.innerText || node.textContent) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }
  var rows = [];
  var table = doc.querySelector('#enqListForm table:nth-of-type(2)');
  if (table && table.rows) {
    for (var i = 1; i < table.rows.length; i += 1) {
      var cells = table.rows[i].cells;
      if (!cells || cells.length < 8 || !text(cells[1]) || !text(cells[7])) {
        continue;
      }
      rows.push({
        kind: text(cells[0]),
        title: text(cells[1]),
        status: text(cells[2]),
        code: text(cells[3]),
        course: text(cells[4]),
        period: text(cells[7])
      });
    }
  }
  var groups = doc.querySelectorAll('#enqListForm ul.campussmart-list');
  for (var g = 0; g < groups.length; g += 1) {
    var kind = text(groups[g].querySelector('li.header'));
    var titles = groups[g].querySelectorAll('span.h3');
    for (var t = 0; t < titles.length; t += 1) {
      var block = titles[t].closest('td') || titles[t].parentElement;
      var all = text(block);
      var course = (all.match(/\(\s*(.+?)\s*\)\s*実施期間/) || [])[1] || '';
      var period = (all.match(/実施期間[：:]\s*(.+?)\s*(?:状態|$)/) || [])[1] || '';
      var row = titles[t].closest('tr') || block;
      var action = row.querySelector('[onclick*="callEnqInfoSearch"]');
      var code = (String(action && action.getAttribute('onclick') || '')
        .match(/'([0-9]{3}[A-Z][0-9]{4})'\s*\)/) || [])[1] || '';
      if (!text(titles[t]) || !period) {
        continue;
      }
      rows.push({
        kind: kind,
        title: text(titles[t]),
        status: (all.match(/状態[：:]\s*(\S+)/) || [])[1] || '',
        code: code,
        course: course.split(' / ')[0].trim(),
        period: period
      });
    }
  }
  return rows;
}
''';

/// Fetches the レポート・小テスト・アンケート提出 list without leaving the
/// current page, so assignments stay current without opening the list.
/// Status is "missing" when Gakujo answers with something else, such as its
/// login page.
const gakujoAssignmentListFetchScript = '''
(function() {
  $gakujoAssignmentRowsScript
  try {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/campusweb/campussquare.do?_flowId=ENW3411100-flow', false);
    xhr.send(null);
    if (xhr.status < 200 || xhr.status >= 400) {
      return JSON.stringify({status: 'error', rows: []});
    }
    var doc = new DOMParser().parseFromString(xhr.responseText, 'text/html');
    var form = doc.querySelector('#enqListForm');
    if (!form) {
      return JSON.stringify({status: 'missing', rows: []});
    }
    // The list states how many there are in all, as 「11件」 or 「1～11/11件」.
    var counts = String(form.textContent || '').match(/([0-9]+)件/g) || [];
    var total = counts.length ? parseInt(counts[0], 10) : -1;
    var rows = readAssignmentRows(doc);
    // Smartphone lists omit the count; only an unpaged list is complete.
    if (!counts.length && form.querySelector('ul.campussmart-list') &&
        !/次へ|前へ/.test(String(form.textContent || '')) &&
        !form.querySelector('[onclick*="paging"], [href*="paging"], ' +
          'select[name="_displayCount"], input[name="_displayCount"]')) {
      total = rows.length;
    }
    return JSON.stringify({
      status: 'ok',
      total: total,
      rows: rows
    });
  } catch (e) {
    return JSON.stringify({status: 'error', rows: []});
  }
})()
''';

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
