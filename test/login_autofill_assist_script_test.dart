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
    expect(result['consoleLogs'], isEmpty);
  });

  test('a navigated external page cannot bypass the origin check', () async {
    final result = await _evaluateLoginAssist(
      [
        {'tag': 'input', 'type': 'text', 'name': 'userId'},
        {'tag': 'input', 'type': 'password', 'name': 'password'},
        {'tag': 'button', 'type': 'submit', 'text': 'ログイン'},
      ],
      url: 'https://docs.google.com/document',
      setupScript: 'Array.prototype.indexOf = function() { return 0; };',
    );
    expect(_valueOf(result, 'userId'), isEmpty);
    expect(_valueOf(result, 'password'), isEmpty);
    expect(result['clickCount'], 0);
  });

  test('checks form and submitter actions before filling and submitting',
      () async {
    final elements = [
      {'tag': 'input', 'type': 'text', 'name': 'userId'},
      {'tag': 'input', 'type': 'password', 'name': 'password'},
      {'tag': 'button', 'type': 'submit', 'name': 'login', 'text': 'ログイン'},
    ];
    for (final attribute in ['action', 'formaction']) {
      for (final action in [
        '',
        'submit.do',
        'https://gakujo.iess.niigata-u.ac.jp/submit.do',
        'https://foreign.example/submit.do',
        '//foreign.example/submit.do',
        'http://gakujo.iess.niigata-u.ac.jp/submit.do',
        'https://gakujo.iess.niigata-u.ac.jp:8443/submit.do',
        'javascript:void(0)',
        'https://[',
      ]) {
        final allowed = action.isEmpty ||
            action == 'submit.do' ||
            action == 'https://gakujo.iess.niigata-u.ac.jp/submit.do';
        final control = attribute == 'action'
            ? "document.querySelectorAll('input')[0].form"
            : "document.querySelectorAll('button, input, a, [role=\"button\"]')[2]";
        final encodedAction = jsonEncode(action);
        final result = await _evaluateLoginAssist(
          elements,
          setupScript: "$control.setAttribute('$attribute', $encodedAction);",
          monitorTicks: 2,
        );

        expect(_valueOf(result, 'userId').isNotEmpty, allowed);
        expect(_valueOf(result, 'password').isNotEmpty, allowed);
        expect(result['clickCount'], allowed ? 1 : 0);
        expect(result['requestSubmitCount'], 0);
        expect(result['formSubmitCount'], 0);
        expect(_hasReport(result, 'skip', 'foreign-action'), !allowed);
      }
    }
    final foreignBase = await _evaluateLoginAssist(
      elements,
      setupScript: """
document.baseURI = 'https://foreign.example/';
document.querySelectorAll('input')[0].form.setAttribute('action', 'submit.do');
""",
    );
    expect(_valueOf(foreignBase, 'password'), isEmpty);
    expect(foreignBase['clickCount'], 0);
    expect(_hasReport(foreignBase, 'skip', 'foreign-action'), isTrue);

    final changedAction = await _evaluateLoginAssist(
      elements,
      setupScript: """
window.setTimeout = function(callback) {
  document.querySelectorAll('input')[0].form.setAttribute(
    'action', 'https://foreign.example/submit.do');
  callback();
};
""",
    );
    expect(changedAction['clickCount'], 0);
    expect(changedAction['requestSubmitCount'], 0);
    expect(changedAction['formSubmitCount'], 0);
    expect(_hasReport(changedAction, 'skip', 'foreign-action'), isTrue);
  });

  test('stops automatic login on lockout and password expiry messages',
      () async {
    for (final message in [
      'ロックされています',
      'アカウントはロック中です',
      'ログインIDはロック中です',
      'パスワードの有効期限が切れました',
      'パスワードが期限切れです',
      'パスワードを変更してください',
      'パスワードの変更が必要です',
    ]) {
      final encodedMessage = jsonEncode(message);
      final result = await _evaluateLoginAssist(
        [
          {'tag': 'input', 'type': 'text', 'name': 'userId'},
          {'tag': 'input', 'type': 'password', 'name': 'password'},
          {'tag': 'button', 'type': 'submit', 'text': 'ログイン'},
        ],
        setupScript: 'document.body.innerText = $encodedMessage;\n'
            "window.sessionStorage.setItem('MBG_LOGIN_AUTOFILL_LAST_CREDENTIAL:' + "
            "location.origin + location.pathname, 'previous');\n"
            'window.setInterval = function(callback) {\n'
            "  document.body.innerText = '';\n"
            '  callback();\n'
            '  return 1;\n'
            '};',
        monitorTicks: 3,
      );

      expect(result['clickCount'], 0);
      expect(_valueOf(result, 'password'), isEmpty);
      expect(
        (result['sessionValues'] as Map<String, dynamic>)
            .keys
            .any((key) => key.startsWith('MBG_LOGIN_AUTOFILL_ERROR:')),
        isTrue,
      );
    }
  });

  test('unrelated expiry notices on the login page do not stop autofill',
      () async {
    for (final message in [
      'お知らせ：証明書の期限切れについて',
      '一時的に利用できません',
    ]) {
      final encodedMessage = jsonEncode(message);
      final result = await _evaluateLoginAssist(
        [
          {'tag': 'input', 'type': 'text', 'name': 'userId'},
          {'tag': 'input', 'type': 'password', 'name': 'password'},
          {'tag': 'button', 'type': 'submit', 'text': 'ログイン'},
        ],
        setupScript: 'document.body.innerText = $encodedMessage;',
        monitorTicks: 3,
      );
      expect(result['clickCount'], 1, reason: message);
    }
  });

  test('login attempt limit survives rotating URL matrix parameters', () async {
    final script = LoginAutofillAssistScript.build(
      credentials: const GakujoLoginAutofillCredentials(
        loginId: 'saved-user',
        password: 'saved-password',
      ),
    );
    final result = await _evaluateGeneratedLoginAssist(
      '$script\n'
      'delete window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY;\n'
      "location = new URL('https://gakujo.iess.niigata-u.ac.jp/"
      "campusweb;route=second/campussmart.do;JSESSIONID=second;view=login"
      "?step=second#second');\n"
      'document.URL = location.href;\n'
      '$script',
      [
        {'tag': 'input', 'type': 'text', 'name': 'userId'},
        {'tag': 'input', 'type': 'password', 'name': 'password'},
        {'tag': 'button', 'type': 'submit', 'text': 'ログイン'},
      ],
      url: 'https://gakujo.iess.niigata-u.ac.jp/'
          'campusweb;route=first/campussmart.do;jsessionid=first;view=login'
          '?step=first#first',
      monitorTicks: 2,
    );

    expect(result['clickCount'], 1);
    final counts = (result['sessionValues'] as Map<String, dynamic>)
        .entries
        .where((entry) =>
            entry.key.startsWith('MBG_LOGIN_AUTOFILL_SUBMIT_COUNT:'));
    expect(counts, hasLength(1));
    expect(counts.single.key, contains('/campusweb/campussmart.do:'));
    expect(counts.single.value, '1');
  });

  test('reads login failures and lockouts inside the login frame', () async {
    for (final message in ['ログインに失敗しました', 'ロックされています']) {
      final result = await _evaluateLoginAssist(
        [
          {'tag': 'input', 'type': 'text', 'name': 'userId'},
          {'tag': 'input', 'type': 'password', 'name': 'password'},
          {'tag': 'button', 'type': 'submit', 'text': 'ログイン'},
        ],
        frameBodyText: message,
        monitorTicks: 3,
      );

      expect(_valueOf(result, 'password'), isEmpty);
      expect(result['clickCount'], 0);
      expect(_hasReport(result, 'ready-no-submit', 'target-found'), isTrue);
    }
  });

  for (final url in [
    'https://www.niigata-u.ac.jp/campussmart.do',
    'http://gakujo.iess.niigata-u.ac.jp/campussmart.do',
    'https://gakujo.iess.niigata-u.ac.jp.evil.example/campussmart.do',
    'file:///android_asset/qa/login.html',
  ]) {
    test('does not fill, submit or report login credentials on $url', () async {
      final result = await _evaluateGeneratedLoginAssist(
        LoginAutofillAssistScript.build(
          credentials: const GakujoLoginAutofillCredentials(
            loginId: 'saved-user',
            password: 'saved-password',
          ),
          debugLogging: true,
        ),
        [
          {'tag': 'input', 'type': 'text', 'name': 'userId'},
          {'tag': 'input', 'type': 'password', 'name': 'password'},
          {'tag': 'button', 'type': 'submit', 'text': 'ログイン'},
        ],
        url: url,
        monitorTicks: 3,
      );

      expect(_valueOf(result, 'userId'), isEmpty);
      expect(_valueOf(result, 'password'), isEmpty);
      expect(result['clickCount'], 0);
      expect(result['requestSubmitCount'], 0);
      expect(result['formSubmitCount'], 0);
      expect(result['reports'], isEmpty);
      expect(result['consoleLogs'], isEmpty);
      expect(result['sessionValues'], isEmpty);
    });
  }

  for (final debugLogging in [false, true]) {
    test('redacts login event URLs with debugLogging=$debugLogging', () async {
      final result = await _evaluateGeneratedLoginAssist(
        LoginAutofillAssistScript.build(debugLogging: debugLogging),
        [
          {'tag': 'input', 'type': 'text', 'name': 'userId'},
          {'tag': 'input', 'type': 'password', 'name': 'password'},
        ],
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

  test('does not scan authenticated controls without a pending attempt',
      () async {
    final result = await _evaluateGeneratedLoginAssist(
      LoginAutofillAssistScript.build(),
      [
        {'tag': 'ul', 'id': 'logout', 'text': 'ログアウト'},
        {'tag': 'img'},
      ],
      monitorTicks: 3,
    );

    expect(result['authenticatedControlScanCount'], 0);
    expect(_hasReport(result, 'skip', 'not-login-form'), isTrue);
    expect(_hasReport(result, 'authenticated', 'attempt-reset'), isFalse);
  });

  for (final pendingAttempt in ['submitted key', 'session count']) {
    test('resets a pending $pendingAttempt with a visible logout list',
        () async {
      const pageSuffix = ':https://gakujo.iess.niigata-u.ac.jp/campussmart.do';
      const sessionSuffix = '$pageSuffix:no-credentials';
      final pendingAttemptScript = pendingAttempt == 'submitted key'
          ? "window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY = 'no-credentials';"
          : "window.sessionStorage.setItem("
              "'MBG_LOGIN_AUTOFILL_SUBMIT_COUNT$sessionSuffix', '1');";
      final result = await _evaluateGeneratedLoginAssist(
        "$pendingAttemptScript\n"
        "window.sessionStorage.setItem("
        "'MBG_LOGIN_AUTOFILL_ERROR$sessionSuffix', '1');\n"
        "window.sessionStorage.setItem("
        "'MBG_LOGIN_AUTOFILL_LAST_CREDENTIAL$pageSuffix', 'no-credentials');\n"
        '${LoginAutofillAssistScript.build()}',
        [
          {'tag': 'ul', 'id': 'logout', 'text': 'ログアウト'},
          {'tag': 'img'},
        ],
        monitorTicks: 3,
      );

      expect(result['authenticatedControlScanCount'], 1);
      expect(result['submittedKey'], isNull);
      expect(result['sessionValues'], isEmpty);
      expect(_hasReport(result, 'authenticated', 'attempt-reset'), isTrue);
    });
  }

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
  List<Map<String, String>> elements, {
  String setupScript = '',
  String? url,
  String? frameBodyText,
  int monitorTicks = 0,
}) async {
  final script = LoginAutofillAssistScript.build(
    credentials: const GakujoLoginAutofillCredentials(
      loginId: 'saved-user',
      password: 'saved-password',
    ),
  );
  return _evaluateGeneratedLoginAssist(
    '$setupScript\n$script',
    elements,
    url: url,
    frameBodyText: frameBodyText,
    monitorTicks: monitorTicks,
  );
}

Future<Map<String, dynamic>> _evaluateGeneratedLoginAssist(
  String script,
  List<Map<String, String>> elements, {
  String? url,
  String? teardownScript,
  String? frameBodyText,
  bool deferTimers = false,
  bool simulateAuthenticatedTimeout = false,
  int monitorTicks = 0,
}) async {
  final process = await Process.start('node', [
    '-e',
    _nodeDomHarness,
    jsonEncode({
      'elements': elements,
      'url': url,
      'teardownScript': teardownScript,
      'frameBodyText': frameBodyText,
      'deferTimers': deferTimers,
      'simulateAuthenticatedTimeout': simulateAuthenticatedTimeout,
      'monitorTicks': monitorTicks,
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
const consoleLogs = [];
const sessionValues = new Map();
let clickCount = 0;
const clickedNames = [];
let requestSubmitCount = 0;
let formSubmitCount = 0;
let nextTimerId = 1;
const activeTimers = new Map();
const activeIntervals = new Map();
let authenticatedControlScanCount = 0;

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
        selector === 'a, button, input, [role="button"], img' ||
        selector === 'a, button, input, [role="button"], img, #logout') {
      return this.children.filter((element) =>
        ['BUTTON', 'INPUT', 'A', 'IMG'].includes(element.tagName) ||
        element.getAttribute('role') === 'button' ||
        (selector.includes('#logout') && element.id === 'logout')
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
  URL: spec.url || 'https://gakujo.iess.niigata-u.ac.jp/campussmart.do',
  body: {innerText: '', textContent: ''},
  defaultView: null,
  querySelector() { return null; },
  querySelectorAll(selector) {
    if (selector.startsWith('a, button, input, [role="button"], img')) {
      authenticatedControlScanCount += 1;
    }
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
if (spec.frameBodyText != null) {
  const frameDocument = {
    ...document,
    body: {innerText: spec.frameBodyText, textContent: spec.frameBodyText},
    querySelectorAll(selector) {
      return selector === 'iframe, frame' ? [] : form.querySelectorAll(selector);
    }
  };
  const frameWindow = {...window, document: frameDocument};
  frameDocument.defaultView = frameWindow;
  document.querySelectorAll = (selector) => selector === 'iframe, frame'
    ? [{contentWindow: frameWindow}]
    : [];
  form.ownerDocument = frameDocument;
  for (const element of elements) element.ownerDocument = frameDocument;
}

const context = {
  window,
  document,
  URL,
  location: new URL(spec.url ||
    'https://gakujo.iess.niigata-u.ac.jp/campussmart.do'),
  console: {log(message) { consoleLogs.push(message); }}
};
vm.runInNewContext(generatedScript, context);
for (let tick = 0; tick < (spec.monitorTicks || 0); tick += 1) {
  for (const callback of [...activeIntervals.values()]) callback();
}
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
  authenticatedControlScanCount,
  submittedKey: window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY || null,
  sessionValues: Object.fromEntries(sessionValues),
  reports,
  consoleLogs
}));
''';
