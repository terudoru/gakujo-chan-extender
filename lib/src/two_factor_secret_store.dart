import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'base32.dart';

class TwoFactorSecretStore {
  TwoFactorSecretStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _secretKey = 'more_better_gakujo_2fa_secret';

  final FlutterSecureStorage _secureStorage;

  Future<void> save(String rawSecret) async {
    final normalized = Base32.normalize(rawSecret);
    if (!Base32.isValid(normalized)) {
      throw const FormatException('Invalid Base32 secret');
    }

    await _secureStorage.write(key: _secretKey, value: normalized);
  }

  Future<String?> load() {
    return _secureStorage.read(key: _secretKey);
  }

  Future<void> clear() {
    return _secureStorage.delete(key: _secretKey);
  }
}
