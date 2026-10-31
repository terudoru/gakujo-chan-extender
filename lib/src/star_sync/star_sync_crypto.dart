import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';

import '../base32.dart';
import 'star_sync_document.dart';
export 'star_sync_document.dart' show StarSyncFormatException;

class StarSyncWrongPassphraseException implements Exception {
  const StarSyncWrongPassphraseException();
}

class StarSyncDecryptException implements Exception {
  const StarSyncDecryptException();
}

class StarSyncKdfParams {
  const StarSyncKdfParams({
    this.memoryKiB = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  void _validate() {
    if (memoryKiB > 65536 ||
        iterations > 10 ||
        parallelism > 4 ||
        parallelism < 1 ||
        iterations < 1 ||
        memoryKiB < 8 * parallelism) {
      throw const StarSyncFormatException('Invalid KDF parameters');
    }
  }
}

String _encode(List<int> bytes) => base64Encode(bytes);
String _keyId(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

List<int> _decode(Object? value, int length) {
  if (value is! String) {
    throw const StarSyncFormatException();
  }
  try {
    final result = base64Decode(value);
    if (result.length != length) {
      throw const StarSyncFormatException();
    }
    return result;
  } on FormatException {
    throw const StarSyncFormatException();
  }
}

bool _validKeyId(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(value)) {
    return false;
  }
  try {
    final decoded = base64Url.decode(base64Url.normalize(value));
    return decoded.length == 16 && _keyId(decoded) == value;
  } on FormatException {
    return false;
  }
}

class StarSyncKeyring {
  StarSyncKeyring({
    required this.keyId,
    required this.params,
    required List<int> salt,
    required List<int> nonce,
    required List<int> wrappedKey,
  }) : mode = 'passphrase',
       salt = List.unmodifiable(salt),
       nonce = List.unmodifiable(nonce),
       wrappedKey = List.unmodifiable(wrappedKey);

  StarSyncKeyring.pairing({required this.keyId})
    : mode = 'pairing',
      params = const StarSyncKdfParams(),
      salt = const [],
      nonce = const [],
      wrappedKey = const [];

  static const int schema = 1;
  final String mode;
  final String keyId;
  final StarSyncKdfParams params;
  final List<int> salt;
  final List<int> nonce;
  final List<int> wrappedKey;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'keyId': keyId,
    'mode': mode,
    if (mode == 'passphrase')
      'kdf': {
        'name': 'argon2id',
        'memoryKiB': params.memoryKiB,
        'iterations': params.iterations,
        'parallelism': params.parallelism,
      },
    if (mode == 'passphrase') 'salt': _encode(salt),
    if (mode == 'passphrase') 'nonce': _encode(nonce),
    if (mode == 'passphrase') 'wrappedKey': _encode(wrappedKey),
  };

  static StarSyncKeyring fromJson(Object? value) {
    if (value is! Map ||
        value['schema'] != schema ||
        value['keyId'] is! String ||
        !_validKeyId(value['keyId'] as String)) {
      throw const StarSyncFormatException();
    }
    final mode = value.containsKey('mode') ? value['mode'] : 'passphrase';
    if (mode == 'pairing') {
      if (value.length != 3) throw const StarSyncFormatException();
      return StarSyncKeyring.pairing(keyId: value['keyId'] as String);
    }
    if (mode != 'passphrase' ||
        value['kdf'] is! Map ||
        value.keys.any(
          (key) => !{
            'schema',
            'keyId',
            'mode',
            'kdf',
            'salt',
            'nonce',
            'wrappedKey',
          }.contains(key),
        )) {
      throw const StarSyncFormatException();
    }
    final kdf = value['kdf'] as Map;
    if (kdf.length != 4 ||
        kdf['name'] != 'argon2id' ||
        kdf['memoryKiB'] is! int ||
        kdf['iterations'] is! int ||
        kdf['parallelism'] is! int) {
      throw const StarSyncFormatException();
    }
    final params = StarSyncKdfParams(
      memoryKiB: kdf['memoryKiB'] as int,
      iterations: kdf['iterations'] as int,
      parallelism: kdf['parallelism'] as int,
    );
    params._validate();
    return StarSyncKeyring(
      keyId: value['keyId'] as String,
      params: params,
      salt: _decode(value['salt'], 16),
      nonce: _decode(value['nonce'], 12),
      wrappedKey: _decode(value['wrappedKey'], 48),
    );
  }
}

List<int> _randomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

({StarSyncKeyring keyring, List<int> dataKey}) createStarSyncPairingKeyring() {
  return (
    keyring: StarSyncKeyring.pairing(keyId: _keyId(_randomBytes(16))),
    dataKey: _randomBytes(32),
  );
}

String _encodeBase32(List<int> bytes) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final result = StringBuffer();
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      result.write(alphabet[(buffer >> bits) & 31]);
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) result.write(alphabet[(buffer << (5 - bits)) & 31]);
  return result.toString();
}

