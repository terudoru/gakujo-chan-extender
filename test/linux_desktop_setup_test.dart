import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/main.dart';
import 'package:morebettergakujo_flutter/src/file_system_gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:morebettergakujo_flutter/src/keyring_lock_gate_storage.dart';
import 'package:morebettergakujo_flutter/src/linux_session_settings.dart';
import 'package:morebettergakujo_flutter/src/secure_storage_transaction.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rootKey = 'more_better_gakujo_download_root_path';
  const channel = MethodChannel('net.yoshida.morebettergakujo/window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('Linux backup picker keeps the JSON extension and MIME filters', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickOpenFile');
      expect(call.arguments, {
        'allowedTypeGroups': [
          {
            'label': 'JSON',
            'extensions': ['json'],
            'mimeTypes': ['application/json', 'text/plain'],
          },
        ],
      });
      return '/home/student/backup.json';
    });
    expect((await pickGakujoBackupFile())?.path, '/home/student/backup.json');
  });

  test('Linux backup picker cancellation returns no file', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickOpenFile');
      return null;
    });
    expect(await pickGakujoBackupFile(), isNull);
  });

  for (final existing in [false, true]) {
    test(
      'Linux save picker saves to the chosen path (existing: $existing)',
      () async {
        final directory = await Directory.systemTemp.createTemp('mbg-save-');
        addTearDown(() => directory.delete(recursive: true));
        final selected = File('${directory.path}/saved.pdf');
        if (existing) await selected.writeAsString('old contents');
        final bytes = Uint8List.fromList('%PDF-1.7\nnew contents'.codeUnits);
        final initialDirectory = await linuxDownloadInitialDirectory(
          downloadsDirectory: getDownloadsDirectory,
          homeDirectory: Platform.environment['HOME'],
        );
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pickSaveFile');
          expect(call.arguments, {
            'initialDirectory': initialDirectory,
            'suggestedName': 'lecture.pdf',
          });
          return selected.path;
        });
        final service = FileSystemGakujoDownloadService(
          authenticatedBytesLoader: (request, {userAgent}) async =>
              AuthenticatedDownloadedFile(
                bytes: bytes,
                finalUrl: request.url,
                mimeType: 'application/pdf',
              ),
        );

        final result = await service.download(
          const GakujoDownloadRequest(
            url: 'https://gakujo.iess.niigata-u.ac.jp/file',
            method: 'GET',
            fileName: 'lecture.pdf',
            courseName: '',
            formFields: {},
          ),
          saveMode: DownloadSaveMode.flatWithPickerEachTime,
        );

        expect(result.location, selected.path);
        expect(result.fileName, 'saved.pdf');
        expect(await selected.readAsBytes(), bytes);
      },
    );
  }

  test('cancelling the Linux save picker cleans up without saving', () async {
    final directory = await Directory.systemTemp.createTemp('mbg-save-');
    addTearDown(() => directory.delete(recursive: true));
    final temporary = File('${directory.path}/payload');
    await temporary.writeAsString('%PDF-1.7\ncontents');
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickSaveFile');
      return null;
    });
    final service = FileSystemGakujoDownloadService(
      authenticatedBytesLoader: (request, {userAgent}) async =>
          AuthenticatedDownloadedFile.fromFile(
            file: temporary,
            cleanup: temporary.delete,
            finalUrl: request.url,
            mimeType: 'application/pdf',
          ),
    );

    await expectLater(
      service.download(
        const GakujoDownloadRequest(
          url: 'https://gakujo.iess.niigata-u.ac.jp/file',
          method: 'GET',
          fileName: 'lecture.pdf',
          courseName: '',
          formFields: {},
        ),
        saveMode: DownloadSaveMode.flatWithPickerEachTime,
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'cancelled',
        ),
      ),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test(
    'Linux folder selection uses the localized runner dialog and persists',
    () async {
      final directory = await Directory.systemTemp.createTemp('mbg-picker-');
      addTearDown(() => directory.delete(recursive: true));
      final selected = await Directory('${directory.path}/selected').create();
      FlutterSecureStorage.setMockInitialValues({rootKey: directory.path});
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'pickDownloadDirectory');
        expect(call.arguments, {'initialDirectory': directory.path});
        return selected.path;
      });
      final service = FileSystemGakujoDownloadService(
        secureStorage: const FlutterSecureStorage(),
        usesNativeDownloadRoot: false,
      );

      final result = await service.pickDownloadRoot();

      expect(result.isConfigured, isTrue);
      expect(result.path, selected.path);
      expect(
        await const FlutterSecureStorage().read(key: rootKey),
        selected.path,
      );
    },
  );

  test(
    'cancelling the Linux folder picker preserves the configured folder',
    () async {
      final directory = await Directory.systemTemp.createTemp('mbg-picker-');
      addTearDown(() => directory.delete(recursive: true));
      FlutterSecureStorage.setMockInitialValues({rootKey: directory.path});
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      final service = FileSystemGakujoDownloadService(
        secureStorage: const FlutterSecureStorage(),
        usesNativeDownloadRoot: false,
      );

      final result = await service.pickDownloadRoot();

      expect(result.isConfigured, isTrue);
      expect(result.path, directory.path);
      expect(
        await const FlutterSecureStorage().read(key: rootKey),
        directory.path,
      );
    },
  );

  test(
    'a locked keyring still allows choosing and clearing a session folder',
    () async {
      final directory = await Directory.systemTemp.createTemp('mbg-picker-');
      addTearDown(() => directory.delete(recursive: true));
      final storage = _FolderStorage()..readError = _lockedError();
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => directory.path,
      );
      final service = FileSystemGakujoDownloadService(
        secureStorage: storage,
        usesNativeDownloadRoot: false,
      );

      final result = await service.pickDownloadRoot();

      expect(result.path, directory.path);
      expect(result.isConfigured, isTrue);
      expect(result.isSessionOnly, isTrue);
      expect((await service.getDownloadRoot()).path, directory.path);
      expect(storage.readCalls, 1);
      expect(storage.writeCalls, 0);
      final cleared = await service.clearDownloadRoot();
      expect(cleared.isConfigured, isFalse);
      expect(cleared.isSessionOnly, isTrue);
      expect((await service.getDownloadRoot()).path, isNull);
      expect(storage.deleteCalls, 0);
    },
  );

  test('the folder picker leaves a closed keyring gate closed', () async {
    final inner = _FolderStorage()..readError = _lockedError();
    final gate = KeyringLockGateStorage(inner: inner);
    await expectLater(
      gate.read(key: rootKey),
      throwsA(isA<PlatformException>()),
    );
    var pickerOpened = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      pickerOpened = true;
      return null;
    });
    final service = FileSystemGakujoDownloadService(
      secureStorage: gate,
      usesNativeDownloadRoot: false,
    );

    final result = await service.pickDownloadRoot();

    expect(pickerOpened, isTrue);
    expect(result.isSessionOnly, isTrue);
    expect(inner.readCalls, 1);
  });

  test(
    'a read timeout opens the picker without making its selection session-only',
    () async {
      final directory = await Directory.systemTemp.createTemp('mbg-picker-');
      addTearDown(() => directory.delete(recursive: true));
      final pending = Completer<String?>();
      final storage = _FolderStorage()..pendingRead = pending.future;
      var pickerOpened = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        pickerOpened = true;
        return directory.path;
      });
      final service = FileSystemGakujoDownloadService(
        secureStorage: storage,
        usesNativeDownloadRoot: false,
      );

      final result = await service.pickDownloadRoot().timeout(
        const Duration(seconds: 5),
      );

      expect(pickerOpened, isTrue);
      expect(result.path, directory.path);
      expect(result.isSessionOnly, isFalse);
      expect(storage.writeCalls, 1);
      expect(storage.readValue, directory.path);
      pending.complete('old-folder');
      await Future<void>.delayed(Duration.zero);
      storage.pendingRead = null;
      expect((await service.getDownloadRoot()).path, directory.path);
    },
  );

  test('a slow healthy keyring read keeps folder persistence', () async {
    final directory = await Directory.systemTemp.createTemp('mbg-picker-');
    addTearDown(() => directory.delete(recursive: true));
    final pending = Completer<String?>();
    final storage = _FolderStorage()..pendingRead = pending.future;
    var pickerOpened = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      pickerOpened = true;
      expect(call.arguments, {'initialDirectory': directory.path});
      return directory.path;
    });
    final service = FileSystemGakujoDownloadService(
      secureStorage: storage,
      usesNativeDownloadRoot: false,
    );

    final selection = service.pickDownloadRoot();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(pickerOpened, isFalse);
    pending.complete(directory.path);
    final result = await selection;

    expect(pickerOpened, isTrue);
    expect(result.isSessionOnly, isFalse);
    expect(storage.writeCalls, 1);
  });

  test('a slow healthy folder write has no read timeout', () async {
    final directory = await Directory.systemTemp.createTemp('mbg-picker-');
    addTearDown(() => directory.delete(recursive: true));
    final pending = Completer<void>();
    final storage = _FolderStorage()
      ..readValue = directory.path
      ..pendingWrite = pending.future;
    messenger.setMockMethodCallHandler(channel, (call) async => directory.path);
    final service = FileSystemGakujoDownloadService(
      secureStorage: storage,
      usesNativeDownloadRoot: false,
    );

    var completed = false;
    final selection = service.pickDownloadRoot().then((result) {
      completed = true;
      return result;
    });
    await Future<void>.delayed(const Duration(milliseconds: 3100));
    expect(storage.writeCalls, 1);
    expect(completed, isFalse);
    pending.complete();
    final result = await selection;

    expect(result.path, directory.path);
    expect(result.isSessionOnly, isFalse);
    expect(storage.readValue, directory.path);
  });

  test('a locked folder write keeps the selection for the session', () async {
    final directory = await Directory.systemTemp.createTemp('mbg-picker-');
    addTearDown(() => directory.delete(recursive: true));
    final storage = _FolderStorage()
      ..readValue = directory.path
      ..writeError = _lockedError();
    messenger.setMockMethodCallHandler(channel, (call) async => directory.path);
    final service = FileSystemGakujoDownloadService(
      secureStorage: storage,
      usesNativeDownloadRoot: false,
    );

    final result = await service.pickDownloadRoot();

    expect(result.path, directory.path);
    expect(result.isSessionOnly, isTrue);
    expect((await service.getDownloadRoot()).path, directory.path);
    expect(storage.readCalls, 1);
    expect(storage.writeCalls, 1);
  });

  test(
    'a folder write timeout error is not treated as a locked keyring',
    () async {
      final directory = await Directory.systemTemp.createTemp('mbg-picker-');
      addTearDown(() => directory.delete(recursive: true));
      final error = TimeoutException('storage unavailable');
      final storage = _FolderStorage()
        ..readValue = directory.path
        ..writeError = error;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => directory.path,
      );
      final service = FileSystemGakujoDownloadService(
        secureStorage: storage,
        usesNativeDownloadRoot: false,
      );

      await expectLater(service.pickDownloadRoot(), throwsA(same(error)));

      expect((await service.getDownloadRoot()).isSessionOnly, isFalse);
    },
  );

  test('other storage failures still propagate from the picker', () async {
    final error = PlatformException(
      code: 'io_error',
      message: 'permission denied',
    );
    final service = FileSystemGakujoDownloadService(
      secureStorage: _FolderStorage()..readError = error,
      usesNativeDownloadRoot: false,
    );
    await expectLater(service.pickDownloadRoot(), throwsA(same(error)));
  });

  test('Windows keeps rejecting unavailable secure folder storage', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final error = _lockedError();
    final service = FileSystemGakujoDownloadService(
      secureStorage: _FolderStorage()..readError = error,
      usesNativeDownloadRoot: false,
    );
    await expectLater(service.pickDownloadRoot(), throwsA(same(error)));
  });

  test('Linux locked storage is explained without the raw exception', () {
    final message = gakujoUserFacingMessage(
      '保存先を設定できませんでした: KeyringLocked',
      platform: TargetPlatform.linux,
    );
    expect(message, contains('キーリング'));
    expect(message, contains('ロックを解除'));
    expect(message, isNot(contains('KeyringLocked')));
    expect(message, isNot(contains('PlatformException')));
  });

  test('Linux initial folder prefers Downloads before HOME', () async {
    final home = await Directory.systemTemp.createTemp('mbg-home-');
    addTearDown(() => home.delete(recursive: true));
    final downloads = await Directory('${home.path}/Downloads').create();
    expect(
      await linuxDownloadInitialDirectory(
        downloadsDirectory: () async => downloads,
        homeDirectory: home.path,
      ),
      downloads.path,
    );
  });

  for (final missing in [false, true]) {
    test(
      'Linux initial folder falls back to HOME without xdg-user-dirs ($missing)',
      () async {
        final home = await Directory.systemTemp.createTemp('mbg-home-');
        addTearDown(() => home.delete(recursive: true));
        expect(
          await linuxDownloadInitialDirectory(
            downloadsDirectory: () async {
              if (missing) {
                throw MissingPlatformDirectoryException('unavailable');
              }
              return null;
            },
            homeDirectory: home.path,
          ),
          home.path,
        );
      },
    );
  }

  for (final home in [null, '', 'nonexistent-mbg-home-directory']) {
    test(
      'Linux picker needs no initial directory when HOME is missing ($home)',
      () async {
        expect(
          await linuxDownloadInitialDirectory(
            downloadsDirectory: () async =>
                throw MissingPlatformDirectoryException('unavailable'),
            homeDirectory: home,
          ),
          isNull,
        );
      },
    );
  }

  test(
    'session settings changes compose and show one notice without writes',
    () async {
      final session = LinuxSessionSettings();
      final operations = StorageOperationQueue();
      final messages = <String>[];
      var settings = const GakujoAppSettings();
      var writes = 0;
      Future<void> disable(GakujoFeatureFlag flag) => saveGakujoSettingsChange(
        operations: operations,
        save: () async {
          expect(
            await session.save(
              () async {
                writes++;
              },
              storageAvailable: false,
              showSnackBar: messages.add,
            ),
            isFalse,
          );
        },
        currentSettings: () => settings,
        update: (latest) => latest.copyWith(
          disabledFeatureFlags: {...latest.disabledFeatureFlags, flag},
        ),
        apply: (latest) => settings = latest,
        mirror: (_) async {},
      );

      await Future.wait([
        disable(GakujoFeatureFlag.downloadCapture),
        disable(GakujoFeatureFlag.uploadCompression),
      ]);
      session.showNotice(messages.add); // Setup and folder selection share it.

      expect(settings.disabledFeatureFlags, {
        GakujoFeatureFlag.downloadCapture,
        GakujoFeatureFlag.uploadCompression,
      });
      expect(writes, 0);
      expect(messages, [LinuxSessionSettings.message]);
    },
  );

  test(
    'a newly locked keyring allows a non-secret setting change in memory',
    () async {
      final session = LinuxSessionSettings();
      final messages = <String>[];
      var settings = const GakujoAppSettings();
      await saveGakujoSettingsChange(
        save: () async {
          expect(
            await session.save(
              () async => throw _lockedError(),
              storageAvailable: true,
              showSnackBar: messages.add,
            ),
            isFalse,
          );
        },
        currentSettings: () => settings,
        update: (latest) => latest.copyWith(pageMode: GakujoPageMode.desktop),
        apply: (latest) => settings = latest,
        mirror: (_) async {},
      );
      expect(settings.pageMode, GakujoPageMode.desktop);
      expect(messages, [LinuxSessionSettings.message]);
    },
  );

  test(
    'available storage still saves settings without a session notice',
    () async {
      final session = LinuxSessionSettings();
      final messages = <String>[];
      var writes = 0;
      expect(
        await session.save(
          () async {
            writes++;
          },
          storageAvailable: true,
          showSnackBar: messages.add,
        ),
        isTrue,
      );
      expect(writes, 1);
      expect(messages, isEmpty);
    },
  );

  test(
    'unrelated settings failures are not treated as a locked keyring',
    () async {
      final error = PlatformException(code: 'io_error');
      final messages = <String>[];
      await expectLater(
        LinuxSessionSettings().save(
          () async => throw error,
          storageAvailable: true,
          showSnackBar: messages.add,
        ),
        throwsA(same(error)),
      );
      expect(messages, isEmpty);
    },
  );

  test('Linux preserves the same error details as Windows', () {
    for (final message in [
      '保存できませんでした: PlatformException(io_error, native failure)',
      'FileSystemException: permission denied',
      'StateError: failed',
      '保存しました: report.pdf',
    ]) {
      for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
        expect(gakujoUserFacingMessage(message, platform: platform), message);
      }
    }
  });

  test('Linux text uses one Japanese font family before system fallbacks', () {
    final theme = buildGakujoTheme(TargetPlatform.linux);
    for (final style in [
      theme.textTheme.bodyMedium,
      theme.textTheme.titleLarge,
    ]) {
      expect(style!.fontFamily, 'Noto Sans CJK JP');
      expect(style.fontFamilyFallback, [
        'Noto Sans JP',
        'Source Han Sans JP',
        'IPAexGothic',
        'IPAGothic',
        'VL Gothic',
      ]);
    }
  });

  test('other platforms keep the default font selection', () {
    final defaults = ThemeData(useMaterial3: true).textTheme.bodyMedium!;
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.linux) continue;
      final style = buildGakujoTheme(platform).textTheme.bodyMedium!;
      expect(style.fontFamily, defaults.fontFamily, reason: platform.name);
      expect(
        style.fontFamilyFallback,
        defaults.fontFamilyFallback,
        reason: platform.name,
      );
    }
  });
}

PlatformException _lockedError() =>
    PlatformException(code: 'KeyringLocked', message: 'KeyringLocked');

class _FolderStorage extends FlutterSecureStorage {
  String? readValue;
  Object? readError;
  Object? writeError;
  Future<String?>? pendingRead;
  Future<void>? pendingWrite;
  int readCalls = 0;
  int writeCalls = 0;
  int deleteCalls = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readCalls++;
    if (readError != null) throw readError!;
    return pendingRead == null ? readValue : await pendingRead;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writeCalls++;
    if (writeError != null) throw writeError!;
    await pendingWrite;
    readValue = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deleteCalls++;
  }
}
