import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const script = await readFile(process.argv[2], 'utf8');
let called = 0;
const window = {__MBG_UPLOAD_PREVIEW_OFFICE_LIBRARY_LOADED() {
  assert.ok(window.JSZip);
  assert.equal(window['__MBG_UPLOAD_LIBRARY_READY_preview-office'], true);
  called++;
}};
const context = vm.createContext({window, URL: {revokeObjectURL() {}}});
assert.equal(vm.runInContext(script, context), 'mbg-ready');
assert.equal(called, 1);
assert.equal(vm.runInContext(script, context), 'mbg-ready');
assert.equal(called, 2);
