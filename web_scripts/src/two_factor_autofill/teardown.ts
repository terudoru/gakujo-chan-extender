export {};

function twoFactorAutofillTeardown() {
  window.__MBG_2FA_AUTOFILL_DISABLED = true;
  window.clearTimeout(window.__MBG_2FA_AUTOFILL_TIMER);
  delete window.__MBG_2FA_AUTOFILL_TIMER;
  function restore(win: Window) {
    try {
      var doc = win.document;
      var inputs = doc.querySelectorAll<HTMLInputElement>('input[data-mbg-2fa-original-type]');
      for (var i = 0; i < inputs.length; i += 1) {
        inputs[i].type = inputs[i].getAttribute('data-mbg-2fa-original-type')!;
        inputs[i].removeAttribute('data-mbg-2fa-original-type');
      }
      var frames = doc.querySelectorAll<HTMLIFrameElement | HTMLFrameElement>('iframe, frame');
      for (var j = 0; j < frames.length; j += 1) {
        if (frames[j].contentWindow) restore(frames[j].contentWindow!);
      }
    } catch (_) {
      // Cross-origin frames cannot be inspected.
    }
  }
  restore(window);
}

twoFactorAutofillTeardown();
