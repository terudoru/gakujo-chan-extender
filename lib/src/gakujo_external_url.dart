/// Keeps navigation identifiers while removing session data from exports.
String sanitizeGakujoExternalUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    return '';
  }
  final query = <String, List<String>>{};
  try {
    for (final entry in uri.queryParametersAll.entries) {
      final name = entry.key.toLowerCase();
      final safeValue = switch (name) {
        '_flowid' => RegExp(r'^[A-Za-z0-9-]{1,80}-flow$'),
        'keijitype' || 'genrecd' || 'seqno' => RegExp(r'^[0-9]{1,32}$'),
        'page' => RegExp(r'^main$'),
        'tabid' => RegExp(r'^(en|sch|kj|si)$'),
        _ => null,
      };
      if (safeValue != null && entry.value.every(safeValue.hasMatch)) {
        query[entry.key] = entry.value;
      }
    }
  } on FormatException {
    return '';
  }
  // Decode each segment before inspecting it so encoded semicolons cannot
  // carry a session identifier through an export. Re-encode via Uri below.
  final segments = uri.pathSegments.map((segment) => segment.replaceAll(
    RegExp(r';jsessionid=[^/;]*', caseSensitive: false),
    '',
  )).toList();
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: segments.any((s) => s.toLowerCase().contains('jsessionid'))
        ? const [] : segments,
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

Map<String, Object?> sanitizeGakujoExternalEntry(Map<String, Object?> entry) {
  final result = Map<String, Object?>.of(entry);
  final url = result['url'];
  if (url is String) result['url'] = sanitizeGakujoExternalUrl(url);
  return result;
}

String sanitizeGakujoNotificationKey(String key) {
  final first = key.indexOf('|');
  final second = first < 0 ? -1 : key.indexOf('|', first + 1);
  if (second < 0) return key;
  final url = key.substring(first + 1, second);
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasAuthority) return key;
  return '${key.substring(0, first + 1)}${sanitizeGakujoExternalUrl(url)}'
      '${key.substring(second)}';
}
