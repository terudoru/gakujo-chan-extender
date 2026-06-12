import 'package:morebettergakujo_flutter/src/allowed_web_origins.dart';
import 'package:test/test.dart';

void main() {
  test('allows only HTTPS Gakujo pages in release mode', () {
    expect(
      AllowedWebOrigins.canLoad(
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do',
        debugAllowed: false,
      ),
      isTrue,
    );
    expect(
      AllowedWebOrigins.canLoad(
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do;jsessionid=redacted',
        debugAllowed: false,
      ),
      isTrue,
    );
    expect(
      AllowedWebOrigins.canLoad(
        'https://gakujo.iess.niigata-u.ac.jp/some/other/page',
        debugAllowed: false,
      ),
      isTrue,
    );

    expect(
      AllowedWebOrigins.canLoad(
        'http://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
        debugAllowed: false,
      ),
      isFalse,
    );
    expect(
      AllowedWebOrigins.canLoad('https://example.com/', debugAllowed: false),
      isFalse,
    );
    expect(
      AllowedWebOrigins.canLoad(
        'file:///android_asset/qa/two_factor.html',
        debugAllowed: false,
      ),
      isFalse,
    );
  });

  test('allows debug fixture only when debug is enabled', () {
    const fixtureUrl = 'file:///android_asset/qa/two_factor.html';

    expect(
      AllowedWebOrigins.canLoad(fixtureUrl, debugAllowed: true),
      isTrue,
    );
    expect(
      AllowedWebOrigins.canAutofill(fixtureUrl, debugAllowed: true),
      isTrue,
    );
    expect(
      AllowedWebOrigins.canLoad(fixtureUrl, debugAllowed: false),
      isFalse,
    );
  });

  test('rejects blank and malformed urls', () {
    expect(AllowedWebOrigins.canLoad(null, debugAllowed: true), isFalse);
    expect(AllowedWebOrigins.canLoad('', debugAllowed: true), isFalse);
    expect(
      AllowedWebOrigins.canLoad('not a url', debugAllowed: true),
      isFalse,
    );
  });
}
