import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/star_sync/star_sync_crypto.dart';

void main() {
  test('keyring and encrypted file round trip', () async {
    final created = createStarSyncDriveKeyring();
    final parsed = StarSyncKeyring.fromJson(created.keyring.toJson());
    final key = starSyncKeyFromBytes(parsed.dataKey);
    expect(
      await starSyncKeyBytes(key),
      created.dataKey,
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

  test('file key id is read from a well formed header only', () async {
    final created = createStarSyncDriveKeyring();
    final bytes = await encryptStarSyncFile(
      dataKey: starSyncKeyFromBytes(created.dataKey),
      keyId: created.keyring.keyId,
      deviceId: 'device',
      plaintext: [1],
    );
    expect(starSyncFileKeyId(bytes), created.keyring.keyId);
    bytes[bytes.length - 1] ^= 1;
    expect(starSyncFileKeyId(bytes), created.keyring.keyId);
    expect(starSyncFileKeyId(bytes.sublist(0, 9)), isNull);
    expect(starSyncFileKeyId([1, 2, 3]), isNull);
    bytes[0] = 0;
    expect(starSyncFileKeyId(bytes), isNull);
  });

  test('authenticated header and ciphertext reject modifications', () async {
    final created = createStarSyncDriveKeyring();
    final bytes = await encryptStarSyncFile(
      dataKey: starSyncKeyFromBytes(created.dataKey),
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
        dataKey: starSyncKeyFromBytes(created.dataKey),
        keyId: created.keyring.keyId,
        bytes: tamperedHeader,
        expectedDeviceId: 'device',
      ),
      throwsA(isA<StarSyncDecryptException>()),
    );
    final tamperedBody = Uint8List.fromList(bytes)..[9 + size] ^= 1;
    await expectLater(
      decryptStarSyncFile(
        dataKey: starSyncKeyFromBytes(created.dataKey),
        keyId: created.keyring.keyId,
        bytes: tamperedBody,
        expectedDeviceId: 'device',
      ),
      throwsA(isA<StarSyncDecryptException>()),
    );
    await expectLater(
      decryptStarSyncFile(
        dataKey: starSyncKeyFromBytes(created.dataKey),
        keyId: created.keyring.keyId,
        bytes: bytes,
        expectedDeviceId: 'other',
      ),
      throwsA(isA<StarSyncFormatException>()),
    );
  });

  test('legacy keyrings parse for reset', () {
    final created = createStarSyncDriveKeyring();
    final legacy = {'schema': 1, 'keyId': created.keyring.keyId};
    expect(StarSyncKeyring.fromJson(legacy).mode, 'passphrase');
    expect(StarSyncKeyring.fromJson({...legacy, 'mode': 'passphrase'}).mode, 'passphrase');
    expect(StarSyncKeyring.fromJson({...legacy, 'mode': 'pairing'}).mode, 'pairing');
  });

  test('drive keyring round trips and rejects malformed data', () {
    final created = createStarSyncDriveKeyring();
    final drive = StarSyncKeyring.drive(
      keyId: created.keyring.keyId,
      dataKey: created.dataKey,
    );
    final json = drive.toJson();
    expect(json.keys.toSet(), {'schema', 'keyId', 'mode', 'dataKey'});
    final parsed = StarSyncKeyring.fromJson(json);
    expect(parsed.mode, 'drive');
    expect(parsed.keyId, drive.keyId);
    expect(parsed.dataKey, created.dataKey);
    for (final invalid in [
      {...json, 'schema': 2},
      {...json, 'dataKey': base64Encode(List<int>.filled(31, 0))},
      {...json, 'dataKey': 'invalid!'},
      {...json, 'dataKey': null},
      {...json, 'extra': true},
      {...json, 'keyId': 'invalid'},
    ]) {
      expect(
        () => StarSyncKeyring.fromJson(invalid),
        throwsA(isA<StarSyncFormatException>()),
      );
    }
  });


}
