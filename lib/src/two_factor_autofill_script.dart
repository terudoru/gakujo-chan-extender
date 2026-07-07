import 'dart:convert';

class TwoFactorAutofillScript {
  static const inputName = 'ninshoCode';

  const TwoFactorAutofillScript._();

  static String build({
    required String token,
    int maxAttempts = 20,
    int intervalMillis = 250,
    bool autoSubmit = true,
  }) {
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be positive');
    }
    if (intervalMillis <= 0) {
      throw ArgumentError.value(
        intervalMillis,
        'intervalMillis',
        'must be positive',
      );
    }

    final encodedToken = jsonEncode(token);
    final autoSubmitLiteral = autoSubmit ? 'true' : 'false';

    return '''
(function() {
  var assistVersion = 2;
  var attempts = 0;
  var maxAttempts = $maxAttempts;
  var intervalMillis = $intervalMillis;
  var token = $encodedToken;
  var autoSubmit = $autoSubmitLiteral;
  var maxAutoSubmitPerSession = 3;

  function sessionKey(suffix) {
    var normalizedUrl = location.origin + location.pathname;
    return 'MBG_2FA_AUTOFILL_' + suffix + ':' + normalizedUrl;
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

  function hasTwoFactorError() {
    var documents = allDocuments();
    for (var i = 0; i < documents.length; i += 1) {
      var text = '';
      try {
        text = (documents[i].body &&
          (documents[i].body.innerText || documents[i].body.textContent) || '')
          .replace(/\\s+/g, ' ')
          .toLowerCase();
      } catch (_) {
        continue;
      }
      if (/認証コード.*正しく|認証コード.*誤|コード.*正しく|コード.*誤|コード.*無効|確認コード.*正しく|確認コード.*誤|ワンタイム.*正しく|ワンタイム.*誤|invalid.*code|invalid.*token|incorrect.*code|wrong.*code|authentication.*code.*failed|verification.*failed/.test(text)) {
        setSessionValue(sessionKey('ERROR'), '1');
        return true;
      }
    }
    return false;
  }

  function shouldBlockAutoSubmit() {
    if (!autoSubmit || window.__MBG_2FA_AUTO_SUBMITTED) {
      return true;
    }
    if (sessionValue(sessionKey('ERROR')) === '1' || hasTwoFactorError()) {
      return true;
    }
    var count = parseInt(sessionValue(sessionKey('SUBMIT_COUNT')) || '0', 10);
    return isFinite(count) && count >= maxAutoSubmitPerSession;
  }

  function markAutoSubmitAttempted() {
    window.__MBG_2FA_AUTO_SUBMITTED = true;
    var key = sessionKey('SUBMIT_COUNT');
    var count = parseInt(sessionValue(key) || '0', 10);
    if (!isFinite(count) || count < 0) {
      count = 0;
    }
    setSessionValue(key, String(count + 1));
  }

  function isLikelySubmitControl(element) {
    if (!element) {
      return false;
    }

    var tagName = (element.tagName || '').toLowerCase();
    var type = (element.getAttribute('type') || '').toLowerCase();
    if (tagName === 'button') {
      return type === '' || type === 'submit';
    }
    if (tagName === 'input') {
      return type === 'submit';
    }
    return false;
  }

  function submitFrom(input) {
    if (shouldBlockAutoSubmit()) {
      console.log('MBG_2FA_AUTO_SUBMIT_BLOCKED');
      return false;
    }

    var form = input.form || input.closest('form');
    var submitControl = null;
    if (form) {
      submitControl = form.querySelector('button[type="submit"], input[type="submit"], button:not([type])');
    }
    if (!submitControl) {
      var ownerDocument = input.ownerDocument || document;
      var controls = ownerDocument.querySelectorAll('button, input[type="submit"]');
      for (var i = 0; i < controls.length; i += 1) {
        if (isLikelySubmitControl(controls[i])) {
          submitControl = controls[i];
          break;
        }
      }
    }

    if (submitControl) {
      markAutoSubmitAttempted();
      submitControl.click();
      console.log('MBG_2FA_AUTO_SUBMIT_SUCCESS');
      return true;
    }
    if (form) {
      markAutoSubmitAttempted();
      if (typeof form.requestSubmit === 'function') {
        form.requestSubmit();
      } else {
        var event = new Event('submit', { bubbles: true, cancelable: true });
        if (form.dispatchEvent(event)) {
          form.submit();
        }
      }
      console.log('MBG_2FA_AUTO_SUBMIT_SUCCESS');
      return true;
    }

    return false;
  }

  function fill() {
    attempts += 1;
    var input = null;
    var documents = allDocuments();
    for (var i = 0; i < documents.length; i += 1) {
      input = documents[i].querySelector('input[name="$inputName"]');
      if (input) {
        break;
      }
    }
    if (!input) {
      if (attempts < maxAttempts) {
        window.setTimeout(fill, intervalMillis);
      }
      return false;
    }

    input.type = 'text';
    input.value = token;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
    input.focus();
    console.log('MBG_2FA_AUTOFILL_SUCCESS');
    submitFrom(input);
    return true;
  }

  return fill();
})();
''';
  }
}
