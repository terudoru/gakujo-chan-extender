declare global {
  interface Window {
    __MBG_PAGE_WATCH_STATE?: { running: number; observers: MutationObserver[]; fallbacks?: { [ms: string]: { timer: number; runs: Array<(docs: Document[]) => boolean> } } };
  }
}

function collectPageDocuments(win: Window): Document[] {
  var docs: Document[] = [];
  function collect(current: Window) {
    try {
      var doc = current.document;
      if (!doc || docs.indexOf(doc) >= 0 || doc.defaultView === null) return;
      docs.push(doc);
      for (var i = 0; i < current.frames.length; i += 1) {
        try { collect(current.frames[i]); } catch (_) {}
      }
    } catch (_) {}
  }
  collect(win);
  return docs;
}

export function watchPage(win: Window, callback: () => void, options: { fallbackMs: number; legacyIntervalMs: number; onMutation?: (doc: Document) => void }): () => void {
  var Observer = (win as Window & typeof globalThis).MutationObserver;
  if (typeof Observer !== 'function') {
    var legacyTimer = win.setInterval(callback, options.legacyIntervalMs);
    return function() { win.clearInterval(legacyTimer); };
  }

  var entries: { doc: Document; observer: MutationObserver }[] = [];
  var state = win.__MBG_PAGE_WATCH_STATE || { running: 0, observers: [] };
  win.__MBG_PAGE_WATCH_STATE = state;
  var fallbacks = state.fallbacks || (state.fallbacks = {});
  var timer: number | undefined;
  var disposed = false;
  var running = false;

  function schedule() {
    if (disposed || running || state.running || timer !== undefined) return;
    timer = win.setTimeout(function() { timer = undefined; run(); }, 100);
  }

  function sync(docs: Document[]) {
    for (var i = entries.length - 1; i >= 0; i -= 1) {
      if (docs.indexOf(entries[i].doc) < 0) {
        remove(entries[i]);
        entries.splice(i, 1);
      }
    }
    docs.forEach(function(doc) {
      if (!doc.documentElement || entries.some(function(entry) { return entry.doc === doc; })) return;
      try {
        var observer = new Observer(function() {
          if (options.onMutation) options.onMutation(doc);
          schedule();
        });
        observer.observe(doc.documentElement, { childList: true, subtree: true, characterData: true, attributes: true });
        doc.addEventListener('load', schedule, true);
        doc.addEventListener('input', schedule, true);
        doc.addEventListener('change', schedule, true);
        entries.push({ doc: doc, observer: observer });
        state.observers.push(observer);
      } catch (_) {}
    });
  }

  function remove(entry: { doc: Document; observer: MutationObserver }) {
    entry.observer.disconnect();
    var index = state.observers.indexOf(entry.observer);
    if (index >= 0) state.observers.splice(index, 1);
    entry.doc.removeEventListener('load', schedule, true);
    entry.doc.removeEventListener('input', schedule, true);
    entry.doc.removeEventListener('change', schedule, true);
  }

  function run(docs?: Document[]): boolean {
    if (disposed) return false;
    if (timer !== undefined) { win.clearTimeout(timer); timer = undefined; }
    sync(docs || collectPageDocuments(win));
    running = true;
    state.running += 1;
    var changed = false;
    try { callback(); } catch (_) {} finally {
      state.observers.forEach(function(observer) {
        if (observer.takeRecords().length) changed = true;
      });
      state.running -= 1;
      running = false;
    }
    return changed;
  }

  sync(collectPageDocuments(win));
  var fallbackKey = String(options.fallbackMs);
  var fallback = fallbacks[fallbackKey];
  if (!fallback) {
    fallback = { timer: win.setInterval(function() {
      var docs: Document[] | undefined;
      fallback.runs.slice().forEach(function(registeredRun) {
        if (!docs) docs = collectPageDocuments(win);
        // A callback can insert or remove a frame before the next watcher runs.
        if (registeredRun(docs)) docs = undefined;
      });
    }, options.fallbackMs), runs: [] };
    fallbacks[fallbackKey] = fallback;
  }
  fallback.runs.push(run);
  return function() {
    if (disposed) return;
    disposed = true;
    if (timer !== undefined) win.clearTimeout(timer);
    var index = fallback.runs.indexOf(run);
    if (index >= 0) fallback.runs.splice(index, 1);
    if (!fallback.runs.length) {
      win.clearInterval(fallback.timer);
      delete fallbacks[fallbackKey];
    }
    entries.forEach(remove);
    entries = [];
    if (!state.observers.length && !Object.keys(fallbacks).length) delete win.__MBG_PAGE_WATCH_STATE;
  };
}
