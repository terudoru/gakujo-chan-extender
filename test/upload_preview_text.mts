import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

class Element {
  [key: string]: any;
  constructor(tag: any, doc: any) { this.tagName = tag; this.ownerDocument = doc; this.children = []; this.style = {}; this.listeners = {}; this.attributes = {}; this.isConnected = true; }
  append(...nodes: any[]) { nodes.forEach((node: any) => this.appendChild(node)); }
  appendChild(node: any) { this.children.push(node); node.parentNode = this; return node; }
  insertBefore(node: any) { return this.appendChild(node); }
  setAttribute(key: any, value: any) { this.attributes[key] = value; }
  addEventListener(key: any, fn: any) { (this.listeners[key] ||= []).push(fn); }
  removeEventListener(key: any, fn: any) { this.listeners[key] = (this.listeners[key] || []).filter((x: any) => x !== fn); }
  fire(key: any) { (this.listeners[key] || []).forEach((fn: any) => fn({target: this})); }
  getBoundingClientRect() { return {left: 0, top: 0}; }
  remove() { this.isConnected = false; if (this.parentNode) this.parentNode.children = this.parentNode.children.filter((x: any) => x !== this); }
  focus() {}
}
const doc: any = {createElement: (tag: any) => new Element(tag, doc)};
doc.body = new Element('body', doc);
const input: any = new Element('input', doc); doc.body.appendChild(input);
doc.querySelectorAll = (selector: any) => selector === 'input[type="file"]' ? [input] : [];
const viewportListeners: any = new Set();
const window: any = {document: doc, location: {origin: 'https://example.invalid'},
  visualViewport: {scale: 0.4, width: 320, height: 500, addEventListener(_: any, fn: any) {viewportListeners.add(fn);}, removeEventListener(_: any, fn: any) {viewportListeners.delete(fn);}},
  setInterval() {return 1;}, clearInterval() {}, addEventListener() {}, removeEventListener() {}};
window.top = window; doc.defaultView = window;
class FileReader {
  [key: string]: any;
  readAsArrayBuffer(file: any) { this.result = Uint8Array.from(file.bytes).buffer; this.onload(); }
  abort() {}
}
vm.runInNewContext(await readFile(process.argv[2], 'utf8'), {
  window, document: doc, FileReader, TextDecoder, Uint8Array, DataView, ArrayBuffer, Promise, Math, Number, Error,
});
const button: any = input.__mbgPreviewButton;
for (const bytes of [
  [...Buffer.from('日本語', 'utf8')],
  [0x93, 0xfa, 0x96, 0x7b, 0x8c, 0xea], // Shift_JIS
  [0xff, 0xfe, 0xe5, 0x65, 0x2c, 0x67, 0x9e, 0x8a], // UTF-16LE BOM
]) {
  input.files = [{name: 'sample.txt', type: 'text/plain', size: bytes.length, bytes}];
  button.fire('click');
  const overlay: any = doc.body.children.find((node: any) => node.attributes.role === 'dialog');
  const body: any = overlay.children[1];
  const pre: any = body.children.find((node: any) => node.tagName === 'pre');
  assert.equal(pre.textContent, '日本語');
  assert.equal(pre.style.zoom, '2.5', 'text remains readable on a scaled desktop-width page');
  window.visualViewport.scale = 1;
  for (const listener of viewportListeners) listener();
  assert.equal(pre.style.zoom, '1', 'text adapts when the page scale changes');
  window.visualViewport.scale = 0.4;
  for (const listener of viewportListeners) listener();
  const bar: any = overlay.children[0];
  bar.children.find((node: any) => node.textContent === '拡大').fire('click');
  assert.equal(pre.style.fontSize, '120%');
  assert.equal(bar.children.find((node: any) => node.attributes['aria-label'] === '表示倍率').textContent, '120%');
  bar.children.find((node: any) => node.textContent === '縮小').fire('click');
  assert.equal(pre.style.fontSize, '100%');
  body.scrollLeft = body.scrollTop = 0;
  let prevented: any = false;
  body.listeners.wheel[0]({ctrlKey:true, deltaY:-10, clientX:40, clientY:40,
    cancelable:true, preventDefault(){prevented=true;}});
  assert.equal(prevented,true);
  assert.ok(parseFloat(pre.style.fontSize)>100,'Ctrl-wheel zooms text');
  overlay.children[0].children.find((node: any) => node.textContent === '閉じる').fire('click');
}
console.log('UTF-8, Shift_JIS and UTF-16 text render correctly.');
