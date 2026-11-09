import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_adapters.dart';

void main() {
  test('sync backup respects collection scope and omits star details', () {
    final payload = portableSyncBackupPayload(
      {
        'version': 2,
        'favorites': ['private'],
        'notifiedDeadlineKeys': ['private'],
        'messageExcludeKeywords': ['private'],
        'reportDrafts': ['private'],
        'deadlines': ['private'],
        'changes': ['private'],
        'reportLists': ['private'],
        'starredMessages': [
          {
            'keijitype': '1',
            'genrecd': '2',
            'seqNo': '3',
            'title': 'title',
            'starredAt': '2026-01-01',
            'body': 'private',
            'sender': 'private',
          },
        ],
      },
      disabledCollections: {'favorites', 'settings', 'notified-deadlines'},
    );
    expect(payload, isNot(contains('favorites')));
    expect(payload, isNot(contains('notifiedDeadlineKeys')));
    expect(payload, isNot(contains('messageExcludeKeywords')));
    expect(payload, isNot(contains('reportDrafts')));
    expect(payload, isNot(contains('deadlines')));
    expect(payload, isNot(contains('changes')));
    expect(payload, isNot(contains('reportLists')));
    expect((payload['starredMessages'] as List).single, {
      'keijitype': '1',
      'genrecd': '2',
      'seqNo': '3',
      'title': 'title',
      'starredAt': '2026-01-01',
    });
  });

  test('sync restore preserves local star details', () {
    GakujoStarredMessage star(String title, String body) =>
        GakujoStarredMessage(
          keijitype: '1',
          genrecd: '2',
          seqNo: '3',
          title: title,
          body: body,
          sender: body,
          starredAt: DateTime.utc(2026),
        );
    final restored = mergeSyncBackupStars(
      [star('remote', '')],
      [star('local', 'detail')],
    ).single;
    expect(restored.title, 'remote');
    expect(restored.body, 'detail');
    expect(restored.sender, 'detail');
  });

  test('restore markers use only settings present in the backup', () {
    final backup = parseGakujoBackup(
      '{"version":2,"notificationTopics":["report"]}',
    );
    expect(restoredSyncCollections(backup, {'version', 'notificationTopics'}), {
      'settings': {'notificationTopics', 'messageNotification'},
    });
    expect(
      restoredSyncCollections(const GakujoBackupImport(version: 2), {}),
      isEmpty,
    );
  });

  test('legacy notification choice is selected for restore', () {
    final backup = parseGakujoBackup(
      '{"version":2,"notificationTopics":["message"]}',
    );
    final restored = restoredMessageNotification(backup, {
      'version',
      'notificationTopics',
    });
    expect(restored?.mode, GakujoMessageNotificationMode.deadlines);
    expect(restoredSyncCollections(backup, {'version', 'notificationTopics'}), {
      'settings': {'notificationTopics', 'messageNotification'},
    });
    expect(restoredMessageNotification(backup, {'version'}), isNull);
  });

  test('portable settings compare against the current snapshot', () {
    final settings = GakujoAppSettings();
    final snapshot = exportStarSyncPortableSettings(settings);
    expect(portableSyncSettingsMatch(settings, snapshot), isTrue);
    expect(
      portableSyncSettingsMatch(settings, {
        ...snapshot,
        'messageExcludeKeywords': ['changed'],
      }),
      isFalse,
    );
  });

  test('sync restore ignores stored download paths', () {
    final portable = portableSyncBackupPayload({
      'version': 2,
      'downloadHistory': [
        {
          'fileName': 'a.pdf',
          'courseName': 'course',
          'savedAt': '2026-01-01T00:00:00Z',
          'location': 'content://downloads/a',
        },
      ],
      'failedDownloads': [
        {
          'id': 'id',
          'request': {'url': 'https://example.com/', 'filePath': '/private/a'},
          'failedAt': '2026-01-01T00:00:00Z',
        },
      ],
    });
    final backup = parseGakujoBackup(jsonEncode(portable));
    expect(backup.downloadHistory, isNull);
    expect(backup.failedDownloads, isNull);
  });

  test('sync backup removes local settings and nested credentials', () {
    final payload = <String, Object?>{
      'version': 2,
      'downloadSaveMode': 'local',
      'pageMode': 'local',
      'disabledFeatureFlags': [
        'gpa_display', 'report_tools', 'message_tools', 'message_stars',
        'other',
      ],
      'notificationPreferences': {'mutedCourses': ['Course'], 'skipSubmitted': false},
      'nested': {'password': 'hidden', 'accessToken': 'hidden', 'safe': 'kept'},
      'downloadHistory': [
        {'fileName': 'a.pdf', 'location': 'content://downloads/a'},
        {'fileName': 'b.pdf', 'location': r'C:\Users\user\b.pdf'},
      ],
      'failedDownloads': [
        {
          'request': {
            'url': 'https://example.com/',
            'filePath': '/private/a',
            'contentUri': 'content://downloads/a',
          },
        },
      ],
    };
    final portable = portableSyncBackupPayload(payload);
    expect(portable, isNot(contains('downloadSaveMode')));
    expect(portable, isNot(contains('pageMode')));
    expect(portable['disabledFeatureFlags'], ['other']);
    expect(portable['notificationPreferences'], {'skipSubmitted': false});
    expect(portable, isNot(contains('nested')));
    expect(portable, isNot(contains('downloadHistory')));
    expect(portable, isNot(contains('failedDownloads')));
    expect(
      portableSyncBackupPayload(
        jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
      ),
      portable,
    );
    expect(payload['downloadSaveMode'], 'local');
  });

  test('portable backup checks UTF-8 size before upload', () async {
    final overhead = utf8
        .encode(jsonEncode({'version': 2, 'messageExcludeKeywords': ''}))
        .length;
    final atLimit = {
      'version': 2,
      'messageExcludeKeywords': 'a' * (maxGakujoBackupBytes - overhead),
    };
    expect(encodePortableSyncBackup(atLimit), hasLength(maxGakujoBackupBytes));
    var uploaded = false;
    Future<void> upload(Map<String, Object?> payload) async {
      final bytes = encodePortableSyncBackup(payload);
      uploaded = bytes.isNotEmpty;
    }

    await expectLater(
      upload({
        'version': 2,
        'messageExcludeKeywords': '${atLimit['messageExcludeKeywords']}あ',
      }),
      throwsA(
        isA<GakujoBackupImportException>().having(
          (error) => error.message,
          'message',
          'バックアップが大きすぎるため、同期先に保存できませんでした',
        ),
      ),
    );
    expect(uploaded, isFalse);
  });
}
