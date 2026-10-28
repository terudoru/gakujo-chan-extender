import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(process.argv[2], 'utf8');
const ticks = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
let readers = 0, maxReaders = 0, aborted = 0, workers = 0, maxRenders = 0, renders = 0;
let currentReader, currentRender;
const timers = new Map(), intervals = new Map();
let timerId = 0;

class Element {
  constructor(tag, doc) {
    this.tagName = tag; this.ownerDocument = doc; this.children = [];
    this.style = {}; this.listeners = {}; this.attributes = {}; this.isConnected = true;
  }
  append(...children) { for (const child of children) this.appendChild(child); }
  appendChild(child) { this.children.push(child); child.parentNode = this; return child; }
  insertBefore(child) { this.appendChild(child); }
  after(child) { this.parentNode.appendChild(child); }
  remove() {
    this.isConnected = false;
    if (this.parentNode) this.parentNode.children = this.parentNode.children.filter(x => x !== this);
  }
  removeChild(child) { child.remove(); }
  get lastChild() { return this.children.at(-1); }
  setAttribute(name, value) { this.attributes[name] = value; }
  addEventListener(name, fn) { (this.listeners[name] ||= []).push(fn); }
  removeEventListener(name, fn) { this.listeners[name] = (this.listeners[name] || []).filter(x => x !== fn); }
  fire(name) { for (const fn of [...(this.listeners[name] || [])]) fn({target: this}); }
  focus() {}
  getContext() { return {}; }
}
const doc = { createElement: tag => new Element(tag, doc) };
doc.body = new Element('body', doc);
const parent = new Element('div', doc); doc.body.appendChild(parent);
const file = { name: 'synthetic.pdf', type: 'application/pdf', size: 64,
  arrayBuffer() { throw new Error('PDF reads must be abortable'); } };
const inputs = [new Element('input', doc), new Element('input', doc)];
for (const input of inputs) { input.files = [file]; parent.appendChild(input); }
doc.querySelectorAll = selector => selector === 'input[type="file"]' ? inputs : [];
const windowListeners = {};
const window = {
  document: doc, location: {origin: 'https://example.invalid'},
  setTimeout(fn) { const id = ++timerId; timers.set(id, () => { timers.delete(id); fn(); }); return id; },
  clearTimeout(id) { timers.delete(id); },
  setInterval(fn) { const id = ++timerId; intervals.set(id, fn); return id; },
  clearInterval(id) { intervals.delete(id); },
  addEventListener(name, fn) { (windowListeners[name] ||= []).push(fn); },
  removeEventListener(name, fn) { windowListeners[name] = (windowListeners[name] || []).filter(x => x !== fn); },
  __MBG_PDF_WORKER_URL: 'blob:synthetic',
};
window.top = window; doc.defaultView = window;
class FileReader {
  readAsArrayBuffer() { readers++; maxReaders = Math.max(maxReaders, readers); currentReader = this; }
  abort() { if (this.done) return; this.done = true; readers--; aborted++; this.onabort(); }
  finish() { if (this.done) return; this.done = true; readers--; this.result = new ArrayBuffer(4); this.onload(); }
}
class Worker {
  constructor() { workers++; }
  terminate() { workers--; }
}
const pdf = {
  numPages: 3,
  getPage(number) {
    return Promise.resolve({
      getViewport: () => ({width: 100, height: 100}), cleanup() {},
      render() {
        renders++; maxRenders = Math.max(maxRenders, renders);
        let resolve, reject, ended = false;
        const promise = new Promise((a, b) => { resolve = a; reject = b; });
        currentRender = {
          number, promise,
          cancel() { if (!ended) { ended = true; renders--; reject(new Error('cancelled')); } },
          finish() { if (!ended) { ended = true; renders--; resolve(); } },
        };
        return currentRender;
      },
    });
  },
};
window.pdfjsLib = {
  PDFWorker: {fromPort: () => ({})},
  getDocument: () => ({promise: Promise.resolve(pdf), destroy: () => Promise.resolve()}),
};
const context = {window, document: doc, FileReader, Worker, URL: {revokeObjectURL() {}},
  Promise, ArrayBuffer, Uint8Array, DataView, Math, Number, Error};
