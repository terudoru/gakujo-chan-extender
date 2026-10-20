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

  test('Android upload filters map HTML accept values to type groups', () {
    final groups = androidUploadTypeGroups(['.PDF, image/*', '.docx']);
    expect(groups, hasLength(1));
    expect(groups.single.extensions, unorderedEquals(['pdf', 'docx']));
    expect(groups.single.mimeTypes, ['image/*']);
  });

  test('Android upload filters allow any file without a usable filter', () {
    expect(androidUploadTypeGroups(const []), isEmpty);
    expect(androidUploadTypeGroups(['']), isEmpty);
    expect(androidUploadTypeGroups(['.pdf', '*/*']), isEmpty);
    expect(androidUploadTypeGroups(['audio']), isEmpty);
  });

  test('Flutter handles JavaScript dialogs only for WKWebView platforms', () {
    expect(needsFlutterJavaScriptDialogs(TargetPlatform.iOS), isTrue);
    expect(needsFlutterJavaScriptDialogs(TargetPlatform.macOS), isTrue);
    expect(needsFlutterJavaScriptDialogs(TargetPlatform.android), isFalse);
    expect(needsFlutterJavaScriptDialogs(TargetPlatform.windows), isFalse);
  });
}
