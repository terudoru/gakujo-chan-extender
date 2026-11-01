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
  }
  twoFactorAutofillTeardown();
})();
''';
