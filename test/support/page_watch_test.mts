import assert from 'node:assert/strict';
import { watchPage } from '../../web_scripts/src/shared/page_watch.ts';

let nextId = 0;
const timeouts = new Map<number, () => void>();
const intervals = new Map<number, { callback: () => void; ms: number }>();
const observers: FakeObserver[] = [];
class FakeObserver {
  active = false;
  pending = false;
  target: any;
  callback: () => void;
  constructor(callback: () => void) { this.callback = callback; observers.push(this); }
  observe(target: any) { this.target = target; this.active = true; }
  disconnect() { this.active = false; }
  takeRecords() { this.pending = false; return []; }
}
function makeDocument() {
  const listeners = new Map<string, Set<() => void>>();
  const doc: any = { documentElement: {}, defaultView: {},
    addEventListener(type: string, fn: () => void) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type)!.add(fn);
    },
    removeEventListener(type: string, fn: () => void) { listeners.get(type)?.delete(fn); },
    emit(type: string) { listeners.get(type)?.forEach(fn => fn()); },
    listenerCount() { return [...listeners.values()].reduce((n, set) => n + set.size, 0); }
  };
  return doc;
}
const doc = makeDocument();
const win: any = { document: doc, frames: [], MutationObserver: FakeObserver,
  setTimeout(fn: () => void) { const id = ++nextId; timeouts.set(id, fn); return id; },
  clearTimeout(id: number) { timeouts.delete(id); },
  setInterval(fn: () => void, ms: number) { const id = ++nextId; intervals.set(id, { callback: fn, ms }); return id; },
  clearInterval(id: number) { intervals.delete(id); }
};
function flush() { const tasks = [...timeouts.values()]; timeouts.clear(); tasks.forEach(fn => fn()); }
function deliverMutations() { observers.filter(o => o.active && o.pending).forEach(o => { o.pending = false; o.callback(); }); }
let runs = 0;
const dispose = watchPage(win, () => {
  runs++;
  observers.filter(o => o.active).forEach(o => { o.pending = true; });
  doc.emit('input');
}, { fallbackMs: 5000, legacyIntervalMs: 500 });
assert.equal(intervals.values().next().value!.ms, 5000);
observers[0].callback(); observers[0].callback(); doc.emit('change');
assert.equal(timeouts.size, 1);
flush(); deliverMutations();
assert.equal(runs, 1);
assert.equal(timeouts.size, 0);
const child = makeDocument();
win.frames.push({ document: child, frames: [] });
doc.emit('load'); flush();
assert.ok(observers.some(o => o.active && o.target === child.documentElement));
child.emit('input'); flush();
assert.equal(runs, 3);
doc.emit('change');
dispose();
assert.equal(timeouts.size, 0);
assert.equal(intervals.size, 0);
assert.equal(doc.listenerCount(), 0);
assert.equal(child.listenerCount(), 0);
assert.ok(observers.every(o => !o.active));
doc.emit('input'); deliverMutations(); flush();
assert.equal(runs, 3);
delete win.MutationObserver;
const disposeLegacy = watchPage(win, () => { runs++; }, { fallbackMs: 5000, legacyIntervalMs: 700 });
assert.equal(intervals.values().next().value!.ms, 700);
intervals.values().next().value!.callback();
assert.equal(runs, 4);
disposeLegacy();
assert.equal(intervals.size, 0);

win.MutationObserver = FakeObserver;
let otherRuns = 0;
let firstRuns = 0;
const firstDispose = watchPage(win, () => {
  firstRuns++;
  observers.filter(o => o.active).forEach(o => { o.pending = true; });
  doc.emit('input');
}, { fallbackMs: 5000, legacyIntervalMs: 500 });
const secondDispose = watchPage(win, () => { otherRuns++; }, { fallbackMs: 5000, legacyIntervalMs: 500 });
assert.equal(intervals.size, 1);
assert.equal(intervals.values().next().value!.ms, 5000);
const firstActive = observers.find(o => o.active)!;
firstActive.callback();
flush(); deliverMutations(); flush();
assert.equal(otherRuns, 0);
assert.equal(firstRuns, 1);
intervals.values().next().value!.callback();
assert.equal(firstRuns, 2);
assert.equal(otherRuns, 1);
firstDispose();
assert.equal(intervals.size, 1);
assert.ok(win.__MBG_PAGE_WATCH_STATE);
secondDispose();
assert.equal(intervals.size, 0);
assert.equal(win.__MBG_PAGE_WATCH_STATE, undefined);
