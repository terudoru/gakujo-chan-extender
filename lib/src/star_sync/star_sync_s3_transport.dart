import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'star_sync_transport.dart';

class StarSyncS3Config {
  StarSyncS3Config({
    required this.endpoint,
    required this.region,
    required this.bucket,
    required String prefix,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.pathStyle,
  }) : prefix = prefix.replaceAll(RegExp(r'^/+|/+$'), '').isEmpty
           ? ''
           : '${prefix.replaceAll(RegExp(r'^/+|/+$'), '')}/' {
    validateStarSyncEndpoint(endpoint);
    if (bucket.isEmpty || bucket.contains('/'))
      throw ArgumentError('Invalid bucket');
    if (this.prefix.isNotEmpty)
      validateStarSyncPath(this.prefix.substring(0, this.prefix.length - 1));
  }
  final Uri endpoint;
  final String region;
  final String bucket;
  final String prefix;
  final String accessKeyId;
  final String secretAccessKey;
  final bool pathStyle;
}

String _encode(String value) => utf8.encode(value).map((b) {
  if ((b >= 65 && b <= 90) ||
      (b >= 97 && b <= 122) ||
      (b >= 48 && b <= 57) ||
      b == 45 ||
      b == 46 ||
      b == 95 ||
      b == 126)
    return String.fromCharCode(b);
  return '%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}';
}).join();
String _query(Map<String, String> query) {
  final entries =
      query.entries.map((e) => (_encode(e.key), _encode(e.value))).toList()
        ..sort((a, b) {
          final c = a.$1.compareTo(b.$1);
          return c == 0 ? a.$2.compareTo(b.$2) : c;
        });
  return entries.map((e) => '${e.$1}=${e.$2}').join('&');
}

Uri buildStarSyncS3Url(
  StarSyncS3Config config, {
  String key = '',
  Map<String, String> query = const {},
}) {
  final endpoint = config.endpoint;
  final baseSegments = endpoint.pathSegments
      .where((s) => s.isNotEmpty)
      .toList();
  final segments = [
    ...baseSegments,
    if (config.pathStyle) config.bucket,
    if (key.isNotEmpty) ...key.split('/'),
  ];
  final path = '/${segments.map(_encode).join('/')}';
  final host = config.pathStyle
      ? endpoint.host
      : '${config.bucket}.${endpoint.host}';
  final authorityHost = host.contains(':') ? '[$host]' : host;
  final port = endpoint.hasPort ? ':${endpoint.port}' : '';
  final q = _query(query);
  return Uri.parse(
    '${endpoint.scheme}://$authorityHost$port$path${q.isEmpty ? '' : '?$q'}',
  );
}

Map<String, String> signStarSyncS3Request({
  required String method,
  required Uri uri,
  required String region,
  required String accessKeyId,
  required String secretAccessKey,
  required DateTime time,
  List<int> payload = const [],
  Map<String, String> headers = const {},
}) {
  final utc = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final date =
      '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}${two(utc.day)}';
  final timestamp =
      '${date}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  final hash = sha256.convert(payload).toString();
  final host =
      '${uri.host.contains(':') ? '[${uri.host}]' : uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  final signed = <String, String>{};
  headers.forEach(
    (k, v) =>
        signed[k.toLowerCase()] = v.trim().replaceAll(RegExp(r'\s+'), ' '),
  );
  signed.addAll({
    'host': host,
    'x-amz-date': timestamp,
    'x-amz-content-sha256': hash,
  });
  final names = signed.keys.toList()..sort();
  final headerText = names.map((n) => '$n:${signed[n]}\n').join();
  final signedNames = names.join(';');
  final canonicalQuery = _query(uri.queryParameters);
  final canonicalPath = uri.path.isEmpty
      ? '/'
      : '/${uri.pathSegments.map(_encode).join('/')}';
  final canonical =
      '$method\n$canonicalPath\n$canonicalQuery\n$headerText\n$signedNames\n$hash';
  final scope = '$date/$region/s3/aws4_request';
  final toSign =
      'AWS4-HMAC-SHA256\n$timestamp\n$scope\n${sha256.convert(utf8.encode(canonical))}';
  List<int> hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;
  final dateKey = hmac(utf8.encode('AWS4$secretAccessKey'), date);
  final regionKey = hmac(dateKey, region);
  final serviceKey = hmac(regionKey, 's3');
  final signingKey = hmac(serviceKey, 'aws4_request');
  final signature = Hmac(
    sha256,
    signingKey,
  ).convert(utf8.encode(toSign)).toString();
  signed['authorization'] =
      'AWS4-HMAC-SHA256 Credential=$accessKeyId/$scope, SignedHeaders=$signedNames, Signature=$signature';
  return signed;
}

