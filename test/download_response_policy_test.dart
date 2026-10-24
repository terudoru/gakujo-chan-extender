import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:morebettergakujo_flutter/src/download_response_policy.dart';
import 'package:test/test.dart';

void main() {
  for (final (mimeType, body) in [
    (' Text/HTML ; charset=UTF-8', 'login required'),
    ('application/pdf', '\uFEFF \r\n<!DoCtYpE hTmL><html>expired</html>'),
    ('application/octet-stream', '\t<HtMl>login</HtMl>'),
    (null, '<html>error</html>'),
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
