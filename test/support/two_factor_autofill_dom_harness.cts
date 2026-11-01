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
let fieldsAvailable: any = !generatedTeardown;

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
  name: 'ninshoCode', type: 'password'
});
const controls: any = (spec.controls || [
  {tag: 'button', type: 'submit', text: '認証', ...(spec.formOverride ? {formaction: spec.formOverride} : {})}
]).map((attributes: any) => new FakeElement(attributes.tag, attributes));
const form: any = {
  getAttribute(name: any) { return name === 'action' ? (spec.formAction ?? null) : null; },
  querySelectorAll(selector: any) {
    const elements: any = [hidden, visible, ...controls];
    if (selector === 'button, input, a, [role="button"]') return elements;
    if (selector === 'button, input') {
      return elements.filter((element: any) => ['BUTTON', 'INPUT'].includes(element.tagName));
    }
    return [];
  }
};
const document: any = {
  body: {innerText: '', textContent: ''},
  location: new URL(process.argv[4]),
  baseURI: spec.baseUri || process.argv[4],
  defaultView: null,
  querySelectorAll(selector: any) {
    if (selector === 'iframe, frame') return [];
    if (selector === 'input[name="ninshoCode"]') {
      return fieldsAvailable ? [hidden, visible] : [];
    }
    return [];
  }
};
const window: any = {
  document,
  Event: FakeEvent,
  getComputedStyle(element: any) {
    return {
      display: element.attributes.display || 'block',
      visibility: 'visible',
      opacity: '1'
    };
  },
  clearTimeout(id: any) { activeTimers.delete(id); },
  setTimeout(callback: any) {
    const id: any = nextTimerId++;
    if (generatedTeardown) {
      activeTimers.set(id, callback);
    } else {
      callback();
    }
    return id;
  },
  sessionStorage: {
    getItem(key: any) { return sessionValues.get(key) || null; },
    setItem(key: any, value: any) { sessionValues.set(key, String(value)); }
  },
  MoreBetterGakujoLoginAutofill: {
    postMessage(payload: any) { reports.push(JSON.parse(payload)); }
  }
};
window.window = window;
document.defaultView = window;
for (const element of [hidden, visible, ...controls]) {
  element.ownerDocument = document;
  element.form = form;
}

const context: any = {
  window,
  document,
  URL,
  location: new URL(process.argv[4]),
  Event: FakeEvent,
  console: {log(message: any) { consoleLogs.push(message); }}
};
vm.runInNewContext(generatedScript, context);
if (generatedTeardown) {
  vm.runInNewContext(generatedTeardown, context);
  fieldsAvailable = true;
  for (const callback of [...activeTimers.values()]) callback();
}

process.stdout.write(JSON.stringify({
  hiddenValue: hidden.value,
  visibleValue: visible.value,
  clickCount,
  clickedNames,
  sessionValues: Object.fromEntries(sessionValues),
  reports,
  consoleLogs
}));
