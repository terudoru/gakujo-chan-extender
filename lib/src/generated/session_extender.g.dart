// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/session_extender/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoSessionExtenderJs = r'''
"use strict";
(() => {
  // web_scripts/src/session_extender/main.ts
  function sessionExtender() {
    var version = 1;
    if (window.__MBG_SESSION_EXTENDER_VERSION === version) {
      return;
    }
    window.__MBG_SESSION_EXTENDER_VERSION = version;
    window.clearInterval(window.__MBG_SESSION_EXTENDER_INTERVAL);
    window.__MBG_SESSION_EXTENDER_COUNT = 0;
    window.__MBG_SESSION_EXTENDER_URL = location.href;
    function remainingMinutes() {
      var timer = document.getElementById("timeout-timer");
      if (!timer) {
        return NaN;
      }
      var match = (timer.textContent || "").match(/\d+/);
      return match ? Number(match[0]) : NaN;
    }
    function extendIfNeeded() {
      if (window.__MBG_SESSION_EXTENDER_URL !== location.href) {
        window.__MBG_SESSION_EXTENDER_URL = location.href;
        window.__MBG_SESSION_EXTENDER_COUNT = 0;
      }
      if (window.__MBG_SESSION_EXTENDER_COUNT >= 10) {
        return;
      }
      var minutes = remainingMinutes();
      var button = document.getElementById("portaltimerimg");
      if (!isFinite(minutes) || minutes > 11 || !button) {
        return;
      }
      button.click();
      window.__MBG_SESSION_EXTENDER_COUNT += 1;
    }
    window.__MBG_SESSION_EXTENDER_INTERVAL = window.setInterval(extendIfNeeded, 6e4);
    extendIfNeeded();
  }
  sessionExtender();
})();
''';
