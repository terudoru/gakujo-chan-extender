// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/report_draft/import_all.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoReportDraftImportAllJs(Map<String, Object?> config) =>
    _gakujoReportDraftImportAllJsPrefix +
    jsonEncode(config) +
    _gakujoReportDraftImportAllJsSuffix;

const String _gakujoReportDraftImportAllJsPrefix = r'''(function(__mbgConfig) {
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

  // web_scripts/src/report_draft/import_all.ts
  function reportDraftImportAll() {
    var drafts = JSON.parse(__mbgConfig.drafts);
    var basedOn = JSON.parse(__mbgConfig.basedOn);
    function canonical(value) {
      if (Array.isArray(value)) return value.map(canonical);
      if (value && typeof value === "object") {
        var result = {};
        Object.keys(value).sort().forEach(function(key) {
          result[key] = canonical(value[key]);
        });
        return result;
      }
      return value;
    }
    var matched = true;
    var now = Date.now();
    var writes = [];
    draftDocuments().forEach(function(doc) {
      var store = doc.defaultView.localStorage;
      var keys = Object.keys(basedOn).concat(Object.keys(drafts));
      for (var i2 = 0; i2 < store.length; i2 += 1) keys.push(store.key(i2));
      Array.from(new Set(keys)).forEach(function(key) {
        if (!/^mbg-report-draft:v2:/.test(key)) return;
        var raw = store.getItem(key);
        var current;
        try {
          current = raw === null ? void 0 : JSON.parse(raw);
        } catch (_) {
          current = void 0;
        }
        if (!isRetainedDraft(current, now)) current = void 0;
        var expected = Object.prototype.hasOwnProperty.call(basedOn, key) ? basedOn[key] : void 0;
        if (JSON.stringify(canonical(current)) !== JSON.stringify(canonical(expected))) {
          matched = false;
          return;
        }
        var pending = doc.defaultView.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
        var identity = doc.__MBG_REPORT_DRAFT_IDENTITY;
        var touched = pending && pending.key === key || identity && identity.key === key && identity.fields.some(function(field) {
          return field.__MBG_REPORT_DRAFT_TOUCHED || field.__MBG_REPORT_DRAFT_DIRTY;
        });
        var incoming = Object.prototype.hasOwnProperty.call(drafts, key) ? drafts[key] : void 0;
        if (touched && JSON.stringify(canonical(current)) !== JSON.stringify(canonical(incoming))) {
          matched = false;
          return;
        }
        if (!Object.prototype.hasOwnProperty.call(drafts, key)) {
          if (current !== void 0) writes.push({ store, key, before: raw, value: null });
          return;
        }
        var draft = drafts[key];
        if (!draft || typeof draft !== "object" || Array.isArray(draft) || typeof draft.savedAt !== "number" || !isFinite(draft.savedAt) || !Array.isArray(draft.fields)) return;
        writes.push({ store, key, before: raw, value: JSON.stringify(draft) });
      });
    });
    if (!matched) return false;
    var written = [];
    try {
      writes.forEach(function(write2) {
        written.push(write2);
        if (write2.value === null) write2.store.removeItem(write2.key);
        else write2.store.setItem(write2.key, write2.value);
      });
    } catch (_) {
      for (var i = written.length - 1; i >= 0; i -= 1) {
        try {
          var write = written[i];
          if (write.before === null) write.store.removeItem(write.key);
          else write.store.setItem(write.key, write.before);
        } catch (_2) {
          throw new Error("Draft rollback failed");
        }
      }
      return false;
    }
    return true;
  }
  __mbgEntryResult = reportDraftImportAll();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoReportDraftImportAllJsSuffix = r''')
''';
