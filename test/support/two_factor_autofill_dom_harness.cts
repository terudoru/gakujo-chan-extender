import type {} from 'node:fs';
const vm: any = require('node:vm');
const generatedScript: any = process.argv[2];
const generatedTeardown: any = process.argv[3];
const spec: any = JSON.parse(process.argv[5] || '{}');
const reports: any = [];
const consoleLogs: any = [];
let clickCount: any = 0;
const clickedNames: any = [];
const sessionValues: any = new Map();
const activeTimers: any = new Map();
let nextTimerId: any = 1;
let fieldsAvailable: any = !generatedTeardown || spec.teardownAfterFill === 'true';

class FakeEvent {
  [key: string]: any;
  constructor(type: any, options: any) { this.type = type; Object.assign(this, options || {}); }
}

class FakeElement {
  [key: string]: any;
  constructor(tag: any, attributes: any) {
    this.tagName = tag.toUpperCase();
    this.attributes = {...attributes};
    this.value = '';
    this.type = attributes.type || '';
    this.innerText = attributes.text || '';
    this.textContent = this.innerText;
    this.ownerDocument = null;
    this.form = null;
  }
  getAttribute(name: any) { return this.attributes[name] ?? null; }
  setAttribute(name: any, value: any) { this.attributes[name] = String(value); }
  removeAttribute(name: any) { delete this.attributes[name]; }
  hasAttribute(name: any) { return Object.hasOwn(this.attributes, name); }
  getClientRects() { return this.attributes.display === 'none' ? [] : [{}]; }
  closest(selector: any) { return selector === 'form' ? this.form : null; }
  dispatchEvent() { return true; }
  focus() {}
  click() {
    clickCount += 1;
    clickedNames.push(this.getAttribute('name') || '');
  }
}

const hidden: any = new FakeElement('input', {
  name: 'ninshoCode', type: 'password', display: 'none'
});
const visible: any = new FakeElement('input', {
  name: 'ninshoCode', type: spec.inputType || 'password'
});
const controls: any = (spec.controls || [
  {tag: 'button', type: 'submit', text: '認証', ...(spec.formOverride ? {formaction: spec.formOverride} : {})}
]).map((attributes: any) => new FakeElement(attributes.tag, attributes));
function makeDocument(inputs: FakeElement[] = [], buttons: FakeElement[] = []) {
  const elements = [...inputs, ...buttons];
  const form = {
    getAttribute(name: string) { return name === 'action' ? (spec.formAction ?? null) : null; },
    querySelectorAll(selector: string) {
      if (selector === 'button, input, a, [role="button"]') return elements;
      if (selector === 'button, input') {
        return elements.filter(element => ['BUTTON', 'INPUT'].includes(element.tagName));
      }
      return [];
    }
  };
  const frames: FakeElement[] = [];
  const doc: any = {
    body: {innerText: '', textContent: ''},
    location: new URL(process.argv[4]),
    baseURI: spec.baseUri || process.argv[4],
    querySelectorAll(selector: string) {
      if (selector === 'iframe, frame') return frames;
      if (selector === 'input[name="ninshoCode"]') return fieldsAvailable ? inputs : [];
      if (selector === 'input[data-mbg-2fa-original-type]') {
        return inputs.filter(element => element.hasAttribute('data-mbg-2fa-original-type'));
      }
      return [];
    }
  };
  doc.defaultView = {
    document: doc,
    frameElement: null,
    getComputedStyle(element: FakeElement) {
      if (element.ownerDocument !== doc) throw new Error('Wrong owner window');
      return {
        display: element.attributes.display || 'block',
        visibility: element.attributes.visibility || 'visible',
        opacity: element.attributes.opacity || '1'
      };
    }
  };
  for (const element of elements) {
    element.ownerDocument = doc;
    element.form = form;
  }
  return doc;
}

function attachFrame(parent: any, child: any, attributes = {}) {
  const frame = new FakeElement('iframe', attributes);
  frame.ownerDocument = parent;
  frame.contentWindow = child.defaultView;
  child.defaultView.frameElement = frame;
  parent.querySelectorAll('iframe, frame').push(frame);
  return frame;
}

