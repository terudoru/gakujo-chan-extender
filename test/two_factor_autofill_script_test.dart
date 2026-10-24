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

  test('two-factor attempt limit survives rotating URL matrix parameters',
      () async {
    final script = TwoFactorAutofillScript.build(token: '654321');
    final result = await _evaluateTwoFactorAssist(
      'for (var i = 0; i < 4; i += 1) {\n'
      "  location = new URL('https://gakujo.iess.niigata-u.ac.jp/' +\n"
      "    'campusweb;route=' + i + '/campussmart.do;JSESSIONID=' + i +\n"
      "    ';view=' + i + '?step=' + i + '#' + i);\n"
      '  delete window.__MBG_2FA_AUTO_SUBMITTED_KEY;\n'
      '$script\n'
      '}',
    );

    expect(result['clickCount'], 3);
    final counts = (result['sessionValues'] as Map<String, dynamic>)
        .entries
        .where(
            (entry) => entry.key.startsWith('MBG_2FA_AUTOFILL_SUBMIT_COUNT:'));
    expect(counts, hasLength(1));
    expect(counts.single.key, contains('/campusweb/campussmart.do:'));
    expect(counts.single.value, '3');
  });

  test('clicks only submit controls and excludes help, settings and back',
      () async {
    for (final submitter in [
      {'tag': 'button', 'type': 'submit'},
      {'tag': 'input', 'type': 'submit'},
      {'tag': 'button'},
    ]) {
      final result = await _evaluateTwoFactorAssist(
        TwoFactorAutofillScript.build(token: '654321'),
        controls: [
          {'tag': 'a', 'name': 'link', 'text': '認証'},
          {'tag': 'div', 'role': 'button', 'name': 'role', 'text': '認証'},
          {'tag': 'button', 'type': 'button', 'name': 'other', 'text': '認証'},
          for (final text in [
            '認証 設定方法',
            '認証 ヘルプ',
            'Verify Help',
            '認証 設定',
            '認証 戻る',
            '認証 キャンセル',
          ])
            {'tag': 'button', 'type': 'submit', 'name': 'help', 'text': text},
          {...submitter, 'name': 'verify'},
        ],
      );

      expect(result['clickedNames'], ['verify']);
      expect(result['clickCount'], 1);
    }
  });

  test('fills the visible code field instead of a hidden template', () async {
    final result = await _evaluateTwoFactorAssist(
      TwoFactorAutofillScript.build(token: '654321'),
    );

    expect(result['hiddenValue'], isEmpty, reason: jsonEncode(result));
    expect(result['visibleValue'], '654321', reason: jsonEncode(result));
    expect(result['clickCount'], 1, reason: jsonEncode(result));
    expect(result['consoleLogs'], isEmpty);
  });

  for (final url in [
    'https://www.niigata-u.ac.jp/campussmart.do',
    'http://gakujo.iess.niigata-u.ac.jp/campussmart.do',
    'https://gakujo.iess.niigata-u.ac.jp.evil.example/campussmart.do',
    'file:///android_asset/qa/two_factor.html',
  ]) {
    test('does not fill, submit or report a two-factor token on $url',
        () async {
      final result = await _evaluateTwoFactorAssist(
        TwoFactorAutofillScript.build(
          token: '654321',
          secret: 'test-secret',
          debugLogging: true,
        ),
        url: url,
      );

      expect(result['hiddenValue'], isEmpty);
      expect(result['visibleValue'], isEmpty);
      expect(result['clickCount'], 0);
      expect(result['reports'], isEmpty);
      expect(result['consoleLogs'], isEmpty);
    });
  }

  for (final debugLogging in [false, true]) {
    test('redacts two-factor event URLs with debugLogging=$debugLogging',
        () async {
      final result = await _evaluateTwoFactorAssist(
        TwoFactorAutofillScript.build(
          token: '654321',
          debugLogging: debugLogging,
        ),
        url: 'https://gakujo.iess.niigata-u.ac.jp'
            '/campusweb;JSESSIONID=path-secret'
            '/campussmart.do;jsessionid=tail-secret;view=login'
            '?token=query-secret#hash-secret',
      );

      final reports = result['reports'] as List<dynamic>;
      expect(reports, isNotEmpty);
      for (final report in reports.cast<Map<String, dynamic>>()) {
        expect(
          report['url'],
          'https://gakujo.iess.niigata-u.ac.jp'
          '/campusweb/campussmart.do;view=login',
        );
      }
      final consoleLogs = result['consoleLogs'] as List<dynamic>;
      expect(consoleLogs.isNotEmpty, debugLogging);
      for (final secret in [
        'path-secret',
        'tail-secret',
        'query-secret',
        'hash-secret',
      ]) {
        expect(jsonEncode(result), isNot(contains(secret)));
      }
    });
  }

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
  String? url,
  String? teardownScript,
  List<Map<String, String>>? controls,
}) async {
  final result = await Process.run(
      'node',
      [
        '-e',
        _nodeDomHarness,
        script,
        teardownScript ?? '',
        url ?? 'https://gakujo.iess.niigata-u.ac.jp/campussmart.do',
        jsonEncode({'controls': controls}),
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
const spec = JSON.parse(process.argv[4] || '{}');
const reports = [];
const consoleLogs = [];
let clickCount = 0;
const clickedNames = [];
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
  click() {
    clickCount += 1;
    clickedNames.push(this.getAttribute('name') || '');
  }
}

const hidden = new FakeElement('input', {
  name: 'ninshoCode', type: 'password', display: 'none'
});
const visible = new FakeElement('input', {
  name: 'ninshoCode', type: 'password'
});
const controls = (spec.controls || [
  {tag: 'button', type: 'submit', text: '認証'}
]).map((attributes) => new FakeElement(attributes.tag, attributes));
const form = {
  querySelectorAll(selector) {
    const elements = [hidden, visible, ...controls];
    if (selector === 'button, input, a, [role="button"]') return elements;
    if (selector === 'button, input') {
      return elements.filter((element) => ['BUTTON', 'INPUT'].includes(element.tagName));
    }
    return [];
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
  MoreBetterGakujoLoginAutofill: {
    postMessage(payload) { reports.push(JSON.parse(payload)); }
  }
};
window.window = window;
document.defaultView = window;
for (const element of [hidden, visible, ...controls]) {
  element.ownerDocument = document;
  element.form = form;
}

const context = {
  window,
  document,
  URL,
  location: new URL(process.argv[3]),
  Event: FakeEvent,
  console: {log(message) { consoleLogs.push(message); }}
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
  clickCount,
  clickedNames,
  sessionValues: Object.fromEntries(sessionValues),
  reports,
  consoleLogs
}));
''';
