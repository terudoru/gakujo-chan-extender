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
      var beforePeriod = all.split('実施期間')[0];
      var courses = beforePeriod.match(/\([^()]* \/ [^()]*\)/g) || [];
      var course = courses.length ? courses[courses.length - 1].slice(1, -1) :
        (beforePeriod.match(/\(([^()]*)\)\s*$/) || [])[1] || '';
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
    var base = location.origin + '/campusweb/campussquare.do';
    var url = '/campusweb/campussquare.do?_flowId=ENW3411100-flow';
    var rows = [];
    var seenRows = new Set();
    var visited = new Set();
    var total = -1;
    var complete = false;
    var expanded = false;
    for (var page = 0; page < 10 && url && !visited.has(url); page += 1) {
      visited.add(url);
      var xhr = new XMLHttpRequest();
      xhr.open('GET', url, false);
      xhr.send(null);
      if (xhr.status < 200 || xhr.status >= 400) {
        if (!page) return JSON.stringify({status: 'error', rows: []});
        break;
      }
      var doc = new DOMParser().parseFromString(xhr.responseText, 'text/html');
      var form = doc.querySelector('#enqListForm');
      if (!form) {
        if (!page) return JSON.stringify({status: 'missing', rows: []});
        break;
      }
      // The list states its total as 「11件」 or 「1～11/11件」.
      var content = String(form.textContent || '');
      var counts = content.match(/([0-9]+)件/g) || [];
      total = counts.length ? parseInt(counts[0], 10) : -1;
      var pageRows = readAssignmentRows(doc);
      var previousLength = rows.length;
      pageRows.forEach(function(row) {
        var key = JSON.stringify(row);
        if (!seenRows.has(key)) {
          seenRows.add(key);
          rows.push(row);
        }
      });
      if (total >= 0 && rows.length === total) {
        complete = true;
        break;
      }
      if (page && rows.length === previousLength) break;
      var next = '';
      var controls = form.querySelectorAll('a, button, input[type="submit"]');
      for (var c = 0; c < controls.length; c += 1) {
        var control = controls[c];
        var label = String(control.textContent || control.value || '');
        if (!/次へ/.test(label) || control.disabled ||
            control.getAttribute('aria-disabled') === 'true') continue;
        var href = control.getAttribute('href') || '';
        var onclick = control.getAttribute('onclick') || '';
        var target = ((onclick || href).match(/['"]([^'"]*[?&]_eventId=[^'"]+)['"]/) || [])[1];
        if (!target && href && !/^(?:javascript:|#)/i.test(href)) target = href;
        if (target) {
          var candidate = new URL(target.replace(/&amp;/g, '&'), base);
          if (candidate.origin === location.origin &&
              candidate.pathname === '/campusweb/campussquare.do') {
            next = candidate.href;
            break;
          }
        }
      }
      var displayCount = form.querySelector('select[name="_displayCount"], input[name="_displayCount"]');
      var paging = /次へ|前へ/.test(content) ||
        form.querySelector('[onclick*="paging"], [href*="paging"]') || displayCount;
      if (!next && !expanded && displayCount) {
        var target = new URL(form.getAttribute('action') || url, base);
        var hidden = form.querySelectorAll('input[type="hidden"]');
        for (var h = 0; h < hidden.length; h += 1) {
          if (hidden[h].name) target.searchParams.set(hidden[h].name, hidden[h].value);
        }
        var sizes = Array.from(displayCount.options || [])
          .map(function(option) { return parseInt(option.value, 10); })
          .filter(function(size) { return size > pageRows.length && size <= 500; });
        var size = displayCount.options ? Math.max.apply(null, sizes) : 500;
        if (target.searchParams.has('_flowExecutionKey') && size > pageRows.length &&
            target.origin === location.origin &&
            target.pathname === '/campusweb/campussquare.do') {
          target.searchParams.set('_eventId', 'paging');
          target.searchParams.set('_displayCount', String(size));
          next = target.href;
          expanded = true;
        }
      }
      // Without a count, only a smartphone list without paging is complete.
      if (total < 0 && !next && !paging && form.querySelector('ul.campussmart-list')) {
        total = rows.length;
        complete = true;
      }
      url = next;
    }
    return JSON.stringify({
      status: 'ok',
      total: complete ? total : -1,
      rows: rows
    });
  } catch (e) {
    return JSON.stringify({status: 'error', rows: []});
  }
})()
''';

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
