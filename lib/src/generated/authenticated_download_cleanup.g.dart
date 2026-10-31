// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/authenticated_download/cleanup.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoAuthenticatedDownloadCleanupJs(Map<String, Object?> config) =>
    _gakujoAuthenticatedDownloadCleanupJsPrefix +
    jsonEncode(config) +
    _gakujoAuthenticatedDownloadCleanupJsSuffix;

const String _gakujoAuthenticatedDownloadCleanupJsPrefix =
    r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/authenticated_download/cleanup.ts
  function authenticatedDownloadCleanup() {
    const results = window.__MBG_AUTHENTICATED_DOWNLOAD_RESULTS;
    if (results) {
      const requestId = __mbgConfig.requestId;
      const entry = results[requestId];
      delete results[requestId];
      if (entry && typeof entry.cancel === "function") {
        entry.cancel();
      }
    }
    return true;
  }
  __mbgEntryResult = authenticatedDownloadCleanup();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoAuthenticatedDownloadCleanupJsSuffix = r''')
''';
