import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'course_planner_balance_pdf.dart';
import 'generated/course_planner_capture.g.dart';
import 'generated/course_planner_fetch.g.dart';
import 'web_view_service.dart';

String _attempt() {
  final random = Random.secure();
  return base64Url.encode(List<int>.generate(18, (_) => random.nextInt(256)));
}

// Android / WebView2 may return a quoted JSON string, whereas WebKit
// returns the JavaScript string itself.
String? _bridgeString(Object? result, {int limit = 2 * 1024 * 1024}) {
  if (result is! String || result.length > limit) return null;
  return result.startsWith('"') ? jsonDecode(result) as String? : result;
}

enum CoursePlannerImportKind {
  grades('成績'),
  registration('履修登録状況'),
  balances('区分別の既修得単位数'),
  profile('所属・学年（候補）');

  const CoursePlannerImportKind(this.label);
  final String label;
}

/// Lives only while the student is choosing and reviewing this import.
class CoursePlannerSource {
  CoursePlannerSource(this.controller, this.stillCurrent);
  final GakujoWebViewController controller;
  final bool Function() stillCurrent;
  final String attempt = _attempt();

  Future<Object?> _read([CoursePlannerImportKind? kind, bool timetable = false]) async {
    if (!stillCurrent()) return null;
    final result = await controller.runJavaScriptReturningResult(
      coursePlannerCaptureJs({
        'attempt': attempt,
        if (kind != null) 'kind': kind.name,
        if (timetable) 'timetable': true,
      }),
    );
    if (!stillCurrent()) return null;
    final str = _bridgeString(result);
    if (str == null) return null;
    return jsonDecode(str);
  }

  Future<List<CoursePlannerImportKind>> choices({
    bool includeProfile = false,
  }) async {
    final names = await _read();
    if (names is! List) return [];
    return CoursePlannerImportKind.values
        .where(
          (k) =>
              names.contains(k.name) &&
              (includeProfile || k != CoursePlannerImportKind.profile),
        )
        .toList();
  }

  Future<Map<String, dynamic>?> capture(CoursePlannerImportKind kind) async =>
      _validateCoursePlannerPacket(await _read(kind), kind);

  Future<Object?> captureTimetable() async {
    if (!(await choices()).contains(CoursePlannerImportKind.registration)) return null;
    return _read(CoursePlannerImportKind.registration, true);
  }
}

/// The order in which handoff tokens are copied together.
const coursePlannerHandoffOrder = [
  CoursePlannerImportKind.profile,
  CoursePlannerImportKind.grades,
  CoursePlannerImportKind.balances,
  CoursePlannerImportKind.registration,
];

/// Reads the inquiry pages in the background of the logged-in portal.
///
/// The result lives only in memory for this one copy; it is empty when the
/// fetch fails or the caller's login or page changes meanwhile.
Future<List<(CoursePlannerImportKind, String)>> fetchCoursePlannerHandoffs(
  GakujoWebViewController controller,
  bool Function() stillCurrent,
) async => (await fetchCoursePlannerCapture(controller, stillCurrent)).$1;

const _emptyCoursePlannerCapture = (
  <(CoursePlannerImportKind, String)>[],
  <Object?>[],
  false,
);

Future<(List<(CoursePlannerImportKind, String)>, List<Object?>, bool)>
fetchCoursePlannerCapture(
  GakujoWebViewController controller,
  bool Function() stillCurrent,
) async {
  if (!stillCurrent()) return _emptyCoursePlannerCapture;
  final attempt = _attempt();
  final owner = jsonEncode(attempt);
  final time = Stopwatch()..start();
  Future<Object?> evaluate(String script) => controller
      .runJavaScriptReturningResult(script)
      .timeout(const Duration(seconds: 5));
  try {
    var result = await evaluate(coursePlannerFetchJs({'attempt': attempt}));
    while (stillCurrent() && (result == 'pending' || result == '"pending"')) {
      if (time.elapsed >= const Duration(seconds: 65)) {
        return _emptyCoursePlannerCapture;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!stillCurrent()) return _emptyCoursePlannerCapture;
      result = await evaluate('window.__mbgPlannerFetch?.take($owner) ?? null');
    }
    if (!stillCurrent()) return _emptyCoursePlannerCapture;
    final capture = _parseCoursePlannerCapture(result);
    if (capture == null) return _emptyCoursePlannerCapture;
    if (capture['balancePdf'] case final String pdf) {
      final projected = await _captureBalancePdf(pdf);
      if (!stillCurrent()) return _emptyCoursePlannerCapture;
      if (projected == null) {
        capture['complete'] = false;
      } else {
        capture['packets'] = {
          if (capture['packets'] case final Map<String, dynamic> packets) ...packets,
          'balances': projected,
        };
      }
    }
    return _decodeCoursePlannerCapture(capture);
  } finally {
    try {
      await evaluate('window.__mbgPlannerFetch?.cancel($owner) ?? null');
    } on Object {
      // A replaced WebView already discarded its document-owned capture.
    }
  }
}

