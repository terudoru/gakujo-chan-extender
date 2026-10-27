import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const script = await readFile(process.argv[2], 'utf8');
let created = 0, callbacks = 0;
const revoked = [];
const window = {fail: true, pdfjsLib: {pageProvided: true},
  __MBG_PDF_WORKER_URL: 'blob:page-provided',
  __MBG_UPLOAD_PREVIEW_LIBRARY_LOADED() { callbacks++; }};
const context = vm.createContext({window, Blob, URL: {
  createObjectURL() { return `blob:synthetic-${++created}`; },
  revokeObjectURL(url) { revoked.push(url); },
}});
assert.equal(vm.runInContext(script, context), 'mbg-failed');
assert.deepEqual(revoked, ['blob:synthetic-1']);
assert.equal(window.__MBG_PDF_WORKER_URL, 'blob:page-provided');
assert.equal(callbacks, 1, 'failure should wake waiting previews');
window.fail = false;
assert.equal(vm.runInContext(script, context), 'mbg-ready');
assert.equal(window.__MBG_PDF_WORKER_URL, 'blob:synthetic-2');
assert.deepEqual(revoked, ['blob:synthetic-1']);
assert.equal(vm.runInContext(script, context), 'mbg-ready');
assert.equal(created, 2, 'ready libraries should not create more Blob URLs');
