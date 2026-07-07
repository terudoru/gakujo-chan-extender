import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_service.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('download history entries round-trip through json', () {
    final savedAt = DateTime.utc(2026, 6, 26, 12, 30);
    final entry = GakujoDownloadHistoryEntry(
      fileName: '資料.pdf',
      courseName: '',
      savedAt: savedAt,
      location: '/Downloads/資料.pdf',
    );

    final restored = GakujoDownloadHistoryEntry.fromJson(entry.toJson());

    expect(restored.fileName, '資料.pdf');
    expect(restored.displayCourseName, '未分類');
    expect(restored.savedAt, savedAt);
    expect(restored.location, '/Downloads/資料.pdf');
  });

  test('download history normalizes blank locations', () {
    final restored = GakujoDownloadHistoryEntry.fromJson({
      'fileName': '資料.pdf',
      'courseName': '情報リテラシー',
      'savedAt': '2026-06-26T12:30:00.000Z',
      'location': '   ',
    });

    expect(restored.location, isNull);
  });

  test('replaceHistory drops empty file names before writing', () async {
    final store = GakujoDownloadHistoryStore();

    await store.replaceHistory([
      GakujoDownloadHistoryEntry(
        fileName: '',
        courseName: '情報リテラシー',
        savedAt: DateTime.now(),
      ),
      GakujoDownloadHistoryEntry(
        fileName: '資料.pdf',
        courseName: '情報リテラシー',
        savedAt: DateTime.now(),
      ),
    ]);

    final entries = await store.load();
    expect(entries, hasLength(1));
    expect(entries.single.fileName, '資料.pdf');
  });

  test('load drops stale download history entries', () async {
    final store = GakujoDownloadHistoryStore();

    await store.replaceHistory([
      GakujoDownloadHistoryEntry(
        fileName: '古い資料.pdf',
        courseName: '情報リテラシー',
        savedAt: DateTime.now().subtract(const Duration(days: 220)),
      ),
      GakujoDownloadHistoryEntry(
        fileName: '最近の資料.pdf',
        courseName: '情報リテラシー',
        savedAt: DateTime.now().subtract(const Duration(days: 20)),
      ),
    ]);

    final entries = await store.load();
    expect(entries, hasLength(1));
    expect(entries.single.fileName, '最近の資料.pdf');
  });

  test('replaceHistory keeps newest entries when imported old-first', () async {
    final store = GakujoDownloadHistoryStore();
    final base = DateTime.now().subtract(const Duration(days: 1));

    await store.replaceHistory([
      for (var i = 0; i < 105; i += 1)
        GakujoDownloadHistoryEntry(
          fileName: '資料-$i.pdf',
          courseName: '情報リテラシー',
          savedAt: base.add(Duration(minutes: i)),
        ),
    ]);

    final entries = await store.load();
    expect(entries, hasLength(100));
    expect(entries.first.fileName, '資料-104.pdf');
    expect(entries.last.fileName, '資料-5.pdf');
  });

  test('compact removes stale stored history and keeps newest first', () async {
    const storage = FlutterSecureStorage();
    await storage.write(
      key: 'more_better_gakujo_download_history',
      value: jsonEncode([
        {
          'fileName': '古い資料.pdf',
          'courseName': '情報リテラシー',
          'savedAt': DateTime.now()
              .subtract(const Duration(days: 220))
              .toIso8601String(),
        },
        {
          'fileName': '新しい資料.pdf',
          'courseName': '情報リテラシー',
          'savedAt': DateTime.now()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        },
        {
          'fileName': '少し前の資料.pdf',
          'courseName': '情報リテラシー',
          'savedAt': DateTime.now()
              .subtract(const Duration(days: 20))
              .toIso8601String(),
        },
      ]),
    );

    final store = GakujoDownloadHistoryStore();
    await store.compact();

    final entries = await store.load();
    expect(entries.map((entry) => entry.fileName), ['新しい資料.pdf', '少し前の資料.pdf']);
    final raw = await storage.read(key: 'more_better_gakujo_download_history');
    expect(raw, isNot(contains('古い資料.pdf')));
  });

  test('download result reads optional saved location', () {
    final result = GakujoDownloadResult.fromMap({
      'fileName': 'report.pdf',
      'courseName': '情報リテラシー',
      'location': 'content://downloads/report.pdf',
    });

    expect(result.fileName, 'report.pdf');
    expect(result.courseName, '情報リテラシー');
    expect(result.location, 'content://downloads/report.pdf');
  });

  test('download result treats null native response as cancellation', () {
    expect(
      () => GakujoDownloadResult.fromMap(null),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'cancelled'),
      ),
    );
  });

  test('download result treats empty file name as cancellation', () {
    expect(
      () => GakujoDownloadResult.fromMap({'fileName': ''}),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'cancelled'),
      ),
    );
  });

  test('failed download entries round-trip through json', () {
    final failedAt = DateTime.utc(2026, 6, 26, 13);
    final entry = GakujoFailedDownloadEntry(
      id: '1',
      request: const GakujoDownloadRequest(
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
        method: 'POST',
        courseName: '情報リテラシー',
        fileName: '資料.pdf',
        formFields: {'id': '42'},
      ),
      failedAt: failedAt,
      errorMessage: 'timeout',
    );

    final restored = GakujoFailedDownloadEntry.fromJson(entry.toJson());

    expect(restored.id, '1');
    expect(restored.request.method, 'POST');
    expect(restored.request.courseName, '情報リテラシー');
    expect(restored.request.formFields, {'id': '42'});
    expect(restored.failedAt, failedAt);
    expect(restored.errorMessage, 'timeout');
  });

  test('failed download queue keeps only the newest matching request',
      () async {
    final store = GakujoDownloadHistoryStore();
    const request = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
      method: 'POST',
      courseName: '情報リテラシー',
      fileName: '資料.pdf',
      formFields: {'id': '42', 'token': 'abc'},
    );

    await store.addFailedDownload(
      request: request,
      errorMessage: 'timeout',
    );
    await store.addFailedDownload(
      request: request,
      errorMessage: 'network error',
    );

    final entries = await store.loadFailedDownloads();
    expect(entries, hasLength(1));
    expect(entries.single.errorMessage, 'network error');
  });

  test('failed download queue treats different form fields separately',
      () async {
    final store = GakujoDownloadHistoryStore();
    const first = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
      method: 'POST',
      courseName: '情報リテラシー',
      fileName: '資料.pdf',
      formFields: {'id': '42'},
    );
    const second = GakujoDownloadRequest(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
      method: 'POST',
      courseName: '情報リテラシー',
      fileName: '資料.pdf',
      formFields: {'id': '43'},
    );

    await store.addFailedDownload(request: first, errorMessage: 'first');
    await store.addFailedDownload(request: second, errorMessage: 'second');

    expect(await store.loadFailedDownloads(), hasLength(2));
  });

  test('replaceFailedDownloads drops unusable imported entries', () async {
    final store = GakujoDownloadHistoryStore();

    await store.replaceFailedDownloads([
      GakujoFailedDownloadEntry(
        id: '',
        request: const GakujoDownloadRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/a.pdf',
          method: 'GET',
          courseName: '',
          fileName: 'a.pdf',
          formFields: {},
        ),
        failedAt: DateTime.now(),
        errorMessage: 'missing id',
      ),
      GakujoFailedDownloadEntry(
        id: 'missing-url',
        request: const GakujoDownloadRequest(
          url: '',
          method: 'GET',
          courseName: '',
          fileName: 'b.pdf',
          formFields: {},
        ),
        failedAt: DateTime.now(),
        errorMessage: 'missing url',
      ),
      GakujoFailedDownloadEntry(
        id: 'valid',
        request: const GakujoDownloadRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/b.pdf',
          method: 'GET',
          courseName: '',
          fileName: 'b.pdf',
          formFields: {},
        ),
        failedAt: DateTime.now(),
        errorMessage: 'network',
      ),
    ]);

    final entries = await store.loadFailedDownloads();
    expect(entries, hasLength(1));
    expect(entries.single.id, 'valid');
  });

  test('replaceFailedDownloads keeps newest entries when imported old-first',
      () async {
    final store = GakujoDownloadHistoryStore();
    final base = DateTime.now().subtract(const Duration(days: 1));

    await store.replaceFailedDownloads([
      for (var i = 0; i < 35; i += 1)
        GakujoFailedDownloadEntry(
          id: 'failed-$i',
          request: GakujoDownloadRequest(
            url: 'https://gakujo.iess.niigata-u.ac.jp/$i.pdf',
            method: 'GET',
            courseName: '',
            fileName: '$i.pdf',
            formFields: const {},
          ),
          failedAt: base.add(Duration(minutes: i)),
          errorMessage: 'network',
        ),
    ]);

    final entries = await store.loadFailedDownloads();
    expect(entries, hasLength(30));
    expect(entries.first.id, 'failed-34');
    expect(entries.last.id, 'failed-5');
  });

  test('loadFailedDownloads drops stale failed entries', () async {
    final store = GakujoDownloadHistoryStore();

    await store.replaceFailedDownloads([
      GakujoFailedDownloadEntry(
        id: 'old',
        request: const GakujoDownloadRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/old.pdf',
          method: 'GET',
          courseName: '',
          fileName: 'old.pdf',
          formFields: {},
        ),
        failedAt: DateTime.now().subtract(const Duration(days: 45)),
        errorMessage: 'timeout',
      ),
      GakujoFailedDownloadEntry(
        id: 'recent',
        request: const GakujoDownloadRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/recent.pdf',
          method: 'GET',
          courseName: '',
          fileName: 'recent.pdf',
          formFields: {},
        ),
        failedAt: DateTime.now().subtract(const Duration(days: 10)),
        errorMessage: 'network',
      ),
    ]);

    final entries = await store.loadFailedDownloads();
    expect(entries, hasLength(1));
    expect(entries.single.id, 'recent');
  });
}
