// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/session_extender/teardown.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoSessionExtenderTeardownJs = r'''
"use strict";
(() => {
  // web_scripts/src/session_extender/teardown.ts
  function teardownSessionExtender() {
    window.clearInterval(window.__MBG_SESSION_EXTENDER_INTERVAL);
    delete window.__MBG_SESSION_EXTENDER_INTERVAL;
    delete window.__MBG_SESSION_EXTENDER_VERSION;
    delete window.__MBG_SESSION_EXTENDER_COUNT;
    delete window.__MBG_SESSION_EXTENDER_URL;
  }
  teardownSessionExtender();
})();
''';