class StarSyncS3Transport implements StarSyncTransport {
  StarSyncS3Transport(
    this.config, {
    HttpClient Function()? httpClientFactory,
    DateTime Function()? now,
  }) : _client = (httpClientFactory ?? HttpClient.new)(),
       _now = now ?? DateTime.now {
    validateStarSyncEndpoint(config.endpoint);
  }
  final StarSyncS3Config config;
  final HttpClient _client;
  final DateTime Function() _now;
  Future<StarSyncHttpResponse> _request(
    String method,
    String key, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) {
    final uri = buildStarSyncS3Url(config, key: key, query: query);
    final signed = signStarSyncS3Request(
      method: method,
      uri: uri,
      region: config.region,
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
      time: _now(),
      payload: body,
      headers: headers,
    );
    return starSyncRequest(_client, method, uri, headers: signed, body: body);
  }

  @override
  Future<void> ensureDirectory(String path) async {
    validateStarSyncPath(path);
  }

  @override
  Future<List<StarSyncRemoteEntry>> list(String directory) async {
    validateStarSyncPath(directory);
    final prefix = '${config.prefix}$directory/';
    final result = <StarSyncRemoteEntry>[];
    final seen = <String>{};
    String? token;
    do {
      final response = await _request(
        'GET',
        '',
        query: {
          'list-type': '2',
          'prefix': prefix,
          'delimiter': '/',
          'continuation-token': ?token,
        },
      );
      if (response.statusCode == 404) return result;
      checkStarSyncStatus(response.statusCode);
      try {
        final root = XmlDocument.parse(utf8.decode(response.bytes)).rootElement;
        if (root.name.local != 'ListBucketResult')
          throw const FormatException();
        String? field(XmlElement e, String name) {
          for (final child in e.childElements) {
            if (child.name.local == name) return child.innerText;
          }
          return null;
        }

        for (final item in root.childElements.where(
          (e) => e.name.local == 'Contents',
        )) {
          final key = field(item, 'Key');
          if (key == null || !key.startsWith(prefix)) continue;
          final name = key.substring(prefix.length);
          if (name.isEmpty || name.contains('/')) continue;
          try {
            validateStarSyncPath(name);
          } on ArgumentError {
            continue;
          }
          result.add(
            StarSyncRemoteEntry(
              path: '$directory/$name',
              etag: normalizeStarSyncEtag(field(item, 'ETag')),
              lastModified: DateTime.tryParse(
                field(item, 'LastModified') ?? '',
              ),
              size: int.tryParse(field(item, 'Size') ?? ''),
            ),
          );
        }
        final truncated = field(root, 'IsTruncated') == 'true';
        token = truncated ? field(root, 'NextContinuationToken') : null;
        if (truncated && (token == null || token.isEmpty || !seen.add(token)))
          throw const FormatException();
      } on FormatException {
        throw const StarSyncTransportException(
          StarSyncTransportErrorKind.invalidResponse,
          'Invalid S3 response',
        );
      } on XmlException {
        throw const StarSyncTransportException(
          StarSyncTransportErrorKind.invalidResponse,
          'Invalid S3 response',
        );
      }
    } while (token != null);
    return result;
  }

  @override
  Future<StarSyncRemoteObject?> get(String path) async {
    validateStarSyncPath(path);
    final response = await _request('GET', '${config.prefix}$path');
    if (response.statusCode == 404) return null;
    checkStarSyncStatus(response.statusCode);
    return StarSyncRemoteObject(
      bytes: response.bytes,
      etag: normalizeStarSyncEtag(response.headers.value('etag')),
    );
  }

  @override
  Future<void> put(
    String path,
    List<int> bytes, {
    bool createOnly = false,
  }) async {
    validateStarSyncPath(path);
    final response = await _request(
      'PUT',
      '${config.prefix}$path',
      headers: {if (createOnly) 'if-none-match': '*'},
      body: bytes,
    );
    checkStarSyncStatus(response.statusCode, createOnly: createOnly);
  }

  @override
  Future<void> delete(String path) async {
    validateStarSyncPath(path);
    final response = await _request('DELETE', '${config.prefix}$path');
    if (response.statusCode != 404) checkStarSyncStatus(response.statusCode);
  }

  @override
  void close() => _client.close(force: true);
}
