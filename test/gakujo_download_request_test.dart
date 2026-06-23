import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:test/test.dart';

void main() {
  test('keeps empty captured file names unresolved for response headers', () {
    final request = GakujoDownloadRequest.fromJsonText(
      '{"url":"https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do",'
      '"method":"GET","fileName":"","courseName":"生合成"}',
    );

    expect(request.fileName, isEmpty);
    expect(request.courseName, '生合成');
  });

  test('sanitizes captured file names when the page provides one', () {
    final request = GakujoDownloadRequest.fromJsonText(
      '{"url":"https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do",'
      '"method":"GET","fileName":"講義/資料","mimeType":"application/pdf"}',
    );

    expect(request.fileName, '講義資料.pdf');
  });
}
