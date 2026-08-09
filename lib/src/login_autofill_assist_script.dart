import 'dart:convert';

import 'package:crypto/crypto.dart';

class LoginAutofillAssistScript {
  const LoginAutofillAssistScript._();

  static const channelName = 'MoreBetterGakujoLoginAutofill';

  static String buildTeardown() {
    return r'''
(function() {
  window.__MBG_LOGIN_AUTOFILL_DISABLED = true;
  window.clearTimeout(window.__MBG_LOGIN_AUTOFILL_TIMER);
  window.clearTimeout(window.__MBG_LOGIN_AUTOFILL_SUBMIT_TIMER);
  delete window.__MBG_LOGIN_AUTOFILL_TIMER;
  delete window.__MBG_LOGIN_AUTOFILL_SUBMIT_TIMER;
  delete window.__MBG_LOGIN_AUTOFILL_ASSIST_VERSION;
})();
''';
  }

  static String build({
    GakujoLoginAutofillCredentials? credentials,
  }) {
    final username = jsonEncode(credentials?.loginId);
    final password = jsonEncode(credentials?.password);
    final credentialKey = jsonEncode(
      credentials == null
          ? null
          : sha256
              .convert(
                utf8.encode(
                    '${credentials.loginId}\u0000${credentials.password}'),
              )
              .toString(),
    );
    final channelName = jsonEncode(LoginAutofillAssistScript.channelName);
    return '''
(function() {
  var assistVersion = 8;
  var savedUsername = $username;
  var savedPassword = $password;
  var savedCredentialKey = $credentialKey;
  var logChannelName = $channelName;
  if (window.__MBG_LOGIN_AUTOFILL_ASSIST_VERSION === assistVersion) {
    if (!savedUsername || !savedPassword || shouldBlockAutoSubmit()) {
      return;
    }
  }
  window.__MBG_LOGIN_AUTOFILL_ASSIST_VERSION = assistVersion;
  window.__MBG_LOGIN_AUTOFILL_DISABLED = false;
  window.clearTimeout(window.__MBG_LOGIN_AUTOFILL_TIMER);
  window.clearTimeout(window.__MBG_LOGIN_AUTOFILL_SUBMIT_TIMER);

  function report(event, detail) {
    var payload = {
      event: event,
      detail: detail || '',
      hasCredentials: !!(savedUsername && savedPassword),
      url: location.href
    };
    try {
      if (window[logChannelName] && window[logChannelName].postMessage) {
        window[logChannelName].postMessage(JSON.stringify(payload));
      }
    } catch (_) {
    }
    try {
      console.log('MBG_LOGIN_AUTOFILL ' + JSON.stringify(payload));
    } catch (_) {
    }
  }

  report('start', 'version=' + assistVersion);

  function pageSessionKey(suffix) {
    var normalizedUrl = location.origin + location.pathname;
    return 'MBG_LOGIN_AUTOFILL_' + suffix + ':' + normalizedUrl;
  }

  function sessionKey(suffix) {
    return pageSessionKey(suffix) + ':' +
      (savedCredentialKey || 'no-credentials');
  }

  function sessionValue(key) {
    try {
      return window.sessionStorage && window.sessionStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  function setSessionValue(key, value) {
    try {
      if (window.sessionStorage) {
        window.sessionStorage.setItem(key, value);
      }
    } catch (_) {
    }
  }

  function hasLoginError() {
    var text = '';
    try {
      text = (document.body && (document.body.innerText || document.body.textContent) || '')
        .replace(/\\s+/g, ' ')
        .toLowerCase();
    } catch (_) {
      return false;
    }
    return /認証失敗|認証に失敗|ログイン失敗|ログインに失敗|ユーザーidまたはパスワード|ユーザidまたはパスワード|idまたはパスワード|パスワード.*違|invalid.*password|authentication.*failed|login.*failed/.test(text);
  }

  function shouldBlockAutoSubmit() {
    if (window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY ===
        (savedCredentialKey || 'no-credentials')) {
      return true;
    }
    if (sessionValue(sessionKey('ERROR')) === '1') {
      return true;
    }
    var attempts = parseInt(sessionValue(sessionKey('SUBMIT_COUNT')) || '0', 10);
    if (attempts >= 1) {
      if (hasLoginError()) {
        setSessionValue(sessionKey('ERROR'), '1');
      }
      return true;
    }
    var currentCredentialKey = savedCredentialKey || 'no-credentials';
    var previousCredentialKey = sessionValue(pageSessionKey('LAST_CREDENTIAL'));
    var credentialsChanged = previousCredentialKey &&
      previousCredentialKey !== currentCredentialKey;
    if (hasLoginError() && !credentialsChanged) {
      setSessionValue(sessionKey('ERROR'), '1');
      return true;
    }
    return false;
  }

  function markAutoSubmitAttempted() {
    window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY =
      savedCredentialKey || 'no-credentials';
    setSessionValue(
      pageSessionKey('LAST_CREDENTIAL'),
      savedCredentialKey || 'no-credentials'
    );
    var key = sessionKey('SUBMIT_COUNT');
    var attempts = parseInt(sessionValue(key) || '0', 10);
    if (!isFinite(attempts) || attempts < 0) {
      attempts = 0;
    }
    setSessionValue(key, String(attempts + 1));
  }

  function visible(element) {
    if (!element) {
      return false;
    }
    var pageWindow = element.ownerDocument.defaultView || window;
    var style = pageWindow.getComputedStyle(element);
    return style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      style.opacity !== '0' &&
      element.getClientRects().length > 0;
  }

  function allDocuments() {
    var documents = [];
    function collect(win) {
      try {
        if (!win || !win.document || documents.indexOf(win.document) !== -1) {
          return;
        }
        documents.push(win.document);
        var frames = Array.prototype.slice.call(win.document.querySelectorAll('iframe, frame'));
        for (var i = 0; i < frames.length; i += 1) {
          collect(frames[i].contentWindow);
        }
      } catch (_) {
      }
    }
    collect(window);
    return documents;
  }

  function fieldLabelText(input) {
    var pieces = [
      input.getAttribute('name'),
      input.getAttribute('id'),
      input.getAttribute('placeholder'),
      input.getAttribute('aria-label'),
      input.getAttribute('title')
    ];

    var ownerDocument = input.ownerDocument || document;
    var pageWindow = ownerDocument.defaultView || window;
    if (input.id && pageWindow.CSS && pageWindow.CSS.escape) {
      var label = ownerDocument.querySelector('label[for="' + pageWindow.CSS.escape(input.id) + '"]');
      if (label) {
        pieces.push(label.innerText || label.textContent);
      }
    }

    var wrappingLabel = input.closest('label');
    if (wrappingLabel) {
      pieces.push(wrappingLabel.innerText || wrappingLabel.textContent);
    }
    return pieces.filter(Boolean).join(' ').replace(/\\s+/g, ' ').trim().toLowerCase();
  }

  function isKnownUsernameField(input) {
    var type = (input.getAttribute('type') || 'text').toLowerCase();
    if (type !== 'text' && type !== 'email' && type !== 'tel' && type !== '') {
      return false;
    }

    var identifiers = [
      input.getAttribute('name'),
      input.getAttribute('id')
    ].filter(Boolean);
    var knownIdentifiers = ['userid', 'loginid', 'username', 'jusername'];
    for (var i = 0; i < identifiers.length; i += 1) {
      var normalized = identifiers[i].toLowerCase().replace(/[\\s_-]+/g, '');
      if (knownIdentifiers.indexOf(normalized) !== -1) {
        return true;
      }
    }
    return false;
  }

  function isPasswordInput(input) {
    return (input.getAttribute('type') || '').toLowerCase() === 'password' &&
      (input.getAttribute('name') || '').toLowerCase() !== 'ninshocode' &&
      (input.getAttribute('id') || '').toLowerCase() !== 'ninshocode';
  }

  function isPasswordChangeField(input) {
    var identifier = [
      input.getAttribute('name'),
      input.getAttribute('id')
    ].filter(Boolean).join(' ').toLowerCase().replace(/[\\s_-]+/g, '');
    if (/(?:new|confirm|confirmation|old|current)(?:password|passwd|pwd)|(?:password|passwd|pwd)(?:new|confirm|confirmation|old|current)/.test(identifier)) {
      return true;
    }

    var autocomplete = (input.getAttribute('autocomplete') || '').toLowerCase();
    if (autocomplete === 'new-password') {
      return true;
    }

    var text = fieldLabelText(input);
    return /パスワード.{0,8}(?:変更|確認|再入力)|(?:新しい|新規|現在|現行|旧|確認用|再入力).{0,8}パスワード|再入力/.test(text);
  }

  function firstVisible(inputs, predicate) {
    for (var i = 0; i < inputs.length; i += 1) {
      if (visible(inputs[i]) && predicate(inputs[i])) {
        return inputs[i];
      }
    }
    return null;
  }

  function findLoginFields(doc) {
    var inputs = Array.prototype.slice.call(doc.querySelectorAll('input'));
    var password = firstVisible(inputs, isPasswordInput);
    if (!password) {
      return null;
    }

    var form = password.form || password.closest('form');
    var formInputs = form ?
      Array.prototype.slice.call(form.querySelectorAll('input')) :
      inputs;
    var visiblePasswordInputs = formInputs.filter(function(input) {
      return visible(input) && isPasswordInput(input);
    });
    if (visiblePasswordInputs.length >= 2 ||
        visiblePasswordInputs.some(isPasswordChangeField)) {
      return null;
    }

    var username = firstVisible(formInputs, isKnownUsernameField);

    if (!username) {
      return null;
    }

    return {
      doc: doc,
      form: form,
      username: username,
      password: password
    };
  }

  function findLoginTarget() {
    var documents = allDocuments();
    for (var i = 0; i < documents.length; i += 1) {
      var target = findLoginFields(documents[i]);
      if (target) {
        return target;
      }
    }
    return null;
  }

  function setInputValue(input, value) {
    var pageWindow = input.ownerDocument.defaultView || window;
    var descriptor = pageWindow.HTMLInputElement &&
      Object.getOwnPropertyDescriptor(pageWindow.HTMLInputElement.prototype, 'value');
    input.focus();
    try {
      input.dispatchEvent(new pageWindow.InputEvent('beforeinput', {
        bubbles: true,
        cancelable: true,
        inputType: 'insertReplacementText',
        data: value
      }));
    } catch (_) {
    }
    if (descriptor && descriptor.set) {
      descriptor.set.call(input, value);
    } else {
      input.value = value;
    }
    input.dispatchEvent(new pageWindow.InputEvent('input', {
      bubbles: true,
      inputType: 'insertReplacementText',
      data: value
    }));
    input.dispatchEvent(new pageWindow.Event('change', { bubbles: true }));
    input.blur();
  }

  function setIfMissing(element, name, value) {
    if (!element.getAttribute(name)) {
      element.setAttribute(name, value);
    }
  }

  function enableCredentialAutofill(target) {
    if (target.form) {
      target.form.setAttribute('autocomplete', 'on');
    }

    target.username.setAttribute('autocomplete', 'username');
    target.username.setAttribute('autocapitalize', 'none');
    target.username.setAttribute('autocorrect', 'off');
    target.username.setAttribute('spellcheck', 'false');
    target.username.setAttribute('enterkeyhint', 'next');
    setIfMissing(target.username, 'name', 'username');
    setIfMissing(target.username, 'id', 'username');
    setIfMissing(target.username, 'aria-label', 'ログインID');

    target.password.setAttribute('autocomplete', 'current-password');
    target.password.setAttribute('autocapitalize', 'none');
    target.password.setAttribute('autocorrect', 'off');
    target.password.setAttribute('spellcheck', 'false');
    target.password.setAttribute('enterkeyhint', 'done');
    setIfMissing(target.password, 'name', 'password');
    setIfMissing(target.password, 'id', 'password');
    setIfMissing(target.password, 'aria-label', 'パスワード');
  }

  function submitForm(target) {
    if (window.__MBG_LOGIN_AUTOFILL_DISABLED) {
      return;
    }
    if (shouldBlockAutoSubmit()) {
      report('submit-blocked', 'session-limit-or-error');
      return;
    }
    markAutoSubmitAttempted();

    var form = target.form;
    var doc = target.doc;
    var pageWindow = doc.defaultView || window;
    var password = target.password;
    var scope = form || doc;

    if (form &&
        form.id === 'wf_PTW0000011_20120827233559-form' &&
        typeof pageWindow.send === 'function') {
      report('submit', 'campus-square-send');
      pageWindow.send();
      return;
    }

    var candidates = Array.prototype.slice.call(
      scope.querySelectorAll('button, input, a, [role="button"]')
    );
    var submitter = firstVisible(candidates, function(element) {
      var type = (element.getAttribute('type') || '').toLowerCase();
      if (element === target.username || element === target.password ||
          type === 'hidden' || type === 'password' || type === 'text') {
        return false;
      }
      var text = [
        element.innerText,
        element.textContent,
        element.value,
        element.getAttribute('aria-label'),
        element.getAttribute('title')
      ].filter(Boolean).join(' ').toLowerCase();
      var idText = [
        element.getAttribute('id'),
        element.getAttribute('name'),
        element.getAttribute('class')
      ].filter(Boolean).join(' ').toLowerCase();
      return type === 'submit' ||
        type === 'image' ||
        /login|log in|sign in|submit|ログイン|サインイン|送信|認証|次へ/.test(text) ||
        /login|submit|auth/.test(idText);
    });

    if (submitter) {
      report('submit', 'click');
      submitter.click();
      return;
    }
    if (form && form.requestSubmit) {
      report('submit', 'requestSubmit');
      form.requestSubmit();
      return;
    }
    if (form && form.submit) {
      report('submit', 'formSubmit');
      form.submit();
      return;
    }
    report('submit', 'enter-key');
    password.focus();
    password.dispatchEvent(new pageWindow.KeyboardEvent('keydown', {
      key: 'Enter',
      code: 'Enter',
      keyCode: 13,
      which: 13,
      bubbles: true
    }));
  }

  function assist(attempt) {
    if (window.__MBG_LOGIN_AUTOFILL_DISABLED) {
      return;
    }
    var target = findLoginTarget();
    if (!target) {
      if (attempt < 20) {
        if (attempt === 0 || attempt === 5 || attempt === 19) {
          report('skip', 'not-login-form attempt=' + attempt);
        }
        window.__MBG_LOGIN_AUTOFILL_TIMER = window.setTimeout(function() {
          assist(attempt + 1);
        }, 500);
      }
      return;
    }

    enableCredentialAutofill(target);

    if (!savedUsername || !savedPassword || shouldBlockAutoSubmit()) {
      report('ready-no-submit', 'target-found');
      console.log('MBG_LOGIN_AUTOFILL_ASSIST_READY');
      return;
    }

    report('fill', 'target-found form=' + (target.form ? target.form.id : 'none'));
    setInputValue(target.username, savedUsername);
    setInputValue(target.password, savedPassword);
    window.__MBG_LOGIN_AUTOFILL_SUBMIT_TIMER = window.setTimeout(function() {
      submitForm(target);
    }, 250);
  }

  assist(0);
})();
''';
  }
}

class GakujoLoginAutofillCredentials {
  const GakujoLoginAutofillCredentials({
    required this.loginId,
    required this.password,
  });

  final String loginId;
  final String password;
}
