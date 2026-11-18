import type {} from 'node:fs';
const vm: any = require('node:vm');
const generatedScript: any = require('node:fs').readFileSync(0, 'utf8');
const spec: any = JSON.parse(process.argv[2]);
const reports: any = [];
const consoleLogs: any = [];
const sessionValues: any = new Map();
let clickCount: any = 0;
const clickedNames: any = [];
let requestSubmitCount: any = 0;
let formSubmitCount: any = 0;
let nextTimerId: any = 1;
const activeTimers: any = new Map();
const activeIntervals: any = new Map();
let authenticatedControlScanCount: any = 0;
let now = 0;
const submissions: any[] = [];
const checkpoints: any[] = [];

class FakeEvent {
  [key: string]: any;
  constructor(type: any, options: any) {
    this.type = type;
    Object.assign(this, options || {});
  }
}

class FakeElement {
  [key: string]: any;
  constructor(tag: any, attributes: any) {
    this.tagName = tag.toUpperCase();
    this.attributes = {};
    for (const [name, value] of Object.entries(attributes || {})) {
      if (name !== 'tag' && name !== 'text') {
        this.attributes[name] = String(value);
      }
    }
    this.id = this.attributes.id || '';
    this.value = this.attributes.value || '';
    this.innerText = attributes.text || '';
    this.textContent = this.innerText;
    this.ownerDocument = null;
    this.parentForm = null;
    this.children = [];
  }

  getAttribute(name: any) {
    return Object.prototype.hasOwnProperty.call(this.attributes, name)
      ? this.attributes[name]
      : null;
  }

  setAttribute(name: any, value: any) {
    this.attributes[name] = String(value);
    if (name === 'id') {
      this.id = String(value);
    }
  }

  getClientRects() {
    return this.isConnected && this.ownerDocument.defaultView?.document === this.ownerDocument
      ? [{}] : [];
  }

  get isConnected(): boolean {
    if (this.tagName === 'FORM') return this.ownerDocument?.currentForm === this;
    return !!this.parentForm?.isConnected && this.parentForm.children.includes(this);
  }

  get form() {
    const id = this.getAttribute('form');
    if (id === null) return this.parentForm;
    const candidate = this.ownerDocument?.currentForm;
    return candidate && candidate.id === id ? candidate : null;
  }

  closest(selector: any) {
    if (selector === 'form') return this.parentForm;
    if (selector === 'tr, p, div, li, label' && this.attributes.rowText) {
      return {
        innerText: this.attributes.rowText,
        textContent: this.attributes.rowText
      };
    }
    if (selector === 'label' && this.attributes.labelText) {
      return {
        innerText: this.attributes.labelText,
        textContent: this.attributes.labelText
      };
    }
    return null;
  }

  focus() {}
  blur() {}
  dispatchEvent() { return true; }
  click() {
    clickCount += 1;
    clickedNames.push(this.getAttribute('name') || this.getAttribute('id') || '');
    if (this.getAttribute('type') === 'submit') this.form?.dispatchSubmit();
  }

  querySelectorAll(selector: any) {
    if (selector === 'input') {
      return this.children.filter((element: any) => element.tagName === 'INPUT');
    }
    if (selector === 'button, input, a, [role="button"]' ||
        selector === 'a, button, input, [role="button"], img' ||
        selector === 'a, button, input, [role="button"], img, #logout') {
      return this.children.filter((element: any) =>
        ['BUTTON', 'INPUT', 'A', 'IMG'].includes(element.tagName) ||
        element.getAttribute('role') === 'button' ||
        (selector.includes('#logout') && element.id === 'logout')
      );
    }
    return [];
  }
}

function makeDocument(bodyText = ''): any {
  return {
    URL: spec.url || 'https://gakujo.iess.niigata-u.ac.jp/campussmart.do',
    body: {innerText: bodyText, textContent: bodyText},
    documentElement: {},
    currentForm: null,
    frames: [],
    addEventListener() {},
    removeEventListener() {},
    querySelector() { return null; },
    querySelectorAll(selector: string) {
      if (selector.startsWith('a, button, input, [role="button"], img')) {
        authenticatedControlScanCount += 1;
      }
      if (selector === 'iframe, frame') return this.frames;
      return this.currentForm?.querySelectorAll(selector) || [];
    }
  };
}

function replaceFields(form: any, only?: number) {
  form.children = spec.elements.map((attrs: any, index: number) => {
    const previous = form.children[index];
    if (only !== undefined && index !== only) return previous;
    if (previous) previous.parentForm = null;
    const child = new FakeElement(attrs.tag, attrs);
    child.ownerDocument = form.ownerDocument;
    child.parentForm = form;
    return child;
  });
}

function installForm(doc: any, id: string) {
  const form = new FakeElement('form', {id});
  form.ownerDocument = doc;
  doc.currentForm = form;
  replaceFields(form);
  const events = new EventTarget();
  events.addEventListener('submit', event => {
    event.preventDefault();
    submissions.push({id, at: now, values: form.querySelectorAll('input').map(input => input.value)});
  });
  form.dispatchSubmit = () => {
    if (form.getClientRects().length) events.dispatchEvent(new Event('submit', {cancelable: true}));
  };
  form.requestSubmit = () => { requestSubmitCount += 1; form.dispatchSubmit(); };
  form.submit = () => { formSubmitCount += 1; };
  return form;
}

const document = makeDocument();

