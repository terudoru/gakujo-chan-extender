import 'package:morebettergakujo_flutter/src/two_factor_secret_store.dart';
import 'package:test/test.dart';

import 'support/memory_secure_storage.dart';

void main() {
  test('save normalizes lowercase and whitespace before storing', () async {
    final storage = MemorySecureStorage();
    final store = TwoFactorSecretStore(secureStorage: storage);

    await store.save(' jbsw y3dp\tehpk 3pxp\n');

    expect(await store.load(), 'JBSWY3DPEHPK3PXP');
  });

  test('save rejects invalid Base32 without storing a value', () async {
    final storage = MemorySecureStorage();
    final store = TwoFactorSecretStore(secureStorage: storage);

    for (final secret in ['', 'JBSWY3DP1', 'A', 'MY=']) {
      expect(store.save(secret), throwsFormatException, reason: secret);
      expect(await store.load(), isNull, reason: secret);
    }
  });

  test('clear removes the stored secret', () async {
    final storage = MemorySecureStorage();
    final store = TwoFactorSecretStore(secureStorage: storage);
    await store.save('JBSWY3DPEHPK3PXP');

    await store.clear();

    expect(await store.load(), isNull);
  });
}