/// Adds any kinds offered by the displayed page that [fetched] lacks, keeping
/// [coursePlannerHandoffOrder].
///
/// Failures while reading the displayed page do not discard [fetched]. Returns
/// an empty list if [stillCurrent] becomes false.
Future<List<(CoursePlannerImportKind, String)>> supplementCoursePlannerHandoffs(
  GakujoWebViewController controller,
  bool Function() stillCurrent,
  List<(CoursePlannerImportKind, String)> fetched,
) async {
  if (!stillCurrent()) return const [];
  final byKind = <CoursePlannerImportKind, String>{
    for (final (kind, token) in fetched) kind: token,
  };
  if (byKind.length < coursePlannerHandoffOrder.length) {
    final source = CoursePlannerSource(controller, stillCurrent);
    var displayed = const <CoursePlannerImportKind>[];
    try {
      displayed = await source.choices(includeProfile: true);
    } on Object {
      // Displayed-page failures must not lose the fetched kinds.
    }
    if (!stillCurrent()) return const [];
    for (final kind in displayed) {
      if (byKind.containsKey(kind)) continue;
      try {
        final packet = await source.capture(kind);
        if (!stillCurrent()) return const [];
        final token = encodeCoursePlannerHandoff(packet, kind);
        if (token != null) byKind[kind] = token;
      } on Object {
        if (!stillCurrent()) return const [];
      }
    }
  }
  if (!stillCurrent()) return const [];
  return [
    for (final kind in coursePlannerHandoffOrder)
      if (byKind[kind] case final token?) (kind, token),
  ];
}

/// One MBGPLAN1 token per kind found, in [coursePlannerHandoffOrder].
List<(CoursePlannerImportKind, String)> decodeCoursePlannerFetch(
  Object? result,
) => _decodeCoursePlannerCapture(_parseCoursePlannerCapture(result)).$1;

Map<String, dynamic>? _parseCoursePlannerCapture(Object? result) {
  try {
    final text = _bridgeString(result, limit: 8 * 1024 * 1024);
    final data = text == null ? null : jsonDecode(text);
    return data is Map<String, dynamic> && data['v'] == 1 ? data : null;
  } on Object {
    return null;
  }
}

Future<Map<String, dynamic>?> _captureBalancePdf(String pdf) async {
  if (pdf.length > ((coursePlannerBalancePdfLimit + 2) ~/ 3) * 4) return null;
  try {
    return await Isolate.run(() => readCoursePlannerBalancePdf(base64Decode(pdf)));
  } on Object {
    // An unrecognized report must leave the other successful inquiries available.
    return null;
  }
}

(List<(CoursePlannerImportKind, String)>, List<Object?>, bool)
_decodeCoursePlannerCapture(Map<String, dynamic>? data) {
  if (data == null) return _emptyCoursePlannerCapture;
  final packets = data['packets'];
  final timetable = data['timetable'];
  return (
    [
      if (packets is Map<String, dynamic>)
        for (final kind in coursePlannerHandoffOrder)
          if (encodeCoursePlannerHandoff(packets[kind.name], kind) case final token?)
            (kind, token),
    ],
    timetable is List && timetable.length <= 60
        ? timetable.cast<Object?>()
        : const [],
    data['complete'] == true && timetable is List && timetable.length <= 60,
  );
}

/// The clipboard text for several handoff tokens.
String joinCoursePlannerHandoffs(
  List<(CoursePlannerImportKind, String)> handoffs,
) => handoffs.map((handoff) => handoff.$2).join('\n');

String? encodeCoursePlannerHandoff(
  Object? packet,
  CoursePlannerImportKind kind,
) {
  final validated = _validateCoursePlannerPacket(packet, kind);
  if (validated == null) return null;
  final payload = base64Url
      .encode(utf8.encode(jsonEncode(validated)))
      .replaceAll('=', '');
  const prefix = 'MBGPLAN1.';
  return prefix.length + payload.length <= 2 * 1024 * 1024
      ? prefix + payload
      : null;
}

