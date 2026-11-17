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
  for (final method in ['GET', 'POST']) {
    test('$method sends every repeated form value in order', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = _LocalClient(server.port);
      final directory = await Directory.systemTemp.createTemp('mbg-pairs-');
      FlutterSecureStorage.setMockInitialValues({
        'more_better_gakujo_download_root_path': directory.path,
      });
      final received = Completer<String>();
      server.listen((request) async {
        received.complete(method == 'GET'
            ? client.requests.single.query
            : await utf8.decoder.bind(request).join());
        request.response.add([1, 2, 3]);
        await request.response.close();
      });
      try {
        await FileSystemGakujoDownloadService(
          httpClientFactory: () => client,
          usesNativeDownloadRoot: false,
        ).download(
          GakujoDownloadRequest(
            url: 'https://gakujo.iess.niigata-u.ac.jp/file?keep=x&fileId=old',
            method: method, fileName: 'notes.pdf', courseName: '',
            formFields: const {'fileId': 'B'},
            formFieldPairs: const [['fileId', 'A'], ['event', 'download'], ['fileId', 'B']],
          ),
          saveMode: DownloadSaveMode.flatToConfiguredFolder,
        );
        expect(await received.future, method == 'GET'
            ? 'keep=x&fileId=A&event=download&fileId=B'
            : 'fileId=A&event=download&fileId=B');
      } finally {
        client.close(force: true);
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    });
  }

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

  for (final (responseName, extended, displayName) in [
    (null, false, ''),
    ('course-files.zip', false, ''),
    ('bulk11.zip', false, '一括ダウンロード'),
    ('一括資料11.zip', true, '一括ダウンロード'),
    ('一括資料11.zip', true, '一括ダウンロード (3件)'),
    ('bulk-save.zip', false, '一括保存（３件）'),
  ]) {
    test(
        'bulk POST preserves fields and saves ZIP as ${responseName ?? 'document.zip'} (display: $displayName)',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = _LocalClient(server.port);
      final directory =
          await Directory.systemTemp.createTemp('mbg-zip-network-');
      const fields = {
        '_flowId': 'SDW-filerefer-flow',
        'downloadType': 'multi',
        'fileId': '41881,41882',
      };
      final zipBytes = [0x50, 0x4b, 0x05, 0x06, ...List.filled(18, 0)];
      final methods = <String>[];
      final bodies = <String>[];
      final contentTypes = <String?>[];
      FlutterSecureStorage.setMockInitialValues({
        'more_better_gakujo_download_root_path': directory.path,
      });
      server.listen((request) async {
        methods.add(request.method);
        bodies.add(await utf8.decoder.bind(request).join());
        contentTypes.add(request.headers.contentType?.mimeType);
        request.response.headers.contentType =
            ContentType('application', 'zip');
        if (responseName != null) {
          final disposition = extended
              ? 'attachment; filename="fallback.zip"; '
                  "filename*=UTF-8''${Uri.encodeComponent(responseName)}"
              : 'attachment; filename="$responseName"';
          request.response.headers
              .set(HttpHeaders.contentDisposition, disposition);
        }
        request.response.add(zipBytes);
        await request.response.close();
      });
      try {
        final result = await FileSystemGakujoDownloadService(
          httpClientFactory: () => client,
          usesNativeDownloadRoot: false,
        ).download(
          GakujoDownloadRequest.fromJsonText(jsonEncode({
            'url':
                'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
            'method': 'POST',
            'fileName': displayName,
            'courseName': '未分類',
            'courseNameAmbiguous': true,
            'formFields': fields,
          })),
          saveMode: DownloadSaveMode.autoSortToConfiguredFolder,
        );
        expect(methods, ['POST']);
        expect(Uri.splitQueryString(bodies.single), fields);
        expect(contentTypes, ['application/x-www-form-urlencoded']);
        final saved = File(result.location!);
        expect(result.courseName, '未分類');
        expect(saved.uri.pathSegments.last, responseName ?? 'document.zip');
        expect(await saved.readAsBytes(), zipBytes);
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
