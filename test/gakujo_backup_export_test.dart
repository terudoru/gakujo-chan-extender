import 'dart:convert';

import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:test/test.dart';

void main() {
  test('backup failed downloads omit request form fields', () {
    final payload = buildGakujoBackupPayload(
      appSettings: const GakujoAppSettings(),
      downloadHistory: const [],
      failedDownloads: [
        GakujoFailedDownloadEntry(
          id: 'failed-1',
          request: const GakujoDownloadRequest(
            url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/download',
            method: 'POST',
            courseName: '情報リテラシー',
            fileName: '資料.pdf',
            formFields: {
              'csrfToken': 'secret-csrf-token',
              'sessionId': 'secret-session-id',
            },
          ),
          failedAt: DateTime.utc(2026, 7, 16, 12),
          errorMessage: 'timeout',
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
  });
}
