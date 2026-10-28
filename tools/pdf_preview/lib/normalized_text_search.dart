import 'package:characters/characters.dart';

class NormalizedTextLimit implements Exception {
  const NormalizedTextLimit();
}

/// Finds ranges in the original UTF-16 text, even when compatibility forms
/// expand or a producer stores right-to-left text in visual order.
List<({int start, int end})> normalizedTextMatches(
  String text,
  String query, {
  required String Function(String) normalize,
  required bool caseInsensitive,
  required int maxMatches,
  int maxUnits = 500000,
}) {
  if (query.isEmpty || maxMatches <= 0) return [];
  if (query.length > maxUnits) throw const NormalizedTextLimit();
  String fold(String value) {
    var result = normalize(value);
    if (caseInsensitive) result = result.toLowerCase();
    return result
        .replaceAll('\u06cc', '\u064a')
        .replaceAll('\u0649', '\u064a')
        .replaceAll('\u06a9', '\u0643');
  }

  final buffer = StringBuffer();
  final starts = <int>[], ends = <int>[];
  var offset = 0;
  for (final cluster in text.characters) {
    final normalized = fold(cluster);
    if (starts.length + normalized.length > maxUnits) {
      throw const NormalizedTextLimit();
    }
    buffer.write(normalized);
    for (var i = 0; i < normalized.length; i++) {
      starts.add(offset);
      ends.add(offset + cluster.length);
    }
    offset += cluster.length;
  }
  final haystack = buffer.toString();
  final foldedQuery = fold(query);
  if (foldedQuery.length > maxUnits) throw const NormalizedTextLimit();
  if (foldedQuery.isEmpty) return [];
  final queries = <String>{foldedQuery};
  if (RegExp(r'[\u0590-\u08ff\ufb1d-\ufeff]').hasMatch(foldedQuery)) {
    queries.add(foldedQuery.characters.toList().reversed.join());
  }
  final matches = <({int start, int end})>{};
  for (final needle in queries) {
    var from = 0;
    while (from <= haystack.length - needle.length) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) break;
      matches.add((start: starts[at], end: ends[at + needle.length - 1]));
      if (matches.length >= maxMatches) break;
      from = at + needle.length;
    }
    if (matches.length >= maxMatches) break;
  }
  final result = matches.toList()
    ..sort(
      (a, b) => a.start != b.start
          ? a.start.compareTo(b.start)
          : a.end.compareTo(b.end),
    );
  return result;
}
