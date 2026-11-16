// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/two_factor_autofill/teardown.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoTwoFactorAutofillTeardownJs = r'''
"use strict";
(() => {
  // web_scripts/src/two_factor_autofill/teardown.ts
  function twoFactorAutofillTeardown() {
    window.__MBG_2FA_AUTOFILL_DISABLED = true;
    window.clearTimeout(window.__MBG_2FA_AUTOFILL_TIMER);
    delete window.__MBG_2FA_AUTOFILL_TIMER;
    function restore(win) {
      try {
        var doc = win.document;
        var inputs = doc.querySelectorAll("input[data-mbg-2fa-original-type]");
        for (var i = 0; i < inputs.length; i += 1) {
          inputs[i].type = inputs[i].getAttribute("data-mbg-2fa-original-type");
          inputs[i].removeAttribute("data-mbg-2fa-original-type");
        }
        var frames = doc.querySelectorAll("iframe, frame");
        for (var j = 0; j < frames.length; j += 1) {
          if (frames[j].contentWindow) restore(frames[j].contentWindow);
        }
      } catch (_) {
      }
    }
    restore(window);
  }
  twoFactorAutofillTeardown();
})();
''';
