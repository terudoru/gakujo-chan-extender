class Base32 {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  const Base32._();

  static String normalize(String secret) {
    return secret.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  }

  static bool isValid(String secret) {
    final normalized = normalize(secret);
    if (normalized.isEmpty ||
        !RegExp(r'^[A-Z2-7]+={0,6}$').hasMatch(normalized)) {
      return false;
    }

    final paddingStart = normalized.indexOf('=');
    final data =
        paddingStart < 0 ? normalized : normalized.substring(0, paddingStart);
    final paddingLength = normalized.length - data.length;
    final remainder = data.length % 8;
    const expectedPadding = <int, int>{0: 0, 2: 6, 4: 4, 5: 3, 7: 1};
    if (!expectedPadding.containsKey(remainder)) {
      return false;
    }
    if (paddingLength > 0 &&
        (normalized.length % 8 != 0 ||
            paddingLength != expectedPadding[remainder])) {
      return false;
    }

    return true;
  }

  static List<int> decode(String secret) {
    final normalizedWithPadding = normalize(secret);
    if (!isValid(normalizedWithPadding)) {
      throw const FormatException('Invalid Base32 secret');
    }
    final normalized = normalizedWithPadding.replaceAll(RegExp(r'=+$'), '');

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
