export {};
function teardownSessionExtender() {
  window.clearInterval(window.__MBG_SESSION_EXTENDER_INTERVAL);
  delete window.__MBG_SESSION_EXTENDER_INTERVAL;
  delete window.__MBG_SESSION_EXTENDER_VERSION;
  delete window.__MBG_SESSION_EXTENDER_COUNT;
  delete window.__MBG_SESSION_EXTENDER_URL;
}

teardownSessionExtender();
