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
    this.form = null;
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
    return [{}];
  }

  closest(selector: any) {
    if (selector === 'form') return this.form;
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

const form: any = new FakeElement('form', {id: 'login-form'});
const elements: any = spec.elements.map((attributes: any) =>
  new FakeElement(attributes.tag, attributes)
);
form.children = elements;

const document: any = {
  URL: spec.url || 'https://gakujo.iess.niigata-u.ac.jp/campussmart.do',
  body: {innerText: '', textContent: ''},
  defaultView: null,
  querySelector() { return null; },
  querySelectorAll(selector: any) {
    if (selector.startsWith('a, button, input, [role="button"], img')) {
      authenticatedControlScanCount += 1;
    }
    if (selector === 'iframe, frame') {
      return [];
    }
    return form.querySelectorAll(selector);
  }
};

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
  setTimeout(callback: any) {
    const id: any = nextTimerId++;
    if (spec.deferTimers) {
      activeTimers.set(id, callback);
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
form.ownerDocument = document;
form.requestSubmit = () => { requestSubmitCount += 1; };
form.submit = () => { formSubmitCount += 1; };
for (const element of elements) {
  element.ownerDocument = document;
  element.form = form;
}
if (spec.frameBodyText != null) {
  const frameDocument: any = {
    ...document,
    body: {innerText: spec.frameBodyText, textContent: spec.frameBodyText},
    querySelectorAll(selector: any) {
      return selector === 'iframe, frame' ? [] : form.querySelectorAll(selector);
    }
  };
  const frameWindow: any = {...window, document: frameDocument};
  frameDocument.defaultView = frameWindow;
  document.querySelectorAll = (selector: any) => selector === 'iframe, frame'
    ? [{contentWindow: frameWindow}]
    : [];
  form.ownerDocument = frameDocument;
  for (const element of elements) element.ownerDocument = frameDocument;
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
  form.children = [logout];
  for (const callback of [...activeIntervals.values()]) callback();

  for (const element of elements) {
    element.value = '';
  }
  form.children = elements;
  for (const callback of [...activeIntervals.values()]) callback();
}
if (spec.teardownScript) {
  vm.runInNewContext(spec.teardownScript, context);
}
for (let round: any = 0; round < 50 && activeTimers.size > 0; round += 1) {
  const callbacks: any = [...activeTimers.values()];
  activeTimers.clear();
  for (const callback of callbacks) callback();
}

process.stdout.write(JSON.stringify({
  elements: elements.map((element: any) => ({
    name: element.getAttribute('name'),
    value: element.value
  })),
  clickCount,
  clickedNames,
  requestSubmitCount,
  formSubmitCount,
  authenticatedControlScanCount,
  submittedKey: window.__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY || null,
  sessionValues: Object.fromEntries(sessionValues),
  reports,
  consoleLogs
}));
