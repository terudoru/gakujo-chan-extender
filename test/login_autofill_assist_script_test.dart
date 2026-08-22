import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/login_autofill_assist_script.dart';
import 'package:test/test.dart';

void main() {
  test('adds password manager hints to login fields', () {
    final script = LoginAutofillAssistScript.build();

    expect(script, contains('__MBG_LOGIN_AUTOFILL_ASSIST_VERSION'));
    expect(script, contains('var assistVersion = 9;'));
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
    expect(script, contains("reportState('skip', 'not-login-form')"));
    expect(script, contains('__MBG_LOGIN_AUTOFILL_MONITOR'));
  });

  test('does not treat the 2FA code field as a saved password', () {
    final script = LoginAutofillAssistScript.build();

    expect(
      script,
      contains(
          "(input.getAttribute('name') || '').toLowerCase() !== 'ninshocode'"),
    );
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
    expect(script, contains('window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY'));
  });

  test('limits automatic login submission across page reloads', () {
    final script = LoginAutofillAssistScript.build(
      credentials: const GakujoLoginAutofillCredentials(
        loginId: 'student',
        password: 'wrong-password',
      ),
    );

    expect(script, contains('window.sessionStorage.getItem(key)'));
    expect(script, contains("sessionKey('SUBMIT_COUNT')"));
    expect(script, contains('attempts >= 1'));
    expect(script, contains('function hasLoginError()'));
    expect(script, contains("setSessionValue(sessionKey('ERROR'), '1')"));
    expect(script, contains("report('submit-blocked'"));
  });

  test('fills and submits a positively identified login form', () async {
    final result = await _evaluateLoginAssist([
      {'tag': 'input', 'type': 'text', 'name': 'userId'},
      {'tag': 'input', 'type': 'password', 'name': 'password'},
      {'tag': 'button', 'type': 'submit', 'text': 'ログイン'},
    ]);

    expect(
      _valueOf(result, 'userId'),
      'saved-user',
      reason: jsonEncode(result),
    );
    expect(_valueOf(result, 'password'), 'saved-password');
    expect(result['clickCount'], 1);
    expect(_hasReport(result, 'fill', 'target-found'), isTrue);
  });

  test('does not fill or submit a password change form', () async {
    final result = await _evaluateLoginAssist([
      {'tag': 'input', 'type': 'text', 'name': 'userId'},
      {'tag': 'input', 'type': 'password', 'name': 'currentPassword'},
      {'tag': 'input', 'type': 'password', 'name': 'newPassword'},
      {'tag': 'button', 'type': 'submit', 'text': '変更'},
    ]);

    expect(_valueOf(result, 'userId'), isEmpty);
    expect(_valueOf(result, 'currentPassword'), isEmpty);
    expect(_valueOf(result, 'newPassword'), isEmpty);
    expect(result['clickCount'], 0);
    expect(_hasReport(result, 'skip', 'not-login-form'), isTrue);
  });

  test('rejects a single password field marked for password change', () async {
    final result = await _evaluateLoginAssist([
      {'tag': 'input', 'type': 'text', 'name': 'userName'},
      {'tag': 'input', 'type': 'password', 'name': 'currentPassword'},
      {'tag': 'button', 'type': 'submit', 'text': '確認'},
    ]);

    expect(_valueOf(result, 'userName'), isEmpty);
    expect(_valueOf(result, 'currentPassword'), isEmpty);
    expect(result['clickCount'], 0);
    expect(_hasReport(result, 'skip', 'not-login-form'), isTrue);
  });

  test('does not fill a generic form without a known login ID name', () async {
    final result = await _evaluateLoginAssist([
      {
        'tag': 'input',
        'type': 'text',
        'name': 'accountNumber',
        'aria-label': 'ログインID',
      },
      {'tag': 'input', 'type': 'password', 'name': 'password'},
      {'tag': 'button', 'type': 'submit', 'text': '送信'},
    ]);

    expect(_valueOf(result, 'accountNumber'), isEmpty);
    expect(_valueOf(result, 'password'), isEmpty);
    expect(result['clickCount'], 0);
    expect(_hasReport(result, 'skip', 'not-login-form'), isTrue);
  });

  test('does not count ninshoCode as a second password field', () async {
    final result = await _evaluateLoginAssist([
      {'tag': 'input', 'type': 'text', 'name': 'loginId'},
      {'tag': 'input', 'type': 'password', 'name': 'password'},
      {'tag': 'input', 'type': 'password', 'name': 'ninshoCode'},
      {'tag': 'button', 'type': 'submit', 'text': 'ログイン'},
    ]);

    expect(_valueOf(result, 'loginId'), 'saved-user');
    expect(_valueOf(result, 'password'), 'saved-password');
    expect(_valueOf(result, 'ninshoCode'), isEmpty);
    expect(result['clickCount'], 1);
  });

  test('ignores hidden password templates when identifying the login form',
      () async {
    final result = await _evaluateLoginAssist([
      {'tag': 'input', 'type': 'text', 'name': 'userId'},
      {'tag': 'input', 'type': 'password', 'name': 'password'},
      {
        'tag': 'input',
        'type': 'password',
        'name': 'passwordTemplate',
        'display': 'none',
      },
      {'tag': 'button', 'type': 'submit', 'name': 'login', 'text': 'ログイン'},
    ]);

    expect(_valueOf(result, 'userId'), 'saved-user');
    expect(_valueOf(result, 'password'), 'saved-password');
    expect(result['clickedNames'], ['login']);
  });

  test('skips unrelated type=button controls before the login submitter',
      () async {
    final result = await _evaluateLoginAssist([
      {'tag': 'input', 'type': 'text', 'name': 'userId'},
      {'tag': 'input', 'type': 'password', 'name': 'password'},
      {'tag': 'input', 'type': 'button', 'name': 'clear', 'value': 'クリア'},
      {'tag': 'button', 'type': 'submit', 'name': 'login', 'text': 'ログイン'},
    ]);

    expect(result['clickedNames'], ['login']);
  });

  test('ignores a password-change help link beside the login password',
      () async {
    final result = await _evaluateLoginAssist([
      {'tag': 'input', 'type': 'text', 'name': 'userName'},
      {
        'tag': 'input',
        'type': 'password',
        'name': 'password',
        'rowText': 'パスワード ※パスワード変更はこちら（保護者等除く）',
      },
      {'tag': 'button', 'type': 'submit', 'name': 'login', 'text': 'ログイン'},
    ]);

    expect(_valueOf(result, 'userName'), 'saved-user');
    expect(_valueOf(result, 'password'), 'saved-password');
    expect(result['clickedNames'], ['login']);
  });

  test('allows one new automatic attempt after saved credentials change',
      () async {
    final first = LoginAutofillAssistScript.build(
      credentials: const GakujoLoginAutofillCredentials(
        loginId: 'saved-user',
        password: 'old-password',
      ),
    );
    final corrected = LoginAutofillAssistScript.build(
      credentials: const GakujoLoginAutofillCredentials(
        loginId: 'saved-user',
        password: 'corrected-password',
      ),
    );
    final result = await _evaluateGeneratedLoginAssist(
      '$first\n$corrected',
      [
        {'tag': 'input', 'type': 'text', 'name': 'userId'},
        {'tag': 'input', 'type': 'password', 'name': 'password'},
        {'tag': 'button', 'type': 'submit', 'name': 'login', 'text': 'ログイン'},
      ],
    );

    expect(
      _valueOf(result, 'password'),
      'corrected-password',
      reason: jsonEncode(result),
    );
    expect(result['clickCount'], 2, reason: jsonEncode(result));
  });

  test('automatically submits again when an authenticated page times out',
      () async {
    final result = await _evaluateGeneratedLoginAssist(
      LoginAutofillAssistScript.build(
        credentials: const GakujoLoginAutofillCredentials(
          loginId: 'saved-user',
          password: 'saved-password',
        ),
      ),
      [
        {'tag': 'input', 'type': 'text', 'name': 'userId'},
        {'tag': 'input', 'type': 'password', 'name': 'password'},
        {'tag': 'button', 'type': 'submit', 'name': 'login', 'text': 'ログイン'},
      ],
      simulateAuthenticatedTimeout: true,
    );

    expect(result['clickCount'], 2, reason: jsonEncode(result));
    expect(_hasReport(result, 'authenticated', 'attempt-reset'), isTrue);
    expect(
      (result['reports'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((report) => report['event'] == 'challenge'),
      hasLength(2),
    );
  });

  test('does not retry unchanged credentials on an existing login error',
      () async {
    final script = LoginAutofillAssistScript.build(
      credentials: const GakujoLoginAutofillCredentials(
        loginId: 'saved-user',
        password: 'saved-password',
      ),
    );
    final result = await _evaluateGeneratedLoginAssist(
      "document.body.innerText = 'ログインに失敗しました';\n"
      "document.body.textContent = 'ログインに失敗しました';\n"
      '$script',
      [
        {'tag': 'input', 'type': 'text', 'name': 'userId'},
        {'tag': 'input', 'type': 'password', 'name': 'password'},
        {'tag': 'button', 'type': 'submit', 'name': 'login', 'text': 'ログイン'},
      ],
    );

    expect(result['clickCount'], 0, reason: jsonEncode(result));
  });

  test('changed credentials can retry while the old error remains visible',
      () async {
    final first = LoginAutofillAssistScript.build(
      credentials: const GakujoLoginAutofillCredentials(
        loginId: 'saved-user',
        password: 'old-password',
      ),
    );
    final corrected = LoginAutofillAssistScript.build(
      credentials: const GakujoLoginAutofillCredentials(
        loginId: 'saved-user',
        password: 'corrected-password',
      ),
    );
    final result = await _evaluateGeneratedLoginAssist(
      '$first\n'
      "document.body.innerText = 'ログインに失敗しました';\n"
      "document.body.textContent = 'ログインに失敗しました';\n"
      '$corrected',
      [
        {'tag': 'input', 'type': 'text', 'name': 'userId'},
        {'tag': 'input', 'type': 'password', 'name': 'password'},
        {'tag': 'button', 'type': 'submit', 'name': 'login', 'text': 'ログイン'},
      ],
    );

    expect(_valueOf(result, 'password'), 'corrected-password');
    expect(result['clickCount'], 2, reason: jsonEncode(result));
  });

  test('teardown cancels a pending automatic submit', () async {
    final result = await _evaluateGeneratedLoginAssist(
      LoginAutofillAssistScript.build(
        credentials: const GakujoLoginAutofillCredentials(
          loginId: 'saved-user',
          password: 'saved-password',
        ),
      ),
      [
        {'tag': 'input', 'type': 'text', 'name': 'userId'},
        {'tag': 'input', 'type': 'password', 'name': 'password'},
        {'tag': 'button', 'type': 'submit', 'name': 'login', 'text': 'ログイン'},
      ],
      teardownScript: LoginAutofillAssistScript.buildTeardown(),
      deferTimers: true,
    );

    expect(_valueOf(result, 'password'), 'saved-password');
    expect(result['clickCount'], 0, reason: jsonEncode(result));
  });
}

Future<Map<String, dynamic>> _evaluateLoginAssist(
  List<Map<String, String>> elements,
) async {
  final script = LoginAutofillAssistScript.build(
    credentials: const GakujoLoginAutofillCredentials(
      loginId: 'saved-user',
      password: 'saved-password',
    ),
  );
  return _evaluateGeneratedLoginAssist(script, elements);
}

Future<Map<String, dynamic>> _evaluateGeneratedLoginAssist(
  String script,
  List<Map<String, String>> elements, {
  String? teardownScript,
  bool deferTimers = false,
  bool simulateAuthenticatedTimeout = false,
}) async {
  final process = await Process.start('node', [
    '-e',
    _nodeDomHarness,
    jsonEncode({
      'elements': elements,
      'teardownScript': teardownScript,
      'deferTimers': deferTimers,
      'simulateAuthenticatedTimeout': simulateAuthenticatedTimeout,
    }),
  ]);
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(script);
  await process.stdin.close();
  final exitCode = await process.exitCode;
  final stdoutText = await stdoutFuture;
  final stderrText = await stderrFuture;

  expect(
    exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: $stderrText',
  );
  return jsonDecode(stdoutText) as Map<String, dynamic>;
}

String _valueOf(Map<String, dynamic> result, String name) {
  final elements = result['elements'] as List<dynamic>;
  final element = elements.cast<Map<String, dynamic>>().singleWhere(
        (candidate) => candidate['name'] == name,
      );
  return element['value'] as String;
}

bool _hasReport(
  Map<String, dynamic> result,
  String event,
  String detail,
) {
  final reports = result['reports'] as List<dynamic>;
  return reports.cast<Map<String, dynamic>>().any(
        (report) =>
            report['event'] == event &&
            (report['detail'] as String).contains(detail),
      );
}

const _nodeDomHarness = r'''
const vm = require('node:vm');
const generatedScript = require('node:fs').readFileSync(0, 'utf8');
const spec = JSON.parse(process.argv[1]);
const reports = [];
const sessionValues = new Map();
let clickCount = 0;
const clickedNames = [];
let requestSubmitCount = 0;
let formSubmitCount = 0;
let nextTimerId = 1;
const activeTimers = new Map();
const activeIntervals = new Map();

class FakeEvent {
  constructor(type, options) {
    this.type = type;
    Object.assign(this, options || {});
  }
}

class FakeElement {
  constructor(tag, attributes) {
    this.tagName = tag.toUpperCase();
    this.attributes = {};
    for (const [name, value] of Object.entries(attributes || {})) {
      if (name !== 'tag' && name !== 'text') {
        this.attributes[name] = String(value);
      }
    }
    this.id = this.attributes.id || '';
    this.value = this.attributes.value || '';
    this.innerText = attributes.text || '';
    this.textContent = this.innerText;
    this.ownerDocument = null;
    this.form = null;
    this.children = [];
  }

  getAttribute(name) {
    return Object.prototype.hasOwnProperty.call(this.attributes, name)
      ? this.attributes[name]
      : null;
  }

  setAttribute(name, value) {
    this.attributes[name] = String(value);
    if (name === 'id') {
      this.id = String(value);
    }
  }

  getClientRects() {
    return [{}];
  }

  closest(selector) {
    if (selector === 'form') return this.form;
    if (selector === 'tr, p, div, li, label' && this.attributes.rowText) {
      return {
        innerText: this.attributes.rowText,
        textContent: this.attributes.rowText
      };
    }
    if (selector === 'label' && this.attributes.labelText) {
      return {
        innerText: this.attributes.labelText,
        textContent: this.attributes.labelText
      };
    }
    return null;
  }

  focus() {}
  blur() {}
  dispatchEvent() { return true; }
  click() {
    clickCount += 1;
    clickedNames.push(this.getAttribute('name') || this.getAttribute('id') || '');
  }

  querySelectorAll(selector) {
    if (selector === 'input') {
      return this.children.filter((element) => element.tagName === 'INPUT');
    }
    if (selector === 'button, input, a, [role="button"]' ||
        selector === 'a, button, input, [role="button"], img') {
      return this.children.filter((element) =>
        ['BUTTON', 'INPUT', 'A', 'IMG'].includes(element.tagName) ||
        element.getAttribute('role') === 'button'
      );
    }
    return [];
  }
}

const form = new FakeElement('form', {id: 'login-form'});
const elements = spec.elements.map((attributes) =>
  new FakeElement(attributes.tag, attributes)
);
form.children = elements;

const document = {
  body: {innerText: '', textContent: ''},
  defaultView: null,
  querySelector() { return null; },
  querySelectorAll(selector) {
    if (selector === 'iframe, frame') {
      return [];
    }
    return form.querySelectorAll(selector);
  }
};

const window = {
  document,
  CSS: null,
  HTMLInputElement: null,
  InputEvent: FakeEvent,
  Event: FakeEvent,
  KeyboardEvent: FakeEvent,
  sessionStorage: {
    getItem(key) { return sessionValues.get(key) || null; },
    setItem(key, value) { sessionValues.set(key, String(value)); },
    removeItem(key) { sessionValues.delete(key); }
  },
  getComputedStyle(element) {
    return {
      display: element.getAttribute('display') || 'block',
      visibility: element.getAttribute('visibility') || 'visible',
      opacity: element.getAttribute('opacity') || '1'
    };
  },
  clearTimeout(id) { activeTimers.delete(id); },
  setTimeout(callback) {
    const id = nextTimerId++;
    if (spec.deferTimers) {
      activeTimers.set(id, callback);
    } else {
      callback();
    }
    return id;
  },
  clearInterval(id) { activeIntervals.delete(id); },
  setInterval(callback) {
    const id = nextTimerId++;
    activeIntervals.set(id, callback);
    return id;
  },
  MoreBetterGakujoLoginAutofill: {
    postMessage(payload) { reports.push(JSON.parse(payload)); }
  }
};
window.window = window;
document.defaultView = window;
form.ownerDocument = document;
form.requestSubmit = () => { requestSubmitCount += 1; };
form.submit = () => { formSubmitCount += 1; };
for (const element of elements) {
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
  console: {log() {}}
};
vm.runInNewContext(generatedScript, context);
if (spec.simulateAuthenticatedTimeout) {
  delete window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY;
  const logout = new FakeElement('button', {text: 'ログアウト'});
  logout.ownerDocument = document;
  form.children = [logout];
  for (const callback of [...activeIntervals.values()]) callback();

  for (const element of elements) {
    element.value = '';
  }
  form.children = elements;
  for (const callback of [...activeIntervals.values()]) callback();
}
if (spec.teardownScript) {
  vm.runInNewContext(spec.teardownScript, context);
}
for (let round = 0; round < 50 && activeTimers.size > 0; round += 1) {
  const callbacks = [...activeTimers.values()];
  activeTimers.clear();
  for (const callback of callbacks) callback();
}

process.stdout.write(JSON.stringify({
  elements: elements.map((element) => ({
    name: element.getAttribute('name'),
    value: element.value
  })),
  clickCount,
  clickedNames,
  requestSubmitCount,
  formSubmitCount,
  reports
}));
''';
