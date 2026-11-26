import 'package:base32/base32.dart' as codec;

class Base32 {
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
    final normalized = normalize(secret);
    if (!isValid(normalized)) {
      throw const FormatException('Invalid Base32 secret');
    }
    return codec.base32.decode(normalized).toList();
  }
}
