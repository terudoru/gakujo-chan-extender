import 'package:morebettergakujo_flutter/src/login_autofill_assist_script.dart';
import 'package:test/test.dart';

void main() {
  test('adds password manager hints to login fields', () {
    final script = LoginAutofillAssistScript.build();

    expect(script, contains('__MBG_LOGIN_AUTOFILL_ASSIST_VERSION'));
    expect(script, contains('autocomplete\', \'username'));
    expect(script, contains('autocomplete\', \'current-password'));
    expect(script, contains('autocapitalize\', \'none'));
    expect(script, contains('autocorrect\', \'off'));
    expect(script, contains('spellcheck\', \'false'));
    expect(script, contains('enterkeyhint\', \'next'));
    expect(script, contains('enterkeyhint\', \'done'));
    expect(script, contains('aria-label\', \'ログインID'));
    expect(script, contains('aria-label\', \'パスワード'));
    expect(script, contains('function enableCredentialAutofill(target)'));
    expect(script, contains('function collect(win)'));
    expect(script, contains('element.ownerDocument.defaultView || window'));
    expect(script, contains('ownerDocument.querySelector'));
    expect(script, contains('MBG_LOGIN_AUTOFILL_ASSIST_READY'));
  });

  test('does not treat the 2FA code field as a saved password', () {
    final script = LoginAutofillAssistScript.build();

    expect(script, contains("input.getAttribute('name') !== 'ninshoCode'"));
  });

  test('embeds saved credentials and submits the login form', () {
    final script = LoginAutofillAssistScript.build(
      credentials: const GakujoLoginAutofillCredentials(
        loginId: 'student"123',
        password: r'p@ss\word',
      ),
    );

    expect(script, contains('"student\\"123"'));
    expect(script, contains(r'"p@ss\\word"'));
    expect(script, contains('setInputValue(target.username, savedUsername)'));
    expect(script, contains('submitForm(target)'));
    expect(script, contains('window.__MBG_LOGIN_AUTOFILL_SUBMITTED'));
  });
}
