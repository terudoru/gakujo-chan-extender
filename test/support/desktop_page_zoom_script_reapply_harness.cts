const vm: any = require('node:vm');
const assert: any = require('node:assert/strict');
const fs: any = require('node:fs');
let script: string = process.argv[2];
if (script === '--source') {
  const ts = require('../../web_scripts/node_modules/typescript');
  script = ts.transpileModule(fs.readFileSync('web_scripts/src/desktop_page_zoom/main.ts', 'utf8'),
    {compilerOptions: {module: ts.ModuleKind.CommonJS}}).outputText;
}

function makeChildWindow() {
  const loadListeners: any[] = [];
  return {
    frames: [],
    addEventListener() {},
    document: {
      addEventListener(name, callback, capture) {
        if (name === 'load' && capture) loadListeners.push(callback);
      },
    },
    loadListeners,
  };
}

function runCase(scenario: string) {
  let now = 1000;
  let nextTimer = 0;
  const timers = new Map<number, () => void>();
  const listeners: any = {};
  const documentListeners: any = {};
  let mutation: any;
  let scrollCalls = 0;
  let measurements = 0;
  const child = makeChildWindow();
  const pendingFrame = makeChildWindow();
  const win: any = {
    frames: [child], innerWidth: 900, innerHeight: 700, scrollX: 0, scrollY: 0,
    addEventListener(name, callback) { listeners[name] = callback; },
    setTimeout(callback, delay) { assert.equal(delay, 150); const id = ++nextTimer; timers.set(id, callback); return id; },
    clearTimeout(id) { timers.delete(id); },
    scrollTo(x, y) { scrollCalls++; this.scrollX = x; this.scrollY = y; },
    MutationObserver: class { constructor(callback) { mutation = callback; } observe() {} },
  };
  const bodyStyle = new Proxy({}, {set(target, key, value) {
    if (key === 'transform' && value === 'none') measurements++;
    target[key] = value; return true;
  }});
  const body: any = {style: bodyStyle, scrollWidth: 900, offsetWidth: 900, scrollHeight: 3600, offsetHeight: 3600};
  const element: any = {style: {}, clientWidth: 900, scrollWidth: 900, offsetWidth: 900, scrollHeight: 3600, offsetHeight: 3600};
  win.document = {
    body,
    documentElement: element,
    addEventListener(name, callback, capture) {
      if (capture) documentListeners[name] = callback;
    },
  };
  const fakeDate = class extends Date { static now() { return now; } };
  vm.runInNewContext(script, {window: win, Date: fakeDate, __mbgConfig: {zoom: 1.5, originX: 400, originY: 300}, exports: {}});
  const unscrolled = ['unscrolled', 'imageUnscrolled', 'imageChild', 'imageCoalesced'].includes(scenario);
  win.scrollX = unscrolled ? 0 : 300;
  win.scrollY = unscrolled ? 0 : 1500;
  scrollCalls = 0;
  measurements = 0;
  body.scrollWidth = body.offsetWidth = element.scrollWidth = element.offsetWidth = 1350;
  const fireMutation = () => mutation([{type: 'childList'}]);
  const fireTimer = () => { assert.equal(timers.size, 1); const [id, callback] = timers.entries().next().value; timers.delete(id); callback(); };
  if (scenario === 'resize' || scenario === 'sticky') listeners.resize();
  if (scenario.startsWith('image')) {
    assert.equal(child.loadListeners.length, 1);
    win.frames.push(pendingFrame);
    const imageLoad = {target: {tagName: 'IMG'}};
    if (scenario !== 'imageChild') documentListeners.load(imageLoad);
    if (scenario === 'imageChild' || scenario === 'imageCoalesced') {
      child.loadListeners[0](imageLoad);
    }
    assert.equal(pendingFrame.loadListeners.length, 0);
  } else if (scenario !== 'resize') {
    fireMutation();
  }
  if (scenario === 'scroll') {
    now = 1100; listeners.scroll();
    fireTimer();
    assert.equal(win.__MBG_PAGE_EFFECTIVE_ZOOM, 1.5);
    assert.equal(element.style.minWidth, '1350px');
    assert.equal(scrollCalls, 0);
    assert.equal(measurements, 0);
    assert.equal(timers.size, 1);
    now = 1250;
  }
  fireTimer();
  assert.equal(timers.size, 0);
  assert.equal(measurements, 1);
  return {zoom: win.__MBG_PAGE_EFFECTIVE_ZOOM, x: win.scrollX, y: win.scrollY,
    minWidth: element.style.minWidth, scrollCalls};
}
const results: any = {};
const cases = process.argv[3] === 'image'
  ? ['imageScrolled', 'imageUnscrolled', 'imageChild', 'imageCoalesced']
  : ['shape', 'unscrolled', 'resize', 'scroll', 'sticky'];
for (const scenario of cases) results[scenario] = runCase(scenario);
if (process.argv[3] === 'image') {
  assert.deepEqual(results.imageScrolled, {zoom: 1.5, x: 300, y: 1500, minWidth: '2025px', scrollCalls: 0});
  for (const scenario of ['imageUnscrolled', 'imageChild', 'imageCoalesced']) {
    assert.deepEqual(results[scenario], {zoom: 1, x: 0, y: 0, minWidth: '', scrollCalls: 0});
  }
} else {
  assert.deepEqual(results.shape, {zoom: 1.5, x: 300, y: 1500, minWidth: '2025px', scrollCalls: 0});
  assert.deepEqual(results.scroll, results.shape);
  assert.deepEqual(results.unscrolled, {zoom: 1, x: 0, y: 0, minWidth: '', scrollCalls: 0});
  assert.deepEqual(results.resize, {zoom: 1, x: 200, y: 1000, minWidth: '', scrollCalls: 1});
  assert.deepEqual(results.sticky, results.resize);
}
process.stdout.write(JSON.stringify(results));
