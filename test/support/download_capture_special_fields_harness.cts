const vm = require('node:vm');
const fs = require('node:fs');
const buildScript = fs.readFileSync(process.argv[2], 'utf8');
const upgradeFromVersion19 = process.argv[3] && fs.readFileSync(process.argv[3], 'utf8') === 'upgrade';
const captured = [];
const listeners = new Map();

function listenersFor(type) {
  if (!listeners.has(type)) listeners.set(type, new Set());
  return listeners.get(type);
}

const document = {
  baseURI: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/page.do',
  location: {
    href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/page.do'
  },
  title: '',
  querySelectorAll() { return []; },
  addEventListener(type, handler) { listenersFor(type).add(handler); },
  removeEventListener(type, handler) { listenersFor(type).delete(handler); }
};

let oldHandlerCalls = 0;
function oldClickHandler() { oldHandlerCalls += 1; }

const window: any = {
  document,
  frames: [],
  location: {href: document.baseURI},
  MoreBetterGakujoDownloads: {
    postMessage(message) { captured.push(JSON.parse(message)); }
  }
};
window.window = window;
if (upgradeFromVersion19) {
  document.addEventListener('click', oldClickHandler);
  window.__MBG_DOWNLOAD_CAPTURE_VERSION = 19;
  window.__MBG_DOWNLOAD_CAPTURE_HANDLER = oldClickHandler;
  window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS = [document];
}

class FakeFormData {
  values: Map<string, string>;
  constructor(form) {
    this.values = new Map();
    for (const field of form.fields) {
      this.values.set(field.name, field.value);
    }
  }

  set(name, value) { this.values.set(name, value); }

  forEach(callback) {
    this.values.forEach((value, key) => callback(value, key));
  }
}

const fields: any[] = [
  {name: '__proto__', value: 'special-value'},
  {name: 'constructor', value: 'constructor-value'},
  {name: 'toString', value: 'to-string-value'},
  {name: 'normal', value: 'normal-value'}
];
for (const field of fields) {
  field.id = '';
  field.getAttribute = name => name === 'name' ? field.name : null;
}
const form = {
  ownerDocument: document,
  fields,
  querySelectorAll() { return fields; },
  getAttribute(name) {
    if (name === 'action') return 'download.do';
    if (name === 'method') return 'post';
    return null;
  }
};
const submitter = {
  ownerDocument: document,
  form,
  name: '',
  value: 'Download',
  innerText: 'Download',
  textContent: 'Download',
  getAttribute() { return null; },
  hasAttribute() { return false; },
  closest(selector) {
    if (selector === 'a[href]') return null;
    if (selector === 'button, input[type="submit"], input[type="button"]') {
      return submitter;
    }
    if (selector === 'form') return form;
    return null;
  }
};

const context = vm.createContext({
  window,
  document,
  console,
  URL,
  FormData: FakeFormData
});
vm.runInContext(buildScript, context);

for (const handler of listenersFor('click')) {
  handler({target: submitter, preventDefault() {}, stopPropagation() {}});
}

process.stdout.write(JSON.stringify({
  version: window.__MBG_DOWNLOAD_CAPTURE_VERSION,
  listenerCount: listenersFor('click').size,
  oldHandlerCalls,
  capturedCount: captured.length,
  formFields: captured[0] && captured[0].formFields
}));
