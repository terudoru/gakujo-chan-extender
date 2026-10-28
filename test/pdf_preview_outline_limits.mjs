import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(process.argv[2], 'utf8');
const start = source.indexOf('function loadOutline(params) {');
const end = source.indexOf('async function loadPage(params)', start);
assert(start >= 0 && end > start);
const memory = new WebAssembly.Memory({initial: 32});
let next = 8;
let allocations = 0;
let freed = 0;
let nodes = new Map();
const exports = {
  FPDFBookmark_GetFirstChild: (_doc, id) => id ? nodes.get(id)?.child ?? 0 : 1,
  FPDFBookmark_GetNextSibling: (_doc, id) => nodes.get(id)?.next ?? 0,
  FPDFBookmark_GetDest: () => 0,
  FPDFBookmark_GetTitle: (id, ptr) => {
    const node = nodes.get(id);
    const bytes = node.size ?? (node.title.length + 1) * 2;
    if (ptr) {
      const target = new Uint16Array(memory.buffer, ptr, bytes / 2);
      for (let i = 0; i < node.title.length; i++) target[i] = node.title.charCodeAt(i);
    }
    return bytes;
  },
  malloc: size => { allocations++; const ptr = next; next += size + (size % 2); return ptr; },
  free: () => { freed++; },
};
const context = {Pdfium: {wasmExports: exports, memory}, Uint8Array, Set,
  StringUtils: {utf16BytesToString: bytes => {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let text = '';
    for (let i = 0; i + 1 < bytes.length; i += 2) {
      const char = view.getUint16(i, true);
      if (!char) break;
      text += String.fromCharCode(char);
    }
    return text;
  }},
  _pdfDestFromDest: () => null};
vm.createContext(context);
vm.runInContext(source.slice(start, end), context);
const load = () => context.loadOutline({docHandle: 1}).outline;
nodes = new Map([[1, {title: '日本語', child: 2, next: 3}], [2, {title: 'العربية'}], [3, {title: ''}]]);
let outline = load();
assert.equal(outline.length, 2);
assert.equal(outline[0].title, '日本語');
assert.equal(outline[0].children[0].title, 'العربية');
assert.equal(outline[1].title, '');
assert.equal(outline[0].dest, null);
nodes = new Map([[1, {title: '', size: 8194}]]);
const before = allocations;
assert.throws(load, /outline/i);
assert.equal(allocations, before, 'reject oversized title before allocation');
nodes = new Map(Array.from({length: 34}, (_, i) => [i + 1, {title: '', child: i < 33 ? i + 2 : 0}]));
assert.throws(load, /outline/i);
nodes = new Map(Array.from({length: 2001}, (_, i) => [i + 1, {title: '', next: i < 2000 ? i + 2 : 0}]));
assert.throws(load, /outline/i);
nodes = new Map([[1, {title: '', next: 1}]]);
assert.throws(load, /outline/i);
nodes = new Map(Array.from({length: 129}, (_, i) => [i + 1, {title: '', size: 8192, next: i < 128 ? i + 2 : 0}]));
assert.throws(load, /outline/i, 'aggregate title size is limited');
nodes = new Map([[1, {title: '', size: 3}]]);
assert.throws(load, /outline/i, 'invalid UTF-16 allocation size is rejected');
nodes = new Map([[1, {title: 'ok'}]]);
assert.equal(load()[0].title, 'ok', 'budget resets between documents');
assert.equal(allocations, freed, 'every title allocation is freed');
console.log('outline limits and normal behavior passed');
