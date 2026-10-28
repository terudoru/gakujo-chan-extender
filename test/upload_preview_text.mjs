import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

class Element {
  constructor(tag, doc) { this.tagName = tag; this.ownerDocument = doc; this.children = []; this.style = {}; this.listeners = {}; this.attributes = {}; this.isConnected = true; }
  append(...nodes) { nodes.forEach(node => this.appendChild(node)); }
  appendChild(node) { this.children.push(node); node.parentNode = this; return node; }
  insertBefore(node) { return this.appendChild(node); }
  setAttribute(key, value) { this.attributes[key] = value; }
  addEventListener(key, fn) { (this.listeners[key] ||= []).push(fn); }
  removeEventListener(key, fn) { this.listeners[key] = (this.listeners[key] || []).filter(x => x !== fn); }
  fire(key) { (this.listeners[key] || []).forEach(fn => fn({target: this})); }
  remove() { this.isConnected = false; if (this.parentNode) this.parentNode.children = this.parentNode.children.filter(x => x !== this); }
  focus() {}
}
const doc = {createElement: tag => new Element(tag, doc)};
doc.body = new Element('body', doc);
const input = new Element('input', doc); doc.body.appendChild(input);
doc.querySelectorAll = selector => selector === 'input[type="file"]' ? [input] : [];
const window = {document: doc, location: {origin: 'https://example.invalid'},
  setInterval() {return 1;}, clearInterval() {}, addEventListener() {}, removeEventListener() {}};
window.top = window; doc.defaultView = window;
class FileReader {
  readAsArrayBuffer(file) { this.result = Uint8Array.from(file.bytes).buffer; this.onload(); }
  abort() {}
}
vm.runInNewContext(await readFile(process.argv[2], 'utf8'), {
  window, document: doc, FileReader, TextDecoder, Uint8Array, DataView, ArrayBuffer, Promise, Math, Number, Error,
});
const button = input.__mbgPreviewButton;
for (const bytes of [
  [...Buffer.from('日本語', 'utf8')],
  [0x93, 0xfa, 0x96, 0x7b, 0x8c, 0xea], // Shift_JIS
  [0xff, 0xfe, 0xe5, 0x65, 0x2c, 0x67, 0x9e, 0x8a], // UTF-16LE BOM
]) {
  input.files = [{name: 'sample.txt', type: 'text/plain', size: bytes.length, bytes}];
  button.fire('click');
  const overlay = doc.body.children.find(node => node.attributes.role === 'dialog');
  const body = overlay.children[1];
  assert.equal(body.children.find(node => node.tagName === 'pre').textContent, '日本語');
  overlay.children[0].children.find(node => node.textContent === '閉じる').fire('click');
}
console.log('UTF-8, Shift_JIS and UTF-16 text render correctly.');
