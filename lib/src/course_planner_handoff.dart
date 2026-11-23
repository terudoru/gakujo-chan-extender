import 'dart:convert';
import 'dart:math';

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

  Future<Object?> _read([CoursePlannerImportKind? kind]) async {
    if (!stillCurrent()) return null;
    final result = await controller.runJavaScriptReturningResult(
      coursePlannerCaptureJs({
        'attempt': attempt,
        if (kind != null) 'kind': kind.name,
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
) async {
  if (!stillCurrent()) return const [];
  final result = await controller.runJavaScriptReturningResult(
    coursePlannerFetchJs,
  );
  if (!stillCurrent()) return const [];
  return decodeCoursePlannerFetch(result);
}

/// One MBGPLAN1 token per kind found, in [coursePlannerHandoffOrder].
List<(CoursePlannerImportKind, String)> decodeCoursePlannerFetch(
  Object? result,
) {
  final Object? data;
  try {
    final text = _bridgeString(result, limit: 8 * 1024 * 1024);
    data = text == null ? null : jsonDecode(text);
  } on Object {
    // An unreadable reply offers nothing to copy.
    return const [];
  }
  if (data is! Map<String, dynamic> || data['v'] != 1) return const [];
  final packets = data['packets'];
  if (packets is! Map<String, dynamic>) return const [];
  return [
    for (final kind in coursePlannerHandoffOrder)
      if (encodeCoursePlannerHandoff(packets[kind.name], kind) case final token?)
        (kind, token),
  ];
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
      const {'科目区分', '既修得単位数'},
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
