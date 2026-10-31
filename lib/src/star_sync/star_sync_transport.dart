import 'dart:async';
import 'dart:io';

abstract interface class StarSyncTransport {
  Future<void> ensureDirectory(String path);
  Future<List<StarSyncRemoteEntry>> list(String directory);
  Future<StarSyncRemoteObject?> get(String path);
  Future<void> put(String path, List<int> bytes, {bool createOnly = false});
  Future<void> delete(String path);
  void close();
}

class StarSyncRemoteEntry {
  const StarSyncRemoteEntry({
    required this.path,
    this.etag,
    this.lastModified,
    this.size,
  });
  final String path;
  final String? etag;
  final DateTime? lastModified;
  final int? size;
}

class StarSyncRemoteObject {
  const StarSyncRemoteObject({required this.bytes, this.etag});
  final List<int> bytes;
  final String? etag;
}

enum StarSyncTransportErrorKind {
  auth,
  notFound,
  alreadyExists,
  network,
  tls,
  server,
  invalidResponse,
}

class StarSyncTransportException implements Exception {
  const StarSyncTransportException(this.kind, this.message, {this.statusCode});
  final StarSyncTransportErrorKind kind;
  final String message;
  final int? statusCode;
  @override
  String toString() => 'StarSyncTransportException: $message';
}

void validateStarSyncEndpoint(Uri uri) {
  if (!uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.scheme != 'https' &&
          !(uri.scheme == 'http' &&
              {
                'localhost',
                '127.0.0.1',
                '::1',
              }.contains(uri.host.toLowerCase()))) ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError('Invalid transport endpoint');
  }
}

void validateStarSyncPath(String path) {
  if (path.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
    throw ArgumentError('Invalid relative path');
  }
}

String? normalizeStarSyncEtag(String? value) {
  if (value == null) return null;
  var result = value.trim();
  if (result.startsWith('W/')) result = result.substring(2).trim();
  if (result.length >= 2 && result.startsWith('"') && result.endsWith('"')) {
    result = result.substring(1, result.length - 1);
  }
  return result;
}

const starSyncRequestTimeout = Duration(seconds: 20);

class StarSyncHttpResponse {
  const StarSyncHttpResponse(this.statusCode, this.headers, this.bytes);
  final int statusCode;
  final HttpHeaders headers;
  final List<int> bytes;
}

Future<StarSyncHttpResponse> starSyncRequest(
  HttpClient client,
  String method,
  Uri uri, {
  Map<String, String> headers = const {},
  List<int> body = const [],
}) async {
  Future<StarSyncHttpResponse> send() async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    headers.forEach((name, value) => request.headers.set(name, value));
    if (body.isNotEmpty) request.add(body);
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw const StarSyncTransportException(
          StarSyncTransportErrorKind.invalidResponse,
          'Response is too large',
        );
      }
      bytes.addAll(chunk);
    }
    return StarSyncHttpResponse(response.statusCode, response.headers, bytes);
  }

  try {
    return await send().timeout(starSyncRequestTimeout);
  } on HandshakeException {
    throw const StarSyncTransportException(
      StarSyncTransportErrorKind.tls,
      'TLS connection failed',
    );
  } on TlsException {
    throw const StarSyncTransportException(
      StarSyncTransportErrorKind.tls,
      'TLS connection failed',
    );
  } on SocketException {
    throw const StarSyncTransportException(
      StarSyncTransportErrorKind.network,
      'Network connection failed',
    );
  } on TimeoutException {
    throw const StarSyncTransportException(
      StarSyncTransportErrorKind.network,
      'Request timed out',
    );
  } on HttpException {
    throw const StarSyncTransportException(
      StarSyncTransportErrorKind.network,
      'HTTP connection failed',
    );
  }
}

void checkStarSyncStatus(int status, {bool createOnly = false}) {
  if (status >= 200 && status < 300) return;
  final kind = switch (status) {
    401 || 403 => StarSyncTransportErrorKind.auth,
    404 => StarSyncTransportErrorKind.notFound,
    412 when createOnly => StarSyncTransportErrorKind.alreadyExists,
    _ => StarSyncTransportErrorKind.server,
  };
  throw StarSyncTransportException(
    kind,
    'HTTP request failed ($status)',
    statusCode: status,
  );
}
