import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
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
