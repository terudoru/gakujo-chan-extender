import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/login_autofill_assist_script.dart';
import 'package:test/test.dart';

import 'support/autofill_script_lifecycle_harness.dart';

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
    expect(script, contains("report('skip', 'not-login-form"));
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

  test('teardown cancels retries and is safe before injection', () async {
    final buildScript = LoginAutofillAssistScript.build();
    final teardownScript = LoginAutofillAssistScript.buildTeardown();
    expect(buildScript, contains('__MBG_LOGIN_AUTOFILL_SUBMIT_TIMER'));
    expect(
      teardownScript,
      contains('clearTimeout(window.__MBG_LOGIN_AUTOFILL_SUBMIT_TIMER)'),
    );

    final result = await evaluateAutofillScriptLifecycle(
      markerPrefix: '__MBG_LOGIN_AUTOFILL_',
      buildScript: buildScript,
      teardownScript: teardownScript,
    );
    final afterBuild = result['afterBuild'] as Map<String, dynamic>;
    final afterTeardown = result['afterTeardown'] as Map<String, dynamic>;
    final afterFlush = result['afterFlush'] as Map<String, dynamic>;
    final afterRebuild = result['afterRebuild'] as Map<String, dynamic>;
    final teardownWithoutBuild =
        result['teardownWithoutBuild'] as Map<String, dynamic>;

    expect(afterBuild['activeTimeoutCount'], 1);
    expect(afterBuild['globalMarkers'], isNotEmpty);
    expect(afterTeardown['activeTimeoutCount'], 0);
    expect(afterTeardown['globalMarkers'], isEmpty);
    expect(afterFlush['activeTimeoutCount'], 0);
    expect(afterRebuild['activeTimeoutCount'], 1);
    expect(teardownWithoutBuild['globalMarkers'], isEmpty);
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

  test('login form probe recognizes login and rejects password changes',
      () async {
    final loginResult = await _evaluateLoginScript(
      LoginAutofillAssistScript.buildLoginFormProbe(),
      [
        {'tag': 'input', 'type': 'text', 'name': 'userId'},
        {'tag': 'input', 'type': 'password', 'name': 'password'},
      ],
    );
    final changeResult = await _evaluateLoginScript(
      LoginAutofillAssistScript.buildLoginFormProbe(),
      [
        {'tag': 'input', 'type': 'text', 'name': 'userName'},
        {'tag': 'input', 'type': 'password', 'name': 'currentPassword'},
      ],
    );

    expect(loginResult['scriptResult'], isTrue);
    expect(changeResult['scriptResult'], isFalse);
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
  return _evaluateLoginScript(script, elements);
}

Future<Map<String, dynamic>> _evaluateLoginScript(
  String script,
  List<Map<String, String>> elements,
) async {
  final result = await Process.run('node', [
    '-e',
    _nodeDomHarness,
    script,
    jsonEncode({'elements': elements}),
  ]);

  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
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
const generatedScript = process.argv[1];
const spec = JSON.parse(process.argv[2]);
const reports = [];
const sessionValues = new Map();
let clickCount = 0;
let requestSubmitCount = 0;
let formSubmitCount = 0;

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
    return selector === 'form' ? this.form : null;
  }

  focus() {}
  blur() {}
  dispatchEvent() { return true; }
  click() { clickCount += 1; }

  querySelectorAll(selector) {
    if (selector === 'input') {
      return this.children.filter((element) => element.tagName === 'INPUT');
    }
    if (selector === 'button, input, a, [role="button"]') {
      return this.children.filter((element) =>
        ['BUTTON', 'INPUT', 'A'].includes(element.tagName) ||
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
    setItem(key, value) { sessionValues.set(key, String(value)); }
  },
  getComputedStyle(element) {
    return {
      display: element.getAttribute('display') || 'block',
      visibility: element.getAttribute('visibility') || 'visible',
      opacity: element.getAttribute('opacity') || '1'
    };
  },
  clearTimeout() {},
  setTimeout(callback) {
    callback();
    return 1;
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

const scriptResult = vm.runInNewContext(generatedScript, {
  window,
  document,
  location: {
    href: 'https://gakujo.example/campussmart.do',
    origin: 'https://gakujo.example',
    pathname: '/campussmart.do'
  },
  console: {log() {}}
});

process.stdout.write(JSON.stringify({
  elements: elements.map((element) => ({
    name: element.getAttribute('name'),
    value: element.value
  })),
  clickCount,
  requestSubmitCount,
  formSubmitCount,
  reports,
  scriptResult
}));
''';
