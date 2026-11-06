import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/protected_secrets_vault.dart';
import 'package:morebettergakujo_flutter/src/two_factor_secret_store.dart';

const record = '{"version":1,"loginId":"student","password":"test-password"}';
const secret = 'JBSWY3DPEHPK3PXP';

void main() {
  late MemoryStorage normal;
  late MemoryStorage protected;
  late ProtectedSecretsVault vault;
  late SecretProtectionState state;
  late SecretProtectionController controller;
  late DateTime now;

  setUp(() {
    normal = MemoryStorage({
      loginRecordKey: record,
      twoFactorSecretKey: secret,
      loginIdKey: 'old',
      loginPasswordKey: 'old-password',
    });
    protected = MemoryStorage();
    now = DateTime(2026);
    vault = ProtectedSecretsVault(storage: protected, clock: () => now);
    state = SecretProtectionState(
      storage: normal,
      vault: vault,
      supported: true,
    );
    controller = SecretProtectionController(state);
  });
  tearDown(() => vault.clearCache());

  test(
    'enable verifies and moves both fields, then disable restores them',
    () async {
      await controller.enable();
      expect((await state.read()).enabled, isTrue);
      expect(normal.values[loginRecordKey], loginTombstone);
      expect(normal.values.containsKey(loginIdKey), isFalse);
      expect(normal.values.containsKey(loginPasswordKey), isFalse);
      expect(normal.values.containsKey(twoFactorSecretKey), isFalse);
      expect((await vault.read())?.loginCredentials, record);
      expect((await vault.read())?.twoFactorSecret, secret);
      await controller.disable();
      expect(normal.values[loginRecordKey], record);
      expect(normal.values[twoFactorSecretKey], secret);
      expect((await state.read()).enabled, isFalse);
      expect(protected.values.containsKey(protectedSecretsKey), isFalse);
    },
  );

  test(
    'failed write and failed verification preserve normal storage',
    () async {
      final before = Map<String, String>.of(normal.values);
      protected.failWrite = true;
      await expectLater(controller.enable(), throwsA(isA<Object>()));
      expect(normal.values, before);
      expect((await state.read()).enabled, isFalse);
      protected.failWrite = false;
      protected.mismatch = true;
      await expectLater(controller.enable(), throwsA(isA<Object>()));
      expect(normal.values, before);
      expect((await state.read()).enabled, isFalse);
    },
  );

  test(
    'settings and presence never read vault, shared cache expires',
    () async {
      await controller.enable();
      vault.clearCache();
      protected.reads = 0;
      final settings = GakujoAppSettingsStore(
        secureStorage: normal,
        protectionState: state,
      );
      final twoFactor = TwoFactorSecretStore(
        secureStorage: normal,
        protectionState: state,
      );
      expect((await settings.load()).savedLoginId, 'student');
      expect(await twoFactor.hasSecret(), isTrue);
      expect(protected.reads, 0);
      expect((await settings.loadLoginCredentials())?.loginId, 'student');
      expect(await twoFactor.load(), secret);
      expect(protected.reads, 1);
      now = now.add(const Duration(seconds: 91));
      expect(await twoFactor.load(), secret);
      expect(protected.reads, 2);
    },
  );

  test('concurrent login and two-factor saves preserve both values', () async {
    await state.write(const SecretProtectionInfo(enabled: true));
    final settings = GakujoAppSettingsStore(
      secureStorage: normal,
      protectionState: state,
    );
    final twoFactor = TwoFactorSecretStore(
      secureStorage: normal,
      protectionState: state,
    );

    await Future.wait([
      settings.saveLoginCredentials(
        loginId: 'student',
        password: 'test-password',
      ),
      twoFactor.save(secret),
    ]);

    vault.clearCache();
    final saved = await vault.read();
    expect(saved?.loginCredentials, record);
    expect(saved?.twoFactorSecret, secret);
  });

  test('saving with protection enabled creates a missing vault', () async {
    await state.write(const SecretProtectionInfo(enabled: true));
    final settings = GakujoAppSettingsStore(
      secureStorage: normal,
      protectionState: state,
    );

    await settings.saveLoginCredentials(
      loginId: 'student',
      password: 'test-password',
    );

    expect(protected.values.containsKey(protectedSecretsKey), isTrue);
    vault.clearCache();
    expect((await vault.read())?.loginCredentials, record);
  });

  test('disable with a missing vault clears normal secrets', () async {
    await state.write(const SecretProtectionInfo(enabled: true));

    await controller.disable();

    expect(normal.values[loginRecordKey], loginTombstone);
    expect(normal.values.containsKey(twoFactorSecretKey), isFalse);
    expect((await state.read()).enabled, isFalse);
    expect(protected.values.containsKey(protectedSecretsKey), isFalse);
  });

  test('unreadable vault is typed and discard clears all secrets', () async {
    await controller.enable();
    vault.clearCache();
    protected.failRead = true;
    await expectLater(
      controller.disable(),
      throwsA(isA<ProtectedSecretsUnreadable>()),
    );
    protected.failRead = false;
    await controller.disableAndDiscard();
    expect((await state.read()).enabled, isFalse);
    expect(normal.values[loginRecordKey], loginTombstone);
    expect(normal.values.containsKey(twoFactorSecretKey), isFalse);
    expect(protected.values.containsKey(protectedSecretsKey), isFalse);
  });
}

class MemoryStorage extends FlutterSecureStorage {
  MemoryStorage([Map<String, String>? initial])
    : values = Map.of(initial ?? {});
  final Map<String, String> values;
  int reads = 0;
  bool failWrite = false;
  bool failRead = false;
  bool mismatch = false;

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
    reads++;
    if (failRead) throw StateError('read failed');
    if (mismatch && key == protectedSecretsKey) {
      return jsonEncode({'version': 1});
    }
    return values[key];
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
    if (failWrite) throw StateError('write failed');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
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
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(values);
}
