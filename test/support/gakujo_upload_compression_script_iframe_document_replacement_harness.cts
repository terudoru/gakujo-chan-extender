process.argv = [process.argv[0], ...process.argv.slice(2).map((path) => require('node:fs').readFileSync(path, 'utf8'))];
const assert: any = require('node:assert/strict');
const vm: any = require('node:vm');
const [upload, teardown, rawScenario]: any = process.argv.slice(1);
const scenario: any = JSON.parse(rawScenario);
const intervals: any = new Map();
const timers: any = new Map();
const observers: any = [];
let nextTimer = 0;

function makeDocument() {
  return {
    documentElement: {},
    defaultView: {HTMLFormElement: class {
  [key: string]: any;
      submit() {}
      requestSubmit() {}
    }},
    addEventListener() {},
    removeEventListener() {},
    querySelectorAll(selector) {
      return this === top && selector === 'iframe,frame' ? [iframe] : [];
    },
  };
}
const top: any = makeDocument();
const iframe: any = {contentWindow: {document: makeDocument(), frames: []}};
const window: any = {
  document: top,
  frames: [iframe.contentWindow],
  setInterval(callback, ms) {
    intervals.set(++nextTimer, {callback, ms});
    return nextTimer;
  },
  clearInterval(id) { intervals.delete(id); },
  setTimeout(callback) { timers.set(++nextTimer, callback); return nextTimer; },
  clearTimeout(id) { timers.delete(id); },
};
if (scenario.withObserver) window.MutationObserver = class {
  [key: string]: any;
  constructor(callback) { this.callback = callback; observers.push(this); }
  observe() { this.connected = true; }
  disconnect() { this.connected = false; }
  takeRecords() { return []; }
};
const context: any = vm.createContext({window, document: top});
vm.runInContext(upload, context);

function checkHooks() {
  const liveDocuments: any = [top, iframe.contentWindow.document];
  const hooks = window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES;
  assert.equal(hooks.length, liveDocuments.length * 2);
  for (const doc of liveDocuments) {
    for (const method of ['submit', 'requestSubmit']) {
      assert.equal(hooks.filter(entry =>
        entry.prototype === doc.defaultView.HTMLFormElement.prototype &&
        entry.method === method).length, 1);
    }
  }
}
checkHooks();
for (let i = 0; i < 30; i++) {
  iframe.contentWindow.document = makeDocument();
  window.__MBG_UPLOAD_COMPRESSION_UPDATE();
  checkHooks();
}

function tick() {
  for (const {callback} of intervals.values()) callback();
}
function checkWatching() {
  assert.equal(typeof window.__MBG_UPLOAD_COMPRESSION_WATCH_DISPOSE, 'function');
  assert.equal(intervals.size, 1, 'reinjection must not duplicate the watcher');
  assert.equal([...intervals.values()][0].ms, scenario.withObserver ? 5000 : 1000);
  assert.equal(observers.filter(observer => observer.connected).length,
    scenario.withObserver ? 2 : 0);
  if (scenario.withObserver) {
    assert.equal(window.__MBG_PAGE_WATCH_STATE.fallbacks['5000'].runs.length, 1);
  }
}
function checkStopped() {
  assert.equal(window.__MBG_UPLOAD_COMPRESSION_WATCH_DISPOSE, undefined);
  assert.equal(window.__MBG_PAGE_WATCH_STATE, undefined);
  assert.equal(intervals.size, 0, 'teardown must clear the fallback interval');
  assert.equal(timers.size, 0, 'teardown must clear queued mutation work');
  assert.equal(observers.filter(observer => observer.connected).length, 0);
}

tick();
vm.runInContext(upload, context);
checkWatching();
if (scenario.withObserver) {
  observers.find(observer => observer.connected).callback();
  assert.equal(timers.size, 1);
}
vm.runInContext(teardown, context);
vm.runInContext(teardown, context);
checkStopped();

iframe.contentWindow.document = makeDocument();
tick();
assert.equal(iframe.contentWindow.document.__mbgUploadCompressionAttached, undefined,
  'new iframe file inputs must remain untouched while disabled');
assert.equal(window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES.length, 0);

vm.runInContext(upload, context);
vm.runInContext(upload, context);
assert.equal(iframe.contentWindow.document.__mbgUploadCompressionAttached, true);
checkHooks();
checkWatching();

iframe.contentWindow.document = makeDocument();
if (scenario.withObserver) {
  observers.find(observer => observer.connected).callback();
  for (const [id, callback] of [...timers]) { timers.delete(id); callback(); }
} else {
  tick();
}
assert.equal(iframe.contentWindow.document.__mbgUploadCompressionAttached, true,
  're-enabling must resume watching iframe replacements');
checkHooks();
checkWatching();

iframe.contentWindow.document = makeDocument();
tick();
assert.equal(iframe.contentWindow.document.__mbgUploadCompressionAttached, true,
  'the fallback must also resume after re-enabling');
checkHooks();
checkWatching();
vm.runInContext(teardown, context);
checkStopped();

