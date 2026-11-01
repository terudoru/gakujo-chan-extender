process.argv = [process.argv[0], ...process.argv.slice(2).map((path) => require('node:fs').readFileSync(path, 'utf8'))];
const vm: any = require('node:vm');
const buildScript = process.argv[1];
const captured: any = [];

function createDocument(baseURI?: any) {
  const listeners: any = new Map();
  return {
    baseURI,
    location: {href: baseURI},
    title: '',
    listeners,
    querySelectorAll() { return []; },
    addEventListener(type, handler) { listeners.set(type, handler); },
    removeEventListener(type, handler) {
      if (listeners.get(type) === handler) listeners.delete(type);
    }
  };
}

const topDocument: any = createDocument(
  'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do'
);
const oldChildDocument: any = createDocument(
  'https://gakujo.iess.niigata-u.ac.jp/campusweb/loading.do'
);
const loadedChildDocument: any = createDocument(
  'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'
);
const childWindow: any = {document: oldChildDocument, frames: []};
const window: any = {
  document: topDocument,
  frames: [childWindow],
  location: {href: topDocument.baseURI},
  MoreBetterGakujoDownloads: {
    postMessage(message) { captured.push(JSON.parse(message)); }
  }
};
window.window = window;

class FakeFormData {
  [key: string]: any;
  set() {}
  forEach() {}
}

const context: any = vm.createContext({
  window,
  document: topDocument,
  console,
  URL,
  FormData: FakeFormData
});
vm.runInContext(buildScript, context);

const oldDocumentHadListener: any = oldChildDocument.listeners.has('click');
childWindow.document = loadedChildDocument;
topDocument.listeners.get('load')({target: {tagName: 'IFRAME'}});

const fileName = '大学等への修学支援の措置に係る学修計画書.docx';
const element: any = {
  ownerDocument: loadedChildDocument,
  innerText: fileName,
  textContent: fileName,
  value: '',
  getAttribute(name) {
    if (name === 'href') {
      return 'campussquare.do?_flowId=SDW-filerefer-flow&fileId=41475';
    }
    return null;
  },
  hasAttribute() { return false; },
  closest(selector) { return selector === 'a[href]' ? element : null; }
};

let downloadPrevented = false;
loadedChildDocument.listeners.get('click')({
  target: element,
  preventDefault() { downloadPrevented = true; },
  stopPropagation() {}
});

process.stdout.write(JSON.stringify({
  oldDocumentHadListener,
  oldDocumentListenerRemoved: !oldChildDocument.listeners.has('click'),
  newDocumentHasListener: loadedChildDocument.listeners.has('click'),
  downloadPrevented,
  capturedUrl: captured[0] && captured[0].url,
  capturedName: captured[0] && captured[0].fileName
}));

