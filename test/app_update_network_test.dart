import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/app_update_service.dart';
import 'package:test/test.dart';

void main() {
  test('closes the HTTP client when a release response body stalls', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = _LocalReleaseClient(server.port);
    final responseStarted = Completer<void>();
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"tag_name":');
      await request.response.flush();
      responseStarted.complete();
    });
    try {
      final checking = AppUpdateService(
        httpClientFactory: () => client,
        requestTimeout: const Duration(milliseconds: 300),
      ).checkLatestRelease(currentVersion: '1.0.0');
      await responseStarted.future.timeout(const Duration(seconds: 2));
      await expectLater(
        checking.timeout(const Duration(seconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
      expect(client.closed, isTrue,
          reason:
              'A stalled body must release the connection at the app timeout');
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });

  test('parses a completed release and closes the connection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = _LocalReleaseClient(server.port);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'tag_name': 'v1.0.1',
        'html_url': 'https://github.com/example/app/releases/tag/v1.0.1',
      }));
      await request.response.close();
    });
    try {
      final release = await AppUpdateService(
        httpClientFactory: () => client,
      ).checkLatestRelease(currentVersion: '1.0.0');
      expect(release.hasUpdate, isTrue);
      expect(release.latestVersion, 'v1.0.1');
      expect(client.closed, isTrue);
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });
}

class _LocalReleaseClient implements HttpClient {
  _LocalReleaseClient(this.port);
  final int port;
  final HttpClient _inner = HttpClient();
  bool closed = false;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _inner.getUrl(Uri.parse('http://127.0.0.1:$port/releases/latest'));

  @override
  void close({bool force = false}) {
    closed = true;
    _inner.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
