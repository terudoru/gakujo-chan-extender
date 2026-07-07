import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';

void main() {
  test('cookiePathMatches follows RFC6265 path boundaries', () {
    expect(cookiePathMatches('/foo', '/foo'), isTrue);
    expect(cookiePathMatches('/foo/bar', '/foo'), isTrue);
    expect(cookiePathMatches('/foobar', '/foo'), isFalse);
    expect(cookiePathMatches('/foo', '/foo/'), isFalse);
    expect(cookiePathMatches('/foo/bar', '/foo/'), isTrue);
    expect(cookiePathMatches('/anything', '/'), isTrue);
  });
}
