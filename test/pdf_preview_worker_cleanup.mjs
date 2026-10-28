import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

let worker;
const listeners = new Map();
class FakeWorker {
  constructor(url) { this.url = url; this.messages = []; worker = this; }
  postMessage(message) { this.messages.push(message); }
  terminate() { this.terminated = true; }
}
const context = {
  Worker: FakeWorker,
  pdfiumWasmWorkerUrl: 'blob:worker',
  addEventListener(type, callback) { listeners.set(type, callback); },
  console,
  Promise,
};
vm.runInNewContext(await readFile(process.argv[2], 'utf8'), context);
context.PdfiumWasmCommunicator.sendCommand('loadDocument', {synthetic: true});
assert.equal(worker.messages.length, 1);
assert.equal(worker.terminated, undefined);
listeners.get('pagehide')();
assert.equal(worker.terminated, true, 'leaving the preview must stop the PDF worker');
console.log('PDF worker terminates when its preview page is closed.');
