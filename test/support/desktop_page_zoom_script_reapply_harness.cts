const vm: any = require('node:vm');
const assert: any = require('node:assert/strict');
const fs: any = require('node:fs');
let script: string = process.argv[2];
if (script === '--source') {
  const ts = require('../../web_scripts/node_modules/typescript');
  script = ts.transpileModule(fs.readFileSync('web_scripts/src/desktop_page_zoom/main.ts', 'utf8'),
    {compilerOptions: {module: ts.ModuleKind.CommonJS}}).outputText;
}

type TestMutation = {type: string; attributeName?: string};

function boot() {
  let now = 1000;
  let nextTimer = 0;
  const timers = new Map<number, {owner: string; due: number; callback: () => void}>();

  function makeWindow(name: string) {
    const listeners: Record<string, Array<() => void>> = {};
    const loadListeners: Array<(event: {target: {tagName: string}}) => void> = [];
    let mutation: (records: TestMutation[]) => void;
    let measurements = 0;
    let scrollCalls = 0;
    let observations = 0;
    const bodyStyle = new Proxy<Record<string, string>>({}, {
      set(target, key: string, value: string) {
        if (key === 'transform' && value === 'none') measurements++;
        target[key] = value;
        return true;
      },
    });
    return {
      frames: [], innerWidth: 900, innerHeight: 700, scrollX: 0, scrollY: 0,
      listeners,
      loadListeners,
      addEventListener(type, callback) { (listeners[type] ??= []).push(callback); },
      emit(type: string) { for (const callback of listeners[type] ?? []) callback(); },
      setTimeout(callback, delay) {
        assert.equal(delay, 150);
        const id = ++nextTimer;
        timers.set(id, {owner: name, due: now + delay, callback});
        return id;
      },
      clearTimeout(id) { timers.delete(id); },
      scrollTo(x, y) { scrollCalls++; this.scrollX = x; this.scrollY = y; },
      get measurements() { return measurements; },
      get scrollCalls() { return scrollCalls; },
      get observations() { return observations; },
      resetCounts() { measurements = scrollCalls = 0; },
      MutationObserver: class {
        constructor(callback) { mutation = callback; }
        observe() { observations++; }
      },
      mutate(records: TestMutation[] = [{type: 'childList'}]) { mutation(records); },
      load(tagName: string) {
        for (const callback of loadListeners) callback({target: {tagName}});
      },
      document: {
        body: {style: bodyStyle, scrollWidth: 900, offsetWidth: 900, scrollHeight: 3600, offsetHeight: 3600},
        documentElement: {style: {}, clientWidth: 900, scrollWidth: 900,
          offsetWidth: 900, scrollHeight: 3600, offsetHeight: 3600},
        addEventListener(type, callback, capture) {
          if (type === 'load' && capture) loadListeners.push(callback);
        },
      },
    };
  }

  const win: any = makeWindow('top');
  const child = makeWindow('child');
  win.frames.push(child);
  const fakeDate = class extends Date { static now() { return now; } };
  const context = vm.createContext({
    window: win, Date: fakeDate, __mbgConfig: {zoom: 1.5, originX: 400, originY: 300}, exports: {},
  });
  function inject(nextScript = script) { vm.runInContext(nextScript, context); }
  inject();
  win.scrollX = 300;
  win.scrollY = 1500;
  win.resetCounts();
  const {body, documentElement} = win.document;
  body.scrollWidth = body.offsetWidth = documentElement.scrollWidth = documentElement.offsetWidth = 1350;

  function advanceTo(time: number) {
    while (true) {
      const next = [...timers].sort((a, b) => a[1].due - b[1].due)[0];
      if (!next || next[1].due > time) break;
      const [id, {due, callback}] = next;
      now = due;
      timers.delete(id);
      callback();
    }
    now = time;
  }

  return {win, child, timers, makeWindow, advanceTo, inject};
}

function runCase(scenario: string) {
  const {win, child, timers, makeWindow, advanceTo} = boot();
  const element = win.document.documentElement;
  const unscrolled = ['unscrolled', 'imageUnscrolled', 'imageChild', 'imageCoalesced'].includes(scenario);
  win.scrollX = unscrolled ? 0 : 300;
  win.scrollY = unscrolled ? 0 : 1500;
  if (scenario === 'resize' || scenario === 'sticky') win.emit('resize');
  if (scenario.startsWith('image')) {
    assert.equal(child.loadListeners.length, 1);
    const pendingFrame = makeWindow('pending');
    win.frames.push(pendingFrame);
    if (scenario !== 'imageChild') win.load('IMG');
    if (scenario === 'imageChild' || scenario === 'imageCoalesced') {
      child.load('IMG');
    }
    assert.equal(pendingFrame.loadListeners.length, 0);
  } else if (scenario !== 'resize') {
    win.mutate();
  }
  assert.equal(timers.size, 1);
  if (scenario === 'scroll') {
    advanceTo(1100);
    win.emit('scroll');
    advanceTo(1150);
    assert.equal(win.__MBG_PAGE_EFFECTIVE_ZOOM, 1.5);
    assert.equal(element.style.minWidth, '1350px');
    assert.equal(win.scrollCalls, 0);
    assert.equal(win.measurements, 0);
    assert.equal(timers.size, 1);
  }
  advanceTo(scenario === 'scroll' ? 1300 : 1150);
  assert.equal(timers.size, 0);
  assert.equal(win.measurements, 1);
  return {zoom: win.__MBG_PAGE_EFFECTIVE_ZOOM, x: win.scrollX, y: win.scrollY,
    minWidth: element.style.minWidth, scrollCalls: win.scrollCalls};
}

