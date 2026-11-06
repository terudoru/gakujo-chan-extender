import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'base32.dart';
import 'secure_storage_factory.dart';
import 'protected_secrets_vault.dart';

class TwoFactorSecretStore {
  TwoFactorSecretStore({
    FlutterSecureStorage? secureStorage,
    SecretProtectionState? protectionState,
  }) : _secureStorage = secureStorage ?? SecureStorageFactory.create(),
       protectionState = protectionState ?? SecretProtectionState(storage: secureStorage);

  static const _secretKey = 'more_better_gakujo_2fa_secret';

  final FlutterSecureStorage _secureStorage;
  final SecretProtectionState protectionState;

  Future<void> save(String rawSecret) async {
    final normalized = Base32.normalize(rawSecret);
    if (!Base32.isValid(normalized)) {
      throw const FormatException('Invalid Base32 secret');
    }

    final info = await protectionState.read();
    if (info.enabled) {
      await protectionState.updateSecrets(
        (old) => ProtectedSecrets(
          loginCredentials: old.loginCredentials,
          twoFactorSecret: normalized,
        ),
      );
      return;
    }
    await _secureStorage.write(key: _secretKey, value: normalized);
  }

  Future<String?> load() async {
    if ((await protectionState.read()).enabled) {
      return (await protectionState.vault.read())?.twoFactorSecret;
    }
    return _secureStorage.read(key: _secretKey);
  }

  Future<bool> hasSecret() async {
    final info = await protectionState.read();
    return info.enabled ? info.hasTwoFactorSecret : await load() != null;
  }

  Future<void> clear() async {
    final info = await protectionState.read();
    if (info.enabled) {
      await protectionState.updateSecrets(
        (old) => ProtectedSecrets(loginCredentials: old.loginCredentials),
      );
      return;
    }
    await _secureStorage.delete(key: _secretKey);
  }
}
