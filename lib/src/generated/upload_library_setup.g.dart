// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/upload_library_setup/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoUploadLibrarySetupJs(Map<String, Object?> config) =>
    _gakujoUploadLibrarySetupJsPrefix +
    jsonEncode(config) +
    _gakujoUploadLibrarySetupJsSuffix;

const String _gakujoUploadLibrarySetupJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/upload_library_setup/main.ts
  function uploadLibrarySetup() {
    const { kind, sources } = __mbgConfig;
    if (kind === "pdf" && sources.length === 3) {
      window.__MBG_QPDF_WORKER_URL = URL.createObjectURL(new Blob([sources[0]], { type: "text/javascript" }));
      window.__MBG_QPDF_MODULE_URL = URL.createObjectURL(new Blob([sources[1]], { type: "text/javascript" }));
      const raw = atob(sources[2]);
      const bytes = new Uint8Array(raw.length);
      for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
      window.__MBG_QPDF_WASM_URL = URL.createObjectURL(new Blob([bytes], { type: "application/wasm" }));
    } else if (kind === "preview" && sources.length > 0) {
      window.__MBG_PDF_WORKER_URL = URL.createObjectURL(new Blob([sources[0]], { type: "text/javascript" }));
      if (sources.length >= 6) {
        window.__MBG_PDF_VIEWER_CSS = sources[3];
        window.__MBG_PDF_CMAPS = sources[4];
        window.__MBG_PDF_STANDARD_FONTS = sources[5];
      }
    }
  }
  uploadLibrarySetup();
})();
})(''';
const String _gakujoUploadLibrarySetupJsSuffix = r''');
''';
