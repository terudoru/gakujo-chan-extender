import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:morebettergakujo_flutter/src/download_response_policy.dart';
import 'package:test/test.dart';

void main() {
  for (final (mimeType, body) in [
    (' Text/HTML ; charset=UTF-8', '<html>login required</html>'),
    ('application/xhtml+xml', '\uFEFF \r\n<!DoCtYpE hTmL><html>expired</html>'),
    ('application/octet-stream', '\t<HtMl>login</HtMl>'),
    ('application/pdf', '<html>session expired</html>'),
    (null, '<html>error</html>'),
    ('', '<html lang="en">error</html>'),
    ('text/html', '<html/>'),
  ]) {
    test('rejects a non-HTML attachment containing a page: $mimeType', () {
      expect(
        () => DownloadResponsePolicy.validate(
          fileName: 'attachment.pdf',
          mimeType: mimeType,
          prefix: utf8.encode(body),
        ),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'download_failed')
            .having((error) => error.message, 'message',
                'ファイルではなくページが返されました。ログインし直してから、もう一度ダウンロードしてください')),
      );
    });
  }

  for (final (mimeType, body) in [
    ('text/html', '%PDF-1.7'),
    ('application/xhtml+xml', '%PDF-1.7'),
    ('text/html', 'login required'),
    ('text/plain', '<html> is an HTML tag'),
    (' Text/CSV ; charset=UTF-8', '<html>,is an HTML tag'),
    ('application/octet-stream', '<htmlish>literal bytes'),
    ('text/html', '<!doctype htmlish>literal bytes'),
    ('text/html', '<html'),
    ('text/html', '\uFEFF\uFEFF<html>literal bytes</html>'),
  ]) {
    test('preserves non-HTML text and non-page bytes: $mimeType / $body', () {
      DownloadResponsePolicy.validate(
        fileName: 'attachment.pdf',
        mimeType: mimeType,
        prefix: utf8.encode(body),
      );
    });
  }

  test('a generic label allows a Content-Disposition HTML attachment', () {
    for (final name in ['page.HTML', 'page.HtM']) {
      DownloadResponsePolicy.validate(
        fileName: 'Download',
        contentDispositionFileName: name,
        mimeType: 'text/html',
        prefix: utf8.encode('<html>attachment</html>'),
      );
    }
  });

  test('HTML URL paths are exempt but HTML names in queries are not', () {
    for (final path in ['page.HTML?download=1', 'page.HtM#content']) {
      DownloadResponsePolicy.validate(
        fileName: 'Download',
        finalUrl: 'https://gakujo.iess.niigata-u.ac.jp/$path',
        mimeType: 'application/pdf',
        prefix: utf8.encode('<html>attachment</html>'),
      );
    }
    expect(
      () => DownloadResponsePolicy.validate(
        fileName: 'Download',
        finalUrl: 'https://gakujo.iess.niigata-u.ac.jp/file?name=page.html',
        mimeType: 'text/html',
        prefix: utf8.encode('<html>session expired</html>'),
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  test('allows explicit HTML attachments and ordinary file bytes', () {
    for (final name in ['page.HTML', 'page.HtM']) {
      DownloadResponsePolicy.validate(
        fileName: name,
        mimeType: 'text/html',
        prefix: utf8.encode('<html>attachment</html>'),
      );
    }
    for (final body in ['%PDF-1.7', 'Use <html> in your document', '']) {
      DownloadResponsePolicy.validate(
        fileName: 'notes.txt',
        mimeType: 'text/plain',
        prefix: utf8.encode(body),
      );
    }
    DownloadResponsePolicy.validate(
      fileName: 'data.bin',
      prefix: [0xff, 0x00, 0x80, 0x01],
    );
  });
}
