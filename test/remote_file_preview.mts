import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import vm from 'node:vm';

const source: any = await readFile(process.argv[2], 'utf8');
const flush: any = async () => { for (let i: any = 0; i < 20; i++) await new Promise((r: any) => setImmediate(r)); };
class Element {
  [key: string]: any;
  constructor(tag: any, doc: any) { this.tagName = tag; this.ownerDocument = doc; this.children = []; this.style = {}; this.listeners = {}; this.attributes = {}; this.isConnected = true; }
  append(...nodes: any[]) { nodes.forEach((node: any) => this.appendChild(node)); }
  appendChild(node: any) { this.children.push(node); node.parentNode = this; return node; }
  remove() { this.isConnected = false; if (this.parentNode) this.parentNode.children = this.parentNode.children.filter((n: any) => n !== this); }
  setAttribute(key: any, value: any) { this.attributes[key] = value; }
  addEventListener(key: any, fn: any) { (this.listeners[key] ||= []).push(fn); }
  removeEventListener(key: any, fn: any) { this.listeners[key] = (this.listeners[key] || []).filter((x: any) => x !== fn); }
  fire(key: any) { for (const fn of this.listeners[key] || []) fn({target: this}); }
  focus() {}
}
const doc: any = {createElement: (tag: any) => new Element(tag, doc), querySelectorAll: () => []};
doc.body = new Element('body', doc);
const timers: any = new Map(); let timerId: any = 0;
const window: any = {document: doc, location: {origin: 'https://gakujo.iess.niigata-u.ac.jp', href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/page'},
  setTimeout(fn: any) { timers.set(++timerId, fn); return timerId; }, clearTimeout(id: any) { timers.delete(id); },
  setInterval() { return ++timerId; }, clearInterval() {}, addEventListener() {}, removeEventListener() {}};
window.top = window; doc.defaultView = window;
class FileReader {
  [key: string]: any;
  readAsText(file: any) { file.text().then((result: any) => {this.result = result; this.onload();}); }
  readAsArrayBuffer(file: any) { file.arrayBuffer().then((result: any) => {this.result = result; this.onload();}); }
  abort() { if (this.onabort) this.onabort(); }
}
class DOMParser {
  [key: string]: any;
  parseFromString(text: any) {
    const paragraphs: any = [...text.matchAll(/<w:p(?:\s[^>]*)?>([\s\S]*?)<\/w:p>/g)].map((match: any) => ({
      getElementsByTagNameNS(_: any, name: any) {
        return name === 't' ? [...match[1].matchAll(/<w:t>([\s\S]*?)<\/w:t>/g)].map((x: any) => ({textContent:x[1]})) : [];
      },
    }));
    return {getElementsByTagName: () => [], getElementsByTagNameNS: (_: any, name: any) => name === 'p' ? paragraphs : []};
  }
}
let previewFileSize: number | undefined;
class PreviewFile extends File {
  get size() { return previewFileSize ?? super.size; }
}
let calls: any = [], body: any = [], type: any = 'text/plain', disposition: any = '', declaredLength: any = null, stall: any = false;
function fetch(url: any, options: any) {
  calls.push({url, options});
  if (stall) return new Promise((_: any, reject: any) => options.signal.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), {name:'AbortError'}))));
  const chunks: any = [...body];
  return Promise.resolve({ok: true, url,
    headers: {get(name: any) { return ({'content-type': type, 'content-disposition': disposition, 'content-length': declaredLength})[name] || null; }},
    body: {getReader: () => ({read: async () => chunks.length ? {done: false, value: chunks.shift()} : {done: true}})}});
}
vm.runInNewContext(source, {window, document: doc, FileReader, fetch, URL, URLSearchParams,
  AbortController, File: PreviewFile, Blob, Uint8Array, DataView, ArrayBuffer, Promise, Math, Number, Error,
  DOMParser, TextDecoder});
const request: any = {url:'https://gakujo.iess.niigata-u.ac.jp/campusweb/file.txt', method:'GET', fileName:'sample.txt', formFields:{}};
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, url:'https://evil.invalid/file.txt'}), false);
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, method:'DELETE'}), false);
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, formFields:{_eventId:'submit'}}), false);
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, formFields:{_eventId_download:'1', _eventId_reset:'1'}}), false);
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, formFields:{_eventId:'downloadAndDelete'}}), false);
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request, url:'https://gakujo.iess.niigata-u.ac.jp/campusweb/page', formFields:{}}), false);
assert.equal(calls.length, 0);
body = [new TextEncoder().encode('safe content')];
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW(request), true);
assert.equal(window.__MBG_PREVIEW_NAVIGATE('back'), true);
assert.equal(doc.body.children.find((e: any) => e.attributes.role === 'dialog').style.display, 'none');
await flush();
assert.equal(calls.length, 1);
assert.equal(calls[0].options.credentials, 'same-origin');
assert.equal(calls[0].options.redirect, 'error');
const dialog: any = doc.body.children.find((e: any) => e.attributes.role === 'dialog');
assert.ok(dialog);
assert.equal(dialog.style.display, 'none', 'fetch completion must not reopen a hidden preview');
assert.equal(window.__MBG_PREVIEW_NAVIGATE('forward'), true);
assert.equal(dialog.style.display, 'flex');
const pre: any = dialog.children[1].children.find((e: any) => e.tagName === 'pre');
assert.equal(pre.textContent, 'safe content');
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
assert.equal(doc.body.children.length, 0);
assert.equal(timers.size, 0);

