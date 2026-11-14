import assert from 'node:assert/strict';
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
const crossOrigin = Object.defineProperty({}, 'document', { get() { throw Error('cross origin'); } });
const win: any = { document: top.doc, history: top.history,
  frames: [crossOrigin, { document: frame.doc, frames: [{ document: child.doc, frames: [] }] }, { document: blank.doc, frames: [] }],
  crypto: { getRandomValues(bytes: Uint8Array) { bytes.fill(13); } },
  MbgPreviewNavigation: { postMessage(message: string) { messages.push(message); } },
  setInterval() { return 1; }, clearInterval() {},
  setTimeout(fn: () => void, delay: number) { assert.equal(delay, 0); timers.push(fn); },
};
assert.equal(historyMarker(win, { action: 'stamp-dialog', kind: 'bad' }), false);
assert.equal(historyMarker(win, { action: 'stamp-dialog', kind: 'starred' }), 'ok');
assert.equal(top.history.state.existing, 42);
assert.deepEqual(JSON.parse(historyMarker(win, { action: 'read' })),
  { dialog: 'starred', preview: null, active: 'none', activeToken: null });
assert.deepEqual(top.history.state.__mbgReturnDialog,
  { kind: 'starred', frames: [
    { path: '1', url: frame.doc.location.href },
    { path: '1/0', url: child.doc.location.href },
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
