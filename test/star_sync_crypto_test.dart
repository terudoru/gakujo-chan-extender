import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_crypto.dart';

const fast = StarSyncKdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

void main() {
  test('keyring and encrypted file round trip', () async {
    final created = await createStarSyncKeyring('password', params: fast);
    final parsed = StarSyncKeyring.fromJson(created.keyring.toJson());
    final key = await unwrapStarSyncKeyring(parsed, 'password');
    expect(
      await starSyncKeyBytes(key),
      await starSyncKeyBytes(created.dataKey),
    );
    final bytes = await encryptStarSyncFile(
      dataKey: key,
      keyId: parsed.keyId,
      deviceId: 'device',
      plaintext: utf8.encode('hello'),
    );
    final plain = await decryptStarSyncFile(
      dataKey: key,
      keyId: parsed.keyId,
      bytes: bytes,
      expectedDeviceId: 'device',
    );
    expect(utf8.decode(plain), 'hello');
    expect(
      await starSyncKeyBytes(starSyncKeyFromBytes(await starSyncKeyBytes(key))),
      await starSyncKeyBytes(key),
    );
    expect(() => starSyncKeyFromBytes([1]), throwsArgumentError);
  });

  test('wrong passphrase is rejected and rewrap preserves the key', () async {
    final created = await createStarSyncKeyring('old', params: fast);
    await expectLater(
      unwrapStarSyncKeyring(created.keyring, 'wrong'),
      throwsA(isA<StarSyncWrongPassphraseException>()),
    );
    final rewrapped = await rewrapStarSyncKeyring(
      created.dataKey,
      created.keyring,
      'new',
      params: fast,
    );
    expect(rewrapped.keyId, created.keyring.keyId);
    expect(rewrapped.salt, isNot(created.keyring.salt));
    expect(
      await starSyncKeyBytes(await unwrapStarSyncKeyring(rewrapped, 'new')),
      await starSyncKeyBytes(created.dataKey),
    );
    await expectLater(
      unwrapStarSyncKeyring(rewrapped, 'old'),
      throwsA(isA<StarSyncWrongPassphraseException>()),
    );
  });

  test('authenticated header and ciphertext reject modifications', () async {
    final created = await createStarSyncKeyring('pass', params: fast);
    final bytes = await encryptStarSyncFile(
      dataKey: created.dataKey,
      keyId: created.keyring.keyId,
      deviceId: 'device',
      plaintext: [1, 2, 3],
    );
    final size = ByteData.sublistView(bytes, 5, 9).getUint32(0);
    final header = jsonDecode(utf8.decode(bytes.sublist(9, 9 + size))) as Map;
    final nonce = base64Decode(header['nonce'] as String)..[0] ^= 1;
    header['nonce'] = base64Encode(nonce);
    final changedHeader = utf8.encode(jsonEncode(header));
    expect(changedHeader.length, size);
    final tamperedHeader = Uint8List.fromList(bytes)
      ..setRange(9, 9 + size, changedHeader);
    await expectLater(
      decryptStarSyncFile(
        dataKey: created.dataKey,
        keyId: created.keyring.keyId,
        bytes: tamperedHeader,
        expectedDeviceId: 'device',
      ),
      throwsA(isA<StarSyncDecryptException>()),
    );
    final tamperedBody = Uint8List.fromList(bytes)..[9 + size] ^= 1;
    await expectLater(
      decryptStarSyncFile(
        dataKey: created.dataKey,
        keyId: created.keyring.keyId,
        bytes: tamperedBody,
        expectedDeviceId: 'device',
      ),
      throwsA(isA<StarSyncDecryptException>()),
    );
    await expectLater(
      decryptStarSyncFile(
        dataKey: created.dataKey,
        keyId: created.keyring.keyId,
        bytes: bytes,
        expectedDeviceId: 'other',
      ),
      throwsA(isA<StarSyncFormatException>()),
    );
  });

  test('rejects unsupported schema and unsafe KDF parameters', () async {
    final created = await createStarSyncKeyring('pass', params: fast);
    final json = created.keyring.toJson();
    json['schema'] = 2;
    expect(
      () => StarSyncKeyring.fromJson(json),
      throwsA(isA<StarSyncFormatException>()),
    );
    json['schema'] = 1;
    final kdf = json['kdf'] as Map;
    kdf['memoryKiB'] = 1048577;
    expect(
      () => StarSyncKeyring.fromJson(json),
      throwsA(isA<StarSyncFormatException>()),
    );
    kdf['memoryKiB'] = 64;
    kdf['iterations'] = 21;
    expect(
      () => StarSyncKeyring.fromJson(json),
      throwsA(isA<StarSyncFormatException>()),
    );
    kdf['iterations'] = 1;
    kdf['parallelism'] = 9;
    expect(
      () => StarSyncKeyring.fromJson(json),
      throwsA(isA<StarSyncFormatException>()),
    );
  });

  test('legacy keyrings and strict pairing keyrings', () async {
    final created = await createStarSyncKeyring('password', params: fast);
    final legacy = created.keyring.toJson()..remove('mode');
    expect(StarSyncKeyring.fromJson(legacy).mode, 'passphrase');
    final pairing = createStarSyncPairingKeyring();
    final json = pairing.keyring.toJson();
    expect(json.keys.toSet(), {'schema', 'keyId', 'mode'});
    expect(StarSyncKeyring.fromJson(json).mode, 'pairing');
    json['salt'] = 'unexpected';
    expect(
      () => StarSyncKeyring.fromJson(json),
      throwsA(isA<StarSyncFormatException>()),
    );
  });

  test('pairing code normalization and checksum', () {
    final pairing = createStarSyncPairingKeyring();
    final code = encodeStarSyncPairingCode(
      pairing.keyring.keyId,
      pairing.dataKey,
    );
    final decoded = decodeStarSyncPairingCode('mbgstar: ${code.toLowerCase()}');
    expect(decoded.keyId, pairing.keyring.keyId);
    expect(decoded.dataKey, pairing.dataKey);
    final plain = code.replaceAll('-', '');
    final last = plain[plain.length - 1];
    final changed =
        plain.substring(0, plain.length - 1) + (last == 'A' ? 'B' : 'A');
    expect(
      () => decodeStarSyncPairingCode(changed),
      throwsA(isA<StarSyncFormatException>()),
    );
  });
}
