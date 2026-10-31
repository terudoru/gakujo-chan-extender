import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_webdav_transport.dart';

void main() {
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
  for (final prefixed in [true, false]) {
    test(
      'WebDAV operations and ${prefixed ? 'prefixed' : 'default'} DAV namespace',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final files = <String, List<int>>{};
        final base = 'http://127.0.0.1:${server.port}/base';
        final subscription = server.listen((request) async {
          final path = request.uri.path;
          if (request.headers.value('authorization') !=
              'Basic ${base64Encode(utf8.encode('u:p'))}') {
            request.response.statusCode = 401;
          } else if (request.method == 'MKCOL') {
            expect(path, endsWith('/'));
            request.response.statusCode = 405;
          } else if (request.method == 'PROPFIND') {
            expect(path, endsWith('/'));
            expect(request.headers.value('depth'), '1');
            final p = prefixed ? 'D:' : '';
            final ns = prefixed ? 'xmlns:D="DAV:"' : 'xmlns="DAV:"';
            request.response.statusCode = 207;
            request.response.write(
              '<${p}multistatus $ns><${p}response><${p}href>$base/stars/</${p}href></${p}response><${p}response><${p}href>$base/stars/a%20b</${p}href><${p}propstat><${p}prop><${p}getetag>W/&quot;v1&quot;</${p}getetag><${p}getcontentlength>3</${p}getcontentlength><${p}resourcetype/></${p}prop><${p}status>HTTP/1.1 200 OK</${p}status></${p}propstat></${p}response></${p}multistatus>',
            );
          } else if (request.method == 'PUT') {
            expect(request.headers.value('transfer-encoding'), isNull);
            expect(request.headers.contentLength, anyOf(0, 2));
            if (request.headers.value('if-none-match') == '*' &&
                files.containsKey(path)) {
              request.response.statusCode = 412;
            } else {
              files[path] = await request.fold<List<int>>(
                [],
                (a, b) => a..addAll(b),
              );
              request.response.statusCode = 201;
            }
          } else if (request.method == 'GET') {
            final data = files[path];
            if (data == null) {
              request.response.statusCode = 404;
            } else {
              request.response.add(data);
            }
          } else if (request.method == 'DELETE') {
            request.response.statusCode = files.remove(path) == null
                ? 404
                : 204;
          }
          await request.response.close();
        });
        final transport = StarSyncWebDavTransport(
          StarSyncWebDavConfig(
            baseUrl: Uri.parse(base),
            username: 'u',
            password: 'p',
          ),
        );
        try {
          await transport.ensureDirectory('stars/devices');
          final entries = await transport.list('stars');
          expect(entries.single.path, 'stars/a b');
          expect(entries.single.etag, 'v1');
          expect(entries.single.size, 3);
          expect(await transport.get('stars/missing'), isNull);
          await transport.put('stars/file', [1, 2], createOnly: true);
          expect((await transport.get('stars/file'))!.bytes, [1, 2]);
          await expectLater(
            transport.put('stars/file', [], createOnly: true),
            throwsA(
              isA<StarSyncTransportException>().having(
                (e) => e.kind,
                'kind',
                StarSyncTransportErrorKind.alreadyExists,
              ),
            ),
          );
          await transport.delete('stars/file');
          await transport.delete('stars/file');
          final bad = StarSyncWebDavTransport(
            StarSyncWebDavConfig(
              baseUrl: Uri.parse(base),
              username: 'bad',
              password: 'p',
            ),
          );
          try {
            await expectLater(
              bad.get('stars/file'),
              throwsA(
                isA<StarSyncTransportException>().having(
                  (e) => e.kind,
                  'kind',
                  StarSyncTransportErrorKind.auth,
                ),
              ),
            );
          } finally {
            bad.close();
          }
        } finally {
          transport.close();
          await subscription.cancel();
          await server.close(force: true);
        }
      },
    );
  }
}
