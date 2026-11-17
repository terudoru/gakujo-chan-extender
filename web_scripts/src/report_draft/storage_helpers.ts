export var retentionMs = 14 * 24 * 60 * 60 * 1000;
export function isRetainedDraft(draft: any, now: number) {
    return !!draft && typeof draft === 'object' && !Array.isArray(draft) &&
      typeof draft.savedAt === 'number' && isFinite(draft.savedAt) &&
      !!draft.savedAt && Array.isArray(draft.fields) &&
      now - draft.savedAt <= retentionMs;
  }
export function isDraftKey(key: unknown) {
    return typeof key === 'string' && /^mbg-report-draft:v[12]:/.test(key);
  }
export var migrationPrefix = 'mbg-report-draft:migration:';
export function migrationSources(store: Storage, key: string): string[] {
    var raw = store.getItem(migrationPrefix + key);
    if (!raw) return [];
    var sources = JSON.parse(raw);
    return Array.isArray(sources) ? sources.filter(function(source) {
      return isDraftKey(source) && source !== key;
    }) : [];
  }
export function rememberMigration(store: Storage | null, key: string, source: string) {
    if (!store) return false;
    try {
      var sources = migrationSources(store, key);
      if (sources.indexOf(source) < 0) sources.push(source);
      store.setItem(migrationPrefix + key, JSON.stringify(sources));
      return true;
    } catch (_) { return false; }
  }
export function cleanupMigrationSources(store: Storage, key: string) {
    migrationSources(store, key).forEach(function(source) { store.removeItem(source); });
    // Keep the link until every source is gone, so a failed removal is retried.
    store.removeItem(migrationPrefix + key);
  }
export function draftDocuments() {
    // Same frames the draft editor binds to (document plus every accessible
    // direct iframe/frame), so flushing and import refusal see every form.
    var docs = [document];
    var frames: ArrayLike<HTMLIFrameElement> = [];
    if (typeof document.querySelectorAll === 'function') {
      frames = document.querySelectorAll<HTMLIFrameElement>('iframe,frame');
    } else if (typeof document.querySelector === 'function') {
      var main = document.querySelector<HTMLIFrameElement>('iframe#main-frame-if');
      if (main) frames = [main];
    }
    for (var i = 0; i < frames.length; i += 1) {
      try {
        if (frames[i].contentWindow && frames[i].contentWindow!.document &&
            docs.indexOf(frames[i].contentWindow!.document) < 0) {
          docs.push(frames[i].contentWindow!.document);
        }
      } catch (e) {
        // Cross-origin frames cannot be inspected.
      }
    }
    return docs;
  }
