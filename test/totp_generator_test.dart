import 'package:morebettergakujo_flutter/src/base32.dart';
import 'package:morebettergakujo_flutter/src/totp_generator.dart';
import 'package:test/test.dart';

void main() {
  test('validates and normalizes Base32 secrets', () {
    expect(Base32.normalize('abcd efgh-2345'), 'ABCDEFGH2345');
    expect(Base32.isValid('abcd efgh-2345'), isTrue);
    expect(Base32.isValid('abcd 0189'), isFalse);
  });

  test('generates known TOTP vector', () {
    const generator = TotpGenerator(digits: 8);
    final token = generator.currentToken(
      'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
      now: DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true),
    );

    expect(token, '94287082');
  });

  test('generates HOTP with six digits', () {
    const generator = TotpGenerator();
    final token = generator.hotp(
      Base32.decode('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
      1,
    );

    expect(token, '287082');
  });
}
