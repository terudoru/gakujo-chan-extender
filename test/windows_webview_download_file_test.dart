import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/file_system_gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/windows_webview_authenticated_download.dart';
import 'package:test/test.dart';

const _request = GakujoDownloadRequest(
  url: 'https://gakujo.iess.niigata-u.ac.jp/file',
  method: 'GET',
  fileName: 'large.bin',
  courseName: '',
  formFields: {},
);

void main() {
  test(
      'Windows page errors preserve the exact message and remove scratch files',
      () async {
    final root = await Directory.systemTemp.createTemp('mbg-page-error-');
    var cleaned = false;
    try {
      await expectLater(
        receiveWindowsWebViewDownload(
          request: _request,
          temporaryRoot: root,
          start: () async {},
          readState: () async => jsonEncode({
            'state': 'error',
            'code': 'page_response',
            'message': 'ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください',
          }),
          cleanup: () async {
            cleaned = true;
          },
        ),
        throwsA(isA<PlatformException>().having((error) => error.message,
            'message', 'ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください')),
      );
      expect(cleaned, isTrue);
      expect(await root.list().toList(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });

  for (final (name, mimeType, body, rejected) in [
    ('attachment.pdf', 'text/html; charset=UTF-8', 'login required', true),
    (
      'attachment.pdf',
      'application/pdf',
      '\uFEFF \n<!DoCtYpE hTmL><html>expired</html>',
      true,
    ),
    ('attachment.pdf', '', '\t<HtMl>login</HtMl>', true),
    ('attachment.HTML', 'text/html', '<html>attachment</html>', false),
    ('', 'text/html', '<html>attachment</html>', false),
  ]) {
    test(
        'Windows validates pages and cleans temporary files: $name / $mimeType',
        () async {
      final root = await Directory.systemTemp.createTemp('mbg-page-webview-');
      final bytes = utf8.encode(body);
      final states = [
        jsonEncode({
          'state': 'chunk',
          'index': 0,
          'bodyBase64': base64Encode(bytes.sublist(0, 2)),
        }),
        jsonEncode({
          'state': 'chunk',
          'index': 1,
          'bodyBase64': base64Encode(bytes.sublist(2)),
        }),
        jsonEncode({
          'state': 'done',
          'payload': {
            'status': 200,
            'ok': true,
            'mimeType': mimeType,
            'contentDisposition': 'attachment; filename=page.HTM',
            'bodyByteLength': bytes.length,
            'chunkCount': 2,
          },
        }),
      ];
      var cleaned = false;
      try {
        final downloading = receiveWindowsWebViewDownload(
          request: GakujoDownloadRequest(
            url: _request.url,
            method: 'GET',
            fileName: name,
            courseName: '',
            formFields: {},
          ),
          temporaryRoot: root,
          start: () async {},
          readState: () async => states.removeAt(0),
          cleanup: () async {
            cleaned = true;
          },
        );
        if (rejected) {
          await expectLater(
              downloading,
              throwsA(isA<PlatformException>()
                  .having((error) => error.code, 'code', 'download_failed')
                  .having((error) => error.message, 'message',
                      'ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください')));
        } else {
          final downloaded = await downloading;
          expect(await downloaded.readBytes(), bytes);
          await downloaded.dispose();
        }
        expect(cleaned, isTrue);
        expect(await root.list().toList(), isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    });
  }

  test('streams the JavaScript response through Dart to a saved file',
      () async {
    final root = await Directory.systemTemp.createTemp('mbg-stream-test-');
    final scratch = await Directory('${root.path}/scratch').create();
    final destination = await Directory('${root.path}/saved').create();
    FlutterSecureStorage.setMockInitialValues({
      'more_better_gakujo_download_root_path': destination.path,
    });
    final bridge = await _Bridge.create();
    try {
      final service = FileSystemGakujoDownloadService(
        usesNativeDownloadRoot: false,
        authenticatedBytesLoader: (request, {userAgent}) =>
            receiveWindowsWebViewDownload(
          request: request,
          temporaryRoot: scratch,
          start: () async {
            expect(await bridge.exchange('start'), 'true');
          },
          readState: () => bridge.exchange('poll'),
          cleanup: () async {
            expect(await bridge.exchange('cleanup'), 'true');
          },
        ),
      );
      final result = await service.download(_request,
          saveMode: DownloadSaveMode.flatToConfiguredFolder);
      final file = File(result.location!);
      expect(await file.length(), 8 * 1024 * 1024 + 13);
      var offset = 0;
      var valid = true;
      await for (final chunk in file.openRead()) {
        for (var index = 0; index < chunk.length; index++) {
          if (chunk[index] != (offset + index) % 251) valid = false;
        }
        offset += chunk.length;
      }
      expect(valid, isTrue);
      expect(await scratch.list().toList(), isEmpty);
      expect(await bridge.exchange('poll'), 'null');
    } finally {
      await bridge.close();
      await root.delete(recursive: true);
    }
  });

  for (final badState in [
    {
      'state': 'done',
      'payload': {'status': 200, 'ok': true}
    },
    {
      'state': 'done',
      'payload': {'status': 200, 'ok': true, 'bodyBase64': 'AQID'}
    },
    {'state': 'chunk', 'index': 2, 'bodyBase64': 'BAUG'},
    {
      'state': 'done',
      'payload': {
        'status': 200,
        'ok': true,
        'bodyByteLength': 8,
        'chunkCount': 1
      }
    },
    {'state': 'error', 'message': 'network disconnected'},
  ]) {
    test('incomplete download removes its temporary file: $badState', () async {
      final root = await Directory.systemTemp.createTemp('mbg-stream-failure-');
      var cleaned = false;
      final states = [
        jsonEncode({'state': 'chunk', 'index': 0, 'bodyBase64': 'AQID'}),
        jsonEncode(badState),
      ];
      try {
        await expectLater(
            receiveWindowsWebViewDownload(
              request: _request,
              temporaryRoot: root,
              start: () async {},
              readState: () async => states.removeAt(0),
              cleanup: () async {
                cleaned = true;
              },
            ),
            throwsA(anyOf(isFormatException, isA<PlatformException>())));
        expect(cleaned, isTrue);
        expect(await root.list().toList(), isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    });
  }

  test('a destination failure still removes the completed temporary file',
      () async {
    final root = await Directory.systemTemp.createTemp('mbg-save-failure-');
    FlutterSecureStorage.setMockInitialValues({
      'more_better_gakujo_download_root_path': '${root.path}/missing',
    });
    try {
      final states = [
        '{"state":"chunk","index":0,"bodyBase64":"AQID"}',
        '{"state":"done","payload":{"status":200,"ok":true,"bodyByteLength":3,"chunkCount":1}}',
      ];
      final service = FileSystemGakujoDownloadService(
        usesNativeDownloadRoot: false,
        authenticatedBytesLoader: (request, {userAgent}) =>
            receiveWindowsWebViewDownload(
          request: request,
          temporaryRoot: root,
          start: () async {},
          readState: () async => states.removeAt(0),
          cleanup: () async {},
        ),
      );
      await expectLater(
          service.download(_request,
              saveMode: DownloadSaveMode.flatToConfiguredFolder),
          throwsA(isA<PlatformException>()));
      expect(await root.list().toList(), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
}

class _Bridge {
  _Bridge(this.process)
      : lines = StreamIterator(process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())),
        errors = process.stderr.transform(utf8.decoder).join();
  final Process process;
  final StreamIterator<String> lines;
  final Future<String> errors;
  static Future<_Bridge> create() async {
    const id = 'file-fixture';
    return _Bridge(await Process.start('node', [
      '-e',
      _bridgeScript,
      WindowsWebViewAuthenticatedDownloadScript.start(
          requestId: id, request: _request),
      WindowsWebViewAuthenticatedDownloadScript.poll(id),
      WindowsWebViewAuthenticatedDownloadScript.cleanup(id),
    ]));
  }

  Future<String> exchange(String command) async {
    process.stdin.writeln(command);
    if (!await lines.moveNext().timeout(const Duration(seconds: 3))) {
      throw StateError('JavaScript bridge closed unexpectedly');
    }
    return lines.current;
  }

  Future<void> close() async {
    await process.stdin.close();
    await lines.cancel();
    final exitCode = await process.exitCode.timeout(const Duration(seconds: 3),
        onTimeout: () {
      process.kill();
      return -1;
    });
    expect(exitCode, 0, reason: await errors);
  }
}

const _bridgeScript = r'''
const vm=require('node:vm'), readline=require('node:readline');
const [start,poll,cleanup]=process.argv.slice(1);
const length=8*1024*1024+13;
const context=vm.createContext({
  window:{location:{href:'https://gakujo.iess.niigata-u.ac.jp/'}},
  URL, URLSearchParams, Uint8Array, AbortController,
  fetch:async url=>({url,ok:true,status:200,headers:{get:()=>''},
    body:{getReader(){let offset=0;return {
      async read(){
        if(offset===length)return {done:true};
        const bytes=new Uint8Array(Math.min(65537,length-offset));
        for(let i=0;i<bytes.length;i++)bytes[i]=(offset+i)%251;
        offset+=bytes.length;return {value:bytes,done:false};
      },releaseLock(){}
    };}}
  }),btoa:binary=>Buffer.from(binary,'binary').toString('base64')
});
readline.createInterface({input:process.stdin}).on('line',command=>{
  const script={start,poll,cleanup}[command];
  process.stdout.write(String(vm.runInContext(script,context))+'\n');
});
''';
