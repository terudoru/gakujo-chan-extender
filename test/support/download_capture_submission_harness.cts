const vm = require('node:vm');
const buildScript = require('node:fs').readFileSync(process.argv[2], 'utf8');
const captured = [];
const listeners = new Map();

const document = {
  baseURI: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/child/page.do',
  location: {
    href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/child/page.do'
  },
  title: '',
  querySelectorAll() { return []; },
  addEventListener(type, handler) { listeners.set(type, handler); },
  removeEventListener(type, handler) {
    if (listeners.get(type) === handler) listeners.delete(type);
  }
};

const window: any = {
  document,
  frames: [],
  location: {href: document.baseURI},
  MoreBetterGakujoDownloads: {
    postMessage(message) { captured.push(JSON.parse(message)); }
  }
};
window.window = window;

class FakeFormData {
  values: Map<string, string>;
  constructor(form) {
    this.values = new Map();
    for (const field of form.fields || []) {
      if (field.name) this.values.set(field.name, field.value);
    }
  }

  set(name, value) { this.values.set(name, value); }

  forEach(callback) {
    this.values.forEach((value, key) => callback(value, key));
  }
}

function javascriptAnchor() {
  const element = {
    ownerDocument: document,
    innerText: '\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9',
    textContent: '\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9',
    value: '',
    getAttribute(name) {
      if (name === 'href') return 'javascript:void(0)';
      return null;
    },
    hasAttribute() { return false; },
    closest(selector) { return selector === 'a[href]' ? element : null; }
  };
  return element;
}

function submitterWithForm(formaction, formmethod) {
  const hiddenField = {
    name: 'k',
    id: '',
    value: 'v',
    getAttribute(name) { return name === 'name' ? 'k' : null; }
  };
  const form = {
    ownerDocument: document,
    fields: [hiddenField],
    querySelectorAll() { return [hiddenField]; },
    getAttribute(name) {
      if (name === 'action') return 'list.do';
      if (name === 'method') return 'post';
      return null;
    }
  };
  const element = {
    ownerDocument: document,
    form,
    name: 'b',
    value: '1',
    innerText: '\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9',
    textContent: '\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9',
    getAttribute(name) {
      if (name === 'formaction') return formaction;
      if (name === 'formmethod') return formmethod;
      return null;
    },
    hasAttribute(name) { return name === 'formaction' ? formaction !== null : name === 'formmethod' ? formmethod !== null : false; },
    closest(selector) {
      if (selector === 'a[href]') return null;
      if (selector === 'button, input[type="submit"], input[type="button"]') {
        return element;
      }
      if (selector === 'form') return form;
      return null;
    }
  };
  return element;
}

function click(target, pageHandler?: () => void) {
  let prevented = false;
  let stopped = false;
  listeners.get('click')({
    target,
    preventDefault() { prevented = true; },
    stopPropagation() { stopped = true; }
  });
  if (!stopped && pageHandler) pageHandler();
  return {prevented, stopped};
}

const context = vm.createContext({
  window,
  document,
  console,
  URL,
  FormData: FakeFormData
});
vm.runInContext(buildScript, context);

let pageActionRan = false;
const javascriptOutcome = click(javascriptAnchor(), () => {
  pageActionRan = true;
});
const javascriptPostCount = captured.length;
captured.length = 0;

click(submitterWithForm('fileDownload.do', 'get'));
click(submitterWithForm(null, null));

process.stdout.write(JSON.stringify({
  javascriptPostCount,
  javascriptPrevented: javascriptOutcome.prevented,
  javascriptPropagationStopped: javascriptOutcome.stopped,
  pageActionRan,
  overridePayload: captured[0],
  controlPayload: captured[1]
}));
