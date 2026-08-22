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

  test('external json omits form fields while internal json keeps them', () {
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
      method: 'POST',
      courseName: '情報リテラシー',
      fileName: '資料.pdf',
      formFields: {'csrfToken': 'secret', 'sessionId': 'private'},
    );

    expect(request.toExternalJson(), isNot(contains('formFields')));
    expect(request.toJson()['formFields'], request.formFields);
  });

  test('restores a request from json without form fields', () {
    final request = GakujoDownloadRequest.fromJsonMap({
      'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
      'method': 'POST',
      'courseName': '情報リテラシー',
      'fileName': '資料.pdf',
    });

    expect(request.method, 'POST');
    expect(request.formFields, isEmpty);
  });

  test('download gate rejects only a matching in-flight request', () {
    final gate = GakujoDownloadOperationGate();
    const first = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
      method: 'POST',
      courseName: '情報リテラシー',
      fileName: 'ダウンロード',
      formFields: {'token': '1', 'file': '42'},
    );
    const duplicateFromAnotherCapturePath = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
      method: 'post',
      courseName: '未分類',
      fileName: '',
      formFields: {'file': '42', 'token': '1'},
    );
    const differentFile = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
      method: 'POST',
      courseName: '情報リテラシー',
      fileName: '別の資料.pdf',
      formFields: {'token': '1', 'file': '43'},
    );

    final firstKey = gate.tryStart(first);
    expect(firstKey, isNotNull);
    expect(gate.tryStart(duplicateFromAnotherCapturePath), isNull);

    final differentKey = gate.tryStart(differentFile);
    expect(differentKey, isNotNull);
    gate.finish(differentKey!);

    gate.finish(firstKey!);
    expect(
      gate.tryStart(duplicateFromAnotherCapturePath),
      isNotNull,
      reason: 'completed downloads and manually deleted files can be retried',
    );
  });
}
