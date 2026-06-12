import 'package:morebettergakujo_flutter/src/login_autofill_assist_script.dart';
import 'package:test/test.dart';

void main() {
  test('adds password manager hints to login fields', () {
    final script = LoginAutofillAssistScript.build();

    expect(script, contains('__MBG_LOGIN_AUTOFILL_ASSIST_VERSION'));
    expect(script, contains('autocomplete\', \'username'));
    expect(script, contains('autocomplete\', \'current-password'));
    expect(script, contains('autocapitalize\', \'none'));
    expect(script, contains('spellcheck\', \'false'));
    expect(script, contains('MBG_LOGIN_AUTOFILL_ASSIST_READY'));
  });

  test('does not treat the 2FA code field as a saved password', () {
    final script = LoginAutofillAssistScript.build();

    expect(script, contains("input.getAttribute('name') !== 'ninshoCode'"));
  });
}
