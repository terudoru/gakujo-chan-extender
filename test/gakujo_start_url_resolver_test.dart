import 'package:morebettergakujo_flutter/src/allowed_web_origins.dart';
import 'package:morebettergakujo_flutter/src/gakujo_start_url_resolver.dart';
import 'package:test/test.dart';

void main() {
  test('uses PC portal URL by default', () {
    expect(
      GakujoStartUrlResolver.resolve(debugAllowed: false),
      AllowedWebOrigins.gakujoUrl,
    );
    expect(
      AllowedWebOrigins.gakujoUrl,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
    );
  });

  test('uses saved Gakujo URL when debug start URL is absent', () {
    const savedUrl = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/student.do';

    expect(
      GakujoStartUrlResolver.resolve(
        debugAllowed: false,
        savedUrl: savedUrl,
      ),
      savedUrl,
    );
  });

  test('ignores invalid saved URL', () {
    expect(
      GakujoStartUrlResolver.resolve(
        debugAllowed: false,
        savedUrl: 'https://example.com/',
      ),
      AllowedWebOrigins.gakujoUrl,
    );
  });

  test('debug start URL has priority over saved URL', () {
    const debugStartUrl = 'file:///android_asset/qa/two_factor.html';
    const savedUrl = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/student.do';

    expect(
      GakujoStartUrlResolver.resolve(
        debugAllowed: true,
        debugStartUrl: debugStartUrl,
        savedUrl: savedUrl,
      ),
      debugStartUrl,
    );
  });
}
