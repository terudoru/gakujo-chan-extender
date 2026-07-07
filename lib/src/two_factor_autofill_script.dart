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

  function reportProgress(event, detail) {
    try {
      var channel = window.MoreBetterGakujoLoginAutofill;
      if (channel && channel.postMessage) {
        channel.postMessage(JSON.stringify({
          event: '2fa-' + event,
          detail: detail || '',
          url: location.href
        }));
      }
    } catch (_) {
    }
    try {
      console.log('MBG_2FA_' + event.toUpperCase() + ' ' + (detail || ''));
    } catch (_) {
    }
  }

  function isVisible(element) {
    if (!element) {
      return false;
    }
    try {
      var pageWindow = (element.ownerDocument && element.ownerDocument.defaultView) || window;
      var style = pageWindow.getComputedStyle(element);
      return style.display !== 'none' &&
        style.visibility !== 'hidden' &&
        style.opacity !== '0' &&
        element.getClientRects().length > 0;
    } catch (_) {
      return true;
    }
  }

  function controlText(element) {
    return [
      element.innerText,
      element.textContent,
      element.value,
      element.getAttribute && element.getAttribute('aria-label'),
      element.getAttribute && element.getAttribute('title')
    ].filter(Boolean).join(' ').replace(/\\s+/g, ' ').trim().toLowerCase();
  }

  function isBackOrResetControl(element) {
    var text = controlText(element);
    var idText = [
      element.getAttribute && element.getAttribute('id'),
      element.getAttribute && element.getAttribute('name'),
      element.getAttribute && element.getAttribute('class')
    ].filter(Boolean).join(' ').toLowerCase();
    return /戻る|もどる|リセット|キャンセル|再送|reset|back|cancel|resend/.test(text) ||
      /reset|cancel|back/.test(idText);
  }

  // CampusSquare submits via a "ログイン"/"認証" button whose onclick calls the
  // page's send() helper (which populates hidden action fields). A raw
  // form.submit() skips that helper and the server bounces back to login, so we
  // must click the real control (mirroring the login autofill script).
  function findSubmitControl(input) {
    var form = input.form || input.closest('form');
    var scope = form || input.ownerDocument || document;
    var candidates = Array.prototype.slice.call(
      scope.querySelectorAll('button, input, a, [role="button"]')
    );
    var explicit = null;
    var labeled = null;
    for (var i = 0; i < candidates.length; i += 1) {
      var element = candidates[i];
      if (element === input) {
        continue;
      }
      var tagName = (element.tagName || '').toLowerCase();
      var type = (element.getAttribute('type') || '').toLowerCase();
      if (type === 'hidden' || type === 'password' || type === 'text') {
        continue;
      }
      if (!isVisible(element) || isBackOrResetControl(element)) {
        continue;
      }
      if (!explicit &&
          ((tagName === 'button' && (type === '' || type === 'submit')) ||
           (tagName === 'input' && type === 'submit'))) {
        explicit = element;
      }
      if (!labeled &&
          /ログイン|認証|確認|送信|次へ|つぎへ|ok|verify|submit|sign\\s?in|log\\s?in/.test(controlText(element))) {
        labeled = element;
      }
    }
    return labeled || explicit || null;
  }

  function submitFrom(input) {
    if (shouldBlockAutoSubmit()) {
      reportProgress('submit-blocked', 'session-limit-or-error');
      return false;
    }

    var control = findSubmitControl(input);
    if (control) {
      markAutoSubmitAttempted();
      reportProgress('submit', 'click ' + (control.tagName || '') + '/' +
        (control.getAttribute('type') || '') + ' "' + controlText(control).slice(0, 24) + '"');
      control.click();
      return true;
    }

    var pageWindow = (input.ownerDocument && input.ownerDocument.defaultView) || window;
    if (typeof pageWindow.send === 'function') {
      markAutoSubmitAttempted();
      reportProgress('submit', 'campus-square-send');
      pageWindow.send();
      return true;
    }

    var form = input.form || input.closest('form');
    if (form) {
      markAutoSubmitAttempted();
      reportProgress('submit', 'form-submit-fallback');
      if (typeof form.requestSubmit === 'function') {
        form.requestSubmit();
      } else {
        var event = new Event('submit', { bubbles: true, cancelable: true });
        if (form.dispatchEvent(event)) {
          form.submit();
        }
      }
      return true;
    }

    reportProgress('submit', 'no-control');
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
