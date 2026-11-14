// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/history_marker/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoHistoryMarkerJs(Map<String, Object?> config) =>
    _gakujoHistoryMarkerJsPrefix +
    jsonEncode(config) +
    _gakujoHistoryMarkerJsSuffix;

const String _gakujoHistoryMarkerJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/history_marker/marker.ts
  var selector = "button[data-mbg-submitted-preview]";
  var tokenPattern = /^[A-Za-z0-9_-]{8,64}$/;
  var kinds = ["starred", "favorites", "cachedReports"];
  function historyMarker(win, config) {
    var _a;
    function documents(onVisit) {
      const docs = [];
      let visited = 0;
      function visit(current, path) {
        if (visited++ >= 64) return;
        try {
          const doc = current.document;
          if (!doc || docs.indexOf(doc) >= 0) return;
          docs.push(doc);
          onVisit == null ? void 0 : onVisit(doc, path);
          for (let i = 0; i < current.frames.length && visited < 64; i++) {
            try {
              visit(current.frames[i], path ? path + "/" + i : String(i));
            } catch (_) {
            }
          }
        } catch (_) {
        }
      }
      visit(win, "");
      return docs;
    }
    function frames() {
      const values = [];
      documents((doc, path) => {
        if (!path) return;
        const url = doc.location.href;
        if (/^https?:/.test(url)) values.push({ path, url });
      });
      return values;
    }
    function marker(doc) {
      var _a2, _b;
      try {
        const value = (_b = (_a2 = doc.defaultView) == null ? void 0 : _a2.history.state) == null ? void 0 : _b.__mbgPreview;
        return value && typeof value.token === "string" && tokenPattern.test(value.token) && Number.isInteger(value.index) && value.index >= 0 && typeof value.name === "string" ? value : null;
      } catch (_) {
        return null;
      }
    }
    function name(button) {
      const source = button.previousElementSibling;
      const tag = source == null ? void 0 : source.tagName.toLowerCase();
      if (tag === "a" || tag === "button") return (source.textContent || "").trim();
      return tag === "input" ? source.value.trim() : null;
    }
    if (config.action === "stamp-dialog") {
      if (!config.kind || kinds.indexOf(config.kind) < 0) return false;
      win.history.replaceState(Object.assign({}, win.history.state, {
        __mbgReturnDialog: { kind: config.kind, frames: frames() }
      }), "");
      return "ok";
    }
    if (config.action === "read") {
      const saved = (_a = win.history.state) == null ? void 0 : _a.__mbgReturnDialog;
      const kind = typeof saved === "string" ? saved : saved == null ? void 0 : saved.kind;
      const unchanged = typeof saved === "string" || Array.isArray(saved == null ? void 0 : saved.frames) && saved.frames.every((frame) => {
        try {
          let current = win;
          for (const index of frame.path.split("/")) current = current.frames[Number(index)];
          return current.document.location.href === frame.url;
        } catch (_) {
          return false;
        }
      });
      const preview = documents().map(marker).find((value) => value !== null);
      const active = win.__MBG_ACTIVE_UPLOAD_PREVIEW;
      const activeToken = active == null ? void 0 : active.__mbgToken;
      return JSON.stringify({
        dialog: unchanged && kinds.indexOf(kind) >= 0 ? kind : null,
        preview: (preview == null ? void 0 : preview.token) || null,
        active: active ? active.visible ? "visible" : "hidden" : "none",
        activeToken: typeof activeToken === "string" && tokenPattern.test(activeToken) ? activeToken : null
      });
    }
    if (config.action === "install-preview-tracker") {
      let attach2 = function() {
        documents().forEach((doc) => {
          if (installed.has(doc)) return;
          installed.add(doc);
          doc.addEventListener("load", attach2, true);
          doc.addEventListener("click", (event) => {
            var _a2, _b;
            const target = event.target;
            const button = (_a2 = target == null ? void 0 : target.closest) == null ? void 0 : _a2.call(target, selector);
            if (!button || !doc.defaultView) return;
            const buttons = Array.from(doc.querySelectorAll(selector));
            const index = buttons.indexOf(button);
            const sourceName = name(button);
            if (index < 0 || sourceName === null) return;
            const random = new Uint8Array(16);
            win.crypto.getRandomValues(random);
            const token = Array.from(random, (byte) => byte.toString(16).padStart(2, "0")).join("");
            doc.defaultView.history.replaceState(Object.assign({}, doc.defaultView.history.state, {
              __mbgPreview: { token, index, name: sourceName }
            }), "");
            win.setTimeout(() => {
              const active = win.__MBG_ACTIVE_UPLOAD_PREVIEW;
              if (active) active.__mbgToken = token;
            }, 0);
            try {
              (_b = win.MbgPreviewNavigation) == null ? void 0 : _b.postMessage("token:" + token);
            } catch (_) {
            }
          }, true);
        });
      };
      var attach = attach2;
      if (win.__MBG_HISTORY_TRACKER_INSTALLED) return "ok";
      win.__MBG_HISTORY_TRACKER_INSTALLED = true;
      const installed = /* @__PURE__ */ new WeakSet();
      attach2();
      win.setInterval(attach2, 2e3);
      return "ok";
    }
    if (config.action === "reopen-preview") {
      if (!config.token || !tokenPattern.test(config.token)) return false;
      for (const doc of documents()) {
        const saved = marker(doc);
        if (!saved || saved.token !== config.token) continue;
        const buttons = Array.from(doc.querySelectorAll(selector));
        const indexed = buttons[saved.index];
        const button = indexed && name(indexed) === saved.name ? indexed : buttons.find((item) => name(item) === saved.name);
        if (!button) return false;
        button.click();
        return true;
      }
      return false;
    }
    return false;
  }

  // web_scripts/src/history_marker/main.ts
  __mbgEntryResult = historyMarker(window, __mbgConfig);
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoHistoryMarkerJsSuffix = r''')
''';
