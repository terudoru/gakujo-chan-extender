class Base32 {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  const Base32._();

  static String normalize(String secret) {
    return secret.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  }

  static bool isValid(String secret) {
    final normalized = normalize(secret);
    return normalized.isNotEmpty &&
        RegExp(r'^[A-Z2-7]+=*$').hasMatch(normalized);
  }

  static List<int> decode(String secret) {
    final normalized = normalize(secret).replaceAll(RegExp(r'=+$'), '');
    if (!isValid(normalized)) {
      throw const FormatException('Invalid Base32 secret');
    }

    final output = <int>[];
    var buffer = 0;
    var bitsLeft = 0;

    for (final codeUnit in normalized.codeUnits) {
      final value = _alphabet.indexOf(String.fromCharCode(codeUnit));
      if (value < 0) {
        throw const FormatException('Invalid Base32 character');
      }

      buffer = (buffer << 5) | value;
      bitsLeft += 5;

      if (bitsLeft >= 8) {
        output.add((buffer >> (bitsLeft - 8)) & 0xff);
        bitsLeft -= 8;
      }
    }

    return output;
  }
}
