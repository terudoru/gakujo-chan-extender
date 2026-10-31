// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/report_draft/list.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoReportDraftListJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/report_draft/storage_helpers.ts
  var retentionMs = 14 * 24 * 60 * 60 * 1e3;
  function isDraftKey(key) {
    return typeof key === "string" && /^mbg-report-draft:v[12]:/.test(key);
  }
  function draftDocuments() {
    var docs = [document];
    try {
      var frame = document.querySelector("iframe#main-frame-if");
      if (frame && frame.contentWindow && frame.contentWindow.document) {
        docs.push(frame.contentWindow.document);
      }
    } catch (e) {
    }
    return docs;
  }

  // web_scripts/src/report_draft/list.ts
  function reportDraftList() {
    var entries = /* @__PURE__ */ Object.create(null);
    var now = Date.now();
    draftDocuments().forEach(function(doc) {
      try {
        var store = doc.defaultView.localStorage;
        for (var i = store.length - 1; i >= 0; i -= 1) {
          var key = store.key(i);
          if (!isDraftKey(key)) continue;
          var draft = null;
          try {
            draft = JSON.parse(store.getItem(key));
          } catch (_) {
          }
          if (!draft || typeof draft.savedAt !== "number" || !isFinite(draft.savedAt) || !draft.savedAt || !Array.isArray(draft.fields) || now - draft.savedAt > retentionMs) {
            store.removeItem(key);
            continue;
          }
          var version = key.indexOf("mbg-report-draft:v2:") === 0 ? 2 : 1;
          var text = draft.fields.filter(function(item) {
            return item && (version === 1 || item.kind === "text") && typeof item.value === "string";
          }).map(function(item) {
            return item.value;
          }).join("\n\n");
          var entry = {
            key,
            version,
            savedAt: draft.savedAt,
            heading: String((version === 1 ? draft.title : draft.heading) || draft.title || ""),
            preview: text.substring(0, 120),
            text
          };
          if (!entries[key] || entries[key].savedAt < entry.savedAt) entries[key] = entry;
        }
      } catch (e) {
      }
    });
    return JSON.stringify(Object.keys(entries).map(function(key) {
      return entries[key];
    }).sort(function(a, b) {
      return b.savedAt - a.savedAt;
    }));
  }
  __mbgEntryResult = reportDraftList();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
