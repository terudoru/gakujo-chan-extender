import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import vm from 'node:vm';

const source = await readFile(process.argv[2], 'utf8');
const flush = async () => { for (let i = 0; i < 20; i++) await new Promise(r => setImmediate(r)); };
class Element {
  constructor(tag, doc) { this.tagName = tag; this.ownerDocument = doc; this.children = []; this.style = {}; this.listeners = {}; this.attributes = {}; this.isConnected = true; }
  append(...nodes) { nodes.forEach(node => this.appendChild(node)); }
  appendChild(node) { this.children.push(node); node.parentNode = this; return node; }
  remove() { this.isConnected = false; if (this.parentNode) this.parentNode.children = this.parentNode.children.filter(n => n !== this); }
  setAttribute(key, value) { this.attributes[key] = value; }
  addEventListener(key, fn) { (this.listeners[key] ||= []).push(fn); }
  removeEventListener(key, fn) { this.listeners[key] = (this.listeners[key] || []).filter(x => x !== fn); }
  fire(key) { for (const fn of this.listeners[key] || []) fn({target: this}); }
  focus() {}
}
const doc = {createElement: tag => new Element(tag, doc), querySelectorAll: () => []};
doc.body = new Element('body', doc);
const timers = new Map(); let timerId = 0;
const window = {document: doc, location: {origin: 'https://gakujo.iess.niigata-u.ac.jp', href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/page'},
  setTimeout(fn) { timers.set(++timerId, fn); return timerId; }, clearTimeout(id) { timers.delete(id); },
  setInterval() { return ++timerId; }, clearInterval() {}, addEventListener() {}, removeEventListener() {}};
window.top = window; doc.defaultView = window;
class FileReader {
  readAsText(file) { file.text().then(result => {this.result = result; this.onload();}); }
  readAsArrayBuffer(file) { file.arrayBuffer().then(result => {this.result = result; this.onload();}); }
  abort() { if (this.onabort) this.onabort(); }
}
class DOMParser {
  parseFromString(text) {
    const paragraphs = [...text.matchAll(/<w:p(?:\s[^>]*)?>([\s\S]*?)<\/w:p>/g)].map(match => ({
      getElementsByTagNameNS(_, name) {
        return name === 't' ? [...match[1].matchAll(/<w:t>([\s\S]*?)<\/w:t>/g)].map(x => ({textContent:x[1]})) : [];
      },
    }));
    return {getElementsByTagName: () => [], getElementsByTagNameNS: (_, name) => name === 'p' ? paragraphs : []};
  }
}
let calls = [], body = [], type = 'text/plain', disposition = '', declaredLength = null, stall = false;
function fetch(url, options) {
  calls.push({url, options});
  if (stall) return new Promise((_, reject) => options.signal.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), {name:'AbortError'}))));
  const chunks = [...body];
  return Promise.resolve({ok: true, url,
    headers: {get(name) { return ({'content-type': type, 'content-disposition': disposition, 'content-length': declaredLength})[name] || null; }},
    body: {getReader: () => ({read: async () => chunks.length ? {done: false, value: chunks.shift()} : {done: true}})}});
}
vm.runInNewContext(source, {window, document: doc, FileReader, fetch, URL, URLSearchParams,
  AbortController, File, Blob, Uint8Array, DataView, ArrayBuffer, Promise, Math, Number, Error,
  DOMParser, TextDecoder});
const request = {url:'https://gakujo.iess.niigata-u.ac.jp/campusweb/file.txt', method:'GET', fileName:'sample.txt', formFields:{}};
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, url:'https://evil.invalid/file.txt'}), false);
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, method:'DELETE'}), false);
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, formFields:{_eventId:'submit'}}), false);
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, formFields:{_eventId_download:'1', _eventId_reset:'1'}}), false);
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, formFields:{_eventId:'downloadAndDelete'}}), false);
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, url:'https://gakujo.iess.niigata-u.ac.jp/campusweb/page', formFields:{}}), false);
assert.equal(calls.length, 0);
body = [new TextEncoder().encode('safe content')];
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW(request), true);
await flush();
assert.equal(calls.length, 1);
assert.equal(calls[0].options.credentials, 'same-origin');
assert.equal(calls[0].options.redirect, 'error');
const dialog = doc.body.children.find(e => e.attributes.role === 'dialog');
assert.ok(dialog);
const pre = dialog.children[1].children.find(e => e.tagName === 'pre');
assert.equal(pre.textContent, 'safe content');
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
assert.equal(doc.body.children.length, 0);
assert.equal(timers.size, 0);

body = [...new TextEncoder().encode('<html>login</html>')].map(c => Uint8Array.of(c));
type = 'application/octet-stream';
window.__MBG_OPEN_REMOTE_PREVIEW(request);
await flush();
assert.match(doc.body.children.find(e => e.attributes.role === 'dialog').children[0].textContent, /ページ/);
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();

declaredLength = String(64 * 1024 * 1024 + 1);
window.__MBG_OPEN_REMOTE_PREVIEW(request);
await flush();
assert.match(doc.body.children.find(e => e.attributes.role === 'dialog').children[0].textContent, /大きすぎ/);
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
assert.equal(timers.size, 0);

declaredLength = null;
type = 'text/plain'; disposition = 'attachment; filename="sample.txt"';
body = [new TextEncoder().encode('POST attachment')];
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request,
  url:'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
  method:'POST', formFields:{_eventId:'download', fileId:'42'}}), true);
await flush();
assert.equal(calls.at(-1).options.method, 'POST');
assert.equal(new URLSearchParams(calls.at(-1).options.body).get('fileId'), '42');
assert.equal(doc.body.children.find(e => e.attributes.role === 'dialog').children[1].children.find(e => e.tagName === 'pre').textContent, 'POST attachment');
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();

stall = true;
window.__MBG_OPEN_REMOTE_PREVIEW(request);
const signal = calls.at(-1).options.signal;
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
await flush();
assert.equal(signal.aborted, true);
assert.equal(doc.body.children.length, 0);
stall = false;

const JSZip = createRequire(import.meta.url)('../assets/js/upload_compression/jszip.min.js');
window.JSZip = JSZip;
window['__MBG_UPLOAD_LIBRARY_READY_preview-office'] = true;
let zip = new JSZip();
zip.file('word/document.xml', '<w:document><w:p><w:t>Office sample</w:t></w:p></w:document>');
body = [await zip.generateAsync({type:'uint8array'})];
disposition = 'attachment; filename="sample.docx"';
window.__MBG_OPEN_REMOTE_PREVIEW({...request, url:request.url.replace('file.txt', 'file.docx')});
await flush();
const office = doc.body.children.find(e => e.attributes.role === 'dialog');
assert.equal(office.children[1].children.find(e => e.tagName === 'pre').textContent, 'Office sample');
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();

zip = new JSZip();
zip.file('word/document.xml', 'a'.repeat(4 * 1024 * 1024 + 1));
body = [await zip.generateAsync({type:'uint8array', compression:'DEFLATE'})];
window.__MBG_OPEN_REMOTE_PREVIEW({...request, url:request.url.replace('file.txt', 'file.docx')});
await flush();
assert.match(doc.body.children.find(e => e.attributes.role === 'dialog').children[1].children[0].textContent, /大きすぎ/);
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
assert.equal(timers.size, 0);
console.log('Remote preview rejects unsafe requests, closes and bounds responses.');
