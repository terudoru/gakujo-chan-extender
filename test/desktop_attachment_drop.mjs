import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

class Element {
  constructor(tag, doc) {
    this.tagName = tag;
    this.ownerDocument = doc;
    this.listeners = {};
    this.attributes = new Set();
    this.children = [];
    this.style = {};
    this.isConnected = true;
    this.type = tag;
    this.files = [];
    this.accept = '';
  }
  setAttribute(name) { this.attributes.add(name); }
  addEventListener(name, callback) { (this.listeners[name] ||= []).push(callback); }
  querySelector(selector) {
    return this.children.find(child => child.attributes.has(selector.slice(1, -1))) ?? null;
  }
  append(...children) { children.forEach(child => this.appendChild(child)); }
  appendChild(child) { child.parentNode = this; this.children.push(child); return child; }
  after(child) {
    const index = this.parentNode.children.indexOf(this);
    child.parentNode = this.parentNode;
    child.previousSibling = this;
    this.parentNode.children.splice(index + 1, 0, child);
  }
  matches(selector) { return selector === ':disabled' && this.disabled; }
  dispatchEvent(event) { for (const fn of this.listeners[event.type] || []) fn(event); }
}
class Transfer {
  files = [];
  items = {add: file => this.files.push(file)};
}
const doc = {
  documentElement: {},
  createElement: tag => new Element(tag, doc),
  addEventListener(...args) { root.addEventListener(...args); },
  querySelectorAll: () => [single, multi],
};
const root = new Element('body', doc);
const single = root.appendChild(doc.createElement('file'));
const multi = root.appendChild(doc.createElement('file'));
multi.multiple = true;
single.accept = multi.accept = '.pdf';
const view = {
  document: doc, frames: [], DataTransfer: Transfer,
  Event: class { constructor(type) { this.type = type; } },
  setInterval() { return 1; }, addEventListener() {},
};
doc.defaultView = view;
vm.runInNewContext(await readFile(process.argv[2], 'utf8'), {window: view});
const zones = root.children.filter(child => child.tagName === 'span').map(span =>
  span.querySelector('[data-mbg-attachment-drop]'));
assert.equal(zones.filter(Boolean).length, 2);
const files = ['1.pdf', '2.pdf'].map(name => new File(['payload'], name, {type:'application/pdf'}));
const other = new File(['x'], 'wrong.png', {type:'image/png'});
let events = [];
single.addEventListener('input', () => events.push('input'));
single.addEventListener('change', () => events.push('change'));
multi.addEventListener('change', () => events.push('multi'));

function drag(target, type, draggedFiles, types = ['Files'], items = []) {
  const event = {
    type, dataTransfer: {types, files: draggedFiles, items}, defaultPrevented: false,
    preventDefault() { this.defaultPrevented = true; },
    stopPropagation() {},
  };
  target.dispatchEvent(event);
  return event;
}

assert.equal(drag(zones[0], 'dragover', []).dataTransfer.dropEffect, 'copy');
assert.equal(drag(zones[0], 'drop', files).defaultPrevented, true);
assert.deepEqual(single.files, []);
assert.match(zones[0].children[1].textContent, /1つ/);
assert.equal(drag(zones[0], 'drop', [files[0]]).defaultPrevented, true);
assert.deepEqual(Array.from(single.files), [files[0]]);
assert.deepEqual(events, ['input', 'change']);
assert.equal(await single.files[0].text(), 'payload');

assert.equal(drag(zones[0], 'drop', [other]).defaultPrevented, true);
assert.deepEqual(Array.from(single.files), [files[0]]);
assert.match(zones[0].children[1].textContent, /形式/);
assert.equal(drag(zones[0], 'drop', [], ['text/uri-list']).defaultPrevented, false);
assert.equal(drag(root, 'drop', [files[1]]).defaultPrevented, true);
assert.deepEqual(Array.from(single.files), [files[0]]);
assert.deepEqual(events, ['input', 'change']);

drag(zones[1], 'drop', [files[0]]);
drag(zones[1], 'drop', [files[1]]);
assert.deepEqual(Array.from(multi.files), files);
drag(zones[1], 'drop', files, ['Files'], [{webkitGetAsEntry: () => ({isDirectory:true})}]);
assert.deepEqual(Array.from(multi.files), files);
single.disabled = true;
assert.equal(drag(zones[0], 'dragover', []).dataTransfer.dropEffect, 'none');
drag(zones[0], 'drop', [files[1]]);
assert.deepEqual(Array.from(single.files), [files[0]]);
view.__MBG_ASSIGNMENT_ATTACHMENT.setShared(true);
assert.equal(root.children.length, 4, 're-injection does not duplicate targets');
assert.equal(zones[0].hidden, true);
assert.deepEqual(events, ['input', 'change', 'multi', 'multi']);
