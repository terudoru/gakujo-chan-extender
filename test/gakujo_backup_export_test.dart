import 'dart:convert';

import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:morebettergakujo_flutter/src/gakujo_external_url.dart';
import 'package:test/test.dart';

void main() {
  test('local backup rejects oversized supported collections without truncation', () {
    final now = DateTime.now();
    final body = 'あ' * 4000;
    final payload = buildGakujoBackupPayload(
      appSettings: const GakujoAppSettings(),
      downloadHistory: const [],
      failedDownloads: const [],
      favorites: const [],
      starredMessages: [
        for (var i = 0; i < 300; i += 1)
          GakujoStarredMessage(
            keijitype: '1',
            genrecd: '2',
            seqNo: '$i',
            title: 'notice $i',
            body: body,
            starredAt: now,
          ),
      ],
      deadlines: [
        for (var i = 0; i < 80; i += 1)
          GakujoDeadlineEntry(
            title: 'deadline $i',
            url:
                'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do?seqNo=$i',
            dueText: '2099/07/01 17:00',
            detectedAt: now,
            source: '連絡通知',
            messageText: body,
          ),
      ],
      reportLists: [
        for (var i = 0; i < 20; i += 1)
          GakujoCachedReportList(
            title: 'reports $i',
            url:
                'https://gakujo.iess.niigata-u.ac.jp/campusweb/reports?course=$i',
            capturedAt: now,
            items: [for (var j = 0; j < 100; j += 1) '$j ${'あ' * 120}'],
          ),
      ],
    );
    final original = jsonEncode(payload);
    expect(utf8.encode(original).length, greaterThan(maxGakujoBackupBytes));
    expect(() {
      encodeGakujoBackupPayload(payload);
    }, throwsA(isA<GakujoBackupExportException>()));
    expect(jsonEncode(payload), original);
  });

  test('local backup measures pretty UTF-8 bytes at the import boundary', () {
    final payload = <String, Object?>{'version': 2, 'padding': ''};
    final overhead = utf8
        .encode(const JsonEncoder.withIndent('  ').convert(payload))
        .length;
    final available = maxGakujoBackupBytes - overhead;
    payload['padding'] = '${'あ' * (available ~/ 3)}${'a' * (available % 3)}';
    final text = encodeGakujoBackupPayload(payload);
    expect(utf8.encode(text), hasLength(maxGakujoBackupBytes));
    expect(text, const JsonEncoder.withIndent('  ').convert(payload));
    expect(parseGakujoBackup(text).version, 2);
    payload['padding'] = '${payload['padding']}あ';
    expect(() {
      encodeGakujoBackupPayload(payload);
    }, throwsA(isA<GakujoBackupExportException>()));
  });

  test('local backup rejects pretty output even when compact JSON fits', () {
    final payload = <String, Object?>{'version': 2, 'padding': ''};
    payload['padding'] =
        'a' * (maxGakujoBackupBytes - jsonEncode(payload).length);
    expect(utf8.encode(jsonEncode(payload)), hasLength(maxGakujoBackupBytes));
    expect(() {
      encodeGakujoBackupPayload(payload);
    }, throwsA(isA<GakujoBackupExportException>()));
  });

  test('external URLs retain safe portal navigation and remove credentials', () {
    final sanitized = sanitizeGakujoExternalUrl(
      'https://user:password@gakujo.iess.niigata-u.ac.jp/'
      'campusweb%3BJSESSIONID%3Dsecret/campusportal.do'
      '?page=main&tabId=en&token=secret#private',
    );
    final uri = Uri.parse(sanitized);
    expect(uri.userInfo, isEmpty);
    expect(uri.path, '/campusweb/campusportal.do');
    expect(uri.queryParameters, {'page': 'main', 'tabId': 'en'});
    expect(sanitized, isNot(contains('secret')));
    expect(uri.fragment, isEmpty);
  });
  test('external URLs strip jsessionid path parameters and query tokens', () {
    final sanitized = sanitizeGakujoExternalUrl(
      'https://gakujo.iess.niigata-u.ac.jp/'
      'campusweb;jsessionid=secret-path/campusportal.do'
      '?page=main&tabId=en&jsessionid=secret-query'
      '&_flowExecutionKey=e1s1&token=secret-token',
    );
    expect(
      sanitized,
      'https://gakujo.iess.niigata-u.ac.jp/'
      'campusweb/campusportal.do?page=main&tabId=en',
    );
  });
  test('automatic backup omits starred messages without requesting deletion', () {
    final payload = buildGakujoBackupPayload(
      appSettings: const GakujoAppSettings(),
      downloadHistory: const [], failedDownloads: const [], favorites: const [],
      deadlines: const [], reportLists: const [],
      includeStarredMessages: false,
      starredMessages: [GakujoStarredMessage(
        keijitype: '1', genrecd: '2', seqNo: '3', title: 'notice',
        body: 'private body', starredAt: DateTime.utc(2026),
      )],
    );
    expect(payload, isNot(contains('starredMessages')));
    expect(jsonEncode(payload), isNot(contains('private body')));
    expect(parseGakujoBackup(encodeGakujoBackupPayload(payload)).starredMessages, isNull);
  });

  test('backup removes session data from activity URLs and notification keys', () {
    const url = 'https://gakujo.iess.niigata-u.ac.jp/campusweb;JSESSIONID=secret-path/campussmart.do?_flowId=KJW0001100-flow&seqNo=42&token=secret-query';
    final deadline = GakujoDeadlineEntry(
      title: '提出', url: url, dueText: '明日', detectedAt: DateTime.utc(2026),
    );
    final payload = buildGakujoBackupPayload(
      appSettings: const GakujoAppSettings(),
      downloadHistory: const [], failedDownloads: const [], favorites: const [],
      deadlines: [deadline], notifiedDeadlineKeys: [deadline.key],
      reportLists: const [],
    );
    final text = jsonEncode(payload);
    expect(text, isNot(contains('secret-path')));
    expect(text, isNot(contains('secret-query')));
    final restored = GakujoDeadlineEntry.fromJson(
      (payload['deadlines']! as List).single as Map,
    );
    expect((payload['notifiedDeadlineKeys']! as List).single, restored.key);
    expect(restored.url, contains('_flowId=KJW0001100-flow'));
    expect(restored.url, contains('seqNo=42'));
  });

  test('backup failed downloads omit request form fields', () {
    final payload = buildGakujoBackupPayload(
      appSettings: const GakujoAppSettings(),
      downloadHistory: const [],
      failedDownloads: [
        GakujoFailedDownloadEntry(
          id: 'failed-1-secret-id',
          request: const GakujoDownloadRequest(
            url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb;jsessionid=secret-path/download?token=secret-query',
            method: 'POST',
            courseName: '情報リテラシー',
            fileName: '資料.pdf',
            formFields: {
              'csrfToken': 'secret-csrf-token',
              'sessionId': 'secret-session-id',
            },
          ),
          failedAt: DateTime.utc(2026, 7, 16, 12),
          errorMessage: 'timeout secret-error',
        ),
      ],
      favorites: const [],
      deadlines: const [],
      reportLists: const [],
      createdAt: DateTime.utc(2026, 7, 16, 13),
    );

    final failedDownloads = payload['failedDownloads']! as List<Object?>;
    final failedDownload = failedDownloads.single! as Map<String, Object?>;
    final request = failedDownload['request']! as Map<String, Object?>;

    expect(request, isNot(contains('formFields')));
    expect(jsonEncode(payload), isNot(contains('secret-csrf-token')));
    expect(jsonEncode(payload), isNot(contains('secret-session-id')));
    for (final secret in ['secret-id', 'secret-path', 'secret-query', 'secret-error']) {
      expect(jsonEncode(payload), isNot(contains(secret)));
    }
    expect(failedDownload['canRetry'], isFalse);
    expect(request['url'], 'https://gakujo.iess.niigata-u.ac.jp/');
  });
}
