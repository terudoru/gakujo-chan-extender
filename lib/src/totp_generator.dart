import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'base32.dart';

class TotpGenerator {
  const TotpGenerator({
    this.periodSeconds = 30,
    this.digits = 6,
  });

  final int periodSeconds;
  final int digits;

  String currentToken(String base32Secret, {DateTime? now}) {
    final nowMillis = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final counter = nowMillis ~/ 1000 ~/ periodSeconds;
    return hotp(Base32.decode(base32Secret), counter);
  }

  String hotp(List<int> secret, int counter) {
    final counterBytes = ByteData(8)..setInt64(0, counter);
    final hmac = Hmac(sha1, secret);
    final hash = hmac.convert(counterBytes.buffer.asUint8List()).bytes;
    final offset = hash.last & 0x0f;
    final binary = ((hash[offset] & 0x7f) << 24) |
        ((hash[offset + 1] & 0xff) << 16) |
        ((hash[offset + 2] & 0xff) << 8) |
        (hash[offset + 3] & 0xff);
    final modulo = _pow10(digits);
    return (binary % modulo).toString().padLeft(digits, '0');
  }

  int _pow10(int exponent) {
    if (exponent <= 0) {
      throw ArgumentError.value(exponent, 'digits', 'must be positive');
    }

    return int.parse('1${'0' * exponent}');
  }
}
