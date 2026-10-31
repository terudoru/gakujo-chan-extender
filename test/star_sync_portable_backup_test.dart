import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_adapters.dart';

void main() {
  test('restore markers use only settings present in the backup', () {
    final backup = parseGakujoBackup(
      '{"version":2,"notificationTopics":["report"]}',
    );
    expect(restoredSyncCollections(backup, {'version', 'notificationTopics'}), {
      'settings': {'notificationTopics'},
    });
    expect(
      restoredSyncCollections(const GakujoBackupImport(version: 2), {}),
      isEmpty,
    );
  });

  test('sync restore merges messageStars from the current settings', () {
    const star = GakujoFeatureFlag.messageStars;
    const other = GakujoFeatureFlag.values;
    final portable = other.where((flag) => flag != star).take(1).toSet();
    expect(syncRestoreFeatureFlags(portable, {star}), {...portable, star});
    expect(syncRestoreFeatureFlags({...portable, star}, {}), portable);
    expect(syncRestoreFeatureFlags(null, {star}), isNull);
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
    expect(backup.downloadHistory!.single.location, isNull);
    expect(backup.failedDownloads!.single.request.url, 'https://example.com/');
  });

  test('sync backup removes local settings and nested credentials', () {
    final payload = <String, Object?>{
      'version': 2,
      'downloadSaveMode': 'local',
      'pageMode': 'local',
      'disabledFeatureFlags': [
        GakujoFeatureFlag.messageStars.storageValue,
        'other',
      ],
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
    expect(portable['nested'], {'safe': 'kept'});
    expect(portable['downloadHistory'], [
      {'fileName': 'a.pdf'},
      {'fileName': 'b.pdf'},
    ]);
    expect(portable['failedDownloads'], [
      {
        'request': {'url': 'https://example.com/'},
      },
    ]);
    expect(
      portableSyncBackupPayload(
        jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
      ),
      portable,
    );
    expect(payload['downloadSaveMode'], 'local');
  });

  test('portable backup checks UTF-8 size before upload', () async {
    final overhead = utf8.encode(jsonEncode({'version': 2, 'data': ''})).length;
    final atLimit = {
      'version': 2,
      'data': 'a' * (maxGakujoBackupBytes - overhead),
    };
    expect(encodePortableSyncBackup(atLimit), hasLength(maxGakujoBackupBytes));
    var uploaded = false;
    Future<void> upload(Map<String, Object?> payload) async {
      final bytes = encodePortableSyncBackup(payload);
      uploaded = bytes.isNotEmpty;
    }

    await expectLater(
      upload({'version': 2, 'data': '${atLimit['data']}あ'}),
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
