import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'star_sync_transport.dart';

typedef StarSyncAccessTokenProvider = Future<String> Function({
  bool forceRefresh,
});

class StarSyncGoogleDriveTransport implements StarSyncTransport {
  StarSyncGoogleDriveTransport({
    required this.accessToken,
    HttpClient Function()? httpClientFactory,
    Uri? apiBase,
    Future<void> Function(Duration)? delay,
  }) : _client = (httpClientFactory ?? HttpClient.new)(),
       _apiBase = apiBase ?? Uri.parse('https://www.googleapis.com'),
       _delay = delay ?? Future<void>.delayed {
    validateStarSyncEndpoint(_apiBase);
  }

  final StarSyncAccessTokenProvider accessToken;
  final HttpClient _client;
  final Uri _apiBase;
  final Future<void> Function(Duration) _delay;
  final Map<String, List<_DriveFile>> _files = {};

  Uri _uri(String path, [Map<String, String> query = const {}]) {
    final base = _apiBase.path.replaceFirst(RegExp(r'/+$'), '');
    return _apiBase.replace(path: '$base$path', queryParameters: query);
  }

  bool _isRateLimit(StarSyncHttpResponse response) {
    if (response.statusCode != 403) return false;
    try {
      final json = jsonDecode(utf8.decode(response.bytes));
      final errors = (json as Map<String, dynamic>)['error'];
      if (errors is! Map<String, dynamic> || errors['errors'] is! List) {
        return false;
      }
      return (errors['errors'] as List).any(
        (item) =>
            item is Map &&
            (item['reason'] == 'rateLimitExceeded' ||
                item['reason'] == 'userRateLimitExceeded'),
      );
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  Future<StarSyncHttpResponse> _request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) async {
    var token = await accessToken();
    var refreshed = false;
    var retries = 0;
    while (true) {
      final response = await starSyncRequest(
        _client,
        method,
        uri,
        headers: {...headers, 'authorization': 'Bearer $token'},
        body: body,
      );
      if (response.statusCode == 401 && !refreshed) {
        token = await accessToken(forceRefresh: true);
        refreshed = true;
        continue;
      }
      final retryable =
          response.statusCode == 429 ||
          response.statusCode >= 500 && response.statusCode < 600 ||
          _isRateLimit(response);
      if (retryable) {
        if (retries == 3) {
          throw StarSyncTransportException(
            StarSyncTransportErrorKind.server,
            'HTTP request failed (${response.statusCode})',
            statusCode: response.statusCode,
          );
        }
        await _delay(Duration(seconds: 1 << retries));
        retries++;
        continue;
      }
      return response;
    }
  }

  Future<void> _refresh() async {
    final found = <String, List<_DriveFile>>{};
    final seen = <String>{};
    String? token;
    do {
      final response = await _request(
        'GET',
        _uri('/drive/v3/files', {
          'spaces': 'appDataFolder',
          'q': 'trashed=false',
          'pageSize': '1000',
          'fields': 'nextPageToken,files(id,name,version,md5Checksum,modifiedTime,size,createdTime)',
          'pageToken': ?token,
        }),
      );
      checkStarSyncStatus(response.statusCode);
      try {
        final data =
            jsonDecode(utf8.decode(response.bytes)) as Map<String, dynamic>;
        final items = data['files'] as List;
        for (final item in items) {
          final file = _DriveFile.fromJson(item as Map<String, dynamic>);
          found.putIfAbsent(file.name, () => []).add(file);
        }
        token = data['nextPageToken'] as String?;
        if (token != null && (token.isEmpty || !seen.add(token))) {
          throw const FormatException();
        }
      } on FormatException {
        throw const StarSyncTransportException(
          StarSyncTransportErrorKind.invalidResponse,
          'Invalid Google Drive response',
        );
      } on TypeError {
        throw const StarSyncTransportException(
          StarSyncTransportErrorKind.invalidResponse,
          'Invalid Google Drive response',
        );
      }
    } while (token != null);
    for (final files in found.values) {
      files.sort((a, b) {
        final byTime = a.created.compareTo(b.created);
        return byTime == 0 ? a.id.compareTo(b.id) : byTime;
      });
    }
    _files
      ..clear()
      ..addAll(found);
  }

  Future<List<_DriveFile>> _lookup(String path) async {
    if (!_files.containsKey(path)) await _refresh();
    return _files[path] ?? [];
  }

  @override
  Future<void> ensureDirectory(String path) async {
    validateStarSyncPath(path);
  }

  @override
  Future<List<StarSyncRemoteEntry>> list(String directory) async {
    validateStarSyncPath(directory);
    await _refresh();
    final prefix = '$directory/';
    final result = <StarSyncRemoteEntry>[];
    for (final entry in _files.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final leaf = entry.key.substring(prefix.length);
      if (leaf.isEmpty || leaf.contains('/')) continue;
      try {
        validateStarSyncPath(leaf);
      } on ArgumentError {
        continue;
      }
      final file = entry.value.first;
      result.add(
        StarSyncRemoteEntry(
          path: file.name,
          etag: file.etag,
          lastModified: file.modified,
          size: file.size,
        ),
      );
    }
    return result;
  }

  @override
  Future<StarSyncRemoteObject?> get(String path) async {
    validateStarSyncPath(path);
    final files = await _lookup(path);
    if (files.isEmpty) return null;
    final file = files.first;
    final response = await _request(
      'GET',
      _uri('/drive/v3/files/${Uri.encodeComponent(file.id)}', {'alt': 'media'}),
    );
    if (response.statusCode == 404) {
      _files.remove(path);
      return null;
    }
    checkStarSyncStatus(response.statusCode);
    return StarSyncRemoteObject(bytes: response.bytes, etag: file.etag);
  }

  @override
  Future<void> put(
    String path,
    List<int> bytes, {
    bool createOnly = false,
  }) async {
    validateStarSyncPath(path);
    if (createOnly) await _refresh();
    final files = await _lookup(path);
    if (files.isNotEmpty) {
      if (createOnly) {
        throw const StarSyncTransportException(
          StarSyncTransportErrorKind.alreadyExists,
          'File already exists',
        );
      }
      final response = await _request(
        'PATCH',
        _uri('/upload/drive/v3/files/${Uri.encodeComponent(files.first.id)}', {
          'uploadType': 'media',
        }),
        headers: {'content-type': 'application/octet-stream'},
        body: bytes,
      );
      checkStarSyncStatus(response.statusCode);
      _files.remove(path);
      return;
    }
    final random = Random.secure();
    final boundary =
        'star_sync_${List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join()}';
    final metadata = jsonEncode({
      'name': path,
      'parents': ['appDataFolder'],
    });
    final body = <int>[
      ...utf8.encode(
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n',
      ),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];
    final response = await _request(
      'POST',
      _uri('/upload/drive/v3/files', {
        'uploadType': 'multipart',
        'fields': 'id',
      }),
      headers: {'content-type': 'multipart/related; boundary=$boundary'},
      body: body,
    );
    checkStarSyncStatus(response.statusCode);
    String id;
    try {
      id =
          (jsonDecode(utf8.decode(response.bytes))
                  as Map<String, dynamic>)['id']
              as String;
      if (id.isEmpty) throw const FormatException();
    } on FormatException {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.invalidResponse,
        'Invalid Google Drive response',
      );
    } on TypeError {
      throw const StarSyncTransportException(
        StarSyncTransportErrorKind.invalidResponse,
        'Invalid Google Drive response',
      );
    }
    _files.remove(path);
    if (createOnly) {
      await _refresh();
      final current = _files[path];
      if (current == null || current.isEmpty) {
        throw const StarSyncTransportException(
          StarSyncTransportErrorKind.invalidResponse,
          'Created file missing from Google Drive listing',
        );
      }
      if (current.first.id != id) {
        await _deleteId(id);
        _files.remove(path);
        throw const StarSyncTransportException(
          StarSyncTransportErrorKind.alreadyExists,
          'File already exists',
        );
      }
    }
  }

  Future<void> _deleteId(String id) async {
    final response = await _request(
      'DELETE',
      _uri('/drive/v3/files/${Uri.encodeComponent(id)}'),
    );
    if (response.statusCode != 404) checkStarSyncStatus(response.statusCode);
  }

  @override
  Future<void> delete(String path) async {
    validateStarSyncPath(path);
    await _refresh();
    for (final file in _files[path] ?? <_DriveFile>[]) {
      await _deleteId(file.id);
    }
    _files.remove(path);
  }

  @override
  void close() => _client.close(force: true);
}

class _DriveFile {
  _DriveFile.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      created = DateTime.parse(json['createdTime'] as String),
      modified = DateTime.tryParse(json['modifiedTime'] as String? ?? ''),
      size = int.tryParse(json['size'] as String? ?? ''),
      etag = (json['version'] ?? json['md5Checksum']) as String?;

  final String id;
  final String name;
  final DateTime created;
  final DateTime? modified;
  final int? size;
  final String? etag;
}
