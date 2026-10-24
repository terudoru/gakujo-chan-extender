import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_restore.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';

const _modeKey = 'more_better_gakujo_download_save_mode';
const _historyKey = 'more_better_gakujo_download_history';
const _favoritesKey = 'more_better_gakujo_favorites';
const _notifiedKeysKey = 'more_better_gakujo_notified_deadline_keys';

void main() {
  final now = DateTime.now().toIso8601String();
  final validCollections = <String, Object>{
    'downloadHistory': [
      {'fileName': 'report.pdf', 'savedAt': now},
    ],
    'failedDownloads': [
      {
        'id': 'failed',
        'request': {'url': 'https://example.com/file'},
        'failedAt': now,
      },
    ],
    'favorites': [
      {'title': 'Favorite', 'url': 'https://example.com/favorite'},
    ],
    'starredMessages': [
      {'title': 'Message', 'keijitype': '1', 'genrecd': '2', 'seqNo': '3'},
    ],
    'deadlines': [
      {
        'title': 'Report',
        'url': 'https://example.com/report',
        'dueText': '2099/07/01 17:00',
        'detectedAt': now,
      },
    ],
    'notifiedDeadlineKeys': ['reminder|42'],
    'changes': [
      {
        'title': 'Changed',
        'url': 'https://example.com/change',
        'previousHash': 'before',
        'nextHash': 'after',
        'changedAt': now,
      },
    ],
    'reportLists': [
      {
        'title': 'Reports',
        'url': 'https://example.com/reports',
        'items': ['Report'],
        'capturedAt': now,
      },
    ],
  };

  for (final key in [
    'failedDownloads',
    'favorites',
    'deadlines',
    'changes',
    'reportLists',
  ]) {
    test('URL filtering cannot turn $key into an empty replacement', () async {
      final storage = _Storage({
        _modeKey: 'flat_configured',
        _favoritesKey: 'old',
      });
      final before = Map<String, String>.of(storage.values);
      await expectLater(
        restoreGakujoBackup(
          backup: parseGakujoBackup(jsonEncode({
            'version': 2,
            'downloadSaveMode': 'flat_picker_each_time',
            key: validCollections[key],
          })),
          settingsStore: GakujoAppSettingsStore(secureStorage: storage),
          historyStore: GakujoDownloadHistoryStore(secureStorage: storage),
          activityStore: GakujoActivityStore(secureStorage: storage),
          isAllowedUrl: (_) => false,
          isAllowedNavigationUrl: (_) => false,
        ),
        throwsA(isA<GakujoBackupImportException>()),
      );
      expect(storage.writes, 0);
      expect(storage.values, before);
    });
  }

  test('validates direct import objects before any writes', () async {
    final storage = _Storage({_favoritesKey: 'old'});
    await expectLater(
      _restoreActivityBackup(
        storage,
        GakujoBackupImport(
          version: 2,
          pageMode: GakujoPageMode.mobile,
          favorites: [GakujoFavoritePage.fromJson({})],
        ),
      ),
      throwsA(isA<GakujoBackupImportException>().having(
        (error) => error.message,
        'message',
        'バックアップのお気に入りを読み取れませんでした',
      )),
    );
    expect(storage.writes, 0);
    expect(storage.values, {_favoritesKey: 'old'});
  });

  for (final (key, dateKey) in [
    ('downloadHistory', 'savedAt'),
    ('failedDownloads', 'failedAt'),
    ('changes', 'changedAt'),
    ('reportLists', 'capturedAt'),
  ]) {
    test('rejects $key if every record would be discarded by retention',
        () async {
      final records = (validCollections[key] as List)
          .map((value) => {
                ...(value as Map),
                dateKey: '1970-01-01T00:00:00.000Z',
              })
          .toList();
      final storage = _Storage({_modeKey: 'old'});
      await expectLater(
        _restoreActivityBackup(
            storage,
            parseGakujoBackup(jsonEncode({
              'version': 2,
              'pageMode': 'mobile',
              key: records,
            }))),
        throwsA(isA<GakujoBackupImportException>()),
      );
      expect(storage.writes, 0);
    });
  }

  test('explicit empty lists still clear each restored collection', () async {
    final storage = _Storage({});
    final activity = GakujoActivityStore(secureStorage: storage);
    await _restoreActivityBackup(
        storage,
        parseGakujoBackup(jsonEncode({
          'version': 2,
          ...validCollections,
        })),
        activity: activity);
    await _restoreActivityBackup(
        storage,
        parseGakujoBackup(jsonEncode({
          'version': 2,
          for (final key in validCollections.keys) key: [],
        })),
        activity: activity);
    final history = GakujoDownloadHistoryStore(secureStorage: storage);
    expect(await history.load(), isEmpty);
    expect(await history.loadFailedDownloads(), isEmpty);
    expect(await activity.loadFavorites(), isEmpty);
    expect(await activity.loadStarredMessages(), isEmpty);
    expect(await activity.loadDeadlines(), isEmpty);
    expect(await activity.loadNotifiedDeadlineKeys(), isEmpty);
    expect(await activity.loadChanges(), isEmpty);
    expect(await activity.loadReportLists(), isEmpty);
  });

  for (final key in [
    _historyKey,
    _favoritesKey,
    'more_better_gakujo_deadlines',
    _notifiedKeysKey,
    'more_better_gakujo_activity_changes',
    'more_better_gakujo_cached_report_lists',
  ]) {
    test('backup fails on unreadable $key and releases all stores', () async {
      final storage = _Storage({})..failReadKey = key;
      final settings = GakujoAppSettingsStore(secureStorage: storage);
      final history = GakujoDownloadHistoryStore(secureStorage: storage);
      final activity = GakujoActivityStore(secureStorage: storage);
      await expectLater(
          readGakujoBackupPayload(
            currentSettings: () => const GakujoAppSettings(),
            settingsStore: settings,
            historyStore: history,
            activityStore: activity,
          ),
          throwsStateError);
      storage.failReadKey = null;
      await _restore(storage,
              settings: settings, history: history, activity: activity)
          .timeout(const Duration(seconds: 2));
    });
  }

  test('backup round trip does not notify restored deadlines again', () async {
    final source = _Storage({});
    final sourceActivity = GakujoActivityStore(secureStorage: source);
    final deadline = _deadline();
    await sourceActivity.mergeDeadlines([deadline]);
    final sourceNotifications = _NotificationService();
    await GakujoDeadlineNotificationCoordinator(
      activityStore: sourceActivity,
      notificationService: sourceNotifications,
    ).notifyPendingDeadlines(notificationsEnabled: true);
    expect(sourceNotifications.notifiedKeys, [deadline.key]);
    await sourceActivity.addNotifiedDeadlineKeys(['reminder|42']);

    final payload = await readGakujoBackupPayload(
      currentSettings: () => const GakujoAppSettings(),
      settingsStore: GakujoAppSettingsStore(secureStorage: source),
      historyStore: GakujoDownloadHistoryStore(secureStorage: source),
      activityStore: sourceActivity,
    );
    expect(payload['notifiedDeadlineKeys'], [deadline.key, 'reminder|42']);
    final target = _Storage({});
    final targetActivity = GakujoActivityStore(secureStorage: target);
    await _restoreActivityBackup(target, parseGakujoBackup(jsonEncode(payload)),
        activity: targetActivity);
    expect((await targetActivity.loadDeadlines()).single.key, deadline.key);
    expect(await targetActivity.loadNotifiedDeadlineKeys(),
        {deadline.key, 'reminder|42'});

    final targetNotifications = _NotificationService();
    final coordinator = GakujoDeadlineNotificationCoordinator(
      activityStore: targetActivity,
      notificationService: targetNotifications,
    );
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
    await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
    expect(targetNotifications.notifiedKeys, isEmpty);
  });

  for (final hasExistingKeys in [false, true]) {
    test('old backup preserves notified keys (existing: $hasExistingKeys)',
        () async {
      final target = _Storage({
        if (hasExistingKeys)
          _notifiedKeysKey: jsonEncode(['existing', 'reminder|42']),
      });
      final activity = GakujoActivityStore(secureStorage: target);
      final deadline = _deadline();
      final backup = parseGakujoBackup(jsonEncode({
        'version': 2,
        'deadlines': [deadline.toJson()],
      }));
      expect(backup.notifiedDeadlineKeys, isNull);
      await _restoreActivityBackup(target, backup, activity: activity);
      expect((await activity.loadDeadlines()).single.key, deadline.key);
      expect(await activity.loadNotifiedDeadlineKeys(),
          hasExistingKeys ? {'existing', 'reminder|42'} : <String>{});
      expect(target.values.containsKey(_notifiedKeysKey), hasExistingKeys);

      final notifications = _NotificationService();
      final coordinator = GakujoDeadlineNotificationCoordinator(
        activityStore: activity,
        notificationService: notifications,
      );
      await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
      await coordinator.notifyPendingDeadlines(notificationsEnabled: true);
      expect(notifications.notifiedKeys, [deadline.key]);
    });
  }

  test('restored notified keys replace existing keys and keep the newest 1000',
      () async {
    final target = _Storage({_notifiedKeysKey: '["target-only"]'});
    final activity = GakujoActivityStore(secureStorage: target);
    final keys = [for (var i = 0; i < 1005; i++) 'reminder|$i'];
    await _restoreActivityBackup(
      target,
      parseGakujoBackup(jsonEncode({
        'version': 2,
        'notifiedDeadlineKeys': keys,
      })),
      activity: activity,
    );
    expect((await activity.loadNotifiedDeadlineKeys()).toList(), keys.skip(5));
    await activity.addNotifiedDeadlineKeys(['next']);
    expect((await activity.loadNotifiedDeadlineKeys()).toList(),
        [...keys.skip(6), 'next']);

    await _restoreActivityBackup(
      target,
      parseGakujoBackup('{"version":2,"notifiedDeadlineKeys":[]}'),
      activity: activity,
    );
    expect(await activity.loadNotifiedDeadlineKeys(), isEmpty);
  });

  for (final originalKeys in [null, '["existing","reminder|42"]']) {
    test('late restore failure rolls back notified keys ($originalKeys)',
        () async {
      final storage = _Storage({
        if (originalKeys != null) _notifiedKeysKey: originalKeys,
      })
        ..failWriteKey = 'more_better_gakujo_activity_changes';
      final before = Map<String, String>.of(storage.values);
      await expectLater(
        _restoreActivityBackup(
          storage,
          const GakujoBackupImport(
            version: 2,
            notifiedDeadlineKeys: ['restored', 'reminder|99'],
            changes: [],
          ),
        ),
        throwsStateError,
      );
      expect(storage.values, before);
    });
  }

  test('backup capture does not mix records from before and after a restore',
      () async {
    final storage = _Storage({});
    final settings = GakujoAppSettingsStore(secureStorage: storage);
    final history = GakujoDownloadHistoryStore(secureStorage: storage);
    final activity = GakujoActivityStore(secureStorage: storage);
    await history.add(GakujoDownloadHistoryEntry(
        fileName: 'before.pdf', courseName: 'course', savedAt: DateTime.now()));
    await activity.addFavorite(GakujoFavoritePage(
        title: 'before',
        url: 'https://example.com/before',
        addedAt: DateTime.now()));
    storage.pauseReadKey = _historyKey;
    storage.readStarted = Completer<void>();
    storage.continueRead = Completer<void>();
    final capture = readGakujoBackupPayload(
        currentSettings: () => const GakujoAppSettings(),
        settingsStore: settings,
        historyStore: history,
        activityStore: activity);
    await storage.readStarted!.future;
    final restore = _restore(storage,
        settings: settings, history: history, activity: activity);
    await Future<void>.delayed(Duration.zero);
    storage.continueRead!.complete();
    final payload = await capture;
    await restore;
    expect(
        (payload['downloadHistory'] as List).single['fileName'], 'before.pdf');
    expect((payload['favorites'] as List).map((e) => e['title']), ['before']);
    expect(await history.load(), isEmpty);
    expect(await activity.loadFavorites(), isEmpty);
    expect(storage.readKeys,
        isNot(contains('more_better_gakujo_login_credentials_v2')));
  });

  test('snapshot read failure does not start any writes', () async {
    final storage = _Storage({_modeKey: 'flat_configured'})
      ..failReadKey = _favoritesKey;
    await expectLater(_restore(storage), throwsStateError);
    expect(storage.writes, 0);
    expect(storage.values, {_modeKey: 'flat_configured'});
  });

  test('queued saves and readers wait until rollback finishes', () async {
    final storage = _Storage({_modeKey: 'flat_configured'})
      ..failWriteKey = _favoritesKey
      ..writeStarted = Completer<void>()
      ..continueWrite = Completer<void>();
    final settings = GakujoAppSettingsStore(secureStorage: storage);
    final history = GakujoDownloadHistoryStore(secureStorage: storage);
    final activity = GakujoActivityStore(secureStorage: storage);
    final restore = _restore(storage,
        settings: settings, history: history, activity: activity);
    final failed = expectLater(restore, throwsStateError);
    await storage.writeStarted!.future;
    var saveFinished = false;
    final save = settings
        .saveDownloadSaveMode(DownloadSaveMode.autoSortToConfiguredFolder)
        .then((_) => saveFinished = true);
    var readFinished = false;
    final read = activity.loadFavorites().then((value) {
      readFinished = true;
      return value;
    });
    final addition = history.add(GakujoDownloadHistoryEntry(
        fileName: 'concurrent.pdf',
        courseName: 'course',
        savedAt: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    expect(saveFinished, isFalse);
    expect(readFinished, isFalse);
    storage.continueWrite!.complete();
    await failed;
    await save;
    await addition;
    expect(await read, isEmpty);
    expect(storage.values[_modeKey], 'auto_sort_configured');
    expect((await history.load()).single.fileName, 'concurrent.pdf');
  });

  test('rollback reports its own failure and still restores other keys',
      () async {
    final storage = _Storage({_modeKey: 'flat_configured', _historyKey: 'old'})
      ..failWriteKey = _favoritesKey
      ..failRollbackKey = _historyKey;
    await expectLater(
        _restore(storage),
        throwsA(isA<BackupRollbackException>()
            .having((e) => e.rollbackErrors.length, 'rollback failures', 1)));
    expect(storage.values[_modeKey], 'flat_configured');
    expect(storage.values.containsKey(_favoritesKey), isFalse);
    storage.failRollbackKey = null;
    await _restore(storage);
    expect(storage.values[_modeKey], 'flat_picker_each_time');
  });

  test('successful import preserves omitted settings and applies URL policy',
      () async {
    final storage = _Storage({_modeKey: 'flat_configured', _historyKey: 'old'});
    final activity = GakujoActivityStore(secureStorage: storage);
    await restoreGakujoBackup(
      backup: GakujoBackupImport(version: 2, favorites: [
        GakujoFavoritePage(
            title: 'allowed',
            url: 'https://example.com/allowed',
            addedAt: DateTime.now()),
        GakujoFavoritePage(
            title: 'blocked',
            url: 'https://example.com/blocked',
            addedAt: DateTime.now()),
      ]),
      settingsStore: GakujoAppSettingsStore(secureStorage: storage),
      historyStore: GakujoDownloadHistoryStore(secureStorage: storage),
      activityStore: activity,
      isAllowedUrl: (_) => false,
      isAllowedNavigationUrl: (url) => url.endsWith('/allowed'),
    );
    expect(storage.values[_modeKey], 'flat_configured');
    expect(storage.values[_historyKey], 'old');
    expect((await activity.loadFavorites()).single.title, 'allowed');
  });

  test('a late write failure restores exact values and absent keys', () async {
    final storage = _Storage({
      _modeKey: 'flat_configured',
      // Even an old or malformed cache must survive a failed import unchanged.
      _historyKey: 'old cache representation',
      'more_better_gakujo_login_credentials_v2': 'untouched',
    })
      ..failWriteKey = _favoritesKey;
    final before = Map<String, String>.of(storage.values);
    final settings = GakujoAppSettingsStore(secureStorage: storage);
    await expectLater(
      restoreGakujoBackup(
        backup: const GakujoBackupImport(
          version: 2,
          downloadSaveMode: DownloadSaveMode.flatWithPickerEachTime,
          downloadHistory: [],
          favorites: [],
        ),
        settingsStore: settings,
        historyStore: GakujoDownloadHistoryStore(secureStorage: storage),
        activityStore: GakujoActivityStore(secureStorage: storage),
        isAllowedUrl: (_) => true,
        isAllowedNavigationUrl: (_) => true,
      ),
      throwsStateError,
    );
    expect(storage.values, before);
    expect(storage.readKeys,
        isNot(contains('more_better_gakujo_login_credentials_v2')));
  });
}

GakujoDeadlineEntry _deadline() => GakujoDeadlineEntry(
      title: 'Restored report',
      url: 'https://example.com/report',
      dueText: '2099/07/01 17:00',
      detectedAt: DateTime.now(),
    );

Future<void> _restoreActivityBackup(
  _Storage storage,
  GakujoBackupImport backup, {
  GakujoActivityStore? activity,
}) =>
    restoreGakujoBackup(
      backup: backup,
      settingsStore: GakujoAppSettingsStore(secureStorage: storage),
      historyStore: GakujoDownloadHistoryStore(secureStorage: storage),
      activityStore: activity ?? GakujoActivityStore(secureStorage: storage),
      isAllowedUrl: (_) => true,
      isAllowedNavigationUrl: (_) => true,
    );

class _NotificationService extends GakujoNotificationService {
  final List<String> notifiedKeys = [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> notifyDeadline(GakujoDeadlineEntry entry) async {
    notifiedKeys.add(entry.key);
    return true;
  }
}

Future<void> _restore(_Storage storage,
        {GakujoAppSettingsStore? settings,
        GakujoDownloadHistoryStore? history,
        GakujoActivityStore? activity}) =>
    restoreGakujoBackup(
        backup: const GakujoBackupImport(
            version: 2,
            downloadSaveMode: DownloadSaveMode.flatWithPickerEachTime,
            downloadHistory: [],
            favorites: []),
        settingsStore:
            settings ?? GakujoAppSettingsStore(secureStorage: storage),
        historyStore:
            history ?? GakujoDownloadHistoryStore(secureStorage: storage),
        activityStore: activity ?? GakujoActivityStore(secureStorage: storage),
        isAllowedUrl: (_) => true,
        isAllowedNavigationUrl: (_) => true);

class _Storage extends FlutterSecureStorage {
  _Storage(this.values);
  final Map<String, String> values;
  final List<String> readKeys = [];
  String? failWriteKey;
  String? failReadKey;
  String? failRollbackKey;
  bool rollingBack = false;
  int writes = 0;
  Completer<void>? writeStarted;
  Completer<void>? continueWrite;
  String? pauseReadKey;
  Completer<void>? readStarted;
  Completer<void>? continueRead;

  @override
  Future<String?> read(
      {required String key,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    readKeys.add(key);
    if (key == failReadKey) throw StateError('read unavailable');
    final value = values[key];
    if (key == pauseReadKey) {
      pauseReadKey = null;
      readStarted!.complete();
      await continueRead!.future;
    }
    return value;
  }

  @override
  Future<void> write(
      {required String key,
      required String? value,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    writes++;
    if (rollingBack && key == failRollbackKey) {
      throw StateError('rollback failed');
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    if (key == failWriteKey) {
      failWriteKey = null;
      writeStarted?.complete();
      await continueWrite?.future;
      rollingBack = true;
      throw StateError('write failed after changing storage');
    }
  }

  @override
  Future<void> delete(
      {required String key,
      AppleOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      AppleOptions? mOptions,
      WindowsOptions? wOptions}) async {
    writes++;
    values.remove(key);
  }
}