const window: any = {
  document,
  CSS: null,
  HTMLInputElement: null,
  InputEvent: FakeEvent,
  Event: FakeEvent,
  KeyboardEvent: FakeEvent,
  sessionStorage: {
    getItem(key: any) { return sessionValues.get(key) || null; },
    setItem(key: any, value: any) { sessionValues.set(key, String(value)); },
    removeItem(key: any) { sessionValues.delete(key); }
  },
  getComputedStyle(element: any) {
    return {
      display: element.getAttribute('display') || 'block',
      visibility: element.getAttribute('visibility') || 'visible',
      opacity: element.getAttribute('opacity') || '1'
    };
  },
  clearTimeout(id: any) { activeTimers.delete(id); },
  setTimeout(callback: any, delay: number) {
    const id: any = nextTimerId++;
    if (spec.deferTimers || spec.steps) {
      activeTimers.set(id, {callback, due: now + delay});
    } else {
      callback();
    }
    return id;
  },
  clearInterval(id: any) { activeIntervals.delete(id); },
  setInterval(callback: any) {
    const id: any = nextTimerId++;
    activeIntervals.set(id, callback);
    return id;
  },
  MoreBetterGakujoLoginAutofill: {
    postMessage(payload: any) { reports.push(JSON.parse(payload)); }
  }
};
window.window = window;
document.defaultView = window;
let loginDocument = document;
let frameWindow: any;
if (spec.frameBodyText != null) {
  loginDocument = makeDocument(spec.frameBodyText);
  frameWindow = {...window, document: loginDocument, frames: []};
  loginDocument.defaultView = frameWindow;
  document.frames.push({contentWindow: frameWindow});
}
const form = installForm(loginDocument, 'login-form');
const elements = form.children;
if (spec.steps) {
  Object.defineProperty(window, 'frames', {get: () => document.frames.map(frame => frame.contentWindow)});
  window.MutationObserver = class {
    root: any;
    notify: () => void;
    constructor(notify: () => void) { this.notify = notify; }
    observe(root: any) { this.root = root; root.notify = this.notify; }
    disconnect() { delete this.root.notify; }
    takeRecords() { return []; }
  };
}

function advance(milliseconds: number) {
  const end = now + milliseconds;
  for (;;) {
    const next = [...activeTimers].sort((a, b) => a[1].due - b[1].due)[0];
    if (!next || next[1].due > end) break;
    now = next[1].due;
    activeTimers.delete(next[0]);
    next[1].callback();
  }
  now = end;
}

const context: any = {
  window,
  document,
  URL,
  location: new URL(spec.url ||
    'https://gakujo.iess.niigata-u.ac.jp/campussmart.do'),
  console: {log(message: any) { consoleLogs.push(message); }}
};
vm.runInNewContext(generatedScript, context);
for (let tick: any = 0; tick < (spec.monitorTicks || 0); tick += 1) {
  for (const callback of [...activeIntervals.values()]) callback();
}
if (spec.simulateAuthenticatedTimeout) {
  delete window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY;
  const logout: any = new FakeElement('button', {text: 'ログアウト'});
  logout.ownerDocument = document;
  logout.parentForm = form;
  form.children = [logout];
  for (const callback of [...activeIntervals.values()]) callback();

  for (const element of elements) {
    element.value = '';
  }
  form.children = elements;
  for (const callback of [...activeIntervals.values()]) callback();
}
for (const step of spec.steps || []) {
  if (typeof step === 'number') { advance(step); continue; }
  switch (step) {
    case 'notify': document.documentElement.notify(); break;
    case 'replace-form': installForm(loginDocument, 'current'); break;
    case 'remove-form': loginDocument.currentForm = null; break;
    case 'replace-fields': replaceFields(loginDocument.currentForm); break;
    case 'replace-username': replaceFields(loginDocument.currentForm, 0); break;
    case 'replace-password': replaceFields(loginDocument.currentForm, 1); break;
    case 'disown-username': elements[0].setAttribute('form', 'missing'); break;
    case 'disown-password': elements[1].setAttribute('form', 'missing'); break;
    case 'remove-frame':
      document.frames = [];
      loginDocument.defaultView = null;
      loginDocument = document;
      break;
    case 'navigate-frame':
      loginDocument.defaultView = null;
      loginDocument = makeDocument();
      frameWindow.document = loginDocument;
      loginDocument.defaultView = frameWindow;
      break;
    case 'show-error': loginDocument.body.innerText = 'Login failed'; break;
    case 'clear-error': loginDocument.body.innerText = ''; break;
    case 'checkpoint':
      checkpoints.push({
        attempts: [...sessionValues.keys()].filter(key => key.startsWith('MBG_LOGIN_AUTOFILL_SUBMIT_COUNT:')).length,
        submittedKey: window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY || null,
        submitReports: reports.filter(report => report.event === 'submit').length
      });
      break;
    default: throw new Error('Unknown lifecycle step: ' + step);
  }
}
if (spec.teardownScript) {
  vm.runInNewContext(spec.teardownScript, context);
}
const pendingTimers = activeTimers.size;
advance(10000);

process.stdout.write(JSON.stringify({
  elements: elements.map((element: any) => ({
    name: element.getAttribute('name'),
    value: element.value
  })),
  clickCount,
  clickedNames,
  submissions,
  checkpoints,
  pendingTimers,
  requestSubmitCount,
  formSubmitCount,
  authenticatedControlScanCount,
  submittedKey: window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY || null,
  sessionValues: Object.fromEntries(sessionValues),
  reports,
  consoleLogs
}));
