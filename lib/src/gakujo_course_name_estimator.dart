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

    final ignored = ['学務情報システム', 'More Better Gakujo', 'CampusSquare'];
    if (ignored.any((value) => trimmed.toLowerCase() == value.toLowerCase())) {
      return null;
    }

    return trimmed;
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
