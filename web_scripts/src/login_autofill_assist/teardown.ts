export {};

function loginAutofillAssistTeardown() {
  window.__MBG_LOGIN_AUTOFILL_DISABLED = true;
  window.clearTimeout(window.__MBG_LOGIN_AUTOFILL_TIMER);
  window.clearTimeout(window.__MBG_LOGIN_AUTOFILL_SUBMIT_TIMER);
  if (window.__MBG_LOGIN_AUTOFILL_WATCH_DISPOSE) window.__MBG_LOGIN_AUTOFILL_WATCH_DISPOSE();
  delete window.__MBG_LOGIN_AUTOFILL_WATCH_DISPOSE;
  window.clearInterval(window.__MBG_LOGIN_AUTOFILL_MONITOR);
  delete window.__MBG_LOGIN_AUTOFILL_TIMER;
  delete window.__MBG_LOGIN_AUTOFILL_SUBMIT_TIMER;
  delete window.__MBG_LOGIN_AUTOFILL_MONITOR;
  delete window.__MBG_LOGIN_AUTOFILL_LAST_REPORT;
  delete window.__MBG_LOGIN_AUTOFILL_CHALLENGE_VISIBLE;
  delete window.__MBG_LOGIN_AUTOFILL_ASSIST_VERSION;
}

loginAutofillAssistTeardown();
