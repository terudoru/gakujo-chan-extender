import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_import.dart';
import 'package:morebettergakujo_flutter/src/gakujo_backup_restore.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_history_store.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';

const _modeKey = 'more_better_gakujo_download_save_mode';
const _historyKey = 'more_better_gakujo_download_history';
const _favoritesKey = 'more_better_gakujo_favorites';

void main() {
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
    return values[key];
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
