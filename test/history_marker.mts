import assert from 'node:assert/strict';
import test from 'node:test';
// Node strips the TypeScript types; no compiler package is needed in CI.
// A computed specifier keeps the tests' type check out of the page source,
// which relies on the page script globals.
const markerModule = '../web_scripts/src/history_marker/marker.ts';
const { historyMarker }: { historyMarker: (win: any, config: any) => any } = await import(markerModule);

function documentWithWindow() {
  const listeners: any[] = [];
  const loadListeners: any[] = [];
  const buttons: any[] = [];
  const history: any = { state: { existing: 42 }, replaceState(value: any) { this.state = value; } };
  const doc: any = { documentElement: {}, defaultView: { history }, location: { href: 'about:blank' },
    addEventListener(type: string, listener: any, capture: boolean) {
      if (type === 'click') { assert.equal(capture, true); listeners.push(listener); }
      if (type === 'load') loadListeners.push(listener);
    },
    querySelectorAll() { return buttons; },
  };
  function button(label: string) {
    const item: any = { previousElementSibling: { tagName: 'A', textContent: label },
      closest() { return item; }, click() { listeners.forEach(fn => fn({ target: item })); item.clicked++; }, clicked: 0 };
    buttons.push(item);
    return item;
  }
  return { doc, history, button, buttons, listeners, loadListeners };
}
const top = documentWithWindow();
const frame = documentWithWindow();
frame.doc.location.href = 'https://gakujo.iess.niigata-u.ac.jp/a';
const child = documentWithWindow();
child.doc.location.href = 'https://gakujo.iess.niigata-u.ac.jp/child';
const blank = documentWithWindow();
const messages: string[] = [];
const timers: (() => void)[] = [];
let randomSeed = 13;
const crossOrigin = Object.defineProperty({}, 'document', { get() { throw Error('cross origin'); } });
const win: any = { document: top.doc, history: top.history,
  frames: [crossOrigin, { document: frame.doc, frames: [{ document: child.doc, frames: [] }] }, { document: blank.doc, frames: [] }],
  crypto: { getRandomValues(bytes: Uint8Array) { bytes.fill(randomSeed++); } },
  MbgPreviewNavigation: { postMessage(message: string) { messages.push(message); } },
  setInterval() { return 1; }, clearInterval() {},
  setTimeout(fn: () => void, delay: number) { assert.equal(delay, 0); timers.push(fn); },
};
assert.equal(historyMarker(win, { action: 'stamp-dialog', kind: 'bad' }), false);
assert.equal(historyMarker(win, { action: 'stamp-dialog', kind: 'starred' }), 'ok');
assert.equal(top.history.state.existing, 42);
assert.equal(frame.history.state.existing, 42);
assert.equal(child.history.state.existing, 42);
assert.match(frame.history.state.__mbgReturnDialogFrame, /^[a-f0-9]{32}$/);
assert.match(child.history.state.__mbgReturnDialogFrame, /^[a-f0-9]{32}$/);
assert.notEqual(frame.history.state.__mbgReturnDialogFrame, child.history.state.__mbgReturnDialogFrame);
const firstFrameToken = frame.history.state.__mbgReturnDialogFrame;
assert.equal(historyMarker(win, { action: 'stamp-dialog', kind: 'starred' }), 'ok');
assert.notEqual(frame.history.state.__mbgReturnDialogFrame, firstFrameToken);
assert.deepEqual(JSON.parse(historyMarker(win, { action: 'read' })),
  { dialog: 'starred', preview: null, active: 'none', activeToken: null });
assert.deepEqual(top.history.state.__mbgReturnDialog,
  { kind: 'starred', frames: [
    { path: '1', url: frame.doc.location.href, token: frame.history.state.__mbgReturnDialogFrame },
    { path: '1/0', url: child.doc.location.href, token: child.history.state.__mbgReturnDialogFrame },
  ] });
