import 'package:morebettergakujo_flutter/src/base32.dart';
import 'package:test/test.dart';

void main() {
  test('decodes unpadded RFC 4648 test vectors', () {
    expect(Base32.decode('MY'), 'f'.codeUnits);
    expect(Base32.decode('MZXQ'), 'fo'.codeUnits);
    expect(Base32.decode('MZXW6'), 'foo'.codeUnits);
    expect(Base32.decode('MZXW6YQ'), 'foob'.codeUnits);
    expect(Base32.decode('MZXW6YTB'), 'fooba'.codeUnits);
    expect(Base32.decode('MZXW6YTBOI'), 'foobar'.codeUnits);
  });

  test('decodes padded RFC 4648 test vectors', () {
    expect(Base32.decode('MY======'), 'f'.codeUnits);
    expect(Base32.decode('MZXQ===='), 'fo'.codeUnits);
    expect(Base32.decode('MZXW6==='), 'foo'.codeUnits);
    expect(Base32.decode('MZXW6YQ='), 'foob'.codeUnits);
    expect(Base32.decode('MZXW6YTB'), 'fooba'.codeUnits);
    expect(Base32.decode('MZXW6YTBOI======'), 'foobar'.codeUnits);
  });

  test('decodes lowercase and separated input through normalization', () {
    expect(Base32.decode('mzxw6ytboi'), 'foobar'.codeUnits);
    expect(Base32.decode('MZXW6-YT BOI'), 'foobar'.codeUnits);
  });

  test('rejects empty and invalid input', () {
    for (final secret in ['', '1', '8', 'MZXW6!']) {
      expect(() => Base32.decode(secret), throwsFormatException);
    }
  });

  test('normalizes whitespace and hyphens to uppercase Base32', () {
    expect(Base32.normalize(' mzxw6-\tytb \n'), 'MZXW6YTB');
  });

  test('validates normal, invalid, empty, and padded secrets', () {
    expect(Base32.isValid('JBSWY3DPEHPK3PXP'), isTrue);
    expect(Base32.isValid(''), isFalse);
    expect(Base32.isValid('JBSWY3DP1'), isFalse);
    expect(Base32.isValid('MZXW6==='), isTrue);
  });
}
