import { draftDocuments, migrationPrefix } from './storage_helpers.js';

function reportDraftClearSavedBefore() {
  draftDocuments().forEach(function(doc) {
    var store = doc.defaultView!.localStorage;
    for (var i = store.length - 1; i >= 0; i -= 1) {
      var key = store.key(i)!;
      if (!/^mbg-report-draft:v[12]:/.test(key)) continue;
      store.removeItem(key);
    }
    for (var i = store.length - 1; i >= 0; i -= 1) {
      var key = store.key(i)!;
      if (key.indexOf(migrationPrefix) === 0) store.removeItem(key);
    }
  });
  return true;
}

__mbgEntryResult = reportDraftClearSavedBefore();
