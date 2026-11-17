import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/main.dart';
import 'package:morebettergakujo_flutter/src/file_system_gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

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

  test('Linux locked storage is explained without the raw exception', () async {
    var pickerOpened = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      pickerOpened = true;
      return null;
    });
    final service = FileSystemGakujoDownloadService(
      secureStorage: _LockedStorage(),
      usesNativeDownloadRoot: false,
    );
    try {
      await service.pickDownloadRoot();
      fail('Expected locked storage to prevent loading the configured folder');
    } on PlatformException catch (error) {
      final message = gakujoUserFacingMessage(
        '保存先を設定できませんでした: ${error.message ?? error.code}',
        platform: TargetPlatform.linux,
      );
      expect(message, contains('キーリング'));
      expect(message, contains('ロックを解除'));
      expect(message, isNot(contains('KeyringLocked')));
      expect(message, isNot(contains('PlatformException')));
    }
    expect(pickerOpened, isFalse);
  });

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

class _LockedStorage extends FlutterSecureStorage {
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
    throw PlatformException(code: 'KeyringLocked', message: 'KeyringLocked');
  }
}
