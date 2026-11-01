// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/pdf_preview_ready/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoPdfPreviewReadyJs(Map<String, Object?> config) =>
    _gakujoPdfPreviewReadyJsPrefix +
    jsonEncode(config) +
    _gakujoPdfPreviewReadyJsSuffix;

const String _gakujoPdfPreviewReadyJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/pdf_preview_ready/main.ts
  window.__MBG_PDF_PREVIEW_URL = __mbgConfig.url;
  window.__MBG_PDF_PREVIEW_POPUP = __mbgConfig.popup;
  window.__MBG_UPLOAD_PREVIEW_LIBRARY_LOADED();
  __mbgEntryResult = "mbg-ready";
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoPdfPreviewReadyJsSuffix = r''')
''';
