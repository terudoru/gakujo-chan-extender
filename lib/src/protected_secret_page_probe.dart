import 'dart:convert';

import 'two_factor_autofill_script.dart';

class ProtectedSecretPageProbe {
  const ProtectedSecretPageProbe._();

  static String login() => _build('login');

  static String twoFactor() => _build('twoFactor');

  static String _build(String kind) => r'''
(function(config) {
  function find(win, seen) {
    try {
      var doc = win && win.document;
      if (!doc || seen.indexOf(doc) !== -1) return false;
      seen.push(doc);
      if (config.kind === 'login') {
        var inputs = doc.querySelectorAll('input');
        for (var i = 0; i < inputs.length; i += 1) {
          var input = inputs[i];
          var style = (input.ownerDocument.defaultView || window).getComputedStyle(input);
          if (style.display !== 'none' && style.visibility !== 'hidden' &&
              style.opacity !== '0' && input.getClientRects().length > 0 &&
              (input.getAttribute('type') || '').toLowerCase() === 'password' &&
              (input.getAttribute('name') || '').toLowerCase() !== 'ninshocode' &&
              (input.getAttribute('id') || '').toLowerCase() !== 'ninshocode') {
            return true;
          }
        }
      } else if (doc.querySelectorAll('input[name="' + config.inputName + '"]').length > 0) {
        return true;
      }
      var frames = doc.querySelectorAll('iframe, frame');
      for (var j = 0; j < frames.length; j += 1) {
        try {
          if (find(frames[j].contentWindow, seen)) return true;
        } catch (_) {}
      }
    } catch (_) {}
    return false;
  }
  return find(window, []);
})(''' + jsonEncode({
    'kind': kind,
    'inputName': TwoFactorAutofillScript.inputName,
  }) + ');';
}
