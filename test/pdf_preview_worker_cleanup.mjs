import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

let worker;
let warnings = 0;
const listeners = new Map();
class FakeWorker {
  constructor(url) { this.url = url; this.messages = []; worker = this; }
  postMessage(message) { this.messages.push(message); }
  terminate() { this.terminated = true; }
}
const context = {
  Worker: FakeWorker,
  pdfiumWasmWorkerUrl: 'blob:worker',
  parent: {},
  ArrayBuffer,
  Event: class { constructor(type) { this.type = type; } },
  addEventListener(type, callback) { listeners.set(type, callback); },
  dispatchEvent(event) { if (event.type === 'mbg-pdf-text-limited') warnings++; },
  console,
  Promise,
};
vm.runInNewContext(await readFile(process.argv[2], 'utf8'), context);
context.PdfiumWasmCommunicator.sendCommand('loadDocument', {synthetic: true});
assert.equal(worker.messages.length, 1);
const first = context.PdfiumWasmCommunicator.sendCommand('loadDocumentFromData');
worker.onmessage({data: {id: 2, status: 'success', result: {docHandle: 1}}});
await first;
worker.onmessage({data: {type: 'mbg-text-limited', docHandle: 1}});
assert.equal(warnings, 1);
const second = context.PdfiumWasmCommunicator.sendCommand('loadDocumentFromData');
worker.onmessage({data: {id: 3, status: 'success', result: {docHandle: 2}}});
await second;
worker.onmessage({data: {type: 'mbg-text-limited', docHandle: 1}});
assert.equal(warnings, 1, 'old document must not warn on a new document');
worker.onmessage({data: {type: 'mbg-text-limited', docHandle: 2}});
assert.equal(warnings, 2);
assert.equal(worker.terminated, undefined);
listeners.get('pagehide')();
assert.equal(worker.terminated, true, 'leaving the preview must stop the PDF worker');
console.log('PDF worker terminates when its preview page is closed.');
