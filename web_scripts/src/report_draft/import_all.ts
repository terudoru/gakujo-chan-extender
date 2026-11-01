import { draftDocuments, isRetainedDraft } from './storage_helpers.js';

declare const __mbgConfig: { drafts: string; basedOn: string };

function reportDraftImportAll() {
  var drafts = JSON.parse(__mbgConfig.drafts);
  var basedOn = JSON.parse(__mbgConfig.basedOn);
  function canonical(value: any): any {
    if (Array.isArray(value)) return value.map(canonical);
    if (value && typeof value === 'object') {
      var result: any = {};
      Object.keys(value).sort().forEach(function(key) { result[key] = canonical(value[key]); });
      return result;
    }
    return value;
  }
  var matched = true;
  var now = Date.now();
  var writes: {store: Storage; key: string; before: string | null; value: string | null}[] = [];
  draftDocuments().forEach(function(doc) {
    var store = doc.defaultView!.localStorage;
    var keys = Object.keys(basedOn).concat(Object.keys(drafts));
    for (var i = 0; i < store.length; i += 1) keys.push(store.key(i)!);
    Array.from(new Set(keys)).forEach(function(key) {
      if (!/^mbg-report-draft:v2:/.test(key)) return;
      var raw = store.getItem(key);
      var current;
      try { current = raw === null ? undefined : JSON.parse(raw); }
      catch (_) { current = undefined; }
      if (!isRetainedDraft(current, now)) current = undefined;
      var expected = Object.prototype.hasOwnProperty.call(basedOn, key) ? basedOn[key] : undefined;
      if (JSON.stringify(canonical(current)) !== JSON.stringify(canonical(expected))) {
        matched = false;
        return;
      }
      var pending = doc.defaultView!.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
      var identity = doc.__MBG_REPORT_DRAFT_IDENTITY;
      var touched = pending && pending.key === key || identity && identity.key === key &&
        identity.fields.some(function(field) { return field.__MBG_REPORT_DRAFT_TOUCHED || field.__MBG_REPORT_DRAFT_DIRTY; });
      var incoming = Object.prototype.hasOwnProperty.call(drafts, key) ? drafts[key] : undefined;
      if (touched && JSON.stringify(canonical(current)) !== JSON.stringify(canonical(incoming))) {
        matched = false;
        return;
      }
      if (!Object.prototype.hasOwnProperty.call(drafts, key)) {
        if (current !== undefined) writes.push({store: store, key: key, before: raw, value: null});
        return;
      }
      var draft = drafts[key];
      if (!draft || typeof draft !== 'object' || Array.isArray(draft) ||
          typeof draft.savedAt !== 'number' || !isFinite(draft.savedAt) ||
          !Array.isArray(draft.fields)) return;
      writes.push({store: store, key: key, before: raw, value: JSON.stringify(draft)});
    });
  });
  if (!matched) return false;
  var written: typeof writes = [];
  try {
    writes.forEach(function(write) {
      written.push(write);
      if (write.value === null) write.store.removeItem(write.key);
      else write.store.setItem(write.key, write.value);
    });
  } catch (_) {
    for (var i = written.length - 1; i >= 0; i -= 1) {
      try {
        var write = written[i];
        if (write.before === null) write.store.removeItem(write.key);
        else write.store.setItem(write.key, write.before);
      } catch (_) { throw new Error('Draft rollback failed'); }
    }
    return false;
  }
  return true;
}

__mbgEntryResult = reportDraftImportAll();