String encodeStarSyncPairingCode(String keyId, List<int> dataKey) {
  if (!_validKeyId(keyId) ||
      dataKey.length != 32 ||
      dataKey.any((byte) => byte < 0 || byte > 255)) {
    throw const StarSyncFormatException();
  }
  final payload = <int>[
    ...ascii.encode('MBGP'),
    1,
    ...base64Url.decode(base64Url.normalize(keyId)),
    ...dataKey,
  ];
  final encoded = _encodeBase32([
    ...payload,
    ...hashes.sha256.convert(payload).bytes.take(2),
  ]);
  return [
    for (var i = 0; i < encoded.length; i += 4)
      encoded.substring(i, min(i + 4, encoded.length)),
  ].join('-');
}

({String keyId, List<int> dataKey}) decodeStarSyncPairingCode(String code) {
  var normalized = Base32.normalize(code);
  if (normalized.startsWith('MBGSTAR:')) normalized = normalized.substring(8);
  try {
    if (!RegExp(r'^[A-Z2-7]{88}$').hasMatch(normalized)) {
      throw const StarSyncFormatException();
    }
    final bytes = Base32.decode(normalized);
    if (bytes.length != 55 ||
        _encodeBase32(bytes) != normalized ||
        bytes[0] != 77 ||
        bytes[1] != 66 ||
        bytes[2] != 71 ||
        bytes[3] != 80 ||
        bytes[4] != 1) {
      throw const StarSyncFormatException();
    }
    final digest = hashes.sha256.convert(bytes.sublist(0, 53)).bytes;
    if (bytes[53] != digest[0] || bytes[54] != digest[1]) {
      throw const StarSyncFormatException();
    }
    return (
      keyId: _keyId(bytes.sublist(5, 21)),
      dataKey: bytes.sublist(21, 53),
    );
  } on FormatException {
    throw const StarSyncFormatException();
  }
}

