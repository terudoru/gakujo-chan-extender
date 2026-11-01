process.argv = [process.argv[0], ...process.argv.slice(2).map((path) => require('node:fs').readFileSync(path, 'utf8'))];
const assert: any = require('node:assert/strict');
const vm: any = require('node:vm');
const [upload, stopUpload, download, stopDownload]: any = process.argv.slice(1);

for (const uploadFirst of [true, false]) {
  for (const stopUploadFirst of [true, false]) {
    const calls: any = [], captured: any = [], result: any = {};
    function makeDocument() {
      const doc: any = {
        baseURI: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/page.do',
        inputs: [], statuses: [], listeners: new Map(),
        defaultView: {HTMLFormElement: class {
  [key: string]: any;
          submit(...args) { calls.push({form: this, args, method: 'submit'}); return result; }
          requestSubmit(...args) { calls.push({form: this, args, method: 'requestSubmit'}); return result; }
        }},
        addEventListener(type, fn) {
          const handlers = doc.listeners.get(type) || new Set();
          handlers.add(fn); doc.listeners.set(type, handlers);
        },
        removeEventListener(type, fn) { doc.listeners.get(type)?.delete(fn); },
        querySelectorAll(selector) {
          if (selector === 'input[type="file"]') return doc.inputs;
          if (selector === 'iframe,frame') return doc === top ? [{contentWindow: frame}] : [];
          return selector.includes('upload-compression-owned') ? doc.statuses : [];
        },
        createElement() {
          const node: any = {style: {}, isConnected: true, setAttribute() {},
            remove() { node.isConnected = false; }};
          doc.statuses.push(node); return node;
        },
      };
      return doc;
    }
    const top: any = makeDocument(), child: any = makeDocument();
    const frame: any = {document: child, frames: []};
    let refreshUpload;
    const window: any = {document: top, frames: [frame], location: {href: top.baseURI},
      setInterval(fn) { refreshUpload = fn; return 1; },
      MoreBetterGakujoDownloads: {postMessage(value) { captured.push(JSON.parse(value)); }}};
    const context: any = vm.createContext({window, document: top, URL,
      FormData: class {
  [key: string]: any; forEach() {} }});
    const run = script => vm.runInContext(script, context);
    const originals: any = [top, child].map(doc => ({
      submit: doc.defaultView.HTMLFormElement.prototype.submit,
      requestSubmit: doc.defaultView.HTMLFormElement.prototype.requestSubmit}));
    function makeForm(doc?: any) {
      const input: any = {tagName: 'INPUT', type: 'file', ownerDocument: doc,
        parentNode: {insertBefore() {}}};
      const form: any = Object.assign(new doc.defaultView.HTMLFormElement(), {
        tagName: 'FORM', elements: [input], ownerDocument: doc, action: 'campussquare.do',
        getAttribute(name) { return name === 'action' ? this.action : null; },
        querySelectorAll() { return []; },
      });
      doc.inputs.push(input);
      return form;
    }
    const forms: any = [makeForm(top), makeForm(child)];
    function checkSubmissions() {
      for (const form of forms) {
        const input = form.elements[0];
        for (const method of ['submit', 'requestSubmit']) {
          input.__mbgUploadCompressionPending = 1;
          const args: any = [];
          const button: any = {tagName: 'BUTTON', type: 'button', form,
            onclick() { return form[method](...args); }};
          if (method === 'submit') args.push(button);
          const before = calls.length;
          for (const listener of form.ownerDocument.listeners.get('click')) {
            listener({type: 'click', target: button,
              preventDefault() { assert.fail('type=button must reach its page handler'); }});
          }
          assert.equal(button.onclick(), undefined);
          assert.equal(calls.length, before);
          assert.equal(input.__mbgUploadCompressionStatus.textContent,
            'ファイルを圧縮しています。完了してから提出してください');
          const other: any = makeForm(form.ownerDocument);
          assert.equal(other[method](...args), result);
          assert.equal(calls.at(-1).form, other);
          delete input.__mbgUploadCompressionPending;
          assert.equal(calls.length, before + 1, 'completion must never submit automatically');
          assert.equal(button.onclick(), result);
          assert.equal(calls.length, before + 2);
          assert.equal(calls.at(-1).form, form);
          assert.deepEqual(calls.at(-1).args, args);
          assert.equal(calls.at(-1).method, method);
        }
      }
      assert.equal(captured.length, 0);
      assert.equal(window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES.length, 4);
    }
    for (const script of uploadFirst ? [upload, download] : [download, upload]) run(script);
    checkSubmissions();
    run(download); run(upload); run(download); run(upload);
    checkSubmissions();
    if (stopUploadFirst) {
      run(stopUpload);
      refreshUpload();
      forms[0].action = 'campussquare.do?_eventId=download';
      forms[0].submit();
      assert.equal(captured.length, 1, 'download hook must survive upload teardown');
      forms[0].action = 'campussquare.do';
      captured.length = 0;
      run(upload);
      checkSubmissions();
      run(stopUpload); run(stopDownload);
    } else {
      run(stopDownload);
      forms[0].action = 'campussquare.do?_eventId=download';
      assert.equal(forms[0].submit(), result, 'download teardown must remove nested capture');
      assert.equal(captured.length, 0);
      forms[0].action = 'campussquare.do';
      checkSubmissions();
      run(stopUpload);
    }
    run(stopUpload); run(stopDownload);
    refreshUpload();
    for (const [index, doc] of [top, child].entries()) {
      for (const method of ['submit', 'requestSubmit']) {
        assert.equal(doc.defaultView.HTMLFormElement.prototype[method], originals[index][method]);
      }
    }
  }
}

