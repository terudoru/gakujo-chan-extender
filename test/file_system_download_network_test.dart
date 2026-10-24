import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/file_system_gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:test/test.dart';

void main() {
  for (final mimeType in ['text/html', 'application/octet-stream']) {
    test('HTTP 200 page responses fail without saving: $mimeType', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = _LocalClient(server.port);
      final directory =
          await Directory.systemTemp.createTemp('mbg-page-network-');
      FlutterSecureStorage.setMockInitialValues({
        'more_better_gakujo_download_root_path': directory.path,
      });
      server.listen((request) async {
        request.response.headers.set(HttpHeaders.contentTypeHeader, mimeType);
        // write() would encode as Latin-1 and cannot carry the BOM.
        request.response
            .add(utf8.encode('\uFEFF \r\n<HtMl>session expired</HtMl>'));
        await request.response.close();
      });
      try {
        await expectLater(
          FileSystemGakujoDownloadService(
            httpClientFactory: () => client,
            usesNativeDownloadRoot: false,
          ).download(
            const GakujoDownloadRequest(
              url: 'https://gakujo.iess.niigata-u.ac.jp/attachment.pdf',
              method: 'GET',
              fileName: 'attachment.pdf',
              courseName: '',
              formFields: {},
            ),
            saveMode: DownloadSaveMode.flatToConfiguredFolder,
          ),
          throwsA(isA<PlatformException>().having((error) => error.message,
              'message', 'ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください')),
        );
        expect(await directory.list().toList(), isEmpty);
        expect(client.closed, isTrue);
      } finally {
        client.close(force: true);
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    });
  }

  test('a completed POST redirect saves the downloaded bytes using GET',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = _LocalClient(server.port);
    final directory = await Directory.systemTemp.createTemp('mbg-network-');
    final methods = <String>[];
    final bodies = <String>[];
    FlutterSecureStorage.setMockInitialValues({
      'more_better_gakujo_download_root_path': directory.path,
    });
    server.listen((request) async {
      methods.add(request.method);
      bodies.add(await utf8.decoder.bind(request).join());
      if (request.uri.path == '/start') {
        request.response.statusCode = HttpStatus.seeOther;
        request.response.headers.set(HttpHeaders.locationHeader, '/file.pdf');
        request.response.write('redirecting');
      } else {
        request.response.headers.contentType =
            ContentType('application', 'pdf');
        request.response.add([1, 2, 3, 255]);
      }
      await request.response.close();
    });
    try {
      final result = await FileSystemGakujoDownloadService(
        httpClientFactory: () => client,
        usesNativeDownloadRoot: false,
      ).download(
        const GakujoDownloadRequest(
            url: 'https://gakujo.iess.niigata-u.ac.jp/start',
            method: 'POST',
            fileName: 'file.pdf',
            courseName: '',
            formFields: {'id': 'fixture'}),
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );
      expect(methods, ['POST', 'GET']);
      expect(bodies, ['id=fixture', '']);
      expect(await File(result.location!).readAsBytes(), [1, 2, 3, 255]);
      expect(client.closed, isTrue);
    } finally {
      client.close(force: true);
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('a stalled redirect body times out and closes its client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = _LocalClient(server.port);
    final started = Completer<void>();
    server.listen((request) async {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader, '/file.pdf');
      request.response.write('redirecting');
      await request.response.flush();
      started.complete();
    });
    try {
      final downloading = FileSystemGakujoDownloadService(
        httpClientFactory: () => client,
        requestTimeout: const Duration(milliseconds: 300),
      ).download(
        const GakujoDownloadRequest(
            url: 'https://gakujo.iess.niigata-u.ac.jp/start',
            method: 'GET',
            fileName: 'file.pdf',
            courseName: '',
            formFields: {}),
        saveMode: DownloadSaveMode.flatToConfiguredFolder,
      );
      final failed = expectLater(
          downloading.timeout(const Duration(seconds: 2)),
          throwsA(isA<PlatformException>().having((error) => error.message,
              'reason', contains('TimeoutException'))));
      await started.future.timeout(const Duration(seconds: 2));
      await failed;
      expect(client.closed, isTrue);
      expect(client.requests, hasLength(1));
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });
}

class _LocalClient implements HttpClient {
  _LocalClient(this.port);
  final int port;
  final HttpClient inner = HttpClient();
  final List<Uri> requests = [];
  bool closed = false;

  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    requests.add(url);
    return inner.openUrl(
        method, Uri.parse('http://127.0.0.1:$port${url.path}'));
  }

  @override
  void close({bool force = false}) {
    closed = true;
    inner.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