vm.runInNewContext(source, context);
const controls = parent.children.filter(node => node.tagName === 'button');
assert.equal(controls.length, 2);
controls[0].fire('click');
await ticks();
assert.equal(readers, 1);
controls[1].fire('click');
await ticks();
assert.equal(aborted, 1, 'opening a new preview must abort the old read');
assert.equal(readers, 1);
assert.equal(maxReaders, 1);
assert.equal(doc.body.children.filter(x => x.attributes.role === 'dialog').length, 1);
currentReader.finish();
await ticks();
assert.equal(workers, 1);
assert.equal(renders, 1);
const overlay = doc.body.children.find(x => x.attributes.role === 'dialog');
const bar = overlay.children[0];
const next = bar.children.find(x => x.textContent === '次へ');
const previous = bar.children.find(x => x.textContent === '前へ');
next.fire('click'); previous.fire('click'); next.fire('click');
await ticks();
assert.equal(maxRenders, 1, 'page renders must not overlap');
assert.equal(renders, 1);
assert.equal(currentRender.number, 2);
currentRender.finish();
await ticks();
assert.equal(renders, 0);
const zoomIn = bar.children.find(x => x.textContent === '拡大');
zoomIn.fire('click');
await ticks();
assert.equal(renders, 1, 'zooming a PDF must render again at the new resolution');
currentRender.finish();
await ticks();
inputs[1].fire('change');
await ticks();
assert.equal(workers, 0);
assert.equal(doc.body.children.filter(x => x.attributes.role === 'dialog').length, 0);
assert.equal(timers.size, 0);

delete window.pdfjsLib;
window.MbgUploadCompression = {postMessage() {}};
for (let i = 0; i < 10; i++) {
  controls[0].fire('click');
  await ticks();
  inputs[0].fire('change');
  await ticks();
}
assert.equal(timers.size, 0, 'closed previews must remove pending library timers');
assert.equal(workers, 0);

// A stalled read is aborted by the watchdog, without leaving a worker alive.
window.pdfjsLib = {
  PDFWorker: {fromPort: () => ({})},
  getDocument: () => ({promise: Promise.resolve(pdf), destroy: () => Promise.resolve()}),
};
controls[0].fire('click');
await ticks();
assert.equal(readers, 1);
assert.equal(timers.size, 1);
[...timers.values()][0]();
await ticks();
assert.equal(readers, 0);
assert.equal(workers, 0);
inputs[0].fire('change');
assert.equal(timers.size, 0);

// A stale page error must not close the newer requested page.
let rejectOld;
let firstPage = true;
const normalGetPage = pdf.getPage;
pdf.getPage = function(number) {
  if (firstPage) {
    firstPage = false;
    return new Promise((_, reject) => { rejectOld = reject; });
  }
  return normalGetPage(number);
};
controls[0].fire('click');
await ticks();
currentReader.finish();
await ticks();
const secondOverlay = doc.body.children.find(x => x.attributes.role === 'dialog');
const secondNext = secondOverlay.children[0].children.find(x => x.textContent === '次へ');
secondNext.fire('click');
rejectOld(new Error('stale page failed'));
await ticks();
assert.equal(workers, 1);
assert.equal(currentRender.number, 2);
currentRender.finish();
await ticks();
inputs[0].fire('change');
assert.equal(workers, 0);
pdf.getPage = normalGetPage;

// Multiple selected files remain available one at a time.
inputs[0].files = [file, {...file, name: 'second.pdf'}];
controls[0].fire('click');
const list = parent.children.find(node => node.tagName === 'div');
assert.equal(list.children.length, 2);
list.children[1].fire('click');
await ticks();
assert.equal(readers, 1);
inputs[0].fire('change');
assert.equal(readers, 0);
assert.equal(workers, 0);
console.log('Preview reads, workers, renders and pending loads are bounded.');
