class LoginAutofillAssistScript {
  const LoginAutofillAssistScript._();

  static String build() {
    return r'''
(function() {
  var assistVersion = 1;
  if (window.__MBG_LOGIN_AUTOFILL_ASSIST_VERSION === assistVersion) {
    return;
  }
  window.__MBG_LOGIN_AUTOFILL_ASSIST_VERSION = assistVersion;

  function visible(element) {
    if (!element) {
      return false;
    }
    var style = window.getComputedStyle(element);
    return style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      element.offsetParent !== null;
  }

  function textAround(input) {
    var pieces = [
      input.getAttribute('name'),
      input.getAttribute('id'),
      input.getAttribute('placeholder'),
      input.getAttribute('aria-label'),
      input.getAttribute('title')
    ];

    if (input.id) {
      var escapedId = window.CSS && CSS.escape ?
        CSS.escape(input.id) :
        input.id.replace(/["\\]/g, '\\$&');
      var label = document.querySelector('label[for="' + escapedId + '"]');
      if (label) {
        pieces.push(label.innerText || label.textContent);
      }
    }

    var parent = input.closest('tr, p, div, li, label');
    if (parent) {
      pieces.push(parent.innerText || parent.textContent);
    }
    return pieces.filter(Boolean).join(' ').replace(/\s+/g, ' ').trim().toLowerCase();
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

  var inputs = Array.prototype.slice.call(document.querySelectorAll('input'));
  var password = firstVisible(inputs, function(input) {
    return (input.getAttribute('type') || '').toLowerCase() === 'password' &&
      input.getAttribute('name') !== 'ninshoCode';
  });
  if (!password) {
    return;
  }

  var form = password.form || password.closest('form');
  var formInputs = form ?
    Array.prototype.slice.call(form.querySelectorAll('input')) :
    inputs;
  var username = firstVisible(formInputs, isUsernameCandidate) ||
    firstVisible(formInputs, function(input) {
      var type = (input.getAttribute('type') || 'text').toLowerCase();
      return input !== password && (type === 'text' || type === 'email' || type === '');
    });

  if (form) {
    form.setAttribute('autocomplete', 'on');
  }

  if (username) {
    username.setAttribute('autocomplete', 'username');
    username.setAttribute('autocapitalize', 'none');
    username.setAttribute('spellcheck', 'false');
    if (!username.getAttribute('name')) {
      username.setAttribute('name', 'username');
    }
    if (!username.getAttribute('id')) {
      username.setAttribute('id', 'username');
    }
  }

  password.setAttribute('autocomplete', 'current-password');
  if (!password.getAttribute('name')) {
    password.setAttribute('name', 'password');
  }
  if (!password.getAttribute('id')) {
    password.setAttribute('id', 'password');
  }

  console.log('MBG_LOGIN_AUTOFILL_ASSIST_READY');
})();
''';
  }
}
