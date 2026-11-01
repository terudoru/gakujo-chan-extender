// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/report_draft/export_all.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoReportDraftExportAllJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/report_draft/storage_helpers.ts
  var retentionMs = 14 * 24 * 60 * 60 * 1e3;
  function isRetainedDraft(draft, now) {
    return !!draft && typeof draft === "object" && !Array.isArray(draft) && typeof draft.savedAt === "number" && isFinite(draft.savedAt) && !!draft.savedAt && Array.isArray(draft.fields) && now - draft.savedAt <= retentionMs;
  }
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

  // web_scripts/src/report_draft/export_all.ts
  function reportDraftExportAll() {
    var entries = /* @__PURE__ */ Object.create(null);
    var now = Date.now();
    draftDocuments().forEach(function(doc) {
      var pending = doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
      var identity = doc.__MBG_REPORT_DRAFT_IDENTITY;
      if ((pending || identity && identity.fields.some(function(field) {
        return field.__MBG_REPORT_DRAFT_DIRTY;
      })) && (!doc.__MBG_REPORT_DRAFT_FLUSH || !doc.__MBG_REPORT_DRAFT_FLUSH())) {
        throw new Error("Pending draft could not be saved");
      }
      var store = doc.defaultView.localStorage;
      for (var i = 0; i < store.length; i += 1) {
        var key = store.key(i);
        if (!/^mbg-report-draft:v2:/.test(key)) continue;
        var draft;
        try {
          draft = JSON.parse(store.getItem(key));
        } catch (_) {
          continue;
        }
        if (!isRetainedDraft(draft, now)) continue;
        if (!entries[key] || entries[key].savedAt < draft.savedAt) entries[key] = draft;
      }
    });
    return JSON.stringify(entries);
  }
  __mbgEntryResult = reportDraftExportAll();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
