import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  test('Linux blocked local file labels decode Japanese names and spaces', () {
    final url = Uri.file('/home/student/課題 資料.pdf', windows: false).toString();

    expect(
      gakujoBlockedNavigationUrlLabel(url, platform: TargetPlatform.linux),
      'file:///home/student/課題 資料.pdf',
    );
  });

  test('Linux decodes a literal percent in a file name only once', () {
    expect(
      gakujoBlockedNavigationUrlLabel(
        'file:///home/student/100%2520.pdf',
        platform: TargetPlatform.linux,
      ),
      'file:///home/student/100%20.pdf',
    );
  });

  test('Linux malformed file labels use a readable fallback', () {
    expect(
      gakujoBlockedNavigationUrlLabel(
        'file:///home/student/%FF.pdf',
        platform: TargetPlatform.linux,
      ),
      'ローカルファイル',
    );
  });

  test('other platforms retain the existing local file labels', () {
    const url = 'file:///C:/Users/student/%E8%AA%B2%E9%A1%8C.pdf';
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.linux) continue;
      expect(gakujoBlockedNavigationUrlLabel(url, platform: platform), url);
    }
  });

  test('Linux leaves other blocked URL schemes unchanged', () {
    for (final url in [
      'https://example.com/%E8%AA%B2%E9%A1%8C.pdf',
      'javascript:alert(1)',
      'data:text/plain,100%25',
    ]) {
      expect(
        gakujoBlockedNavigationUrlLabel(url, platform: TargetPlatform.linux),
        url,
      );
    }
  });
}
