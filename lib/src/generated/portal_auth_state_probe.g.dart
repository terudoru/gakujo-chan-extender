// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/portal_auth_state_probe/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoPortalAuthStateProbeJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/portal_auth_state_probe/main.ts
  function portalAuthStateProbe() {
    var documents = [];
    function collect(win) {
      try {
        if (!win || !win.document || documents.indexOf(win.document) !== -1) {
          return;
        }
        documents.push(win.document);
        for (var i2 = 0; i2 < win.frames.length; i2 += 1) {
          collect(win.frames[i2]);
        }
      } catch (_) {
      }
    }
    function hostsDocument(frame, doc2, view) {
      if (frame.localName !== "embed") {
        return "contentDocument" in frame && frame.contentDocument === doc2 && "contentWindow" in frame && frame.contentWindow === view;
      }
      var parentView = frame.ownerDocument.defaultView;
      return frame.isConnected && parentView !== null && parentView === view.parent && Array.prototype.indexOf.call(parentView.frames, view) !== -1 && (!("contentDocument" in frame) || frame.contentDocument === doc2) && (!("contentWindow" in frame) || frame.contentWindow === view);
    }
    function visible(element) {
      var _a;
      if (!element) {
        return false;
      }
      try {
        var current = element;
        while (true) {
          var doc2 = current.ownerDocument;
          var view = doc2.defaultView;
          if (!view || view.document !== doc2) return false;
          var style = view.getComputedStyle(current);
          if (style.display === "none" || style.visibility === "hidden" || style.opacity === "0" || !current.getClientRects().length) return false;
          if (current !== element && (style.visibility === "collapse" || ((_a = current.checkVisibility) == null ? void 0 : _a.call(current, { checkOpacity: true })) === false)) return false;
          if (doc2 === document) return view === window;
          var frame = view.frameElement;
          if (!frame || !hostsDocument(frame, doc2, view)) return false;
          current = frame;
        }
      } catch (_) {
        return false;
      }
    }
    function normalizedIdentifiers(element) {
      return [
        element.getAttribute && element.getAttribute("name"),
        element.getAttribute && element.getAttribute("id")
      ].filter(Boolean).map(function(value) {
        return String(value).toLowerCase().replace(/[\s_-]+/g, "");
      });
    }
    function controlText(element) {
      return [
        element.innerText,
        element.textContent,
        element.value,
        element.getAttribute && element.getAttribute("alt"),
        element.getAttribute && element.getAttribute("aria-label"),
        element.getAttribute && element.getAttribute("title")
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim().toLowerCase();
    }
    collect(window);
    var hasLoginFields = false;
    var hasTwoFactorField = false;
    var hasAuthenticatedMarker = false;
    var knownUserIdentifiers = ["userid", "loginid", "username", "jusername"];
    for (var d = 0; d < documents.length; d += 1) {
      var doc = documents[d];
      var inputs = Array.prototype.slice.call(doc.querySelectorAll("input"));
      var hasKnownUsername = false;
      var passwordCount = 0;
      var hasPasswordChangeField = false;
      for (var i = 0; i < inputs.length; i += 1) {
        var input = inputs[i];
        if (!visible(input)) {
          continue;
        }
        var identifiers = normalizedIdentifiers(input);
        var type = (input.getAttribute("type") || "").toLowerCase();
        if (identifiers.indexOf("ninshocode") !== -1) {
          hasTwoFactorField = true;
        } else if (identifiers.some(function(identifier2) {
          return knownUserIdentifiers.indexOf(identifier2) !== -1;
        })) {
          hasKnownUsername = true;
        } else if (type === "password") {
          passwordCount += 1;
          var identifier = identifiers.join("");
          if (/(?:new|confirm|confirmation|old|current)(?:password|passwd|pwd)|(?:password|passwd|pwd)(?:new|confirm|confirmation|old|current)/.test(identifier) || (input.getAttribute("autocomplete") || "").toLowerCase() === "new-password") {
            hasPasswordChangeField = true;
          }
        }
      }
      if (hasKnownUsername && passwordCount === 1 && !hasPasswordChangeField) {
        hasLoginFields = true;
      }
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
      hasLoginFields,
      hasTwoFactorField,
      hasAuthenticatedMarker
    });
  }
  __mbgEntryResult = portalAuthStateProbe();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
