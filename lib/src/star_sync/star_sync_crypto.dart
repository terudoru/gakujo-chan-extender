import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'star_sync_document.dart';
export 'star_sync_document.dart' show StarSyncFormatException;

class StarSyncDecryptException implements Exception {
  const StarSyncDecryptException();
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
  StarSyncKeyring._legacy({required this.keyId, required this.mode})
    : dataKey = const [];

  StarSyncKeyring.drive({required this.keyId, required List<int> dataKey})
    : mode = 'drive', dataKey = List.unmodifiable(dataKey);

  static const int schema = 1;
  final String mode;
  final String keyId;
  final List<int> dataKey;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'keyId': keyId,
    'mode': mode,
    if (mode == 'drive') 'dataKey': _encode(dataKey),
  };

  static StarSyncKeyring fromJson(Object? value) {
    if (value is! Map || value['schema'] != schema ||
        value['keyId'] is! String || !_validKeyId(value['keyId'] as String)) {
      throw const StarSyncFormatException();
    }
    final mode = value.containsKey('mode') ? value['mode'] : 'passphrase';
    if (mode is String && mode != 'drive') {
      return StarSyncKeyring._legacy(keyId: value['keyId'] as String, mode: mode);
    }
    if (mode == 'drive' && value.length == 4) {
      return StarSyncKeyring.drive(
        keyId: value['keyId'] as String,
        dataKey: _decode(value['dataKey'], 32),
      );
    }
    throw const StarSyncFormatException();
  }
}

List<int> _randomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

({StarSyncKeyring keyring, List<int> dataKey}) createStarSyncDriveKeyring() {
  final dataKey = _randomBytes(32);
  return (
    keyring: StarSyncKeyring.drive(keyId: _keyId(_randomBytes(16)), dataKey: dataKey),
    dataKey: dataKey,
  );
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
  String? kind,
}) async {
  await starSyncKeyBytes(dataKey);
  final nonce = _randomBytes(12);
  final header = utf8.encode(
    jsonEncode({
      'keyId': keyId,
      'deviceId': deviceId,
      'nonce': _encode(nonce),
      'kind': ?kind,
    }),
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

String? starSyncFileKeyId(List<int> bytes) {
  if (bytes.length < 25 ||
      bytes.take(9).any((byte) => byte < 0 || byte > 255) ||
      bytes[0] != 77 ||
      bytes[1] != 66 ||
      bytes[2] != 71 ||
      bytes[3] != 83 ||
      bytes[4] != 1) {
    return null;
  }
  final size = (bytes[5] << 24) | (bytes[6] << 16) | (bytes[7] << 8) | bytes[8];
  if (size > 4096 || 9 + size + 16 > bytes.length) return null;
  try {
    final headerBytes = bytes.sublist(9, 9 + size);
    if (headerBytes.any((byte) => byte < 0 || byte > 255)) return null;
    final header = jsonDecode(utf8.decode(headerBytes));
    if (header is! Map ||
        header['keyId'] is! String ||
        !_validKeyId(header['keyId'] as String) ||
        header['deviceId'] is! String ||
        (header['deviceId'] as String).isEmpty) {
      return null;
    }
    _decode(header['nonce'], 12);
    return header['keyId'] as String;
  } on FormatException {
    return null;
  } on StarSyncFormatException {
    return null;
  }
}

Future<List<int>> decryptStarSyncFile({
  required SecretKey dataKey,
  required String keyId,
  required List<int> bytes,
  required String expectedDeviceId,
  String? kind,
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
      header['kind'] != kind ||
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