Future<SecretKey> _derive(
  String passphrase,
  List<int> salt,
  StarSyncKdfParams params,
) {
  params._validate();
  return Argon2id(
    memory: params.memoryKiB,
    iterations: params.iterations,
    parallelism: params.parallelism,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
}

Future<StarSyncKeyring> _wrap(
  SecretKey dataKey,
  String keyId,
  String passphrase,
  StarSyncKdfParams params,
) async {
  final keyBytes = await starSyncKeyBytes(dataKey);
  final salt = _randomBytes(16);
  final nonce = _randomBytes(12);
  final wrappingKey = await _derive(passphrase, salt, params);
  final box = await AesGcm.with256bits().encrypt(
    keyBytes,
    secretKey: wrappingKey,
    nonce: nonce,
    aad: utf8.encode('mbg-star-keyring:$keyId'),
  );
  return StarSyncKeyring(
    keyId: keyId,
    params: params,
    salt: salt,
    nonce: nonce,
    wrappedKey: [...box.cipherText, ...box.mac.bytes],
  );
}

Future<({StarSyncKeyring keyring, SecretKey dataKey})> createStarSyncKeyring(
  String passphrase, {
  StarSyncKdfParams params = const StarSyncKdfParams(),
}) async {
  final dataKey = SecretKey(_randomBytes(32));
  final keyring = await _wrap(
    dataKey,
    _keyId(_randomBytes(16)),
    passphrase,
    params,
  );
  return (keyring: keyring, dataKey: dataKey);
}

Future<SecretKey> unwrapStarSyncKeyring(
  StarSyncKeyring keyring,
  String passphrase,
) async {
  final checked = StarSyncKeyring.fromJson(keyring.toJson());
  if (checked.mode != 'passphrase') throw StateError('Pairing keyring');
  final wrappingKey = await _derive(passphrase, checked.salt, checked.params);
  try {
    final bytes = await AesGcm.with256bits().decrypt(
      SecretBox(
        checked.wrappedKey.sublist(0, 32),
        nonce: checked.nonce,
        mac: Mac(checked.wrappedKey.sublist(32)),
      ),
      secretKey: wrappingKey,
      aad: utf8.encode('mbg-star-keyring:${checked.keyId}'),
    );
    return starSyncKeyFromBytes(bytes);
  } on SecretBoxAuthenticationError {
    throw const StarSyncWrongPassphraseException();
  }
}

Future<StarSyncKeyring> rewrapStarSyncKeyring(
  SecretKey dataKey,
  StarSyncKeyring old,
  String newPassphrase, {
  StarSyncKdfParams? params,
}) {
  if (old.mode != 'passphrase') throw StateError('Pairing keyring');
  return _wrap(dataKey, old.keyId, newPassphrase, params ?? old.params);
}

Future<List<int>> starSyncKeyBytes(SecretKey key) async {
  final bytes = await key.extractBytes();
  if (bytes.length != 32) {
    throw ArgumentError('Data key must be 32 bytes');
  }
  return bytes;
}

SecretKey starSyncKeyFromBytes(List<int> bytes) {
  if (bytes.length != 32 || bytes.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError('Data key must be 32 bytes');
  }
  return SecretKey(List<int>.from(bytes));
}

Future<Uint8List> encryptStarSyncFile({
  required SecretKey dataKey,
  required String keyId,
  required String deviceId,
  required List<int> plaintext,
}) async {
  await starSyncKeyBytes(dataKey);
  final nonce = _randomBytes(12);
  final header = utf8.encode(
    jsonEncode({'keyId': keyId, 'deviceId': deviceId, 'nonce': _encode(nonce)}),
  );
  if (header.length > 4096 || keyId.isEmpty || deviceId.isEmpty) {
    throw const StarSyncFormatException();
  }
  final length = ByteData(4)..setUint32(0, header.length, Endian.big);
  final aad = <int>[
    ...ascii.encode('MBGS'),
    1,
    ...length.buffer.asUint8List(),
    ...header,
  ];
  final box = await AesGcm.with256bits().encrypt(
    plaintext,
    secretKey: dataKey,
    nonce: nonce,
    aad: aad,
  );
  return Uint8List.fromList([...aad, ...box.cipherText, ...box.mac.bytes]);
}

Future<List<int>> decryptStarSyncFile({
  required SecretKey dataKey,
  required String keyId,
  required List<int> bytes,
  required String expectedDeviceId,
}) async {
  if (bytes.length < 25 ||
      bytes.any((byte) => byte < 0 || byte > 255) ||
      bytes[0] != 77 ||
      bytes[1] != 66 ||
      bytes[2] != 71 ||
      bytes[3] != 83 ||
      bytes[4] != 1) {
    throw const StarSyncFormatException();
  }
  final size = (bytes[5] << 24) | (bytes[6] << 16) | (bytes[7] << 8) | bytes[8];
  if (size > 4096 || 9 + size + 16 > bytes.length) {
    throw const StarSyncFormatException();
  }
  final end = 9 + size;
  Object? header;
  try {
    header = jsonDecode(utf8.decode(bytes.sublist(9, end)));
  } on FormatException {
    throw const StarSyncFormatException();
  }
  if (header is! Map ||
      header['keyId'] != keyId ||
      header['deviceId'] != expectedDeviceId ||
      keyId.isEmpty ||
      expectedDeviceId.isEmpty) {
    throw const StarSyncFormatException();
  }
  final nonce = _decode(header['nonce'], 12);
  await starSyncKeyBytes(dataKey);
  try {
    return await AesGcm.with256bits().decrypt(
      SecretBox(
        bytes.sublist(end, bytes.length - 16),
        nonce: nonce,
        mac: Mac(bytes.sublist(bytes.length - 16)),
      ),
      secretKey: dataKey,
      aad: bytes.sublist(0, end),
    );
  } on SecretBoxAuthenticationError {
    throw const StarSyncDecryptException();
  }
}
