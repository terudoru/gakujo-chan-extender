import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:morebettergakujo_flutter/src/two_factor_secret_store.dart';
import 'package:test/test.dart';

void main() {
  test('save normalizes lowercase and whitespace before storing', () async {
    final storage = _MemorySecureStorage();
    final store = TwoFactorSecretStore(secureStorage: storage);

    await store.save(' jbsw y3dp\tehpk 3pxp\n');

    expect(await store.load(), 'JBSWY3DPEHPK3PXP');
  });

  test('save rejects invalid Base32 without storing a value', () async {
    final storage = _MemorySecureStorage();
    final store = TwoFactorSecretStore(secureStorage: storage);

    for (final secret in ['', 'JBSWY3DP1']) {
      expect(store.save(secret), throwsFormatException, reason: secret);
      expect(await store.load(), isNull, reason: secret);
    }
  });

  test('clear removes the stored secret', () async {
    final storage = _MemorySecureStorage();
    final store = TwoFactorSecretStore(secureStorage: storage);
    await store.save('JBSWY3DPEHPK3PXP');

    await store.clear();

    expect(await store.load(), isNull);
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage([Map<String, String>? initial])
      : values = Map<String, String>.from(initial ?? const {});

  final Map<String, String> values;

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
}
