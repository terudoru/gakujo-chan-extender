import 'dart:convert';
import 'dart:io';

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

  test(
      'clicks the real submit control and keeps a CampusSquare send() fallback',
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

  test(
      'changed secret gets one fresh attempt while the same secret stays blocked',
      () async {
    String scriptFor(String secret) => TwoFactorAutofillScript.build(
          token: '654321',
          secret: secret,
        );
    const showError = "document.body.innerText = '認証コードが正しくありません';";

    final sameSecret = await _evaluateTwoFactorAssist(
      '${scriptFor('wrong-secret')}\n$showError\n${scriptFor('wrong-secret')}',
    );
    final changedSecret = await _evaluateTwoFactorAssist(
      '${scriptFor('wrong-secret')}\n$showError\n${scriptFor('correct-secret')}',
    );

    expect(sameSecret['clickCount'], 1, reason: jsonEncode(sameSecret));
    expect(changedSecret['clickCount'], 2, reason: jsonEncode(changedSecret));
  });

  test('fills the visible code field instead of a hidden template', () async {
    final result = await _evaluateTwoFactorAssist(
      TwoFactorAutofillScript.build(token: '654321'),
    );

    expect(result['hiddenValue'], isEmpty, reason: jsonEncode(result));
    expect(result['visibleValue'], '654321', reason: jsonEncode(result));
    expect(result['clickCount'], 1, reason: jsonEncode(result));
  });

  test('teardown cancels polling before a delayed code field appears',
      () async {
    final result = await _evaluateTwoFactorAssist(
      TwoFactorAutofillScript.build(token: '654321'),
      teardownScript: TwoFactorAutofillScript.buildTeardown(),
    );

    expect(result['hiddenValue'], isEmpty, reason: jsonEncode(result));
    expect(result['visibleValue'], isEmpty, reason: jsonEncode(result));
    expect(result['clickCount'], 0, reason: jsonEncode(result));
  });
}

Future<Map<String, dynamic>> _evaluateTwoFactorAssist(
  String script, {
  String? teardownScript,
}) async {
  final result = await Process.run(
      'node',
      [
        '-e',
        _nodeDomHarness,
        script,
        teardownScript ?? '',
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const _nodeDomHarness = r'''
const vm = require('node:vm');
const generatedScript = process.argv[1];
const generatedTeardown = process.argv[2];
let clickCount = 0;
const sessionValues = new Map();
const activeTimers = new Map();
let nextTimerId = 1;
let fieldsAvailable = !generatedTeardown;

class FakeEvent {
  constructor(type, options) { this.type = type; Object.assign(this, options || {}); }
}

class FakeElement {
  constructor(tag, attributes) {
    this.tagName = tag.toUpperCase();
    this.attributes = {...attributes};
    this.value = '';
    this.type = attributes.type || '';
    this.innerText = attributes.text || '';
    this.textContent = this.innerText;
    this.ownerDocument = null;
    this.form = null;
  }
  getAttribute(name) { return this.attributes[name] ?? null; }
  getClientRects() { return this.attributes.display === 'none' ? [] : [{}]; }
  closest(selector) { return selector === 'form' ? this.form : null; }
  dispatchEvent() { return true; }
  focus() {}
  click() { clickCount += 1; }
}

const hidden = new FakeElement('input', {
  name: 'ninshoCode', type: 'password', display: 'none'
});
const visible = new FakeElement('input', {
  name: 'ninshoCode', type: 'password'
});
const submit = new FakeElement('button', {type: 'submit', text: '認証'});
const form = {
  querySelectorAll(selector) {
    return selector === 'button, input, a, [role="button"]'
      ? [hidden, visible, submit]
      : [];
  }
};
const document = {
  body: {innerText: '', textContent: ''},
  defaultView: null,
  querySelectorAll(selector) {
    if (selector === 'iframe, frame') return [];
    if (selector === 'input[name="ninshoCode"]') {
      return fieldsAvailable ? [hidden, visible] : [];
    }
    return [];
  }
};
const window = {
  document,
  Event: FakeEvent,
  getComputedStyle(element) {
    return {
      display: element.attributes.display || 'block',
      visibility: 'visible',
      opacity: '1'
    };
  },
  clearTimeout(id) { activeTimers.delete(id); },
  setTimeout(callback) {
    const id = nextTimerId++;
    if (generatedTeardown) {
      activeTimers.set(id, callback);
    } else {
      callback();
    }
    return id;
  },
  sessionStorage: {
    getItem(key) { return sessionValues.get(key) || null; },
    setItem(key, value) { sessionValues.set(key, String(value)); }
  },
  MoreBetterGakujoLoginAutofill: {postMessage() {}}
};
window.window = window;
document.defaultView = window;
for (const element of [hidden, visible, submit]) {
  element.ownerDocument = document;
  element.form = form;
}

const context = {
  window,
  document,
  location: {
    href: 'https://gakujo.example/campussmart.do',
    origin: 'https://gakujo.example',
    pathname: '/campussmart.do'
  },
  Event: FakeEvent,
  console: {log() {}}
};
vm.runInNewContext(generatedScript, context);
if (generatedTeardown) {
  vm.runInNewContext(generatedTeardown, context);
  fieldsAvailable = true;
  for (const callback of [...activeTimers.values()]) callback();
}

process.stdout.write(JSON.stringify({
  hiddenValue: hidden.value,
  visibleValue: visible.value,
  clickCount
}));
''';
