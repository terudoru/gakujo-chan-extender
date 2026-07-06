import 'package:morebettergakujo_flutter/src/allowed_web_origins.dart';
import 'package:test/test.dart';

void main() {
  test('allows only HTTPS Gakujo pages in release mode', () {
    expect(
      AllowedWebOrigins.canLoad(
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
        debugAllowed: false,
      ),
      isTrue,
    );
    expect(
      AllowedWebOrigins.canLoad(
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do;jsessionid=redacted',
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
      AllowedWebOrigins.canNavigate(
        'https://example.com/',
        debugAllowed: false,
      ),
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

  test('allows required university and coop pages for navigation only', () {
    final urls = [
      'https://www.niigata-u.ac.jp/campus/life/class/online_rule/',
      'https://iess.niigata-u.ac.jp/gakujo/manuals/student.pdf',
      'https://cais.niigata-u.ac.jp/service/zoom/',
      'https://career-center.niigata-u.ac.jp/internship/login.php',
      'https://hakkouservice.iess.niigata-u.ac.jp/cert/z/z_login.html',
      'https://univcoop.jp/nuc/index.html',
      'https://accounts.google.com/o/oauth2/v2/auth',
      'https://calendar.google.com/calendar/u/0/r',
      'https://forms.gle/QyubTE8zGVfY8f516',
      'https://docs.google.com/forms/d/e/example/viewform',
      'https://youtu.be/90EsN7f8x8A',
      'https://youtube.com/watch?v=90EsN7f8x8A',
      'https://www.youtube.com/watch?v=90EsN7f8x8A',
      'https://zoom.us/j/98202207683',
    ];

    for (final url in urls) {
      expect(
        AllowedWebOrigins.canNavigate(url, debugAllowed: false),
        isTrue,
        reason: url,
      );
      expect(
        AllowedWebOrigins.canLoad(url, debugAllowed: false),
        isFalse,
        reason: url,
      );
      expect(
        AllowedWebOrigins.canAutofill(url, debugAllowed: false),
        isFalse,
        reason: url,
      );
      expect(
        AllowedWebOrigins.canRestoreLastPage(url, debugAllowed: false),
        isFalse,
        reason: url,
      );
    }
  });

  test('rejects non-HTTPS external navigation', () {
    expect(
      AllowedWebOrigins.canNavigate(
        'http://www.niigata-u.ac.jp/',
        debugAllowed: false,
      ),
      isFalse,
    );
  });

  test('trims URLs before checking navigation policy', () {
    expect(
      AllowedWebOrigins.canLoad(
        '  https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do  ',
        debugAllowed: false,
      ),
      isTrue,
    );
    expect(
      AllowedWebOrigins.canNavigate(
        '  https://forms.gle/QyubTE8zGVfY8f516  ',
        debugAllowed: false,
      ),
      isTrue,
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

  test('does not restore transient timeout pages', () {
    const timeoutUrl =
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/theme/default/TimeoutAlert.html';

    expect(
      AllowedWebOrigins.canLoad(timeoutUrl, debugAllowed: false),
      isTrue,
    );
    expect(
      AllowedWebOrigins.canRestoreLastPage(timeoutUrl, debugAllowed: false),
      isFalse,
    );
    expect(
      AllowedWebOrigins.canRestoreLastPage(
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
        debugAllowed: false,
      ),
      isTrue,
    );
  });
}
