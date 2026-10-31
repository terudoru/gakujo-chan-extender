// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/authenticated_download/poll.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoAuthenticatedDownloadPollJs(Map<String, Object?> config) =>
    _gakujoAuthenticatedDownloadPollJsPrefix +
    jsonEncode(config) +
    _gakujoAuthenticatedDownloadPollJsSuffix;

const String _gakujoAuthenticatedDownloadPollJsPrefix =
    r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/authenticated_download/poll.ts
  function authenticatedDownloadPoll() {
    const results = window.__MBG_AUTHENTICATED_DOWNLOAD_RESULTS;
    const entry = results && results[__mbgConfig.requestId];
    if (!entry) return "null";
    if (entry.state !== "pending") return JSON.stringify(entry);
    if (entry.chunks.length > 0) {
      const chunk = entry.chunks.shift();
      if (entry.resume) entry.resume();
      return JSON.stringify(chunk);
    }
    if (entry.completion) return JSON.stringify({ state: "done", payload: entry.completion });
    return JSON.stringify({ state: "pending" });
  }
  __mbgEntryResult = authenticatedDownloadPoll();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoAuthenticatedDownloadPollJsSuffix = r''')
''';
