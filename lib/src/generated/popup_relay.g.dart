// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/popup_relay/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoPopupRelayJs = r'''
"use strict";
(() => {
  // web_scripts/src/popup_relay/main.ts
  function popupRelay() {
    if (window.opener && window.parent === window) {
      var fromOpener = function(source) {
        var opener = window.opener;
        if (!opener || !source) return false;
        if (source === opener) return true;
        try {
          return source === opener.top;
        } catch (_) {
          return false;
        }
      };
      window.addEventListener("message", function(event) {
        var _a, _b, _c;
        if (fromOpener(event.source) && event.data instanceof ArrayBuffer) {
          window.postMessage(event.data, "*", [event.data]);
        } else if (fromOpener(event.source) && ((_a = event.data) == null ? void 0 : _a.type) === "mbg-preview-pdf" && event.data.data instanceof ArrayBuffer && event.data.data.byteLength > 0 && event.data.data.byteLength <= 512 * 1024 * 1024 && (event.data.initialPage === void 0 || Number.isInteger(event.data.initialPage) && event.data.initialPage >= 1 && event.data.initialPage <= 2e3)) {
          window.postMessage({
            type: "mbg-preview-pdf",
            data: event.data.data,
            initialPage: event.data.initialPage
          }, "*", [event.data.data]);
        } else if (fromOpener(event.source) && event.data && typeof event.data === "object" && event.data.type === "mbg-preview-title" && typeof event.data.name === "string") {
          window.postMessage({ type: "mbg-preview-title", name: event.data.name }, "*");
        } else if (fromOpener(event.source) && event.data && event.data.type === "mbg-preview-image" && event.data.data instanceof ArrayBuffer && event.data.data.byteLength > 0 && event.data.data.byteLength <= 64 * 1024 * 1024 && ["image/png", "image/jpeg", "image/webp"].includes(event.data.mime)) {
          window.postMessage({ type: "mbg-preview-image", data: event.data.data, mime: event.data.mime }, "*", [event.data.data]);
        } else if (fromOpener(event.source) && event.data && event.data.type === "mbg-preview-text" && typeof event.data.text === "string" && event.data.text.length <= 4e6 && (event.data.note === void 0 || typeof event.data.note === "string") && (event.data.note === void 0 || event.data.note.length <= 4e6)) {
          window.postMessage({ type: "mbg-preview-text", text: event.data.text, note: event.data.note }, "*");
        } else if (event.source === window && ((_b = event.data) == null ? void 0 : _b.type) === "mbg-preview-page" && Number.isInteger(event.data.page) && event.data.page >= 1 && event.data.page <= 2e3) {
          (_c = window.opener) == null ? void 0 : _c.postMessage({ type: "mbg-preview-page", page: event.data.page }, "*");
        } else if (event.source === window && typeof event.data === "string" && event.data.indexOf("mbg-preview-") === 0) {
          window.opener.postMessage(event.data, "*");
        }
      });
    }
  }
  popupRelay();
})();
''';
