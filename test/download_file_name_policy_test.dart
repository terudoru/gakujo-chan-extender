import 'package:morebettergakujo_flutter/src/download_file_name_policy.dart';
import 'package:test/test.dart';

void main() {
  test(
      'does not keep campussquare.do when a button name is available elsewhere',
      () {
    final name = DownloadFileNamePolicy.safeFileName(
      preferredName: '授業資料',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
      mimeType: 'application/pdf',
    );

    expect(name, '授業資料.pdf');
  });

  test('does not keep campussquare.do from the URL fallback', () {
    final name = DownloadFileNamePolicy.safeFileName(
      preferredName: '',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
      mimeType: 'application/pdf',
    );

    expect(name, 'document.pdf');
  });

  test('removes forbidden filename characters', () {
    final name = DownloadFileNamePolicy.safeFileName(
      preferredName: r'講義/資料:第*1?回".pdf',
    );

    expect(name, '講義資料第1回.pdf');
  });

  test('falls back to document for empty names', () {
    final name = DownloadFileNamePolicy.safeFileName(
      preferredName: '   ',
      mimeType: 'text/plain',
    );

    expect(name, 'document.txt');
  });

  test('adds a numeric suffix when a name already exists', () {
    final name = DownloadFileNamePolicy.uniqueName(
      '資料.pdf',
      {'資料.pdf', '資料 (1).pdf'},
    );

    expect(name, '資料 (2).pdf');
  });

  test('decodes RFC 5987 content disposition filenames', () {
    final name = DownloadFileNamePolicy.fileNameFromContentDisposition(
      "attachment; filename*=UTF-8''%E7%94%9F%E5%90%88%E6%88%90.pdf",
    );

    expect(name, '生合成.pdf');
  });

  test('decodes RFC 5987 filenames with a language tag', () {
    final name = DownloadFileNamePolicy.fileNameFromContentDisposition(
      "attachment; filename*=UTF-8'ja'%E7%94%9F%E5%90%88%E6%88%90.pdf",
    );

    expect(name, '生合成.pdf');
  });

  test('decodes quoted RFC 5987 filenames', () {
    final name = DownloadFileNamePolicy.fileNameFromContentDisposition(
      'attachment; filename*="UTF-8\'\'%E8%B3%87%E6%96%99.pdf"',
    );

    expect(name, '資料.pdf');
  });

  test('decodes non-UTF-8 RFC 5987 filenames instead of leaving them encoded',
      () {
    final name = DownloadFileNamePolicy.fileNameFromContentDisposition(
      "attachment; filename*=iso-8859-1''%E9tude.pdf",
    );

    expect(name, 'étude.pdf');
  });

  test('reads quoted content disposition filenames', () {
    final name = DownloadFileNamePolicy.fileNameFromContentDisposition(
      'attachment; filename="lecture.pdf"',
    );

    expect(name, 'lecture.pdf');
  });

  test('does not fail on malformed encoded filename hints', () {
    final dispositionName =
        DownloadFileNamePolicy.fileNameFromContentDisposition(
      "attachment; filename*=UTF-8''%E7%ZZ.pdf",
    );
    final fileName = DownloadFileNamePolicy.safeFileName(
      preferredName: '',
      contentDispositionName: dispositionName,
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/%E7%ZZ',
      mimeType: 'application/pdf',
    );

    expect(fileName, '%E7%ZZ.pdf');
  });

  test('sanitizes folder names and falls back to unclassified', () {
    expect(DownloadFileNamePolicy.safeFolderName(r'講義/資料'), '講義資料');
    expect(DownloadFileNamePolicy.safeFolderName('  '), '未分類');
  });

  test('uses requested course folder when it is useful', () {
    expect(
      DownloadFileNamePolicy.courseFolderName(
        requestedCourseName: '情報数学',
        fileName: '第1回 資料.pdf',
      ),
      '情報数学',
    );
  });

  test('infers course folder from file name when requested name is generic',
      () {
    expect(
      DownloadFileNamePolicy.courseFolderName(
        requestedCourseName: '開設一覧',
        fileName: '情報数学 - 第1回 資料.pdf',
      ),
      '情報数学',
    );
  });

  test('falls back to unknown course folder when inference is not useful', () {
    expect(
      DownloadFileNamePolicy.courseFolderName(
        requestedCourseName: '未分類',
        fileName: 'report.pdf',
      ),
      '未分類',
    );
  });
}
