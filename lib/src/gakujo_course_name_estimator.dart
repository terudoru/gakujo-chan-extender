import 'dart:convert';
import 'dart:developer' as developer;

import 'download_file_name_policy.dart';
import 'generated/course_name_body_text.g.dart';
import 'generated/course_name_estimate.g.dart';
import 'generated/course_name_tables.g.dart';

class GakujoCourseNameEstimator {
  const GakujoCourseNameEstimator._();

  static String estimateFromCandidates(Iterable<String?> candidates) {
    for (final raw in candidates) {
      final normalized = _normalize(raw);
      if (normalized != null) {
        return DownloadFileNamePolicy.safeFolderName(normalized);
      }
    }

    return DownloadFileNamePolicy.unknownCourseFolderName;
  }

  static String? _normalize(String? raw) {
    if (raw == null) {
      return null;
    }

    final withoutTags = raw.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final decoded = withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    final trimmed = decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final extracted = _extractCourseName(trimmed).trim();
    if (extracted.isEmpty || _isIgnoredCourseName(extracted)) {
      return null;
    }

    return extracted;
  }

  static String _extractCourseName(String text) {
    final labeledMatch = RegExp(
      r'(?:^|[\s・:：|｜/／\[［(（【])(?:(?:授業科目名|授業科目|科目名|授業名|講義名)(?:[:：]\s*|\s+[:：]?\s*)|科目\s*[:：]\s*)(?:(?=[A-Z]*[0-9])[A-Z0-9]{4,}\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (labeledMatch != null) {
      var value = labeledMatch.group(1)!.trim();
      final closingBracket = const {
        '[': ']',
        '［': '］',
        '(': ')',
        '（': '）',
        '【': '】',
      }[text[labeledMatch.start]];
      if (closingBracket != null && value.endsWith(closingBracket)) {
        value = value.substring(0, value.length - 1).trim();
      }
      return _isFileRow(value) ? '' : _trimAtKnownFieldLabel(value);
    }

    final codeMatch = RegExp(
      r'^(?=[A-Z]*[0-9])[A-Z0-9]{4,}\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (codeMatch != null) {
      return codeMatch.group(1)!.trim();
    }

    final enrolledStudentsMatch = RegExp(
      r'([^\s、。]+?)の履修者各位',
    ).firstMatch(text);
    if (enrolledStudentsMatch != null) {
      return enrolledStudentsMatch.group(1)!.trim();
    }

    return text;
  }

  static bool _isFileRow(String text) => RegExp(
        r'プレビューを見る|\.(?:pdf|docx?|xlsx?|pptx?|zip|txt|csv)(?:\s|$)',
        caseSensitive: false,
      ).hasMatch(text);

  static String _trimAtKnownFieldLabel(String text) {
    final match = RegExp(
      r'\s(?:担当教員|担当|教員|曜日|時限|開講|年度|学期|単位|対象|授業コード|科目区分|シラバス|提出期限|課題)(?:\s|$)',
    ).firstMatch(text);
    final trimmed = match == null ? text : text.substring(0, match.start);
    return trimmed.trim();
  }

  static bool _isIgnoredCourseName(String text) {
    return _isFileRow(text) ||
        text == 'ダウンロード' ||
        text.toLowerCase().startsWith('now loading') ||
        DownloadFileNamePolicy.isGenericCourseName(text);
  }
}

/// The evidence from a single page read. Only confirmed ambiguity suppresses
/// both the starting-course fallback and filename inference.
class GakujoCourseEstimate {
  const GakujoCourseEstimate.absent() : courseName = null, isAmbiguous = false;
  const GakujoCourseEstimate.ambiguous()
    : courseName = DownloadFileNamePolicy.unknownCourseFolderName,
      isAmbiguous = true;
  const GakujoCourseEstimate._named(String name)
    : courseName = name,
      isAmbiguous = false;

  factory GakujoCourseEstimate.fromName(
    String? name,
    bool Function(String) isUseful,
  ) => name != null && isUseful(name)
      ? GakujoCourseEstimate._named(name)
      : const GakujoCourseEstimate.absent();

  final String? courseName;
  final bool isAmbiguous;
}

Future<GakujoCourseEstimate> estimateGakujoPageCourseName({
  required Future<Object?> Function(String script) evaluate,
  required bool Function(String name) isUseful,
  String? fallbackTitle,
}) async {
  Future<Object?> read(String script, {bool json = true}) async {
    try {
      final result = await evaluate(script);
      if (result is! String || result.isEmpty) return null;
      // WebViews may wrap a JavaScript string in another JSON string.
      var raw = result;
      if (raw.startsWith('"') && raw.endsWith('"')) {
        try {
          raw = jsonDecode(raw) as String;
        } on FormatException {
          // Plain body text can itself start and end with a quote.
        }
      }
      return json ? jsonDecode(raw) : raw;
    } on FormatException {
      return null;
    } catch (error, stackTrace) {
      developer.log(
        'Failed to read course name evidence',
        name: 'MoreBetterGakujo',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  final primary = await read(gakujoCourseNameEstimateJs);
  if (primary case {
    'courseName': final String name,
    'courseNameAmbiguous': final bool ambiguous,
  }) {
    if (ambiguous && name == DownloadFileNamePolicy.unknownCourseFolderName) {
      return const GakujoCourseEstimate.ambiguous();
    }
    if (!ambiguous && isUseful(name.trim())) {
      return GakujoCourseEstimate._named(name.trim());
    }
  }

  final tables = await read(gakujoCourseNameTablesJs);
  if (tables case {'courseNameCandidates': final List<Object?> candidates}
      when candidates.every((value) => value is String)) {
    final names = candidates
        .cast<String>()
        .map((raw) => GakujoCourseNameEstimator.estimateFromCandidates([raw]))
        .where(isUseful)
        .toSet();
    if (names.length > 1) return const GakujoCourseEstimate.ambiguous();
    if (names.isNotEmpty) return GakujoCourseEstimate._named(names.single);
  }

  final body = await read(gakujoCourseNameBodyTextJs, json: false);
  if (body is String) {
    final name = GakujoCourseNameEstimator.estimateFromCandidates(
      _courseNameCandidatesFromBodyText(body),
    );
    if (isUseful(name)) return GakujoCourseEstimate._named(name);
  }
  return GakujoCourseEstimate.fromName(fallbackTitle?.trim(), isUseful);
}

List<String> _courseNameCandidatesFromBodyText(String bodyText) {
  final lines = bodyText
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final labeledLines = lines
      .where(
        (line) => RegExp(
          r'(?:^|[\s・:：|｜/／\[［(（【])(?:(?:授業科目名|授業科目|科目名|授業名|講義名)(?:[:：]|\s)|科目\s*[:：])',
        ).hasMatch(line),
      )
      .toList();
  final compactBody = bodyText.replaceAll(RegExp(r'\s+'), ' ').trim();
  return [...labeledLines, compactBody];
}
