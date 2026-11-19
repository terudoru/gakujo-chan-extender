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
  function hostsDocument(frame: Element, doc: Document, view: Window) {
    if (frame.localName !== 'embed') {
      return 'contentDocument' in frame && frame.contentDocument === doc &&
        'contentWindow' in frame && frame.contentWindow === view;
    }
    // An HTML embed can have a child window without exposing either content accessor.
    var parentView = frame.ownerDocument.defaultView;
    return frame.isConnected && parentView !== null && parentView === view.parent &&
      Array.prototype.indexOf.call(parentView.frames, view) !== -1 &&
      (!('contentDocument' in frame) || frame.contentDocument === doc) &&
      (!('contentWindow' in frame) || frame.contentWindow === view);
  }
  function visible(element: HTMLElement) {
    if (!element) {
      return false;
    }
    try {
      var current: Element = element;
      while (true) {
        var doc = current.ownerDocument;
        var view = doc.defaultView;
        if (!view || view.document !== doc) return false;
        var style = view.getComputedStyle(current);
        if (style.display === 'none' || style.visibility === 'hidden' ||
            style.opacity === '0' || !current.getClientRects().length) return false;
        // Child controls can have layout even when their embedding frame is hidden.
        if (current !== element && (style.visibility === 'collapse' ||
            current.checkVisibility?.({checkOpacity: true}) === false)) return false;
        if (doc === document) return view === window;
        var frame = view.frameElement;
        if (!frame || !hostsDocument(frame, doc, view)) return false;
        current = frame;
      }
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
    var passwordCount = 0;
    var hasPasswordChangeField = false;
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
        passwordCount += 1;
        // Mirror login_autofill_assist's password-change exclusions.
        var identifier = identifiers.join('');
        if (/(?:new|confirm|confirmation|old|current)(?:password|passwd|pwd)|(?:password|passwd|pwd)(?:new|confirm|confirmation|old|current)/.test(identifier) ||
            (input.getAttribute('autocomplete') || '').toLowerCase() === 'new-password') {
          hasPasswordChangeField = true;
        }
      }
    }
    if (hasKnownUsername && passwordCount === 1 && !hasPasswordChangeField) {
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