Map<String, dynamic>? _validateCoursePlannerPacket(
  Object? packet,
  CoursePlannerImportKind kind,
) {
  if (packet is! Map<String, dynamic> ||
      packet['v'] != 1 ||
      packet['kind'] != kind.name ||
      !packet.keys.every(const {'v', 'kind', 'tables', 'year'}.contains)) {
    return null;
  }
  final year = packet['year'];
  if (year != null &&
      (year is! String || !RegExp(r'^(19|20)\d\d$').hasMatch(year))) {
    return null;
  }
  final tables = packet['tables'];
  if (tables is! List || tables.isEmpty || tables.length > 50) return null;
  if (kind == CoursePlannerImportKind.profile && tables.length != 1) {
    return null;
  }
  final (headings, columns) = switch (kind) {
    CoursePlannerImportKind.grades => (
      const {'単位修得状況照会'},
      const {
        '開講番号',
        '科目名',
        '単位数',
        '修得単位数',
        '評価',
        '合否',
        '年度',
        '開講所属',
        'クラス',
        '学期',
        '科目区分',
        '重複',
      },
    ),
    CoursePlannerImportKind.registration => (
      const {'履修登録・登録状況照会', '不許可となった科目'},
      const {'開講番号', '科目名', '単位数', '登録状況', '年度'},
    ),
    CoursePlannerImportKind.balances => (
      const {'履修科目確認表'},
      const {'科目区分', '既修得単位数', '既修得単位(昼間)', '既修得単位(夜間)'},
    ),
    CoursePlannerImportKind.profile => (const {'学生所属'}, const {'所属', '学年'}),
  };
  for (final table in tables) {
    if (table is! Map ||
        table.length != 2 ||
        !headings.contains(table['heading'])) {
      return null;
    }
    final rows = table['rows'];
    if (rows is! List || rows.length < 2 || rows.first is! List) return null;
    final headers = rows.first as List;
    if (headers.isEmpty ||
        !headers.every(columns.contains) ||
        headers.length != headers.toSet().length) {
      return null;
    }
    if (kind == CoursePlannerImportKind.balances) {
      final split = headers.contains('既修得単位(昼間)');
      if (split != headers.contains('既修得単位(夜間)') ||
          split && (headers.contains('既修得単位数') || !headers.contains('科目区分'))) {
        return null;
      }
    }
    for (final row in rows.skip(1)) {
      if (row is! List ||
          row.length != headers.length ||
          !row.every((value) => value is String && value.length <= 140)) {
        return null;
      }
    }
    if (kind == CoursePlannerImportKind.profile) {
      if (rows.length != 2 ||
          headers.length != 2 ||
          headers[0] != '所属' ||
          headers[1] != '学年') {
        return null;
      }
      final values = rows[1] as List;
      final affiliation = values[0] as String;
      final grade = values[1] as String;
      if (affiliation.trim().isEmpty ||
          _privateProfileText.hasMatch(affiliation) ||
          !const {'', '1', '2', '3', '4', '5', '6'}.contains(grade)) {
        return null;
      }
    }
  }
  return packet;
}

final _privateProfileText = RegExp(
  r'https?:|[@<>]|学籍番号|在籍番号|学生番号|氏名|メールアドレス|電話番号|\b\d{2}[A-Za-z]\d{4}[A-Za-z]\b|\d{7,}',
  caseSensitive: false,
);

/// Shared capture for automatic sharing and the manual copy fallback.
Future<List<(CoursePlannerImportKind, String)>> captureCoursePlannerHandoffs(
  GakujoWebViewController controller,
  bool Function() stillCurrent, {
  bool background = true,
  bool displayedFallback = true,
}) async {
  var fetched = const <(CoursePlannerImportKind, String)>[];
  if (background) {
    try {
      fetched = await fetchCoursePlannerHandoffs(controller, stillCurrent);
    } on Object {
      // The displayed page can still provide inquiry results.
    }
  }
  if (fetched.isEmpty && !displayedFallback) return const [];
  return supplementCoursePlannerHandoffs(controller, stillCurrent, fetched);
}

Map<String, dynamic>? _decodeCoursePlannerToken(
  String token,
  CoursePlannerImportKind kind,
) {
  if (!token.startsWith('MBGPLAN1.') ||
      token.length > 2 * 1024 * 1024 ||
      !RegExp(r'^MBGPLAN1\.[A-Za-z0-9_-]+$').hasMatch(token)) {
    return null;
  }
  try {
    final packet = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.substring(9)))),
    );
    return encodeCoursePlannerHandoff(packet, kind) == token
        ? packet as Map<String, dynamic>
        : null;
  } on Object {
    return null;
  }
}

bool validCoursePlannerToken(String token, CoursePlannerImportKind kind) =>
    _decodeCoursePlannerToken(token, kind) != null;

bool hasCoursePlannerSplitBalances(String token) {
  final packet = _decodeCoursePlannerToken(token, CoursePlannerImportKind.balances);
  return packet != null &&
      (packet['tables'] as List).any((table) =>
        (table['rows'].first as List).contains('既修得単位(昼間)'));
}

