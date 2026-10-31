export {};
function portalAuthStateProbe(): string {
  var documents: Document[] = [];
  function collect(win: Window) {
    try {
      if (!win || !win.document || documents.indexOf(win.document) !== -1) {
        return;
      }
      documents.push(win.document);
      for (var i = 0; i < win.frames.length; i += 1) {
        collect(win.frames[i]);
      }
    } catch (_) {}
  }
  function visible(element: HTMLElement) {
    if (!element) {
      return false;
    }
    try {
      var pageWindow = element.ownerDocument.defaultView || window;
      var style = pageWindow.getComputedStyle(element);
      return style.display !== 'none' &&
        style.visibility !== 'hidden' &&
        style.opacity !== '0' &&
        element.getClientRects().length > 0;
    } catch (_) {
      return false;
    }
  }
  function normalizedIdentifiers(element: HTMLElement) {
    return [
      element.getAttribute && element.getAttribute('name'),
      element.getAttribute && element.getAttribute('id')
    ].filter(Boolean).map(function(value) {
      return String(value).toLowerCase().replace(/[\s_-]+/g, '');
    });
  }
  function controlText(element: HTMLInputElement) {
    return [
      element.innerText,
      element.textContent,
      element.value,
      element.getAttribute && element.getAttribute('alt'),
      element.getAttribute && element.getAttribute('aria-label'),
      element.getAttribute && element.getAttribute('title')
    ].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim().toLowerCase();
  }

  collect(window);
  var hasLoginFields = false;
  var hasTwoFactorField = false;
  var hasAuthenticatedMarker = false;
  var knownUserIdentifiers = ['userid', 'loginid', 'username', 'jusername'];

  for (var d = 0; d < documents.length; d += 1) {
    var doc = documents[d];
    var inputs = Array.prototype.slice.call(doc.querySelectorAll('input'));
    var hasKnownUsername = false;
    var hasPassword = false;
    for (var i = 0; i < inputs.length; i += 1) {
      var input = inputs[i];
      if (!visible(input)) {
        continue;
      }
      var identifiers = normalizedIdentifiers(input);
      var type = (input.getAttribute('type') || '').toLowerCase();
      if (identifiers.indexOf('ninshocode') !== -1) {
        hasTwoFactorField = true;
      } else if (identifiers.some(function(identifier) {
        return knownUserIdentifiers.indexOf(identifier) !== -1;
      })) {
        hasKnownUsername = true;
      } else if (type === 'password') {
        hasPassword = true;
      }
    }
    if (hasKnownUsername && hasPassword) {
      hasLoginFields = true;
    }

    // The PC portal's ログアウト is a list (ul#logout) of an unlabeled image
    // and a span, not a link or button.
    var controls = Array.prototype.slice.call(
      doc.querySelectorAll('a, button, input, [role="button"], img, #logout')
    );
    for (var c = 0; c < controls.length; c += 1) {
      if (!visible(controls[c])) {
        continue;
      }
      if (/ログアウト|ログオフ|sign\s*out|log\s*out/.test(controlText(controls[c]))) {
        hasAuthenticatedMarker = true;
        break;
      }
    }
  }

  return JSON.stringify({
    hasLoginFields: hasLoginFields,
    hasTwoFactorField: hasTwoFactorField,
    hasAuthenticatedMarker: hasAuthenticatedMarker
  });
}

__mbgEntryResult = portalAuthStateProbe();
