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
  test('automatic backup omits starred messages without requesting deletion', () {
    final payload = buildGakujoBackupPayload(
      appSettings: const GakujoAppSettings(),
      downloadHistory: const [], failedDownloads: const [], favorites: const [],
      deadlines: const [], changes: const [], reportLists: const [],
      includeStarredMessages: false,
      starredMessages: [GakujoStarredMessage(
        keijitype: '1', genrecd: '2', seqNo: '3', title: 'notice',
        body: 'private body', starredAt: DateTime.utc(2026),
      )],
    );
    expect(payload, isNot(contains('starredMessages')));
    expect(jsonEncode(payload), isNot(contains('private body')));
    expect(parseGakujoBackup(jsonEncode(payload)).starredMessages, isNull);
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
      changes: const [], reportLists: const [],
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
      changes: const [],
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
