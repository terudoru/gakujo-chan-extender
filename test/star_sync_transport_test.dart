import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';

class _ObservedRequest implements HttpClientRequest {
  _ObservedRequest(this.inner);
  final HttpClientRequest inner;
  bool aborted = false;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
    inner.abort(exception, stackTrace);
  }

  @override
  HttpHeaders get headers => inner.headers;
  @override
  set followRedirects(bool value) => inner.followRedirects = value;
  @override
  set contentLength(int value) => inner.contentLength = value;
  @override
  void add(List<int> data) => inner.add(data);
  @override
  Future<HttpClientResponse> close() => inner.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedOpenClient implements HttpClient {
  final inner = HttpClient();
  final entered = Completer<void>();
  final release = Completer<void>();
  _ObservedRequest? request;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    request = _ObservedRequest(await inner.openUrl(method, url));
    entered.complete();
    await release.future;
    return request!;
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final cancel in [false, true]) {
    test(
      'request rechecks policy after opening connection, cancel=$cancel',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0;
        final bodies = <List<int>>[];
        server.listen((request) async {
          requests++;
          bodies.add(
            await request.fold<List<int>>(
              [],
              (all, chunk) => all..addAll(chunk),
            ),
          );
          await request.response.close();
        });
        final client = _GatedOpenClient();
        var allowed = true;
        final cancelled = StateError('cancelled by current policy');
        try {
          final pending = starSyncRequest(
            client,
            'POST',
            Uri.parse('http://127.0.0.1:${server.port}/backup'),
            body: [1, 2],
            beforeSend: () {
              if (!allowed) throw cancelled;
            },
          );
          final result = cancel
              ? expectLater(pending, throwsA(same(cancelled)))
              : pending;
          await client.entered.future;
          expect(requests, 0);
          allowed = !cancel;
          client.release.complete();
          await result;
          expect(client.request!.aborted, cancel);
          expect(requests, cancel ? 0 : 1);
          expect(
            bodies,
            cancel
                ? isEmpty
                : [
                    [1, 2],
                  ],
          );
        } finally {
          client.close(force: true);
          await server.close(force: true);
        }
      },
    );
  }

  test('request refuses before opening connection', () async {
    final client = _GatedOpenClient();
    final cancelled = StateError('cancelled');
    try {
      await expectLater(
        starSyncRequest(
          client,
          'POST',
          Uri.parse('http://127.0.0.1:1/backup'),
          beforeSend: () => throw cancelled,
        ),
        throwsA(same(cancelled)),
      );
      expect(client.request, isNull);
    } finally {
      client.close(force: true);
    }
  });

  test('large object requires an increased response limit', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.add(List.filled(5 * 1024 * 1024, 7));
      await request.response.close();
    });
    final client = HttpClient();
    final url = Uri.parse('http://127.0.0.1:${server.port}/backup/device');
    try {
      await expectLater(
        starSyncRequest(client, 'GET', url),
        throwsA(isA<StarSyncTransportException>()),
      );
      expect(
        (await starSyncRequest(client, 'GET', url, maxBytes: 32 * 1024 * 1024)).bytes.length,
        5 * 1024 * 1024,
      );
    } finally {
      client.close(force: true);
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('endpoint validation and traversal', () {
    for (final url in [
      'https://example.com/',
      'http://localhost:123/',
      'http://127.0.0.1/',
      'http://[::1]/',
    ]) {
      validateStarSyncEndpoint(Uri.parse(url));
    }
    for (final url in [
      'http://example.com/',
      'https://user:pass@example.com/',
    ]) {
      expect(
        () => validateStarSyncEndpoint(Uri.parse(url)),
        throwsArgumentError,
      );
    }
    for (final path in ['/a', 'a//b', 'a/../b', 'a/./b', '']) {
      expect(() => validateStarSyncPath(path), throwsArgumentError);
    }
  });

  test('request timeout scales with the request body', () {
    expect(starSyncRequestTimeoutFor(0), const Duration(seconds: 20));
    expect(starSyncRequestTimeoutFor(32767), const Duration(seconds: 20));
    expect(starSyncRequestTimeoutFor(32768), const Duration(seconds: 21));
    expect(
      starSyncRequestTimeoutFor(8 * 1024 * 1024),
      const Duration(seconds: 276),
    );
  });

  test('timeout aborts the connection', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final ended = Completer<void>();
    server.listen((socket) {
      socket.listen(
        (_) {},
        onDone: () {
          socket.destroy();
          if (!ended.isCompleted) ended.complete();
        },
      );
    });
    final client = HttpClient();
    try {
      await expectLater(
        starSyncRequest(
          client,
          'POST',
          Uri.parse('http://127.0.0.1:${server.port}/'),
          body: [1],
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<StarSyncTransportException>().having(
            (error) => error.kind,
            'kind',
            StarSyncTransportErrorKind.network,
          ),
        ),
      );
      await ended.future.timeout(const Duration(seconds: 2));
    } finally {
      client.close(force: true);
      await server.close();
    }
  });
}
