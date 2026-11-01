import { draftDocuments, isRetainedDraft } from './storage_helpers.js';

function reportDraftExportAll() {
  var entries = Object.create(null);
  var now = Date.now();
  draftDocuments().forEach(function(doc) {
    var pending = doc.defaultView!.__MBG_REPORT_DRAFT_PENDING_CONTEXT;
    var identity = doc.__MBG_REPORT_DRAFT_IDENTITY;
    if ((pending || (identity && identity.fields.some(function(field) {
      return field.__MBG_REPORT_DRAFT_DIRTY;
    }))) && (!doc.__MBG_REPORT_DRAFT_FLUSH || !doc.__MBG_REPORT_DRAFT_FLUSH())) {
      throw new Error('Pending draft could not be saved');
    }
    var store = doc.defaultView!.localStorage;
    for (var i = 0; i < store.length; i += 1) {
      var key = store.key(i)!;
      if (!/^mbg-report-draft:v2:/.test(key)) continue;
      var draft;
      try { draft = JSON.parse(store.getItem(key)!); } catch (_) { continue; }
      if (!isRetainedDraft(draft, now)) continue;
      if (!entries[key] || entries[key].savedAt < draft.savedAt) entries[key] = draft;
    }
  });
  return JSON.stringify(entries);
}

__mbgEntryResult = reportDraftExportAll();
