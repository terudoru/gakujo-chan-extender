import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(process.argv[2], 'utf8');
const start = source.indexOf('const previewTextBudgets = new Map();');
const end = source.indexOf('/**\n * @typedef {{rects:', start);
assert(start >= 0 && end > start);
let count = 2;
let freed = 0, closedText = 0, closedPage = 0, charsRead = 0;
let limitMessages = 0;
const memory = new WebAssembly.Memory({initial: 1});
const exports = {
  FPDF_LoadPage: () => 1,
  FPDFText_LoadPage: () => 2,
  FPDFText_CountChars: () => count,
  FPDFText_GetUnicode: (_page, i) => { charsRead++; return '世界'.codePointAt(i); },
  FPDFText_GetCharBox: () => 1,
  FPDFText_ClosePage: () => closedText++,
  FPDF_ClosePage: () => closedPage++,
  malloc: () => 8,
  free: () => freed++,
};
const context = {Pdfium: {wasmExports: exports, memory}, Float64Array, Array, Number,
  Map, postMessage: () => limitMessages++,
  missingFonts: {7: {}}, _resetMissingFonts: () => {}, _updateMissingFonts: () => {},
  _ensurePageAvailable: async () => {}};
vm.createContext(context);
vm.runInContext(source.slice(start, end), context);
const load = () => context.loadText({docHandle: 7, pageIndex: 0});
assert.equal((await load()).fullText, '世界');
assert.equal(freed, 1);
assert.equal(closedText, 1);
assert.equal(closedPage, 1);
count = 100001;
assert.equal((await load()).fullText, '');
assert.equal(charsRead, 2, 'oversized text is rejected before extracting characters');
assert.equal(limitMessages, 1);
assert.equal(closedText, 2);
assert.equal(closedPage, 2);
count = -1;
assert.equal((await load()).fullText, '');
vm.runInContext('previewTextBudgets.set(7, {total: 500000, pages: new Map([[1, 500000]])})', context);
count = 1;
assert.equal((await load()).fullText, '', 'document total is limited');
assert.equal(limitMessages, 3);
vm.runInContext('previewTextBudgets.clear()', context);
exports.FPDFText_GetUnicode = () => { throw new Error('synthetic failure'); };
await assert.rejects(load(), /synthetic failure/);
assert.equal(freed, 2, 'allocation is freed on error');
assert.equal(closedText, 5);
assert.equal(closedPage, 5);
console.log('text limits and resource cleanup passed');
