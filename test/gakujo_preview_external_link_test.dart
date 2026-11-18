import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_pdf_preview_server.dart';

class _ViewerBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key != 'assets/pdf_preview/web/index.html') {
      throw StateError('Unexpected asset: $key');
    }
    return ByteData.sublistView(
      Uint8List.fromList(
        utf8.encode(
          '<html><head><base href="/"></head><body>'
          '<script src="flutter_bootstrap.js" async></script></body></html>',
        ),
      ),
    );
  }
}

void main() {
  Future<({int status, String body})> sendOpenLinkRequest(
    HttpClient client,
    Uri url, {
    String method = 'POST',
    String? origin = 'null',
    String? contentType = 'text/plain; charset=utf-8',
    String? host,
    List<int>? bodyBytes,
  }) async {
    final request = await client.openUrl(method, url);
    request.persistentConnection = false;
    if (host != null) {
      request.headers.set(HttpHeaders.hostHeader, host);
    }
    if (origin != null) {
      request.headers.set('origin', origin);
    }
    if (contentType != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
    }
    if (bodyBytes != null) {
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);
    } else if (method == 'POST') {
      request.contentLength = 0;
    }
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    return (status: response.statusCode, body: responseBody);
  }

  test('POST ./open-link opens allowed https/http URLs preserving exact query and fragment', () async {
    final opened = <Uri>[];
    final ack = Completer<bool>();
    var useAck = true;
    final server = GakujoPdfPreviewServer(
      bundle: _ViewerBundle(),
      openExternalLink: (url) async {
        opened.add(url);
        if (useAck) return ack.future;
        return true;
      },
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });

    final indexUrl = await server.start();
    final openLinkUrl = indexUrl.resolve('open-link');
    const targetHttps =
        'https://www.niigata-u.ac.jp/academics/syllabus/?year=2026&course=CS101&lang=%E6%97%A5%E6%9C%AC%E8%AA%9E#section-2';

    var completed = false;
    final pending =
        sendOpenLinkRequest(
          client,
          openLinkUrl,
          origin: 'null',
          bodyBytes: utf8.encode(targetHttps),
        ).then((result) {
          completed = true;
          return result;
        });

    while (opened.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(opened.single.toString(), targetHttps);
    expect(
      opened.single.query,
      'year=2026&course=CS101&lang=%E6%97%A5%E6%9C%AC%E8%AA%9E',
    );
    expect(opened.single.fragment, 'section-2');
    expect(completed, isFalse);

    ack.complete(true);
    final sandboxResult = await pending;
    expect(sandboxResult.status, HttpStatus.noContent);
    expect(sandboxResult.body, isEmpty);

    // Allowed http URL and Apple popup origin (exact loopback viewer origin)
    useAck = false;
    const targetHttp = 'http://example.edu:8080/path/to/doc?a=1&b=2#top';
    final viewerOrigin = 'http://127.0.0.1:${indexUrl.port}';
    final popupResult = await sendOpenLinkRequest(
      client,
      openLinkUrl,
      origin: viewerOrigin,
      bodyBytes: utf8.encode(targetHttp),
    );
    expect(popupResult.status, HttpStatus.noContent);
    expect(popupResult.body, isEmpty);
    expect(opened.map((u) => u.toString()).toList(), [targetHttps, targetHttp]);
  });

  test('open-link rejects dangerous schemes, relative URLs, credentials, controls, spaces, and backslashes', () async {
    final opened = <Uri>[];
    final server = GakujoPdfPreviewServer(
      bundle: _ViewerBundle(),
      openExternalLink: (url) async {
        opened.add(url);
        return true;
      },
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });

    final indexUrl = await server.start();
    final openLinkUrl = indexUrl.resolve('open-link');

    for (final invalid in <String>[
      '',
      'javascript:alert(1)',
      'data:text/html;base64,PHNjcmlwdD4=',
      'file:///etc/passwd',
      'file:///C:/Windows/System32/cmd.exe',
      'mailto:user@example.com',
      'tel:+819012345678',
      'intent://example.com#Intent;scheme=https;end',
      'ftp://ftp.example.com/file.pdf',
      'custom-scheme://open',
      '/relative/path?x=1',
      'relative/path.html',
      '//example.com/protocol-relative',
      'https:///no-host',
      'http://',
      'https://user@example.com/path',
      'https://user:pass@example.com/path',
      'https://example.com/path with space',
      'https://example.com/path\twith\ttab',
      'https://example.com/path\nwith-newline',
      'https://example.com/path\rwith-cr',
      'https://example.com/path\x00with-null',
      'https://example.com/path\x7fwith-del',
      r'https://example.com\evil.com/path',
      r'https://example.com/path\to\file',
      '::::not-a-uri::::',
    ]) {
      final result = await sendOpenLinkRequest(
        client,
        openLinkUrl,
        bodyBytes: utf8.encode(invalid),
      );
      expect(result.status, HttpStatus.badRequest, reason: 'input=$invalid');
    }

    expect(opened, isEmpty);
  });

  test('open-link enforces capability token, method, origin, MIME, query, and max 8192-byte body', () async {
    final opened = <Uri>[];
    final server = GakujoPdfPreviewServer(
      bundle: _ViewerBundle(),
      openExternalLink: (url) async {
        opened.add(url);
        return true;
      },
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() async {
      client.close(force: true);
      await server.close();
    });

    final indexUrl = await server.start();
    final openLinkUrl = indexUrl.resolve('open-link');
    final validBody = utf8.encode('https://example.com/ok');

    // No GET / HEAD access
    expect(
      (await sendOpenLinkRequest(
        client,
        openLinkUrl,
        method: 'GET',
        bodyBytes: null,
      )).status,
      HttpStatus.notFound,
    );
    expect(
      (await sendOpenLinkRequest(
        client,
        openLinkUrl,
        method: 'HEAD',
        bodyBytes: null,
      )).status,
      HttpStatus.notFound,
    );

    // Wrong capability token, extra path segment, query string, or wrong Host
    expect(
      (await sendOpenLinkRequest(
        client,
        indexUrl.replace(path: '/wrong-token/open-link'),
        bodyBytes: validBody,
      )).status,
      HttpStatus.notFound,
    );
    expect(
      (await sendOpenLinkRequest(
        client,
        indexUrl.replace(
          path: '/${indexUrl.pathSegments.first}/open-link/extra',
        ),
        bodyBytes: validBody,
      )).status,
      HttpStatus.notFound,
    );
    expect(
      (await sendOpenLinkRequest(
        client,
        openLinkUrl.replace(query: 'x=1'),
        bodyBytes: validBody,
      )).status,
      HttpStatus.notFound,
    );
    expect(
      (await sendOpenLinkRequest(
        client,
        openLinkUrl,
        host: 'example.com',
        bodyBytes: validBody,
      )).status,
      HttpStatus.notFound,
    );

    // Untrusted or missing Origin headers rejected with 403
    for (final badOrigin in <String?>[
      'https://gakujo.iess.niigata-u.ac.jp',
      'http://127.0.0.1:1',
      'http://localhost:${indexUrl.port}',
      null,
    ]) {
      final result = await sendOpenLinkRequest(
        client,
        openLinkUrl,
        origin: badOrigin,
        bodyBytes: validBody,
      );
      expect(result.status, HttpStatus.forbidden, reason: 'origin=$badOrigin');
    }

    // Non-text/plain MIME types rejected with 403
    for (final badMime in <String?>[
      'application/json',
      'text/html',
      'application/x-www-form-urlencoded',
    ]) {
      final result = await sendOpenLinkRequest(
        client,
        openLinkUrl,
        contentType: badMime,
        bodyBytes: validBody,
      );
      expect(result.status, HttpStatus.forbidden, reason: 'mime=$badMime');
    }

    // Body > 8192 bytes rejected with 413
    final overLimitUrl = 'https://example.com/${'a' * 8180}';
    final overLimitBytes = utf8.encode(overLimitUrl);
    expect(overLimitBytes.length, greaterThan(8192));
    expect(
      (await sendOpenLinkRequest(
        client,
        openLinkUrl,
        bodyBytes: overLimitBytes,
      )).status,
      HttpStatus.requestEntityTooLarge,
    );

    expect(opened, isEmpty);
  });

  test(
    'open-link surfaces launcher false as 503 and launcher exception as 500',
    () async {
      var mode = 'false';
      final opened = <Uri>[];
      final server = GakujoPdfPreviewServer(
        bundle: _ViewerBundle(),
        openExternalLink: (url) async {
          opened.add(url);
          if (mode == 'throw') throw StateError('launcher exception');
          return mode == 'true';
        },
      );
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() async {
        client.close(force: true);
        await server.close();
      });

      final indexUrl = await server.start();
      final openLinkUrl = indexUrl.resolve('open-link');
      final body = utf8.encode('https://example.com/resource');

      // Launcher returning false yields 503 Service Unavailable
      final falseResult = await sendOpenLinkRequest(
        client,
        openLinkUrl,
        bodyBytes: body,
      );
      expect(falseResult.status, HttpStatus.serviceUnavailable);

      // Launcher throwing yields 500 Internal Server Error
      mode = 'throw';
      final errorResult = await sendOpenLinkRequest(
        client,
        openLinkUrl,
        bodyBytes: body,
      );
      expect(errorResult.status, HttpStatus.internalServerError);

      expect(opened.length, 2);
    },
  );
}
