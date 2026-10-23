import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  test('labels an Android document in primary storage', () {
    const location = 'content://com.android.externalstorage.documents/'
        'tree/primary%3ADocuments/document/primary%3ADocuments%2F'
        '%E3%83%97%E3%83%AD%E3%82%B0%E3%83%A9%E3%83%9F%E3%83%B3'
        '%E3%82%B0%E5%9F%BA%E7%A4%8E%E2%85%A0%2F02.pdf';

    expect(gakujoDownloadLocationLabel(location),
        '内部ストレージ/Documents/プログラミング基礎Ⅰ/02.pdf');
  });

  test('keeps a non-primary volume id in the label', () {
    const location = 'content://com.android.externalstorage.documents/'
        'tree/ABCD-1234%3A/document/ABCD-1234%3ALectures%2F02.pdf';

    expect(gakujoDownloadLocationLabel(location), 'ABCD-1234/Lectures/02.pdf');
  });

  test('falls back to the tree id when there is no document id', () {
    const location = 'content://com.android.externalstorage.documents/'
        'tree/primary%3ADocuments%2FLecture%20notes';

    expect(gakujoDownloadLocationLabel(location),
        '内部ストレージ/Documents/Lecture notes');
  });

  test('uses the last document marker', () {
    const location = 'content://com.android.externalstorage.documents/'
        'document/primary%3Aold/document/primary%3ADocuments%2F02.pdf';

    expect(gakujoDownloadLocationLabel(location), '内部ストレージ/Documents/02.pdf');
  });

  test('decodes only the last path segment for another content provider', () {
    const location = 'content://com.example.provider/files/'
        'Lecture%20notes%20%2B%20%E8%B3%87%E6%96%99.pdf?ignored=1#preview';

    expect(gakujoDownloadLocationLabel(location), 'Lecture notes + 資料.pdf');
  });

  test('decodes a file URI path', () {
    const location = 'file:///Users/student/Lecture%20notes/'
        '%E8%B3%87%E6%96%99.pdf';

    expect(gakujoDownloadLocationLabel(location),
        '/Users/student/Lecture notes/資料.pdf');
  });

  test('leaves a plain Windows path unchanged', () {
    const location = r'C:\Users\student\Downloads\資料%20.pdf';

    expect(gakujoDownloadLocationLabel(location), location);
  });

  test('leaves plain macOS and iOS paths unchanged', () {
    for (final location in [
      '/Users/student/Downloads/資料%20.pdf',
      '/private/var/mobile/Documents/資料.pdf',
    ]) {
      expect(gakujoDownloadLocationLabel(location), location);
    }
  });

  test('decodes percent escapes only once', () {
    const location = 'content://com.android.externalstorage.documents/'
        'document/primary%3ADocuments%2Fliteral%252F.pdf';

    expect(gakujoDownloadLocationLabel(location),
        '内部ストレージ/Documents/literal%2F.pdf');
  });

  test('preserves raw components with malformed percent encoding', () {
    for (final malformed in ['bad%', 'bad%ZZ', 'bad%E3%81']) {
      final documentId = 'primary%3ADocuments%2F$malformed.pdf';
      expect(
        gakujoDownloadLocationLabel(
          'content://com.android.externalstorage.documents/document/$documentId',
        ),
        documentId,
      );
      expect(
        gakujoDownloadLocationLabel(
            'content://com.example.provider/$malformed'),
        malformed,
      );
      expect(gakujoDownloadLocationLabel('file:///tmp/$malformed'),
          '/tmp/$malformed');
    }
  });
}
