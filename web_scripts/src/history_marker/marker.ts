const selector = 'button[data-mbg-submitted-preview]';
const tokenPattern = /^[A-Za-z0-9_-]{8,64}$/;
const kinds = ['starred', 'favorites', 'cachedReports'];
type Marker = { token: string; index: number; name: string };
type Config = { action: string; kind?: string; token?: string };

export function historyMarker(win: Window, config: Config): string | boolean {
  function documents(): Document[] {
    const docs: Document[] = [];
    let visited = 0;
    function visit(current: Window): void {
      if (visited++ >= 64) return;
      try {
        const doc = current.document;
        if (!doc || docs.indexOf(doc) >= 0) return;
        docs.push(doc);
        for (let i = 0; i < current.frames.length && visited < 64; i++) {
          try { visit(current.frames[i]); } catch (_) { /* cross-origin */ }
        }
      } catch (_) { /* cross-origin */ }
    }
    visit(win);
    return docs;
  }
  function marker(doc: Document): Marker | null {
    try {
      const value = doc.defaultView?.history.state?.__mbgPreview;
      return value && typeof value.token === 'string' && tokenPattern.test(value.token) &&
        Number.isInteger(value.index) && value.index >= 0 && typeof value.name === 'string' ? value : null;
    } catch (_) { return null; }
  }
  function name(button: Element): string | null {
    const anchor = button.previousElementSibling;
    return anchor?.tagName.toLowerCase() === 'a' ? (anchor.textContent || '').trim() : null;
  }
  if (config.action === 'stamp-dialog') {
    if (!config.kind || kinds.indexOf(config.kind) < 0) return false;
    win.history.replaceState(Object.assign({}, win.history.state, { __mbgReturnDialog: config.kind }), '');
    return 'ok';
  }
  if (config.action === 'read') {
    const kind = win.history.state?.__mbgReturnDialog;
    const preview = documents().map(marker).find(value => value !== null);
    const active = win.__MBG_ACTIVE_UPLOAD_PREVIEW;
    const activeToken = active?.__mbgToken;
    return JSON.stringify({
      dialog: kinds.indexOf(kind) >= 0 ? kind : null,
      preview: preview?.token || null,
      active: active ? (active.visible ? 'visible' : 'hidden') : 'none',
      activeToken: typeof activeToken === 'string' && tokenPattern.test(activeToken) ? activeToken : null,
    });
  }
  if (config.action === 'install-preview-tracker') {
    if (win.__MBG_HISTORY_TRACKER_INSTALLED) return 'ok';
    win.__MBG_HISTORY_TRACKER_INSTALLED = true;
    const installed = new WeakSet<Document>();
    function attach(): void {
      documents().forEach(doc => {
        if (installed.has(doc)) return;
        installed.add(doc);
        doc.addEventListener('load', attach, true);
        doc.addEventListener('click', event => {
          const target = event.target as Element | null;
          const button = target?.closest?.(selector);
          if (!button || !doc.defaultView) return;
          const buttons = Array.from(doc.querySelectorAll(selector));
          const index = buttons.indexOf(button);
          if (index < 0 || button.previousElementSibling?.tagName.toLowerCase() !== 'a') return;
          const random = new Uint8Array(16);
          win.crypto.getRandomValues(random);
          const token = Array.from(random, byte => byte.toString(16).padStart(2, '0')).join('');
          doc.defaultView.history.replaceState(Object.assign({}, doc.defaultView.history.state, {
            __mbgPreview: { token, index, name: name(button)! },
          }), '');
          win.setTimeout(() => {
            const active = win.__MBG_ACTIVE_UPLOAD_PREVIEW;
            if (active) active.__mbgToken = token;
          }, 0);
          try { win.MbgPreviewNavigation?.postMessage('token:' + token); } catch (_) { /* channel unavailable */ }
        }, true);
      });
    }
    attach();
    win.setInterval(attach, 2000);
    return 'ok';
  }
  if (config.action === 'reopen-preview') {
    if (!config.token || !tokenPattern.test(config.token)) return false;
    for (const doc of documents()) {
      const saved = marker(doc);
      if (!saved || saved.token !== config.token) continue;
      const buttons = Array.from(doc.querySelectorAll<HTMLButtonElement>(selector));
      const indexed = buttons[saved.index];
      const button = indexed && name(indexed) === saved.name ? indexed : buttons.find(item => name(item) === saved.name);
      if (!button) return false;
      button.click();
      return true;
    }
    return false;
  }
  return false;
}
