import 'package:morebettergakujo_flutter/src/two_factor_autofill_script.dart';
import 'package:test/test.dart';

void main() {
  test('builds an autofill script for ninshoCode', () {
    final script = TwoFactorAutofillScript.build(token: '123456');

    expect(script, contains('input[name="ninshoCode"]'));
    expect(script, contains('function allDocuments()'));
    expect(script, contains('function collect(win)'));
    expect(script, contains("document.querySelectorAll('iframe, frame')"));
    expect(script, contains('documents[i].querySelector'));
    expect(script, contains('input.ownerDocument || document'));
    expect(script, contains('var token = "123456";'));
    expect(script, contains('MBG_2FA_AUTOFILL_SUCCESS'));
    expect(script, contains('function findSubmitControl(input)'));
    expect(script, contains('form.requestSubmit()'));
  });

  test('clicks the real submit control and keeps a CampusSquare send() fallback',
      () {
    final script = TwoFactorAutofillScript.build(token: '123456');

    // Prefer clicking the labelled submit control (e.g. the "ログイン" button)
    // so the page's own onclick/send() handler runs, instead of a raw
    // form.submit() that drops CampusSquare's hidden action fields.
    expect(script, contains('function findSubmitControl(input)'));
    expect(script, contains('control.click()'));
    // Never click the back / reset controls on the 2FA page.
    expect(script, contains('function isBackOrResetControl(element)'));
    expect(script, contains('戻る'));
    expect(script, contains('リセット'));
    // Recognise login/auth submit labels.
    expect(script, contains('ログイン|認証'));
    // CampusSquare send() fallback when no clickable control is found.
    expect(script, contains("typeof pageWindow.send === 'function'"));
    expect(script, contains('pageWindow.send()'));
  });

  test('escapes token as JavaScript string literal', () {
    final script = TwoFactorAutofillScript.build(token: '12"34');

    expect(script, contains(r'var token = "12\"34";'));
  });

  test('can disable automatic submit', () {
    final script = TwoFactorAutofillScript.build(
      token: '123456',
      autoSubmit: false,
    );

    expect(script, contains('var autoSubmit = false;'));
  });

  test('limits automatic submit across reloads and stops after errors', () {
    final script = TwoFactorAutofillScript.build(token: '123456');

    expect(script, contains('window.sessionStorage.getItem(key)'));
    expect(script, contains("sessionKey('SUBMIT_COUNT')"));
    expect(script, contains('var maxAutoSubmitPerSession = 3;'));
    expect(script, contains('count >= maxAutoSubmitPerSession'));
    expect(script, contains('function hasTwoFactorError()'));
    expect(script, contains("setSessionValue(sessionKey('ERROR'), '1')"));
    expect(script, contains("reportProgress('submit-blocked'"));
    expect(script, contains('markAutoSubmitAttempted()'));
  });
}
