import 'package:flutter/foundation.dart';
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

  test('native browser history gestures are enabled on Apple WebViews', () {
    expect(supportsNativeGakujoHistoryGestures(TargetPlatform.iOS), isTrue);
    expect(supportsNativeGakujoHistoryGestures(TargetPlatform.macOS), isTrue);
    expect(
        supportsNativeGakujoHistoryGestures(TargetPlatform.android), isFalse);
    expect(
        supportsNativeGakujoHistoryGestures(TargetPlatform.windows), isFalse);
  });
}
