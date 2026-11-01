process.argv = [process.argv[0], ...process.argv.slice(2).map((path) => require('node:fs').readFileSync(path, 'utf8'))];
const assert: any = require('node:assert/strict');
const vm: any = require('node:vm');
const [upload]: any = process.argv.slice(1);

function makeDocument() {
  return {
    defaultView: {HTMLFormElement: class {
  [key: string]: any;
      submit() {}
      requestSubmit() {}
    }},
    addEventListener() {},
    querySelectorAll(selector) {
      return this === top && selector === 'iframe,frame' ? [iframe] : [];
    },
  };
}
const top: any = makeDocument();
const iframe: any = {contentWindow: {document: makeDocument()}};
const window: any = {setInterval() { return 1; }};
const context: any = vm.createContext({window, document: top});
vm.runInContext(upload, context);

function checkHooks() {
  const liveDocuments: any = [top, iframe.contentWindow.document];
  const hooks = window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES;
  assert.equal(hooks.length, liveDocuments.length * 2);
  for (const doc of liveDocuments) {
    for (const method of ['submit', 'requestSubmit']) {
      assert.equal(hooks.filter(entry =>
        entry.prototype === doc.defaultView.HTMLFormElement.prototype &&
        entry.method === method).length, 1);
    }
  }
}
checkHooks();
for (let i = 0; i < 30; i++) {
  iframe.contentWindow.document = makeDocument();
  window.__MBG_UPLOAD_COMPRESSION_UPDATE();
  checkHooks();
}

