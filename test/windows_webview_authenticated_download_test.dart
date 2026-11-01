import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:morebettergakujo_flutter/src/file_system_gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:morebettergakujo_flutter/src/windows_webview_authenticated_download.dart';
import 'package:test/test.dart';

void main() {
  test('does not expose captured form values to a navigated external page',
      () async {
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/file',
      method: 'POST',
      fileName: 'attachment.pdf',
      courseName: '',
      formFields: {'session': 'synthetic-only'},
    );
    final result = await Process.run('node', [
      'test/support/windows_webview_authenticated_download_inline_0.cts',
      WindowsWebViewAuthenticatedDownloadScript.start(
        requestId: 'foreign',
        request: request,
      ),
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('an HTML timeout redirect is rejected by Dart and Windows JavaScript',
      () async {
    const id = 'expired-session';
    const finalUrl = 'https://gakujo.iess.niigata-u.ac.jp/'
        'campusweb/theme/default/Timeout.html';
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/file',
      method: 'GET',
      fileName: 'attachment.pdf',
      courseName: '',
      formFields: {},
    );
    final downloaded = AuthenticatedDownloadedFile(
      bytes: Uint8List.fromList(utf8.encode('<html>')),
      finalUrl: finalUrl,
      mimeType: 'text/html',
    );
    await expectLater(
      downloaded.validateResponse(request.fileName, requestUrl: request.url),
      throwsA(isA<PlatformException>()
          .having((error) => error.code, 'code', 'download_failed')),
    );
    final result = await Process.run(
        'node',
        [
          'test/support/windows_webview_authenticated_download_web_view_download_harness.cts',
          WindowsWebViewAuthenticatedDownloadScript.start(
              requestId: id, request: request),
          WindowsWebViewAuthenticatedDownloadScript.poll(id),
          WindowsWebViewAuthenticatedDownloadScript.cleanup(id),
          'Text/HTML; charset=UTF-8',
          '<html>',
          '',
          finalUrl,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final behavior =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(behavior['state'], 'error');
    expect(behavior['code'], 'page_response');
    expect(
        behavior['message'], 'ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください');
    expect(behavior['bodyBase64'], isEmpty);
    expect(behavior['afterCleanup'], isNull);
  });

  for (final (name, mimeType, body, disposition, rejected) in [
    ('attachment.pdf', 'text/html', '%PDF-1.7', '', false),
    ('notes.txt', 'text/plain', '<html> is an HTML tag', '', false),
    (
      'attachment.pdf',
      'application/pdf',
      '<html>session expired</html>',
      '',
      true
    ),
    ('notes.csv', 'Text/CSV; charset=UTF-8', '<html>,is a tag', '', false),
    (
      'Download',
      'text/html',
      '<html>attachment</html>',
      'attachment; filename="page.HTM"',
      false,
    ),
    (
      'Download',
      'text/html',
      '<html>attachment</html>',
      "attachment; filename*=UTF-8''page%2Ehtm",
      false,
    ),
    ('page.HTML', 'text/html', '<html>attachment</html>', '', false),
    (
      'Download',
      'application/octet-stream',
      '\uFEFF \n<HtMl>login</HtMl>',
      '',
      true,
    ),
    (
      '',
      'application/xhtml+xml',
      '<!DoCtYpE hTmL><html>login</html>',
      '',
      true
    ),
    ('attachment.pdf', '', '<html lang="en">login</html>', '', true),
    ('attachment.pdf', 'text/html', '<htmlish>literal bytes', '', false),
    (
      'attachment.pdf',
      'text/html',
      '<!doctype htmlish>literal bytes',
      '',
      false
    ),
    ('attachment.pdf', 'text/html', '<html', '', false),
    (
      'attachment.pdf',
      'text/html',
      '\uFEFF\uFEFF<html>literal</html>',
      '',
      false
    ),
  ]) {
    test('Windows page policy: $name / $mimeType / $body / $disposition',
        () async {
      const id = 'response-policy';
      final request = GakujoDownloadRequest(
        url: 'https://gakujo.iess.niigata-u.ac.jp/file',
        method: 'GET',
        fileName: name,
        courseName: '',
        formFields: const {},
      );
      final result = await Process.run(
        'node',
        [
          'test/support/windows_webview_authenticated_download_web_view_download_harness.cts',
          WindowsWebViewAuthenticatedDownloadScript.start(
              requestId: id, request: request),
          WindowsWebViewAuthenticatedDownloadScript.poll(id),
          WindowsWebViewAuthenticatedDownloadScript.cleanup(id),
          mimeType,
          body,
          disposition,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final behavior =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(behavior['state'], rejected ? 'error' : 'done');
      if (rejected) {
        expect(behavior['code'], 'page_response');
        expect(behavior['bodyBase64'], isEmpty);
      } else {
        expect(behavior['bodyBase64'], base64Encode(utf8.encode(body)));
      }
      expect(behavior['afterCleanup'], isNull);
    });
  }

  test('Windows exempts the request URL HTML path, excluding its query',
      () async {
    const id = 'html-url';
    const body = '<html>attachment</html>';
    for (final (path, rejected) in [
      ('page.HTML?download=1', false),
      ('page.HtM', false),
      ('file?name=page.html', true),
    ]) {
      final request = GakujoDownloadRequest(
        url: 'https://gakujo.iess.niigata-u.ac.jp/$path',
        method: 'GET',
        fileName: 'Download',
        courseName: '',
        formFields: const {},
      );
      final result = await Process.run(
        'node',
        [
          'test/support/windows_webview_authenticated_download_web_view_download_harness.cts',
          WindowsWebViewAuthenticatedDownloadScript.start(
              requestId: id, request: request),
          WindowsWebViewAuthenticatedDownloadScript.poll(id),
          WindowsWebViewAuthenticatedDownloadScript.cleanup(id),
          'application/pdf',
          body,
          '',
          'https://gakujo.iess.niigata-u.ac.jp/redirected-file',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final behavior =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(behavior['state'], rejected ? 'error' : 'done', reason: path);
      expect(behavior['bodyBase64'],
          rejected ? '' : base64Encode(utf8.encode(body)));
      if (rejected) expect(behavior['code'], 'page_response');
      expect(behavior['afterCleanup'], isNull);
    }
  });

  test('large responses use bounded messages and pause for the receiver',
      () async {
    const requestId = 'large-download';
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/file',
      method: 'GET',
      fileName: 'fixture.bin',
      courseName: '',
      formFields: {},
    );
    final result = await Process.run(
        'node',
        [
          'test/support/windows_webview_authenticated_download_large_download_harness.cts',
          WindowsWebViewAuthenticatedDownloadScript.start(
              requestId: requestId, request: request),
          WindowsWebViewAuthenticatedDownloadScript.poll(requestId),
          WindowsWebViewAuthenticatedDownloadScript.cleanup(requestId),
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final behavior =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(behavior['receivedBytes'], 8 * 1024 * 1024 + 13);
    expect(behavior['validBytes'], isTrue);
    expect(behavior['maximumMessageBytes'], lessThan(400 * 1024));
    expect(behavior['readBeforePolling'], lessThanOrEqualTo(2 * 1024 * 1024));
    expect(behavior['afterCleanup'], isNull);
  });

  test('cleanup aborts a pending fetch and discards a late result', () async {
    const requestId = 'cancelled-download';
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/file',
      method: 'GET',
      fileName: 'fixture.pdf',
      courseName: '',
      formFields: {},
    );
    final result = await Process.run(
        'node',
        [
          'test/support/windows_webview_authenticated_download_cancellation_harness.cts',
          WindowsWebViewAuthenticatedDownloadScript.start(
              requestId: requestId, request: request),
          WindowsWebViewAuthenticatedDownloadScript.poll(requestId),
          WindowsWebViewAuthenticatedDownloadScript.cleanup(requestId),
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final behavior =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(behavior['aborted'], isTrue);
    expect(behavior['afterCleanup'], isNull);
    expect(behavior['restarted'], isTrue);
    expect(behavior['lateResultIgnored'], isTrue);
  });

  test('starts fetch synchronously and exposes its result through polling',
      () async {
    const requestId = 'download-1';
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
          'campussquare.do?_flowId=SDW-filerefer-flow&fileId=41475',
      method: 'GET',
      courseName: '',
      fileName: '大学等への修学支援の措置に係る学修計画書.docx',
      formFields: {},
    );
    final result = await Process.run(
      'node',
      [
        'test/support/windows_webview_authenticated_download_web_view_download_harness.cts',
        WindowsWebViewAuthenticatedDownloadScript.start(
          requestId: requestId,
          request: request,
        ),
        WindowsWebViewAuthenticatedDownloadScript.poll(requestId),
        WindowsWebViewAuthenticatedDownloadScript.cleanup(requestId),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    expect(
      result.exitCode,
      0,
      reason: 'Node JavaScript evaluation failed: ${result.stderr}',
    );
    final behavior =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(behavior['started'], isTrue);
    expect(behavior['requestedUrl'], request.url);
    expect(behavior['requestMethod'], 'GET');
    expect(behavior['credentials'], 'include');
    expect(behavior['redirect'], 'error');
    expect(behavior['state'], 'done');
    expect(behavior['status'], 200);
    expect(behavior['bodyBase64'], 'AQID');
    expect(
        behavior['contentDisposition'], 'attachment; filename=internal.docx');
    expect(behavior['afterCleanup'], isNull);
  });
}
