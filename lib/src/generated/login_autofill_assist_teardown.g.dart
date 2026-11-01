// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/login_autofill_assist/teardown.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoLoginAutofillAssistTeardownJs = r'''
"use strict";
(() => {
  // web_scripts/src/login_autofill_assist/teardown.ts
  function loginAutofillAssistTeardown() {
    window.__MBG_LOGIN_AUTOFILL_DISABLED = true;
    window.clearTimeout(window.__MBG_LOGIN_AUTOFILL_TIMER);
    window.clearTimeout(window.__MBG_LOGIN_AUTOFILL_SUBMIT_TIMER);
    window.clearInterval(window.__MBG_LOGIN_AUTOFILL_MONITOR);
    delete window.__MBG_LOGIN_AUTOFILL_TIMER;
    delete window.__MBG_LOGIN_AUTOFILL_SUBMIT_TIMER;
    delete window.__MBG_LOGIN_AUTOFILL_MONITOR;
    delete window.__MBG_LOGIN_AUTOFILL_LAST_REPORT;
    delete window.__MBG_LOGIN_AUTOFILL_CHALLENGE_VISIBLE;
    delete window.__MBG_LOGIN_AUTOFILL_ASSIST_VERSION;
  }
  loginAutofillAssistTeardown();
})();
''';
