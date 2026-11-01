import { retentionMs, isDraftKey, draftDocuments } from './storage_helpers.js';

function reportDraftList() {

  var entries = Object.create(null);
  var now = Date.now();
  draftDocuments().forEach(function(doc) {
    try {
      var store = doc.defaultView!.localStorage;
      for (var i = store.length - 1; i >= 0; i -= 1) {
        var key = store.key(i)!;
        if (!isDraftKey(key)) continue;
        var draft = null;
        try { draft = JSON.parse(store.getItem(key)!); } catch (_) {}
        if (!draft || typeof draft.savedAt !== 'number' ||
            !isFinite(draft.savedAt) || !draft.savedAt ||
            !Array.isArray(draft.fields) || now - draft.savedAt > retentionMs) {
          store.removeItem(key);
          continue;
        }
        var version = key.indexOf('mbg-report-draft:v2:') === 0 ? 2 : 1;
        var text = draft.fields.filter(function(item: { kind?: string; value?: string }) {
          return item && (version === 1 || item.kind === 'text') &&
            typeof item.value === 'string';
        }).map(function(item: { kind?: string; value?: string }) { return item.value; }).join('\n\n');
        var entry = {
          key: key,
          version: version,
          savedAt: draft.savedAt,
          heading: String((version === 1 ? draft.title : draft.heading) || draft.title || ''),
          preview: text.substring(0, 120),
          text: text
        };
        if (!entries[key] || entries[key].savedAt < entry.savedAt) entries[key] = entry;
      }
    } catch (e) {
      // Other same-origin documents may still have accessible storage.
    }
  });
  return JSON.stringify(Object.keys(entries).map(function(key) {
    return entries[key];
  }).sort(function(a, b) { return b.savedAt - a.savedAt; }));

}

__mbgEntryResult = reportDraftList();
