import 'download_file_name_policy.dart';

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

  static String estimateFromHtml(String html) {
    final candidates = <String?>[
      ..._textsForTags(html, ['tr']),
      ..._textsForTags(html, ['h1', 'h2', 'h3']),
      ..._textsForClassHints(html, [
        'breadcrumb',
        'topic-path',
        'course',
        'jugyo',
        'kamoku',
        'selected',
        'active'
      ]),
      _titleText(html),
    ];
    return estimateFromCandidates(candidates);
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
      r'(?:授業科目名|授業科目|科目名|授業名|講義名|科目\s*[:：])\s*[:：]?\s*(?:[A-Z0-9]{4,}\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (labeledMatch != null) {
      return _trimAtKnownFieldLabel(labeledMatch.group(1)!.trim());
    }

    final codeMatch = RegExp(
      r'^[A-Z0-9]{4,}\s+(.+)$',
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

  static String _trimAtKnownFieldLabel(String text) {
    final match = RegExp(
      r'\s(?:担当教員|担当|教員|曜日|時限|開講|年度|学期|単位|対象|授業コード|科目区分|シラバス|提出期限|課題)(?:\s|$)',
    ).firstMatch(text);
    final trimmed = match == null ? text : text.substring(0, match.start);
    return trimmed.trim();
  }

  static bool _isIgnoredCourseName(String text) {
    final genericPageLabels = {
      '開設一覧',
      '連絡通知',
      '掲示一覧',
      '授業ポートフォリオ',
      'レポート・小テスト・アンケート提出',
      'レポート提出',
      '小テスト',
      'アンケート',
      '年度 開講所属 開講番号 科目名',
      'タイトル',
    };
    if (genericPageLabels.contains(text)) {
      return true;
    }

    final lower = text.toLowerCase();
    final ignored = ['学務情報システム', 'more better gakujo', 'campussquare'];
    return ignored.any(lower.contains);
  }

  static Iterable<String?> _textsForTags(String html, List<String> tags) sync* {
    for (final tag in tags) {
      final regex = RegExp('<$tag\\b[^>]*>(.*?)</$tag>',
          caseSensitive: false, dotAll: true);
      for (final match in regex.allMatches(html)) {
        yield match.group(1);
      }
    }
  }

  static Iterable<String?> _textsForClassHints(
      String html, List<String> hints) sync* {
    final regex = RegExp(
      r'''<[^>]+class\s*=\s*["'][^"']*(?:''' +
          hints.map(RegExp.escape).join('|') +
          r''')[^"']*["'][^>]*>(.*?)</[^>]+>''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in regex.allMatches(html)) {
      yield match.group(1);
    }
  }

  static String? _titleText(String html) {
    final match = RegExp(r'<title\b[^>]*>(.*?)</title>',
            caseSensitive: false, dotAll: true)
        .firstMatch(html);
    return match?.group(1);
  }
}
