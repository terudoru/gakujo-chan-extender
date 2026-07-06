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
  var attempts = 0;
  var maxAttempts = $maxAttempts;
  var intervalMillis = $intervalMillis;
  var token = $encodedToken;
  var autoSubmit = $autoSubmitLiteral;

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
    if (!autoSubmit || window.__MBG_2FA_AUTO_SUBMITTED) {
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

    window.__MBG_2FA_AUTO_SUBMITTED = true;
    if (submitControl) {
      submitControl.click();
      console.log('MBG_2FA_AUTO_SUBMIT_SUCCESS');
      return true;
    }
    if (form) {
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

    window.__MBG_2FA_AUTO_SUBMITTED = false;
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
