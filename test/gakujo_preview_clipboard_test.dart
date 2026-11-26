import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_pdf_preview_server.dart';

import 'support/preview_loopback_fixture.dart';

void main() {
  test(
    'POST ./clipboard writes exact UTF-8 text and awaits native ack before 204',
    () async {
      final received = <String>[];
      final ack = Completer<void>();
      final server = GakujoPdfPreviewServer(
        bundle: PreviewTestAssetBundle(),
        writeClipboard: (text) async {
          received.add(text);
          await ack.future;
        },
      );
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() async {
        client.close(force: true);
        await server.close();
      });

      final indexUrl = await server.start();
      final clipboardUrl = indexUrl.resolve('clipboard');
      const payload = '新潟大学 学務情報システム\n第1行\r\n第2行\t😀🎓';

      var completed = false;
      final pending =
          sendPreviewRequest(
            client,
            clipboardUrl,
            origin: 'null',
            bodyBytes: utf8.encode(payload),
          ).then((result) {
            completed = true;
            return result;
          });

      while (received.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(received, [payload]);
      expect(completed, isFalse);

      ack.complete();
      final sandboxResult = await pending;
      expect(sandboxResult.status, HttpStatus.noContent);
      expect(sandboxResult.body, isEmpty);

      // Apple popup origin (exact loopback viewer origin) is also accepted
      final viewerOrigin = 'http://127.0.0.1:${indexUrl.port}';
      final popupResult = await sendPreviewRequest(
        client,
        clipboardUrl,
        origin: viewerOrigin,
        bodyBytes: utf8.encode('Appleポップアップ経由'),
      );
      expect(popupResult.status, HttpStatus.noContent);
      expect(popupResult.body, isEmpty);
      expect(received, [payload, 'Appleポップアップ経由']);
    },
  );

  test('clipboard endpoint enforces capability token, method, origin, MIME, query, and no read access', () async {
    final received = <String>[];
    final server = GakujoPdfPreviewServer(
      bundle: PreviewTestAssetBundle(),
      writeClipboard: (text) async => received.add(text),
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });

    final indexUrl = await server.start();
    final clipboardUrl = indexUrl.resolve('clipboard');
    final validBody = utf8.encode('テスト');

    // No read endpoints (GET / HEAD)
    expect(
      (await sendPreviewRequest(
        client,
        clipboardUrl,
        method: 'GET',
        bodyBytes: null,
      )).status,
      HttpStatus.notFound,
    );
    expect(
      (await sendPreviewRequest(
        client,
        clipboardUrl,
        method: 'HEAD',
        bodyBytes: null,
      )).status,
      HttpStatus.notFound,
    );

    // Wrong capability token or path
    expect(
      (await sendPreviewRequest(
        client,
        indexUrl.replace(path: '/wrong-token/clipboard'),
        bodyBytes: validBody,
      )).status,
      HttpStatus.notFound,
    );
    expect(
      (await sendPreviewRequest(
        client,
        indexUrl.replace(
          path: '/${indexUrl.pathSegments.first}/clipboard/extra',
        ),
        bodyBytes: validBody,
      )).status,
      HttpStatus.notFound,
    );

    // Query string rejected
    expect(
      (await sendPreviewRequest(
        client,
        clipboardUrl.replace(query: 'x=1'),
        bodyBytes: validBody,
      )).status,
      HttpStatus.notFound,
    );

    // Wrong Host header rejected
    expect(
      (await sendPreviewRequest(
        client,
        clipboardUrl,
        host: 'example.com',
        bodyBytes: validBody,
      )).status,
      HttpStatus.notFound,
    );

    // Untrusted origins rejected (university origin, other loopback port, missing origin)
    for (final badOrigin in <String?>[
      'https://gakujo.iess.niigata-u.ac.jp',
      'http://127.0.0.1:1',
      'http://localhost:${indexUrl.port}',
      null,
    ]) {
      final result = await sendPreviewRequest(
        client,
        clipboardUrl,
        origin: badOrigin,
        bodyBytes: validBody,
      );
      expect(result.status, HttpStatus.forbidden, reason: 'origin=$badOrigin');
    }

    // Non-text/plain MIME types rejected
    for (final badMime in <String?>[
      'application/json',
      'text/html',
      'application/x-www-form-urlencoded',
    ]) {
      final result = await sendPreviewRequest(
        client,
        clipboardUrl,
        contentType: badMime,
        bodyBytes: validBody,
      );
      expect(result.status, HttpStatus.forbidden, reason: 'mime=$badMime');
    }

    expect(received, isEmpty);
  });

  test('clipboard endpoint enforces empty, character, and byte limits and surfaces native errors', () async {
    var shouldThrow = false;
    final received = <String>[];
    final server = GakujoPdfPreviewServer(
      bundle: PreviewTestAssetBundle(),
      writeClipboard: (text) async {
        if (shouldThrow) throw StateError('native clipboard failure');
        received.add(text);
      },
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });

    final indexUrl = await server.start();
    final clipboardUrl = indexUrl.resolve('clipboard');

    // Empty body rejected with 400
    expect(
      (await sendPreviewRequest(
        client,
        clipboardUrl,
        bodyBytes: const [],
      )).status,
      HttpStatus.badRequest,
    );

    // Over 4,000,000 UTF-16 code units rejected with 400
    final overChars = utf8.encode('a' * 4000001);
    expect(
      (await sendPreviewRequest(
        client,
        clipboardUrl,
        bodyBytes: overChars,
      )).status,
      HttpStatus.badRequest,
    );

    // Over 16 MiB rejected with 413 via Content-Length (without invoking writeClipboard).
    // Note: In dart:io _HttpServer, when a request with Transfer-Encoding: chunked (contentLength == -1)
    // is rejected early by breaking out of `await for (final chunk in request)` before the final `0\r\n\r\n`
    // chunk is consumed, `response.close()` aborts/closes the underlying socket without flushing response
    // headers (`Connection closed before full header was received` / empty socket stream), so only Content-Length
    // > 16 MiB produces a readable HTTP 413 response on the wire; chunked overflow closes the connection without
    // calling writeClipboard.
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      indexUrl.port,
    );
    addTearDown(socket.destroy);
    socket.write(
      'POST ${clipboardUrl.path} HTTP/1.1\r\n'
      'Host: 127.0.0.1:${indexUrl.port}\r\n'
      'Origin: null\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n'
      'Content-Length: ${16 * 1024 * 1024 + 1}\r\n'
      'Connection: close\r\n\r\n',
    );
    await socket.flush();
    final responseFuture = utf8.decoder.bind(socket).first;
    final oneMiB = Uint8List(1024 * 1024);
    try {
      for (var i = 0; i < 16; i++) {
        socket.add(oneMiB);
      }
      socket.add(const [65]);
      await socket.flush();
    } on SocketException {
      // Server may reset the connection once 413 is sent.
    }
    final firstChunk = await responseFuture.timeout(const Duration(seconds: 5));
    expect(firstChunk, startsWith('HTTP/1.1 413 '));
    await socket.close();

    // Streamed Transfer-Encoding: chunked without Content-Length exceeding 16 MiB is also aborted by server
    // without invoking writeClipboard.
    final chunkedSocket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      indexUrl.port,
    );
    addTearDown(chunkedSocket.destroy);
    final chunkedDone = Completer<String>();
    final chunkedBuf = StringBuffer();
    chunkedSocket.listen(
      (data) => chunkedBuf.write(utf8.decode(data, allowMalformed: true)),
      onError: (_) {
        if (!chunkedDone.isCompleted) {
          chunkedDone.complete(chunkedBuf.toString());
        }
      },
      onDone: () {
        if (!chunkedDone.isCompleted) {
          chunkedDone.complete(chunkedBuf.toString());
        }
      },
    );
    chunkedSocket.add(
      utf8.encode(
        'POST ${clipboardUrl.path} HTTP/1.1\r\n'
        'Host: 127.0.0.1:${indexUrl.port}\r\n'
        'Origin: null\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        'Transfer-Encoding: chunked\r\n'
        'Connection: close\r\n\r\n'
        '1000001\r\n',
      ),
    );
    try {
      for (var i = 0; i < 16; i++) {
        chunkedSocket.add(oneMiB);
      }
      chunkedSocket.add(const [65, 13, 10, 48, 13, 10, 13, 10]);
      await chunkedSocket.flush();
    } on SocketException {
      // Expected if server closes early.
    }
    final chunkedOutcome = await chunkedDone.future.timeout(
      const Duration(seconds: 5),
    );
    expect(chunkedOutcome, isNot(startsWith('HTTP/1.1 204')));
    expect(received, isEmpty);
    await chunkedSocket.close();

    // Native clipboard failure returns 500, not 204
    shouldThrow = true;
    expect(
      (await sendPreviewRequest(
        client,
        clipboardUrl,
        bodyBytes: utf8.encode('失敗テスト'),
      )).status,
      HttpStatus.internalServerError,
    );
    expect(received, isEmpty);
  });
}
