// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/upload_library_ack/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoUploadLibraryAckJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/upload_library_ack/main.ts
  function uploadLibraryAck(kind, body) {
    const page = window;
    const keys = ["__MBG_QPDF_WORKER_URL", "__MBG_QPDF_MODULE_URL", "__MBG_QPDF_WASM_URL", "__MBG_PDF_WORKER_URL"];
    const values = ["pdfjsLib", "pdfjsViewer", "__MBG_PDF_VIEWER_CSS", "__MBG_PDF_CMAPS", "__MBG_PDF_STANDARD_FONTS"];
    const before = keys.map((key) => page[key]);
    const valuesBefore = values.map((key) => page[key]);
    const marker = "__MBG_UPLOAD_LIBRARY_READY_" + kind;
    const markerBefore = page[marker];
    const callback = kind === "preview" ? "__MBG_UPLOAD_PREVIEW_LIBRARY_LOADED" : kind === "preview-office" ? "__MBG_UPLOAD_PREVIEW_OFFICE_LIBRARY_LOADED" : "__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED";
    function ready() {
      switch (kind) {
        case "pdf":
          return !!(window.__MBG_QPDF_WORKER_URL && window.__MBG_QPDF_MODULE_URL && window.__MBG_QPDF_WASM_URL);
        case "preview":
          return !!(window.pdfjsLib && window.pdfjsViewer && window.__MBG_PDF_WORKER_URL && window.__MBG_PDF_VIEWER_CSS && window.__MBG_PDF_CMAPS && window.__MBG_PDF_STANDARD_FONTS);
        case "preview-office":
        case "office":
          return !!window.JSZip;
        default:
          return false;
      }
    }
    function notify() {
      if (page[callback]) page[callback].call(window, kind);
    }
    try {
      if (page[marker] && ready()) {
        notify();
        return "mbg-ready";
      }
      body();
      if (!ready()) throw new Error("library unavailable");
      page[marker] = true;
      if (kind === "preview-office") notify();
      return "mbg-ready";
    } catch (_) {
      if (markerBefore === void 0) delete page[marker];
      else page[marker] = markerBefore;
      keys.forEach((key, index) => {
        try {
          if (page[key] && page[key] !== before[index]) URL.revokeObjectURL(page[key]);
          if (before[index] === void 0) delete page[key];
          else page[key] = before[index];
        } catch (_2) {
        }
      });
      values.forEach((key, index) => {
        if (valuesBefore[index] === void 0) delete page[key];
        else page[key] = valuesBefore[index];
      });
      try {
        notify();
      } catch (_2) {
      }
      return "mbg-failed";
    }
  }
  __mbgEntryResult = uploadLibraryAck;
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
