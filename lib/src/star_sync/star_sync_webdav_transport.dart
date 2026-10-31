import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import 'star_sync_transport.dart';

class StarSyncWebDavConfig {
  const StarSyncWebDavConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
  });
  final Uri baseUrl;
  final String username;
  final String password;
}

class StarSyncWebDavTransport implements StarSyncTransport {
  StarSyncWebDavTransport(
    this.config, {
    HttpClient Function()? httpClientFactory,
  }) : _client = (httpClientFactory ?? HttpClient.new)() {
    validateStarSyncEndpoint(config.baseUrl);
  }
  final StarSyncWebDavConfig config;
  final HttpClient _client;
  static const _dav = 'DAV:';
  Map<String, String> get _auth => {
    'authorization':
        'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
  };
  Uri _url(String path) {
    validateStarSyncPath(path);
    final base = config.baseUrl.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(
      '$base/${path.split('/').map(Uri.encodeComponent).join('/')}',
    );
  }

  Future<StarSyncHttpResponse> _request(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int> body = const [],
    bool collection = false,
  }) => starSyncRequest(
    _client,
    method,
    collection ? Uri.parse('${_url(path)}/') : _url(path),
    headers: {..._auth, ...headers},
    body: body,
  );
  @override
  Future<void> ensureDirectory(String path) async {
    validateStarSyncPath(path);
    final segments = path.split('/');
    for (var i = 1; i <= segments.length; i++) {
      final response = await _request(
        'MKCOL',
        segments.take(i).join('/'),
        collection: true,
      );
      if (response.statusCode != 405) checkStarSyncStatus(response.statusCode);
    }
  }

  Iterable<XmlElement> _children(XmlElement e, String name) => e.childElements
      .where((x) => x.name.local == name && x.name.namespaceUri == _dav);
  @override
  Future<List<StarSyncRemoteEntry>> list(String directory) async {
    const body =
        '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><getetag/><getlastmodified/><getcontentlength/><resourcetype/></prop></propfind>';
    final response = await _request(
      'PROPFIND',
      directory,
      collection: true,
      headers: {'depth': '1', 'content-type': 'application/xml; charset=utf-8'},
      body: utf8.encode(body),
    );
    if (response.statusCode == 404) return [];
    checkStarSyncStatus(response.statusCode);
    try {
      final root = XmlDocument.parse(utf8.decode(response.bytes)).rootElement;
      if (root.name.local != 'multistatus' || root.name.namespaceUri != _dav) {
        throw const FormatException();
      }
      final result = <StarSyncRemoteEntry>[];
      final target = Uri.parse('${_url(directory)}/');
      final targetSegments = target.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();
      for (final item in _children(root, 'response')) {
        final hrefs = _children(item, 'href');
        if (hrefs.isEmpty) continue;
        final href = target.resolve(hrefs.first.innerText);
        if (href.hasAuthority &&
            (href.scheme != target.scheme ||
                href.host != target.host ||
                href.port != target.port)) {
          continue;
        }
        final segments = href.pathSegments;
        if (segments.length != targetSegments.length + 1 ||
            !List.generate(
              targetSegments.length,
              (i) => segments[i] == targetSegments[i],
            ).every((v) => v)) {
          continue;
        }
        final name = segments.last;
        if (name.isEmpty || name.contains('/')) continue;
        try {
          validateStarSyncPath(name);
        } on ArgumentError {
          continue;
        }
        String? etag;
        DateTime? modified;
        int? size;
        var collection = false;
        var valid = false;
        for (final propstat in _children(item, 'propstat')) {
          final statuses = _children(propstat, 'status');
          if (statuses.isEmpty ||
              !RegExp(r'^HTTP/\S+\s+200(?:\s|$)')
                  .hasMatch(statuses.first.innerText.trim())) {
            continue;
          }
          for (final prop in _children(propstat, 'prop')) {
            valid = true;
            for (final e in prop.childElements.where(
              (x) => x.name.namespaceUri == _dav,
            )) {
              switch (e.name.local) {
                case 'getetag':
                  etag = normalizeStarSyncEtag(e.innerText);
                case 'getlastmodified':
                  try {
                    modified = HttpDate.parse(e.innerText);
                  } on FormatException {
                    modified = DateTime.tryParse(e.innerText);
                  }
                case 'getcontentlength':
                  size = int.tryParse(e.innerText);
                case 'resourcetype':
                  collection = _children(e, 'collection').isNotEmpty;
              }
            }
          }
        }
        if (valid && !collection) {
          result.add(
            StarSyncRemoteEntry(
              path: '$directory/$name',
              etag: etag,
              lastModified: modified,
              size: size,
            ),
          );
        }
      }
      return result;
    } on FormatException {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.invalidResponse,
        'Invalid WebDAV response',
      );
    } on XmlException {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.invalidResponse,
        'Invalid WebDAV response',
      );
    }
  }

  @override
  Future<StarSyncRemoteObject?> get(String path) async {
    final response = await _request('GET', path);
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
    final response = await _request(
      'PUT',
      path,
      headers: {
        'content-type': 'application/octet-stream',
        if (createOnly) 'if-none-match': '*',
      },
      body: bytes,
    );
    checkStarSyncStatus(response.statusCode, createOnly: createOnly);
  }

  @override
  Future<void> delete(String path) async {
    final response = await _request('DELETE', path);
    if (response.statusCode != 404) checkStarSyncStatus(response.statusCode);
  }

  @override
  void close() => _client.close(force: true);
}