function checkCrossWindowScroll(scrollInTop: boolean) {
  const {win, child, timers, advanceTo} = boot();
  const scrollWindow = scrollInTop ? win : child;
  const mutationWindow = scrollInTop ? child : win;
  mutationWindow.mutate();
  advanceTo(1100);
  scrollWindow.emit('scroll');
  advanceTo(1150);
  assert.equal(win.measurements, 0, 'automatic measurement must wait for the other window to stop scrolling');
  assert.equal(timers.size, 1);
  assert.equal(timers.values().next().value.owner, 'top');
  advanceTo(1300);
  assert.equal(timers.size, 0);
  assert.equal(win.measurements, 1);
  assert.equal(win.__MBG_PAGE_EFFECTIVE_ZOOM, 1.5);
  assert.equal(win.scrollY, 1500);
  assert.equal(child.measurements, 0);
}

function checkMixedResize(resizeInTop: boolean) {
  for (const resizeFirst of [true, false]) {
    const {win, child, timers, advanceTo} = boot();
    const resizeWindow = resizeInTop ? win : child;
    const mutationWindow = resizeInTop ? child : win;
    const resize = () => resizeWindow.emit('resize');
    const mutate = () => mutationWindow.mutate();
    const [first, second] = resizeFirst ? [resize, mutate] : [mutate, resize];
    first();
    advanceTo(1040);
    second();
    assert.equal(timers.size, 1, 'mixed resize and mutation must share one debounce timer');
    assert.equal(timers.values().next().value.owner, 'top');
    advanceTo(1170);
    child.emit('scroll');
    advanceTo(1190);
    assert.equal(win.measurements, 0);
    advanceTo(1340);
    assert.equal(timers.size, 0);
    assert.equal(win.measurements, 1);
    assert.equal(win.__MBG_PAGE_EFFECTIVE_ZOOM, 1, 'resize must still refit after a shape event or scroll delay');
    assert.equal(win.scrollX, 200);
    assert.equal(win.scrollY, 1000);
    assert.equal(child.measurements, 0);
  }
}

function checkReplacement() {
  const {win, timers, makeWindow, advanceTo, inject} = boot();
  const replacement = makeWindow('replacement');
  win.frames[0] = replacement;
  win.load('IFRAME');
  assert.equal(replacement.loadListeners.length, 1);
  const nested = makeWindow('nested');
  replacement.frames.push(nested);
  replacement.load('FRAME');
  assert.equal(nested.loadListeners.length, 1);

  inject();
  inject();
  for (const target of [win, replacement, nested]) {
    for (const type of ['keydown', 'wheel', 'scroll', 'resize']) {
      assert.equal(target.listeners[type].length, 1, type);
    }
    assert.equal(target.loadListeners.length, 1);
    assert.equal(target.observations, 1);
  }
  win.resetCounts();
  assert.equal(timers.size, 1);
  advanceTo(1100);
  nested.emit('scroll');
  advanceTo(1150);
  assert.equal(win.measurements, 0);
  advanceTo(1300);
  assert.equal(win.measurements, 1);

  nested.mutate();
  advanceTo(1450);
  assert.equal(win.measurements, 2);
  assert.equal(timers.size, 0);
  assert.equal(replacement.measurements, 0);
  assert.equal(nested.measurements, 0);
}

function checkLatestZoom() {
  const {win, child, advanceTo, inject} = boot();
  const latestScript = process.argv[5];
  assert.ok(latestScript);
  child.mutate();
  advanceTo(1100);
  win.emit('scroll');
  inject(latestScript);
  assert.equal(win.measurements, 1);
  assert.equal(win.__MBG_PAGE_ZOOM_VALUE, 2);
  assert.equal(win.__MBG_PAGE_EFFECTIVE_ZOOM, 4 / 3);
  assert.equal(win.scrollY, 1300);
  advanceTo(1150);
  assert.equal(win.measurements, 1);
  advanceTo(1300);
  assert.equal(win.measurements, 2);
  assert.equal(win.__MBG_PAGE_ZOOM_VALUE, 2);
  assert.equal(win.__MBG_PAGE_EFFECTIVE_ZOOM, 4 / 3);
  assert.equal(win.scrollY, 1300);
}

function checkIgnoredEvents() {
  const {win, child, timers, advanceTo} = boot();
  for (const target of [win, child]) {
    target.mutate([{type: 'attributes', attributeName: 'style'}]);
    target.load('SCRIPT');
    target.load('LINK');
  }
  assert.equal(timers.size, 0);
  advanceTo(1300);
  assert.equal(win.measurements, 0);
}

if (process.argv[3] === 'scheduler') {
  const checks: Record<string, () => void> = {
    'top-scroll': () => checkCrossWindowScroll(true),
    'child-scroll': () => checkCrossWindowScroll(false),
    'top-resize': () => checkMixedResize(true),
    'child-resize': () => checkMixedResize(false),
    'replacement': checkReplacement,
    'latest-zoom': checkLatestZoom,
    'ignored-events': checkIgnoredEvents,
  };
  const check = checks[process.argv[4]];
  assert.ok(check, process.argv[4]);
  check();
  process.exit(0);
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
