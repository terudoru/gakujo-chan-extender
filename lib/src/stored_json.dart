import 'dart:convert';

/// Reads object records without dropping good entries beside malformed ones.
List<T> decodeStoredJsonList<T>(
  String? raw,
  T Function(Map<dynamic, dynamic>) fromJson, {
  bool Function(T)? retain,
  Comparator<T>? compare,
}) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return const [];
    final entries = <T>[];
    for (final item in decoded.whereType<Map<dynamic, dynamic>>()) {
      try {
        final entry = fromJson(item);
        if (retain == null || retain(entry)) entries.add(entry);
      } on Object {
        // Ignore malformed legacy entries individually.
      }
    }
    if (compare != null) entries.sort(compare);
    return entries;
  } on Object {
    return const [];
  }
}

String canonicalJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
