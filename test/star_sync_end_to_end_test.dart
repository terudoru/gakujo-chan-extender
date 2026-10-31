import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_config.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_crypto.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_engine.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_s3_transport.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_transport.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_webdav_transport.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

class _FakeServer {
  _FakeServer(this.s3);

  final bool s3;
  final files = <String, List<int>>{};
  final directories = <String>{};
  late HttpServer server;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  String get endpoint => 'http://127.0.0.1:${server.port}';

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;
    final auth = request.headers.value('authorization');
    if (s3 &&
        (!(auth?.startsWith('AWS4-HMAC-SHA256') ?? false) ||
            request.headers.value('x-amz-content-sha256') == null)) {
      response.statusCode = 403;
    } else if (!s3 && request.method == 'MKCOL') {
      if (!path.endsWith('/')) {
        response.statusCode = 400;
      } else {
        response.statusCode = directories.add(path) ? 201 : 405;
      }
    } else if (!s3 && request.method == 'PROPFIND') {
      if (!path.endsWith('/') || request.headers.value('depth') != '1') {
        response.statusCode = 400;
      } else if (!directories.contains(path)) {
        response.statusCode = 404;
      } else {
        response.statusCode = 207;
        response.write('<D:multistatus xmlns:D="DAV:">');
        for (final entry in files.entries) {
          if (entry.key.startsWith(path) &&
              !entry.key.substring(path.length).contains('/')) {
            response.write(
              '<D:response><D:href>${entry.key}</D:href>'
              '<D:propstat><D:prop><D:getetag>${_etag(entry.value)}</D:getetag>'
              '</D:prop><D:status>HTTP/1.1 200 OK</D:status>'
              '</D:propstat></D:response>',
            );
          }
        }
        response.write('</D:multistatus>');
      }
    } else if (s3 && request.uri.queryParameters['list-type'] == '2') {
      final prefix = request.uri.queryParameters['prefix'] ?? '';
      final delimiter = request.uri.queryParameters['delimiter'];
      if (request.method != 'GET' || delimiter != '/') {
        response.statusCode = 400;
      } else {
        response.write('<ListBucketResult><IsTruncated>false</IsTruncated>');
        for (final entry in files.entries) {
          final key = entry.key.substring('/bucket/'.length);
          if (key.startsWith(prefix) &&
              !key.substring(prefix.length).contains(delimiter!)) {
            response.write(
              '<Contents><Key>$key</Key><ETag>${_etag(entry.value)}</ETag>'
              '<Size>${entry.value.length}</Size></Contents>',
            );
          }
        }
        response.write('</ListBucketResult>');
      }
    } else if (request.method == 'PUT') {
      if (request.headers.value('if-none-match') == '*' &&
          files.containsKey(path)) {
        response.statusCode = 412;
      } else {
        files[path] = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        response.statusCode = 201;
      }
    } else if (request.method == 'GET') {
      final bytes = files[path];
      if (bytes == null) {
        response.statusCode = 404;
      } else {
        response.headers.set('etag', _etag(bytes));
        response.add(bytes);
      }
    } else if (request.method == 'DELETE') {
      response.statusCode = files.remove(path) == null ? 404 : 204;
    } else {
      response.statusCode = 405;
    }
    await response.close();
  }

  String _etag(List<int> bytes) => sha256.convert(bytes).toString();
}

void main() {
  for (final backend in [StarSyncBackend.webDav, StarSyncBackend.s3]) {
    test('${backend.name} syncs stars between two devices', () async {
      final server = _FakeServer(backend == StarSyncBackend.s3);
      await server.start();
      final endpoint = Uri.parse(server.endpoint);
      final config = backend == StarSyncBackend.webDav
          ? StarSyncConfig(
              backend: backend,
              webDav: StarSyncWebDavConfig(
                baseUrl: endpoint,
                username: 'user',
                password: 'password',
              ),
            )
          : StarSyncConfig(
              backend: backend,
              s3: StarSyncS3Config(
                endpoint: endpoint,
                region: 'auto',
                bucket: 'bucket',
                prefix: 'test-prefix',
                accessKeyId: 'access-key',
                secretAccessKey: 'secret-key',
                pathStyle: true,
              ),
            );
      StarSyncTransport transport(StarSyncConfig config) =>
          config.backend == StarSyncBackend.webDav
          ? StarSyncWebDavTransport(config.webDav!)
          : StarSyncS3Transport(config.s3!);

      final storageA = _Storage();
      final storageB = _Storage();
      final activityA = GakujoActivityStore(secureStorage: storageA);
      final activityB = GakujoActivityStore(secureStorage: storageB);
      final a = StarSyncEngine(
        loginId: () => 'student',
        activityStore: activityA,
        secureStorage: storageA,
        transportFactory: transport,
        kdfParams: const StarSyncKdfParams(memoryKiB: 8, iterations: 1),
      );
      final b = StarSyncEngine(
        loginId: () => 'student',
        activityStore: activityB,
        secureStorage: storageB,
        transportFactory: transport,
        kdfParams: const StarSyncKdfParams(memoryKiB: 8, iterations: 1),
      );
      try {
        await a.setUp(config, 'correct horse');
        for (final id in ['3', '4']) {
          await activityA.upsertStarredMessage(
            GakujoStarredMessage(
              keijitype: '1',
              genrecd: '2',
              seqNo: id,
              title: 'Title $id',
              starredAt: DateTime.utc(2026),
            ),
          );
        }
        await a.syncNow();
        await b.setUp(config, 'correct horse');
        expect(
          (await activityB.loadStarredMessages()).map((e) => e.title).toSet(),
          {'Title 3', 'Title 4'},
        );
        await activityA.removeStarredMessage('1|2|3');
        await a.syncNow();
        await b.syncNow();
        expect(
          (await activityB.loadStarredMessages()).map((e) => e.title).toList(),
          ['Title 4'],
        );
      } finally {
        a.dispose();
        b.dispose();
        await server.server.close(force: true);
      }
    });
  }
}
