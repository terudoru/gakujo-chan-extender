// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/authenticated_session_reset/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoAuthenticatedSessionResetJs = r'''
"use strict";
(() => {
  // web_scripts/src/authenticated_session_reset/main.ts
  function authenticatedSessionReset() {
    delete window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY;
    delete window.__MBG_2FA_AUTO_SUBMITTED_KEY;
    try {
      if (!window.sessionStorage) {
        return 0;
      }
      var prefixes = [
        "MBG_LOGIN_AUTOFILL_ERROR:",
        "MBG_LOGIN_AUTOFILL_SUBMIT_COUNT:",
        "MBG_LOGIN_AUTOFILL_LAST_CREDENTIAL:",
        "MBG_2FA_AUTOFILL_ERROR:",
        "MBG_2FA_AUTOFILL_SUBMIT_COUNT:"
      ];
      var removed = 0;
      for (var i = window.sessionStorage.length - 1; i >= 0; i -= 1) {
        var key = window.sessionStorage.key(i) || "";
        for (var p = 0; p < prefixes.length; p += 1) {
          if (key.indexOf(prefixes[p]) === 0) {
            window.sessionStorage.removeItem(key);
            removed += 1;
            break;
          }
        }
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }
  authenticatedSessionReset();
})();
''';
