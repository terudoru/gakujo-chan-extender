import 'allowed_web_origins.dart';

const _authenticationQueryParameters = {
  'state',
  'code',
  'login_hint',
  'id_token',
  'access_token',
  'refresh_token',
  'nonce',
  'code_challenge',
  'code_verifier',
  'samlrequest',
  'samlresponse',
  'relaystate',
  'sigalg',
  'signature',
  'ticket',
  'session',
  'sessionid',
  'jsessionid',
  'token',
  'authuser',
};

/// Keeps navigation identifiers while removing session data from exports.
String sanitizeGakujoExternalUrl(String value) =>
    _sanitizeGakujoUrl(value, preserveExternalQuery: false);

/// Preserves query parameters needed to revisit allowed external pages.
String sanitizeGakujoCopyUrl(String value) =>
    _sanitizeGakujoUrl(value, preserveExternalQuery: true);

String _sanitizeGakujoUrl(String value, {required bool preserveExternalQuery}) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    return '';
  }
  final keepQuery =
      preserveExternalQuery &&
      uri.host != Uri.parse(AllowedWebOrigins.gakujoUrl).host &&
      AllowedWebOrigins.canNavigate(value, debugAllowed: false);
  final query = <String, List<String>>{};
  final externalQuery = <String>[];
  try {
    if (keepQuery) {
      // Preserve duplicate values and original escaping on links such as Forms.
      for (final parameter in uri.query.split('&')) {
        final name = Uri.decodeQueryComponent(parameter.split('=').first);
        if (!_authenticationQueryParameters.contains(name.toLowerCase())) {
          externalQuery.add(parameter);
        }
      }
    }
    for (final entry in uri.queryParametersAll.entries) {
      final name = entry.key.toLowerCase();
      final safeValue = switch (name) {
        '_flowid' => RegExp(r'^[A-Za-z0-9-]{1,80}-flow$'),
        'keijitype' || 'genrecd' || 'seqno' => RegExp(r'^[0-9]{1,32}$'),
        'page' => RegExp(r'^main$'),
        'tabid' => RegExp(r'^(en|sch|kj|si|sd|sy)$'),
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
    query: keepQuery && externalQuery.isNotEmpty
        ? externalQuery.join('&')
        : null,
    queryParameters: keepQuery || query.isEmpty ? null : query,
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
