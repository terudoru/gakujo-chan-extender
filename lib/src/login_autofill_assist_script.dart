import 'dart:convert';

class LoginAutofillAssistScript {
  const LoginAutofillAssistScript._();

  static const channelName = 'MoreBetterGakujoLoginAutofill';

  static String build({
    GakujoLoginAutofillCredentials? credentials,
  }) {
    final username = jsonEncode(credentials?.loginId);
    final password = jsonEncode(credentials?.password);
    final channelName = jsonEncode(LoginAutofillAssistScript.channelName);
    return '''
(function() {
  var assistVersion = 5;
  var savedUsername = $username;
  var savedPassword = $password;
  var logChannelName = $channelName;
  if (window.__MBG_LOGIN_AUTOFILL_ASSIST_VERSION === assistVersion) {
    if (!savedUsername || !savedPassword || window.__MBG_LOGIN_AUTOFILL_SUBMITTED) {
      return;
    }
  }
  window.__MBG_LOGIN_AUTOFILL_ASSIST_VERSION = assistVersion;
  window.clearTimeout(window.__MBG_LOGIN_AUTOFILL_TIMER);

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

  function visible(element) {
    if (!element) {
      return false;
    }
    var style = window.getComputedStyle(element);
    return style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      style.opacity !== '0' &&
      element.getClientRects().length > 0;
  }

  function allDocuments() {
    var documents = [document];
    var frames = Array.prototype.slice.call(document.querySelectorAll('iframe, frame'));
    for (var i = 0; i < frames.length; i += 1) {
      try {
        if (frames[i].contentDocument) {
          documents.push(frames[i].contentDocument);
        }
      } catch (_) {
      }
    }
    return documents;
  }

  function queryFirst(doc, selectors) {
    for (var i = 0; i < selectors.length; i += 1) {
      try {
        var element = doc.querySelector(selectors[i]);
        if (visible(element)) {
          return element;
        }
      } catch (_) {
      }
    }
    return null;
  }

  function textAround(input) {
    var pieces = [
      input.getAttribute('name'),
      input.getAttribute('id'),
      input.getAttribute('placeholder'),
      input.getAttribute('aria-label'),
      input.getAttribute('title')
    ];

    if (input.id && window.CSS && CSS.escape) {
      var label = document.querySelector('label[for="' + CSS.escape(input.id) + '"]');
      if (label) {
        pieces.push(label.innerText || label.textContent);
      }
    }

    var parent = input.closest('tr, p, div, li, label');
    if (parent) {
      pieces.push(parent.innerText || parent.textContent);
    }
    return pieces.filter(Boolean).join(' ').replace(/\\s+/g, ' ').trim().toLowerCase();
  }

  function isUsernameCandidate(input) {
    var type = (input.getAttribute('type') || 'text').toLowerCase();
    if (type !== 'text' && type !== 'email' && type !== 'tel' && type !== '') {
      return false;
    }

    var text = textAround(input);
    return /user|login|account|id|mail|email|ユーザー|ユーザ|ログイン|アカウント|利用者|学籍|職員|メール/.test(text);
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
    var password = queryFirst(doc, [
      'input[type="password"]:not([name="ninshoCode"])',
      'input[name="password"]',
      'input[name="j_password"]',
      'input[id*="password"]',
      'input[name*="password"]'
    ]) || firstVisible(inputs, function(input) {
      return (input.getAttribute('type') || '').toLowerCase() === 'password' &&
        input.getAttribute('name') !== 'ninshoCode';
    });
    if (!password) {
      return null;
    }

    var form = password.form || password.closest('form');
    var formInputs = form ?
      Array.prototype.slice.call(form.querySelectorAll('input')) :
      inputs;
    var username = queryFirst(doc, [
      'input[name="userId"]',
      'input[id="userId"]',
      'input[name="userName"]',
      'input[name="loginId"]',
      'input[id="loginId"]',
      'input[name="j_username"]',
      'input[id="username"]',
      'input[name*="user"]',
      'input[id*="user"]',
      'input[name*="login"]',
      'input[id*="login"]'
    ]) || firstVisible(formInputs, isUsernameCandidate) ||
      firstVisible(formInputs, function(input) {
        var type = (input.getAttribute('type') || 'text').toLowerCase();
        return input !== password &&
          (type === 'text' || type === 'email' || type === 'tel' || type === '');
      });

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

  function submitForm(target) {
    if (window.__MBG_LOGIN_AUTOFILL_SUBMITTED) {
      return;
    }
    window.__MBG_LOGIN_AUTOFILL_SUBMITTED = true;

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
        type === 'button' ||
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
    var target = findLoginTarget();
    if (!target) {
      if (attempt < 20) {
        if (attempt === 0 || attempt === 5 || attempt === 19) {
          report('target-not-found', 'attempt=' + attempt);
        }
        window.__MBG_LOGIN_AUTOFILL_TIMER = window.setTimeout(function() {
          assist(attempt + 1);
        }, 500);
      }
      return;
    }

    if (target.form) {
      target.form.setAttribute('autocomplete', 'on');
    }

    target.username.setAttribute('autocomplete', 'username');
    target.username.setAttribute('autocapitalize', 'none');
    target.username.setAttribute('spellcheck', 'false');
    if (!target.username.getAttribute('name')) {
      target.username.setAttribute('name', 'username');
    }
    if (!target.username.getAttribute('id')) {
      target.username.setAttribute('id', 'username');
    }

    target.password.setAttribute('autocomplete', 'current-password');
    if (!target.password.getAttribute('name')) {
      target.password.setAttribute('name', 'password');
    }
    if (!target.password.getAttribute('id')) {
      target.password.setAttribute('id', 'password');
    }

    if (!savedUsername || !savedPassword || window.__MBG_LOGIN_AUTOFILL_SUBMITTED) {
      report('ready-no-submit', 'target-found');
      console.log('MBG_LOGIN_AUTOFILL_ASSIST_READY');
      return;
    }

    report('fill', 'target-found form=' + (target.form ? target.form.id : 'none'));
    setInputValue(target.username, savedUsername);
    setInputValue(target.password, savedPassword);
    window.setTimeout(function() {
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
