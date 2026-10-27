import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  test('does not contact remote UNC locations or file URI hosts', () async {
    final messages = <String>[];
    var calls = 0;
    for (final location in [r'\\untrusted.example\share\file.pdf', 'file://untrusted.example/share/file.pdf']) {
      await openGakujoSavedDownload(
        location,
        platform: TargetPlatform.windows,
        openNative: (_) async { calls++; return true; },
        openExternal: (_) async { calls++; return true; },
        showSnackBar: messages.add,
      );
    }
    expect(calls, 0);
    expect(messages, List.filled(2, 'ネットワーク上の保存先は開けません'));
  });

  test('missing files and launcher errors show the open-failure message',
      () async {
    final directory = Directory.systemTemp.createTempSync('saved_download_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/report.pdf')..writeAsStringSync('pdf');
    final messages = <String>[];
    var launchCalls = 0;
    Future<void> open(String location, Future<bool> Function(Uri) launch) =>
        openGakujoSavedDownload(
          location,
          platform: TargetPlatform.windows,
          openNative: (_) async => throw StateError('unexpected native open'),
          openExternal: (uri) {
            launchCalls += 1;
            return launch(uri);
          },
          showSnackBar: messages.add,
        );

    await open(file.path, (_) async => true);
    expect(messages, isEmpty);
    expect(launchCalls, 1);

    file.deleteSync();
    for (final location in [file.path, file.uri.toString()]) {
      await open(location, (_) async => true);
    }
    expect(launchCalls, 1, reason: 'missing files must not reach the launcher');
    expect(messages, List.filled(2, 'ファイルを開けませんでした'));

    file.writeAsStringSync('pdf');
    for (final error in [
      PlatformException(code: 'open_failed'),
      StateError('file moved after the existence check'),
    ]) {
      await open(file.path, (_) async => throw error);
    }
    await open(file.path, (_) async => false);
    expect(launchCalls, 4);
    expect(messages, List.filled(5, 'ファイルを開けませんでした'));
  });

  test('converts Windows drive paths to file uris', () {
    final uri = savedDownloadLocationUri(r'C:\Users\student\Downloads\資料.pdf');

    expect(uri.scheme, 'file');
    expect(uri.toString(),
        'file:///C:/Users/student/Downloads/%E8%B3%87%E6%96%99.pdf');
  });

  test('keeps Android content locations as content uris', () {
    final uri = savedDownloadLocationUri('content://downloads/report.pdf');

    expect(uri.scheme, 'content');
    expect(uri.toString(), 'content://downloads/report.pdf');
  });

  test('treats unknown schemes as local file paths', () {
    final uri = savedDownloadLocationUri('javascript:alert(1)');

    expect(uri.scheme, 'file');
  });

  test('opens Android content uris through the native read grant', () {
    final content = savedDownloadLocationUri(
      'content://com.android.externalstorage.documents/document/primary%3Ax.pdf',
    );
    final file = savedDownloadLocationUri('/tmp/x.pdf');

    expect(opensSavedDownloadNatively(content, TargetPlatform.android), isTrue);
    expect(opensSavedDownloadNatively(file, TargetPlatform.android), isFalse);
    expect(opensSavedDownloadNatively(content, TargetPlatform.iOS), isFalse);
  });

  test('opens saved iOS and macOS files natively', () {
    final file = savedDownloadLocationUri('/private/var/mobile/x.pdf');

    expect(opensSavedDownloadNatively(file, TargetPlatform.iOS), isTrue);
    expect(
      opensSavedDownloadNatively(file, TargetPlatform.macOS),
      isTrue,
      reason: 'macOS needs the download folder security scope while opening.',
    );
  });
}