body = [...new TextEncoder().encode('<html>login</html>')].map((c: any) => Uint8Array.of(c));
type = 'application/octet-stream';
window.__MBG_OPEN_REMOTE_PREVIEW(request);
await flush();
assert.match(doc.body.children.find((e: any) => e.attributes.role === 'dialog').children[0].textContent, /ページ/);
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();

const pdfRequest = {...request, url: request.url.replace('file.txt', 'file.pdf'), fileName: 'sample.pdf'};
body = [new TextEncoder().encode('%PDF-1.7\n')];
declaredLength = String(512 * 1024 * 1024 + 1);
window.__MBG_OPEN_REMOTE_PREVIEW(pdfRequest);
await flush();
assert.match(doc.body.children.find((e: any) => e.attributes.role === 'dialog').children[0].textContent, /大きすぎ/);
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
assert.equal(timers.size, 0);

declaredLength = null;
body = [{byteLength: 512 * 1024 * 1024 + 1}];
window.__MBG_OPEN_REMOTE_PREVIEW(pdfRequest);
await flush();
assert.equal(calls.at(-1).options.signal.aborted, true);
assert.match(doc.body.children.find((e: any) => e.attributes.role === 'dialog').children[0].textContent, /大きすぎ/);
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();

body = [new TextEncoder().encode('%PDF-1.7\n')];
const libraryRequests: string[] = [];
window.MbgUploadCompression = {postMessage: (message: string) => libraryRequests.push(message)};
// Declare large sizes while retaining only the small PDF header in memory.
for (const size of [64 * 1024 * 1024 + 1, 512 * 1024 * 1024]) {
  declaredLength = String(size); previewFileSize = size;
  const before = libraryRequests.length;
  window.__MBG_OPEN_REMOTE_PREVIEW(pdfRequest);
  await flush();
  assert.equal(libraryRequests.length, before + 1, `PDF preview accepts ${size} bytes`);
  assert.equal(libraryRequests.at(-1), 'preview');
  window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
  assert.equal(timers.size, 0);
}
declaredLength = null; previewFileSize = 512 * 1024 * 1024 + 1;
window.__MBG_OPEN_REMOTE_PREVIEW(pdfRequest);
await flush();
assert.match(doc.body.children.find((e: any) => e.attributes.role === 'dialog').children[1].children[0].textContent, /大きすぎ/);
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
delete window.MbgUploadCompression;

body = [new TextEncoder().encode('bounded preview')];
for (const [name, mime, limit] of [
  ['sample.png', 'image/png', 64],
  ['sample.pdf', 'image/png', 64],
  ['sample.png', 'application/pdf', 64],
  ['sample.mp4', 'video/mp4', 64],
  ['sample.docx', 'application/octet-stream', 32],
  ['sample.txt', 'text/plain', 4],
] as const) {
  type = mime; previewFileSize = limit * 1024 * 1024 + 1;
  window.__MBG_OPEN_REMOTE_PREVIEW({...request, url: request.url.replace('file.txt', name), fileName: name});
  await flush();
  const preview = doc.body.children.find((e: any) => e.attributes.role === 'dialog');
  assert.match(preview.children[0].textContent + (preview.children[1]?.children[0]?.textContent || ''), /大きすぎ/, name);
  window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
}
previewFileSize = undefined;
assert.equal(timers.size, 0);

type = 'text/plain'; disposition = 'attachment; filename="sample.txt"';
body = [new TextEncoder().encode('POST attachment')];
assert.equal(window.__MBG_OPEN_REMOTE_PREVIEW({...request,
  url:'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
  method:'POST', formFields:{_eventId:'download', fileId:'42'}}), true);
await flush();
assert.equal(calls.at(-1).options.method, 'POST');
assert.equal(new URLSearchParams(calls.at(-1).options.body).get('fileId'), '42');
assert.equal(doc.body.children.find((e: any) => e.attributes.role === 'dialog').children[1].children.find((e: any) => e.tagName === 'pre').textContent, 'POST attachment');
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();

stall = true;
window.__MBG_OPEN_REMOTE_PREVIEW(request);
const signal: any = calls.at(-1).options.signal;
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
await flush();
assert.equal(signal.aborted, true);
assert.equal(doc.body.children.length, 0);
stall = false;

const JSZip: any = createRequire(import.meta.url)('../assets/js/upload_compression/jszip.min.js');
window.JSZip = JSZip;
window['__MBG_UPLOAD_LIBRARY_READY_preview-office'] = true;
let zip: any = new JSZip();
zip.file('word/document.xml', '<w:document><w:p><w:t>Office sample</w:t></w:p></w:document>');
body = [await zip.generateAsync({type:'uint8array'})];
disposition = 'attachment; filename="sample.docx"';
window.__MBG_OPEN_REMOTE_PREVIEW({...request, url:request.url.replace('file.txt', 'file.docx')});
await flush();
const office: any = doc.body.children.find((e: any) => e.attributes.role === 'dialog');
assert.equal(office.children[1].children.find((e: any) => e.tagName === 'pre').textContent, 'Office sample');
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();

zip = new JSZip();
zip.file('word/document.xml', 'a'.repeat(4 * 1024 * 1024 + 1));
body = [await zip.generateAsync({type:'uint8array', compression:'DEFLATE'})];
window.__MBG_OPEN_REMOTE_PREVIEW({...request, url:request.url.replace('file.txt', 'file.docx')});
await flush();
assert.match(doc.body.children.find((e: any) => e.attributes.role === 'dialog').children[1].children[0].textContent, /大きすぎ/);
window.__MBG_ACTIVE_UPLOAD_PREVIEW.close();
assert.equal(timers.size, 0);
console.log('Remote preview rejects unsafe requests, closes and bounds responses.');