frame.doc.location.href = 'https://gakujo.iess.niigata-u.ac.jp/b';
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, null);
frame.doc.location.href = 'https://gakujo.iess.niigata-u.ac.jp/a';
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, 'starred');
const childWindow = win.frames[1].frames.pop();
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, null);
win.frames[1].frames.push(childWindow);
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, 'starred');
blank.doc.location.href = 'https://gakujo.iess.niigata-u.ac.jp/late';
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, 'starred');
const savedDialog = top.history.state.__mbgReturnDialog;
// A CampusSquare POST creates a new child document at the same URL.
const nextChild = documentWithWindow();
nextChild.doc.location.href = child.doc.location.href;
childWindow.document = nextChild.doc;
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, null);
nextChild.history.replaceState({ ...nextChild.history.state, __mbgReturnDialogFrame: 'different-entry' });
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, null);
// Back restores the stamped document and its original history state.
childWindow.document = child.doc;
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, 'starred');

// Entries stamped by older versions still compare frames by URL alone.
top.history.state.__mbgReturnDialog = {
  kind: 'starred', frames: savedDialog.frames.map(({ path, url }: { path: string; url: string }) => ({ path, url })),
};
childWindow.document = nextChild.doc;
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, 'starred');
nextChild.doc.location.href += '/changed';
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, null);
childWindow.document = child.doc;
top.history.state.__mbgReturnDialog = 'starred';
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).dialog, 'starred');
top.history.state.__mbgReturnDialog = savedDialog;
assert.equal(historyMarker(win, { action: 'install-preview-tracker' }), 'ok');
assert.equal(historyMarker(win, { action: 'install-preview-tracker' }), 'ok');
assert.equal(frame.listeners.length, 1);
const late = documentWithWindow();
win.frames.push({ document: late.doc, frames: [] });
top.loadListeners[0]();
assert.equal(late.listeners.length, 1);
const first = frame.button(' first ');
const second = frame.button(' document.pdf ');
second.click();
const token = frame.history.state.__mbgPreview.token;
// The preview is created by the bubbling click handler after the capture listener.
win.__MBG_ACTIVE_UPLOAD_PREVIEW = { visible: true };
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).activeToken, null);
timers.shift()!();
assert.equal(win.__MBG_ACTIVE_UPLOAD_PREVIEW.__mbgToken, token);
assert.equal(frame.history.state.__mbgPreview.index, 1);
assert.equal(frame.history.state.__mbgPreview.name, 'document.pdf');
assert.equal(messages[0], 'token:' + token);
assert.deepEqual(JSON.parse(historyMarker(win, { action: 'read' })),
  { dialog: 'starred', preview: token, active: 'visible', activeToken: token });
win.__MBG_ACTIVE_UPLOAD_PREVIEW.visible = false;
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).active, 'hidden');
win.__MBG_ACTIVE_UPLOAD_PREVIEW.__mbgToken = 'invalid!';
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).activeToken, null);
delete win.__MBG_ACTIVE_UPLOAD_PREVIEW;
assert.equal(JSON.parse(historyMarker(win, { action: 'read' })).active, 'none');
assert.equal(historyMarker(win, { action: 'reopen-preview', token: 'bad!' }), false);
assert.equal(historyMarker(win, { action: 'reopen-preview', token: 'xxxxxxxx' }), false);
frame.buttons.reverse();
assert.equal(historyMarker(win, { action: 'reopen-preview', token }), true);
assert.equal(second.clicked, 2);
assert.equal(first.clicked, 0);
frame.buttons.length = 0;
assert.equal(historyMarker(win, { action: 'reopen-preview', token }), false);
const input = frame.button('');
input.previousElementSibling = { tagName: 'INPUT', value: ' report.pdf ' };
input.click();
const inputMarker = frame.history.state.__mbgPreview;
assert.equal(inputMarker.name, 'report.pdf');
assert.equal(historyMarker(win, { action: 'reopen-preview', token: inputMarker.token }), true);
assert.equal(input.clicked, 2);
const sourceButton = frame.button('');
sourceButton.previousElementSibling = { tagName: 'BUTTON', textContent: ' button.pdf ' };
sourceButton.click();
const buttonMarker = frame.history.state.__mbgPreview;
assert.equal(buttonMarker.name, 'button.pdf');
assert.equal(historyMarker(win, { action: 'reopen-preview', token: buttonMarker.token }), true);
assert.equal(sourceButton.clicked, 2);

