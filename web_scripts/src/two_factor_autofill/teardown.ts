export {};

function twoFactorAutofillTeardown() {
  window.__MBG_2FA_AUTOFILL_DISABLED = true;
  window.clearTimeout(window.__MBG_2FA_AUTOFILL_TIMER);
  delete window.__MBG_2FA_AUTOFILL_TIMER;
}

twoFactorAutofillTeardown();
