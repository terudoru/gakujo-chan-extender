import 'gakujo_activity_store.dart';

enum GakujoStarredMessageSort {
  starredNewest,
  postedNewest,
  postedOldest,
  title,
}

/// Filters saved fields locally; unknown posting dates always sort last.
List<GakujoStarredMessage> queryStarredMessages(
  Iterable<GakujoStarredMessage> entries,
  String query,
  GakujoStarredMessageSort sort,
) {
  final terms = query
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
  final result = entries.where((entry) {
    final text = [
      entry.title,
      entry.genre,
      entry.sender,
      entry.period,
      entry.postedAt,
      entry.body,
    ].join('\n').toLowerCase();
    return terms.every(text.contains);
  }).toList();
  DateTime? posted(GakujoStarredMessage entry) {
    final match = RegExp(
      r'(\d{4})[年/.-](\d{1,2})[月/.-](\d{1,2})日?(?:[ T]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(entry.postedAt);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final hour = int.tryParse(match[4] ?? '') ?? 0;
    final minute = int.tryParse(match[5] ?? '') ?? 0;
    final second = int.tryParse(match[6] ?? '') ?? 0;
    final date = DateTime(year, month, day, hour, minute, second);
    return date.year == year &&
            date.month == month &&
            date.day == day &&
            date.hour == hour &&
            date.minute == minute &&
            date.second == second
        ? date
        : null;
  }

  result.sort((a, b) {
    var order = 0;
    switch (sort) {
      case GakujoStarredMessageSort.starredNewest:
        order = b.starredAt.compareTo(a.starredAt);
      case GakujoStarredMessageSort.title:
        order = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case GakujoStarredMessageSort.postedNewest:
      case GakujoStarredMessageSort.postedOldest:
        final first = posted(a), second = posted(b);
        if (first == null || second == null) {
          order = first == second ? 0 : (first == null ? 1 : -1);
        } else {
          order = sort == GakujoStarredMessageSort.postedNewest
              ? second.compareTo(first)
              : first.compareTo(second);
        }
    }
    return order != 0 ? order : a.id.compareTo(b.id);
  });
  return result;
}
