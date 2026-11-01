// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/report_draft/clear_saved_before.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoReportDraftClearSavedBeforeJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/report_draft/storage_helpers.ts
  var retentionMs = 14 * 24 * 60 * 60 * 1e3;
  function draftDocuments() {
    var docs = [document];
    var frames = [];
    if (typeof document.querySelectorAll === "function") {
      frames = document.querySelectorAll("iframe,frame");
    } else if (typeof document.querySelector === "function") {
      var main = document.querySelector("iframe#main-frame-if");
      if (main) frames = [main];
    }
    for (var i = 0; i < frames.length; i += 1) {
      try {
        if (frames[i].contentWindow && frames[i].contentWindow.document && docs.indexOf(frames[i].contentWindow.document) < 0) {
          docs.push(frames[i].contentWindow.document);
        }
      } catch (e) {
      }
    }
    return docs;
  }

  // web_scripts/src/report_draft/clear_saved_before.ts
  function reportDraftClearSavedBefore() {
    draftDocuments().forEach(function(doc) {
      var store = doc.defaultView.localStorage;
      for (var i = store.length - 1; i >= 0; i -= 1) {
        var key = store.key(i);
        if (!/^mbg-report-draft:v[12]:/.test(key)) continue;
        store.removeItem(key);
      }
    });
    return true;
  }
  __mbgEntryResult = reportDraftClearSavedBefore();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
