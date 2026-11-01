import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source: any = fs.readFileSync(process.argv[2], 'utf8');
const start: any = source.indexOf('function loadOutline(params) {');
const end: any = source.indexOf('async function loadPage(params)', start);
assert(start >= 0 && end > start);
const memory: any = new WebAssembly.Memory({initial: 32});
let next: any = 8;
let allocations: any = 0;
let freed: any = 0;
let nodes: any = new Map();
const exports: any = {
  FPDFBookmark_GetFirstChild: (_doc: any, id: any) => id ? nodes.get(id)?.child ?? 0 : 1,
  FPDFBookmark_GetNextSibling: (_doc: any, id: any) => nodes.get(id)?.next ?? 0,
  FPDFBookmark_GetDest: () => 0,
  FPDFBookmark_GetTitle: (id: any, ptr: any) => {
    const node: any = nodes.get(id);
    const bytes: any = node.size ?? (node.title.length + 1) * 2;
    if (ptr) {
      const target: any = new Uint16Array(memory.buffer, ptr, bytes / 2);
      for (let i: any = 0; i < node.title.length; i++) target[i] = node.title.charCodeAt(i);
    }
    return bytes;
  },
  malloc: (size: any) => { allocations++; const ptr: any = next; next += size + (size % 2); return ptr; },
  free: () => { freed++; },
};
const context: any = {Pdfium: {wasmExports: exports, memory}, Uint8Array, Set,
  StringUtils: {utf16BytesToString: (bytes: any) => {
    const view: any = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let text: any = '';
    for (let i: any = 0; i + 1 < bytes.length; i += 2) {
      const char: any = view.getUint16(i, true);
      if (!char) break;
      text += String.fromCharCode(char);
    }
    return text;
  }},
  _pdfDestFromDest: () => null};
vm.createContext(context);
vm.runInContext(source.slice(start, end), context);
const load: any = () => context.loadOutline({docHandle: 1}).outline;
nodes = new Map([[1, {title: '日本語', child: 2, next: 3}], [2, {title: 'العربية'}], [3, {title: ''}]]);
let outline: any = load();
assert.equal(outline.length, 2);
assert.equal(outline[0].title, '日本語');
assert.equal(outline[0].children[0].title, 'العربية');
assert.equal(outline[1].title, '');
assert.equal(outline[0].dest, null);
nodes = new Map([[1, {title: '', size: 8194}]]);
const before: any = allocations;
assert.throws(load, /outline/i);
assert.equal(allocations, before, 'reject oversized title before allocation');
nodes = new Map(Array.from({length: 34}, (_: any, i: any) => [i + 1, {title: '', child: i < 33 ? i + 2 : 0}]));
assert.throws(load, /outline/i);
nodes = new Map(Array.from({length: 2001}, (_: any, i: any) => [i + 1, {title: '', next: i < 2000 ? i + 2 : 0}]));
assert.throws(load, /outline/i);
nodes = new Map([[1, {title: '', next: 1}]]);
assert.throws(load, /outline/i);
nodes = new Map(Array.from({length: 129}, (_: any, i: any) => [i + 1, {title: '', size: 8192, next: i < 128 ? i + 2 : 0}]));
assert.throws(load, /outline/i, 'aggregate title size is limited');
nodes = new Map([[1, {title: '', size: 3}]]);
assert.throws(load, /outline/i, 'invalid UTF-16 allocation size is rejected');
nodes = new Map([[1, {title: 'ok'}]]);
assert.equal(load()[0].title, 'ok', 'budget resets between documents');
assert.equal(allocations, freed, 'every title allocation is freed');
console.log('outline limits and normal behavior passed');