/// Keep the printed admission year if the caller verified both sources belong
/// to the same student and their affiliations match exactly.
String reuseCoursePlannerAdmissionYear(String displayed, String? fetched) {
  if (fetched == null || fetched == displayed) return displayed;
  const kind = CoursePlannerImportKind.profile;
  final old = _decodeCoursePlannerToken(fetched, kind);
  final year = old?['year'];
  if (year == null) return displayed;
  final current = _decodeCoursePlannerToken(displayed, kind);
  if (current == null ||
      current['year'] != null ||
      current['tables'][0]['rows'][1][0] != old!['tables'][0]['rows'][1][0]) {
    return displayed;
  }
  return encodeCoursePlannerHandoff({...current, 'year': year}, kind) ??
      displayed;
}

typedef _RegistrationRow = ({
  String heading,
  List<String> headers,
  List<String> values,
  String? identity,
  bool confirmed,
});

final _registrationYear = RegExp(r'^((?:19|20)\d{2})(?:年度)?$');
final _registrationCode = RegExp(
  r'^(\d{3}[A-Z][A-Z0-9]{4,5})(?:\s*\(T[1-4](?:,[1-4])*\))?$',
  caseSensitive: false,
);

Iterable<_RegistrationRow> _registrationRows(Map<String, dynamic> packet) sync* {
  final scope = packet['year'] as String?;
  for (final table in packet['tables'] as List) {
    final heading = table['heading'] as String;
    final rows = table['rows'] as List;
    final original = (rows.first as List).cast<String>();
    final yearColumn = original.indexOf('年度');
    final codeColumn = original.indexOf('開講番号');
    final statusColumn = original.indexOf('登録状況');
    final headers = scope != null && yearColumn < 0
        ? ['年度', ...original]
        : original;
    final denied = heading == '不許可となった科目';
    for (final raw in rows.skip(1)) {
      final row = (raw as List).cast<String>();
      final printedYear = yearColumn < 0 ? '' : row[yearColumn].trim();
      final year = printedYear.isEmpty
          ? scope
          : _registrationYear.firstMatch(printedYear)?.group(1);
      // Combining packets removes the enclosing year. Keep inconsistent rows
      // from gaining a valid scope as a side effect.
      if (printedYear.isNotEmpty &&
          (year == null || (scope != null && year != scope))) {
        continue;
      }
      final code = codeColumn < 0
          ? null
          : _registrationCode
                .firstMatch(row[codeColumn].trim())
                ?.group(1)
                ?.toUpperCase();
      final identity =
          year != null && code != null && code.startsWith(year.substring(2))
          ? '$year/$code'
          : null;
      final status = statusColumn < 0 ? '' : row[statusColumn].trim();
      final confirmed = denied
          ? const {'', '不許可', '履修不許可'}.contains(status)
          : const {
              '許可', '許可済', '許可済み', '履修許可', '不許可', '履修不許可',
              '申請中', '申請済', '申請済み', '抽選待ち', '履修申請中', '許可待ち',
            }.contains(status);
      final values = [
        if (scope != null && yearColumn < 0) scope,
        for (final (index, value) in row.indexed)
          if (index == yearColumn && year != null) year else value,
      ];
      yield (
        heading: heading,
        headers: headers,
        values: values,
        identity: identity,
        confirmed: confirmed,
      );
    }
  }
}

/// Combine registration inquiries for one verified student. A valid newer
/// outcome replaces earlier evidence for that offering. Missing rows and
/// unreadable outcomes leave existing facts available to a fresh device.
String? mergeCoursePlannerRegistration(String newer, String older) {
  if (newer == older) return newer;
  const kind = CoursePlannerImportKind.registration;
  final current = _decodeCoursePlannerToken(newer, kind);
  final previous = _decodeCoursePlannerToken(older, kind);
  if (current == null || previous == null) return null;
  final incoming = _registrationRows(current).toList();
  final updated = <String>{
    for (final row in incoming)
      if (row.confirmed && row.identity != null) row.identity!,
  };
  final preserved = _registrationRows(previous)
      .where(
        (row) => row.confirmed &&
            row.identity != null &&
            !updated.contains(row.identity),
      )
      .toList();
  if (preserved.isEmpty) return newer;
  final preservedKeys = preserved.map((row) => row.identity).toSet();
  final groups = <String, ({String heading, List<List<String>> rows})>{};
  final seen = <String>{};
  for (final row in [...preserved, ...incoming]) {
    if (!row.confirmed && preservedKeys.contains(row.identity)) continue;
    final key = jsonEncode([row.heading, row.headers]);
    if (!seen.add(jsonEncode([key, row.values]))) continue;
    final group = groups.putIfAbsent(
      key,
      () => (heading: row.heading, rows: [row.headers]),
    );
    group.rows.add(row.values);
  }
  if (groups.values.fold(0, (count, group) => count + group.rows.length) > 12000) return null;
  return encodeCoursePlannerHandoff({
    'v': 1,
    'kind': kind.name,
    'tables': [
      for (final group in groups.values) {'heading': group.heading, 'rows': group.rows},
    ],
  }, kind);
}