function previewPair(nested: boolean) {
  const top = documentWithWindow();
  const earlier = documentWithWindow();
  const later = documentWithWindow();
  const laterWindow = { document: later.doc, frames: [] };
  const earlierWindow = { document: earlier.doc, frames: nested ? [laterWindow] : [] };
  const timers: (() => void)[] = [];
  const page: any = {
    document: top.doc, history: top.history, crypto: win.crypto,
    frames: nested ? [earlierWindow] : [earlierWindow, laterWindow],
    setInterval() {}, setTimeout(callback: () => void) { timers.push(callback); },
  };
  historyMarker(page, { action: 'install-preview-tracker' });
  function open(source: typeof earlier) {
    const button = source.button('report.pdf');
    button.click();
    page.__MBG_ACTIVE_UPLOAD_PREVIEW = { visible: true };
    timers.shift()!();
    return { token: source.history.state.__mbgPreview.token, button };
  }
  const first = open(earlier);
  page.__MBG_ACTIVE_UPLOAD_PREVIEW.visible = false;
  const current = open(later);
  const read = (token?: string | null) => JSON.parse(historyMarker(page, { action: 'read', token }));
  return { page, laterWindow, first, current, read };
}

for (const layout of ['sibling', 'nested']) {
  test(`hidden preview in a later ${layout} frame owns Forward`, () => {
    const { page, first, current, read } = previewPair(layout === 'nested');
    page.__MBG_ACTIVE_UPLOAD_PREVIEW.visible = false;
    assert.deepEqual(read(first.token),
      { dialog: null, preview: current.token, active: 'hidden', activeToken: current.token });
  });

  test(`detached preview in a later ${layout} frame reopens its own button`, () => {
    const { page, first, current, read } = previewPair(layout === 'nested');
    delete page.__MBG_ACTIVE_UPLOAD_PREVIEW;
    const result = read(current.token);
    assert.deepEqual(result, { dialog: null, preview: current.token, active: 'none', activeToken: null });
    assert.equal(historyMarker(page, { action: 'reopen-preview', token: result.preview }), true);
    assert.equal(current.button.clicked, 2);
    assert.equal(first.button.clicked, 1);
  });
}

test('only current, reachable history entries can supply the preferred marker', () => {
  const { page, laterWindow, first, current, read } = previewPair(false);
  const active = page.__MBG_ACTIVE_UPLOAD_PREVIEW;
  for (const token of [undefined, null, 'bad!']) {
    active.__mbgToken = token;
    assert.deepEqual(read(current.token),
      { dialog: null, preview: first.token, active: 'visible', activeToken: null });
  }
  active.__mbgToken = 'unmatched';
  assert.equal(read(current.token).preview, first.token);
  delete page.__MBG_ACTIVE_UPLOAD_PREVIEW;
  for (const token of [undefined, null, 'bad!', 'unmatched', first.token]) {
    assert.equal(read(token).preview, first.token);
  }

  // The frame can navigate to a new entry, become inaccessible, or leave the traversal limit.
  const original = laterWindow.document;
  laterWindow.document = documentWithWindow().doc;
  page.__MBG_ACTIVE_UPLOAD_PREVIEW = { visible: false, __mbgToken: current.token };
  assert.deepEqual(read(), { dialog: null, preview: first.token, active: 'hidden', activeToken: current.token });
  delete page.__MBG_ACTIVE_UPLOAD_PREVIEW;
  assert.equal(read(current.token).preview, first.token);
  laterWindow.document.defaultView.history.state.__mbgPreview = { token: current.token };
  assert.equal(read(current.token).preview, first.token);
  assert.equal(historyMarker(page, { action: 'reopen-preview', token: current.token }), false);
  laterWindow.document = original;
  page.frames.splice(1, 0, ...Array(63).fill(crossOrigin));
  assert.equal(read(current.token).preview, first.token);
  page.frames = [crossOrigin];
  assert.equal(read(current.token).preview, null);
});