const codeDocument = makeDocument([hidden, visible], controls);
const inFrame = spec.inFrame === 'true' || !!spec.frameVisibility;
const document = inFrame ? makeDocument() : codeDocument;
const window = Object.assign(document.defaultView, {
  Event: FakeEvent,
  clearTimeout(id: any) { activeTimers.delete(id); },
  setTimeout(callback: any, delay: number) {
    const id: any = nextTimerId++;
    activeTimers.set(id, {callback, delay});
    return id;
  },
  sessionStorage: {
    getItem(key: any) { return sessionValues.get(key) || null; },
    setItem(key: any, value: any) { sessionValues.set(key, String(value)); }
  },
  MoreBetterGakujoLoginAutofill: {
    postMessage(payload: any) { reports.push(JSON.parse(payload)); }
  }
});
window.window = window;
if (spec.denySessionStorage) {
  Object.defineProperty(window, 'sessionStorage', {
    get() { throw new Error('storage denied'); }
  });
}
let outerFrame: FakeElement;
let later: FakeElement;
if (inFrame) {
  const inaccessible = new FakeElement('iframe', {});
  inaccessible.ownerDocument = document;
  inaccessible.contentWindow = {get document() { throw new Error('cross-origin'); }};
  document.querySelectorAll('iframe, frame').push(inaccessible);
  const nested = spec.inFrame === 'true';
  const outerDocument = nested ? makeDocument() : codeDocument;
  if (spec.hiddenError) {
    outerDocument.body.innerText = 'Invalid code';
    const location = new URL(process.argv[4]);
    sessionValues.set('MBG_2FA_AUTOFILL_SUBMIT_COUNT:' +
      location.origin + location.pathname + ':no-secret', '1');
  }
  outerFrame = attachFrame(document, outerDocument, {visibility: spec.frameVisibility});
  if (nested) attachFrame(outerDocument, codeDocument, {visibility: 'visible'});
  if (spec.laterFrame === 'true') {
    later = new FakeElement('input', {name: 'ninshoCode', type: 'password'});
    const submit = new FakeElement('button', {name: 'later', type: 'submit', text: 'Verify'});
    attachFrame(document, makeDocument([later], [submit]));
  }
}

function tick() {
  for (const [id, timer] of [...activeTimers]) {
    activeTimers.delete(id);
    timer.callback();
  }
}

const context: any = {
  window,
  document: window.document,
  URL,
  location: new URL(process.argv[4]),
  Event: FakeEvent,
  console: {log(message: any) { consoleLogs.push(message); }}
};
vm.runInNewContext(generatedScript, context);
let beforeReveal;
if (spec.revealAfterAttempts) {
  for (let attempt = 1; attempt < Number(spec.revealAfterAttempts); attempt++) tick();
  beforeReveal = {
    value: visible.value,
    type: visible.type,
    originalType: visible.getAttribute('data-mbg-2fa-original-type'),
    clickCount,
    sessionValues: Object.fromEntries(sessionValues),
    pendingDelays: [...activeTimers.values()].map(timer => timer.delay)
  };
  outerFrame.attributes.visibility = 'visible';
  tick();
}
const visibleTypeBeforeTeardown = visible.type;
const originalTypeBeforeTeardown = visible.getAttribute('data-mbg-2fa-original-type');
if (generatedTeardown) {
  vm.runInNewContext(generatedTeardown, context);
  fieldsAvailable = true;
  tick();
}

process.stdout.write(JSON.stringify({
  hiddenValue: hidden.value,
  visibleValue: visible.value,
  laterValue: later?.value,
  beforeReveal,
  hiddenType: hidden.type,
  visibleType: visible.type,
  visibleTypeBeforeTeardown,
  originalTypeBeforeTeardown,
  originalTypeAfterTeardown: visible.getAttribute('data-mbg-2fa-original-type'),
  activeTimerCount: activeTimers.size,
  clickCount,
  clickedNames,
  sessionValues: Object.fromEntries(sessionValues),
  reports,
  consoleLogs
}));
