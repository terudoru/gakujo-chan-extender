import 'dart:convert';

import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:test/test.dart';

void main() {
  test('keeps ambiguous courses unresolved across capture and retry', () {
    final request = GakujoDownloadRequest.fromJsonText('''{
      "url":"https://gakujo.iess.niigata-u.ac.jp/file",
      "courseName":"未分類", "courseNameAmbiguous":true
    }''');
    expect(request.courseNameAmbiguous, isTrue);
    expect(request.courseName, '未分類');
    expect(GakujoDownloadRequest.fromJsonMap(request.toJson()).courseNameAmbiguous,
        isTrue);
    expect(request.toMethodChannelArguments()['courseNameAmbiguous'], isTrue);
    expect(GakujoDownloadRequest.fromJsonMap({}).courseNameAmbiguous, isFalse);
  });

  test('keeps repeated fields ordered through JSON, retry and native arguments', () {
    final request = GakujoDownloadRequest.fromJsonText('''{
      "url":"https://gakujo.iess.niigata-u.ac.jp/file", "method":"POST",
      "formFields":{"fileId":"B","_eventId":"download"},
      "formFieldPairs":[["fileId","A"],["_eventId","download"],["fileId","B"]]
    }''');
    const pairs = [['fileId', 'A'], ['_eventId', 'download'], ['fileId', 'B']];
    expect(request.orderedFormFields, pairs);
    expect(GakujoDownloadRequest.fromJsonMap(request.toJson()).orderedFormFields,
        pairs);
    expect(request.toMethodChannelArguments()['formFieldPairs'], pairs);
    expect(request.toExternalJson(), isNot(contains('formFieldPairs')));
    final reversed = GakujoDownloadRequest.fromJsonMap({
      ...request.toJson(),
      'formFieldPairs': [['fileId', 'B'], ['_eventId', 'download'], ['fileId', 'A']],
    });
    final gate = GakujoDownloadOperationGate();
    expect(gate.tryStart(request), isNotNull);
    expect(gate.tryStart(reversed), isNotNull);
    expect(gate.tryStart(request), isNull);
    final legacy = GakujoDownloadRequest.fromJsonMap({
      'formFields': {'fileId': 'A'},
    });
    expect(legacy.orderedFormFields, [['fileId', 'A']]);
    expect(legacy.toJson(), isNot(contains('formFieldPairs')));
  });

  test('limits concurrent downloads and releases slots after completion', () {
    final gate = GakujoDownloadOperationGate(maxConcurrentDownloads: 2);
    GakujoDownloadRequest request(int number) => GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/$number',
      method: 'GET', courseName: '', fileName: '', formFields: const {},
    );
    final first = gate.tryStart(request(1))!;
    final second = gate.tryStart(request(2))!;
    expect(gate.atCapacity, isTrue);
    expect(gate.tryStart(request(3)), isNull);
    gate.finish(first);
    expect(gate.tryStart(request(3)), isNotNull);
    gate.finish(second);
  });
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

  test('uses capture MIME hints only at the JSON text entry point', () {
    const payload = {
      'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
      'fileName': '講義資料',
      'mimeType': 'application/pdf',
    };
    expect(GakujoDownloadRequest.fromJsonText(jsonEncode(payload)).fileName,
        '講義資料.pdf');
    expect(GakujoDownloadRequest.fromJsonMap(payload).fileName, '講義資料');
  });

  test('keeps action labels unresolved through capture and retry', () {
    for (final label in [
      '一括ダウンロード',
      '一括保存（３件）',
      'ダウンロード (3件)',
      '保存',
      'Download all files (3)',
    ]) {
      final payload = {
        'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
        'method': 'POST',
        'fileName': label,
        'mimeType': 'application/zip',
      };
      final request = GakujoDownloadRequest.fromJsonText(jsonEncode(payload));
      expect(request.fileName, isEmpty, reason: label);
      expect(GakujoDownloadRequest.fromJsonMap(payload).fileName, isEmpty);
      expect(GakujoDownloadRequest.fromJsonMap(request.toJson()).fileName,
          isEmpty);
      expect(request.toMethodChannelArguments()['fileName'], isEmpty);
    }
  });

  test('fromJsonMap keeps an empty file name unresolved', () {
    final request = GakujoDownloadRequest.fromJsonMap({
      'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
      'method': 'POST',
      'courseName': 'x',
      'fileName': '',
      'formFields': <String, String>{},
    });

    expect(request.fileName, isEmpty);
  });

  test('fromJsonMap keeps a missing file name unresolved', () {
    final request = GakujoDownloadRequest.fromJsonMap({
      'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
      'method': 'POST',
      'courseName': 'x',
      'formFields': <String, String>{},
    });

    expect(request.fileName, isEmpty);
  });

  test('fromJsonMap still sanitizes a non-empty file name', () {
    final request = GakujoDownloadRequest.fromJsonMap({
      'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
      'method': 'POST',
      'courseName': 'x',
      'fileName': 'folder/report.pdf',
      'formFields': <String, String>{},
    });

    expect(request.fileName, 'folderreport.pdf');
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

  test('download gate debounces duplicate capture but allows repeated saves',
      () {
    final gate = GakujoDownloadOperationGate();
    final startedAt = DateTime.utc(2026, 8, 22);
    const first = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
      method: 'POST',
      courseName: '情報リテラシー',
      fileName: 'ダウンロード',
      formFields: {'token': '1', 'file': '42'},
    );
    const duplicateFromAnotherCapturePath = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download#captured',
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

    final firstKey = gate.tryStart(first, now: startedAt);
    expect(firstKey, isNotNull);
    expect(
      gate.tryStart(
        duplicateFromAnotherCapturePath,
        now: startedAt.add(const Duration(milliseconds: 100)),
      ),
      isNull,
    );

    final differentKey = gate.tryStart(
      differentFile,
      now: startedAt.add(const Duration(milliseconds: 100)),
    );
    expect(differentKey, isNotNull);
    gate.finish(differentKey!);

    final concurrentRepeat = gate.tryStart(
      duplicateFromAnotherCapturePath,
      now: startedAt.add(const Duration(milliseconds: 300)),
    );
    expect(
      concurrentRepeat,
      isNotNull,
      reason: 'the same file can be saved again while its first save is active',
    );

    gate.finish(concurrentRepeat!);
    gate.finish(firstKey!);
  });

  test('download gate recovers when the clock moves backwards', () {
    final gate = GakujoDownloadOperationGate();
    final originalTime = DateTime.utc(2026, 8, 22, 12);
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
      method: 'POST',
      courseName: 'course',
      fileName: 'material.pdf',
      formFields: {'token': '1', 'file': '42'},
    );

    final originalOperation = gate.tryStart(request, now: originalTime);
    expect(originalOperation, isNotNull);
    gate.finish(originalOperation!);

    final rolledBackTime = originalTime.subtract(const Duration(minutes: 5));
    final rolledBackOperation = gate.tryStart(request, now: rolledBackTime);
    expect(
      rolledBackOperation,
      isNotNull,
      reason: 'a future-dated start is stale after the clock moves backwards',
    );
    gate.finish(rolledBackOperation!);

    expect(
      gate.tryStart(
        request,
        now: rolledBackTime.add(const Duration(milliseconds: 100)),
      ),
      isNull,
      reason: 'the debounce window restarts from the rolled-back clock',
    );
    expect(
      gate.tryStart(
        request,
        now: rolledBackTime.add(const Duration(milliseconds: 250)),
      ),
      isNotNull,
    );
  });
}
