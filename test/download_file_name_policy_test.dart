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

  test('prefers the frontend display name over a different server name', () {
    final name = DownloadFileNamePolicy.safeFileName(
      preferredName: '画面表示の第1回講義資料',
      contentDispositionName: 'internal_004281.pdf',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
      mimeType: 'application/octet-stream',
    );

    expect(name, '画面表示の第1回講義資料.pdf');
  });

  test('uses the server attachment name when the page only has an action label',
      () {
    final name = DownloadFileNamePolicy.safeFileName(
      preferredName: 'ダウンロード',
      contentDispositionName: '第1回講義資料.pdf',
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
      mimeType: 'application/pdf',
    );

    expect(name, '第1回講義資料.pdf');
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

  test('makes Windows device names safe for files and course folders', () {
    for (final name in ['CON', 'nul.txt', 'COM1.pdf', 'Lpt9', 'AUX.data']) {
      expect(
          DownloadFileNamePolicy.safeFileName(preferredName: name), '_$name');
      expect(DownloadFileNamePolicy.safeFolderName(name), '_$name');
    }
    expect(DownloadFileNamePolicy.safeFileName(preferredName: 'console.pdf'),
        'console.pdf');
  });

  test('removes trailing dots before extension inference or folder creation',
      () {
    expect(
        DownloadFileNamePolicy.safeFileName(
            preferredName: '資料. ', mimeType: 'application/pdf'),
        '資料.pdf');
    expect(DownloadFileNamePolicy.safeFolderName('情報数学... '), '情報数学');
    expect(DownloadFileNamePolicy.safeFolderName('...'), '未分類');
  });

  test('adds a numeric suffix when a name already exists', () {
    final name = DownloadFileNamePolicy.uniqueName(
      '資料.pdf',
      {'資料.pdf', '資料 (1).pdf'},
    );

    expect(name, '資料 (2).pdf');
  });

  test('adds a suffix for a name that differs only by case', () {
    final name = DownloadFileNamePolicy.uniqueName(
      'lecture.pdf',
      {'Lecture.PDF'},
    );

    expect(name, 'lecture (1).pdf');
  });

  test('collision suffixes fit within 255 units and keep the extension', () {
    final base = List.filled(251, 'a').join();
    final desired = '$base.pdf';
    final existing = {desired};
    for (var index = 1; index <= 12; index += 1) {
      final suffix = ' ($index)';
      final expected = '${base.substring(0, 251 - suffix.length)}$suffix.pdf';
      final allocated = DownloadFileNamePolicy.uniqueName(desired, existing);
      expect(allocated, expected);
      expect(allocated.length, 255);
      existing.add(allocated);
    }
  });

  test('truncation does not split a surrogate pair at the suffix boundary', () {
    final prefix = List.filled(246, 'a').join();
    final desired = '$prefix😀xyz.pdf';
    expect(desired.length, 255);
    final allocated = DownloadFileNamePolicy.uniqueName(desired, {desired});
    expect(allocated, '$prefix (1).pdf');
    expect(allocated.codeUnits.any((unit) => unit >= 0xd800 && unit <= 0xdfff),
        isFalse);
    final intact = '${List.filled(245, 'a').join()}😀wxyz.pdf';
    expect(DownloadFileNamePolicy.uniqueName(intact, {intact}),
        '${List.filled(245, 'a').join()}😀 (1).pdf');
  });

  test('a full-length name without an extension also leaves suffix space', () {
    final desired = List.filled(255, 'a').join();
    expect(DownloadFileNamePolicy.uniqueName(desired, {desired}),
        '${desired.substring(0, 251)} (1)');
  });

  test('skips generated suffixes that differ only by case', () {
    final name = DownloadFileNamePolicy.uniqueName(
      'a.pdf',
      {'a.pdf', 'A (1).pdf'},
    );

    expect(name, 'a (2).pdf');
  });

  test('keeps exact-case numeric suffix behavior unchanged', () {
    final name = DownloadFileNamePolicy.uniqueName(
      'lecture.pdf',
      {'lecture.pdf', 'lecture (1).pdf'},
    );

    expect(name, 'lecture (2).pdf');
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

  test('keeps semicolons inside quoted attachment filenames', () {
    expect(
        DownloadFileNamePolicy.fileNameFromContentDisposition(
            'attachment; filename="lecture; part 1.pdf"; size=123'),
        'lecture; part 1.pdf');
  });

  test('accepts parameter whitespace and unescapes quoted filenames', () {
    expect(
        DownloadFileNamePolicy.fileNameFromContentDisposition(
            r'attachment; filename = "lecture \"one\".pdf"'),
        'lecture "one".pdf');
  });

  test('does not mistake another parameter for filename', () {
    expect(
        DownloadFileNamePolicy.fileNameFromContentDisposition(
            'attachment; x-filename="wrong.pdf"; filename="right.pdf"'),
        'right.pdf');
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
    expect(
      DownloadFileNamePolicy.safeFolderName(
        List.filled(
          DownloadFileNamePolicy.maxCourseFolderNameLength + 1,
          '長',
        ).join(),
      ),
      '未分類',
      reason: 'a page dump must not become an OS directory component',
    );
  });

  test('uses the downloads folder for the generic change-list page', () {
    expect(
      DownloadFileNamePolicy.safeFolderName('リスト等の変更'),
      DownloadFileNamePolicy.downloadsFolderName,
    );
    expect(
      DownloadFileNamePolicy.courseFolderName(
        requestedCourseName: 'リスト等の変更',
        fileName: '大学等への修学支援の措置に係る学修計画書.docx',
      ),
      'ダウンロード',
    );
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
