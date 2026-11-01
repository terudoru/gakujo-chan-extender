process.argv = [process.argv[0], ...process.argv.slice(2).map((path) => require('node:fs').readFileSync(path, 'utf8'))];
const vm: any = require('node:vm');
const buildScript = process.argv[1];
const scenario = process.argv[2] || 'links';
const teardownScript = process.argv[3];
const captured: any = [];
let nativeSubmissions = 0, clickStopped = false;

function createDocument(baseURI?: any) {
  const listeners: any = new Map();
  return {
    baseURI,
    defaultView: {HTMLFormElement: class {
  [key: string]: any;
      submit() { nativeSubmissions += 1; }
      requestSubmit(submitter) {
        if (!this.invalid) submitEvent(this, submitter);
      }
    }},
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
const childDocument: any = createDocument(
  'https://gakujo.iess.niigata-u.ac.jp/campusweb/child/page.do'
);
const childWindow: any = {document: childDocument, frames: []};
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
  constructor(form) { this.fields = new Map(Object.entries(form.fields || {})); }
  set(key, value) { this.fields.set(key, value); }
  forEach(callback) { this.fields.forEach(callback); }
}

function anchor(href?: any, text?: any, downloadName?: any, attributes: any = {}) {
  const element: any = {
    id: attributes.id || '',
    attributes: Object.keys(attributes).map(name => ({name})),
    ownerDocument: childDocument,
    innerText: text,
    textContent: text,
    value: '',
    getAttribute(name) {
      if (name === 'href') return href;
      if (name === 'download') return downloadName || null;
      return attributes[name] || null;
    },
    hasAttribute(name) {
      return name in attributes || name === 'download' && !!downloadName;
    },
    closest(selector) { return selector === 'a[href]' ? element : null; }
  };
  return element;
}

function submitterWithForm(text: any = 'ダウンロード', action: any = 'exports/form.pdf', fields: any = {}, attributes: any = {}, ownerDocument: any = childDocument) {
  const internalFileName: any = {
    name: 'fileName',
    id: 'fileName',
    value: 'internal_004281.pdf',
    getAttribute(name) {
      if (name === 'name' || name === 'id') return 'fileName';
      return null;
    }
  };
  const form: any = Object.assign(new ownerDocument.defaultView.HTMLFormElement(), {
    ownerDocument,
    fields,
    hasAttribute() { return false; },
    querySelectorAll() { return [internalFileName]; },
    getAttribute(name) {
      if (name === 'action') return action;
      if (name === 'method') return 'POST';
      return null;
    }
  });
  const rowNumber: any = {
    innerText: '1',
    textContent: '1',
    value: '',
    getAttribute() { return null; }
  };
  const fileLabel: any = {
    innerText: '画面表示の第1回講義資料',
    textContent: '画面表示の第1回講義資料',
    value: '',
    getAttribute() { return null; }
  };
  const publishedDate: any = {
    innerText: '2026/08/22',
    textContent: '2026/08/22',
    value: '',
    getAttribute() { return null; }
  };
  const row: any = {
    querySelectorAll() { return [rowNumber, fileLabel, publishedDate]; }
  };
  const element: any = {
    ownerDocument,
    id: attributes.id || '',
    attributes: Object.keys(attributes).map(name => ({name})),
    form,
    name: '',
    value: text,
    innerText: text,
    textContent: text,
    getAttribute(name) { return attributes[name] || null; },
    hasAttribute(name) { return name in attributes; },
    closest(selector) {
      if (selector === 'a[href]') return null;
      if (selector === 'button, input[type="submit"], input[type="button"]') {
        return element;
      }
      if (selector === 'form') return form;
      if (selector === 'tr, li, .file, .attachment, .document, .download') {
        return row;
      }
      return null;
    }
  };
  return element;
}

function click(target?: any) {
  let prevented = false;
  target.ownerDocument.listeners.get('click')({
    target,
    preventDefault() { prevented = true; },
    stopPropagation() { clickStopped = true; }
  });
  return prevented;
}

function multiDownloadForm(ownerDocument: any = childDocument, fields: any = {
  _flowId: 'SDW-filerefer-flow', downloadType: 'multi', fileId: '41881,41882'
}, action: any = '/campusweb/campussquare.do') {
  const form = submitterWithForm('', action, fields, {}, ownerDocument).form;
  form.name = 'multiDownloadForm';
  form.querySelectorAll = () => [];
  return form;
}

const originalRequestSubmit = childDocument.defaultView.HTMLFormElement.prototype.requestSubmit;
const context: any = vm.createContext({
  window,
  document: topDocument,
  console,
  URL,
  FormData: FakeFormData
});
vm.runInContext(buildScript, context);

function submitEvent(form?: any, submitter?: any) {
  let prevented = false;
  form.ownerDocument.listeners.get('submit')({
    target: form, submitter,
    preventDefault() { prevented = true; }, stopPropagation() {}
  });
  if (!prevented) nativeSubmissions += 1;
  return prevented;
}

function behavior() {
  if (scenario === 'multiDownloadSubmissions') {
    vm.runInContext(buildScript, context);
    vm.runInContext(buildScript, context);
    for (const doc of [topDocument, childDocument]) {
      const form: any = multiDownloadForm(doc);
      // submit() has no submitter, even after an inline button click.
      const button: any = submitterWithForm('一括ダウンロード', '', {}, {
        onclick: 'multiDownloadClick()', formaction: 'wrong.do', formmethod: 'GET'
      }, doc);
      button.form = form;
      button.name = '_eventId';
      button.value = 'confirm';
      click(button);
      form.submit();
    }
    return {captured, nativeSubmissions,
      hookCount: window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_PROTOTYPES.length};
  }
  if (scenario === 'fileReferSubmissions') {
    for (const [action, fields] of [
      ['campussquare.do', {_flowId: 'SDW-filerefer-flow', fileId: '42'}],
      ['campussquare.do?_flowId=SDW-filerefer-flow&fileId=42', {}],
      ['campussquare.do?_flowId=SDW-filerefer-flow', {fileId: '42'}],
      ['campussquare.do?fileId=42', {_flowId: 'SDW-filerefer-flow'}],
      ['campussquare.do', {downloadType: 'multi'}],
      ['campussquare.do?downloadType=multi', {}]
    ]) multiDownloadForm(childDocument, fields, action).submit();
    let expectedSubmissions = 0;
    for (const event of ['confirm', 'entry', 'submit', 'save', 'regist', 'register',
      'update', 'delete', 'back', 'clear', 'cancel', 'next', 'prev', 'complete', 'finish']) {
      for (const named of [false, true]) {
        const form: any = multiDownloadForm();
        form.fields[named ? '_eventId_' + event : '_eventId'] = event;
        form.submit();
        multiDownloadForm(childDocument, undefined,
          'campussquare.do?_eventId' + (named ? '_' + event : '=' + event)).submit();
        expectedSubmissions += 2;
      }
    }
    for (const fields of [
      {_flowId: 'SDW-filerefer-flow'},
      {_flowId: 'SDW-filerefer-flow', fileId: '   '},
      {_flowId: 'SDW-report-flow', fileId: '42'},
      {fileId: '42'}
    ]) {
      multiDownloadForm(childDocument, fields).submit();
      expectedSubmissions += 1;
    }
    return {captured, nativeSubmissions, expectedSubmissions};
  }
  if (scenario === 'ownedMultiDownloadSubmissions') {
    for (const ownership of [{id: 'mbg-download'}, {class: 'other mbg-download'},
      {'data-mbg-download': 'true'}]) {
      for (const nested of [false, true]) {
        const form: any = multiDownloadForm();
        const owner = nested ? {} : form;
        owner.id = ownership.id || '';
        owner.attributes = Object.keys(ownership).map(name => ({name}));
        const original = owner.getAttribute;
        owner.getAttribute = name => ownership[name] || (original ? original(name) : null);
        if (nested) form.parentElement = owner;
        form.submit();
      }
    }
    multiDownloadForm(childDocument, {_eventId: 'confirm'}).submit();
    return {captured, nativeSubmissions};
  }
  if (scenario === 'requestSubmit') {
    const form: any = multiDownloadForm();
    form.requestSubmit();
    form.invalid = true;
    form.requestSubmit();
    multiDownloadForm(childDocument, {_eventId: 'confirm'}).requestSubmit();
    return {captured, nativeSubmissions,
      prototypeUnchanged: childDocument.defaultView.HTMLFormElement.prototype.requestSubmit === originalRequestSubmit};
  }
  if (scenario === 'onclickFilereferDetails') {
    vm.runInContext(buildScript, context);
    const flow = '../campussquare.do?_flowId=SDW-filerefer-flow';
    const prevented: any = [];
    let handlersRun = 0;
    for (const query of [
      '&_eventId=confirm',
      '&fileId=41881&_eventId=confirm',
      '',
      '&fileId=',
      '&fileId=41881',
      '&fileId=41882&_eventId=download'
    ]) {
      clickStopped = false;
      const intercepted: any = click(anchor(flow + query, '詳細', null, {onclick: 'return true'}));
      prevented.push(intercepted);
      if (!intercepted && !clickStopped) handlersRun += 1;
    }
    return {prevented, handlersRun, captured};
  }
  if (scenario === 'onclickAttachments') {
    vm.runInContext(buildScript, context);
    const prevented: any = [];
    let handlersRun = 0;
    for (const href of [
      '#attachment.pdf',
      'javascript:download()',
      'prepare.do',
      'files.do?fileId=42',
      '/campusweb/campussquare.do?_flowId=SDW-filerefer-flow&fileId=41881',
      'exports/form.pdf',
      '../campussquare.do?_eventId=download&fileId=42'
    ]) {
      clickStopped = false;
      const intercepted: any = click(anchor(href, 'Download x.pdf', null, {onclick: 'return true'}));
      prevented.push(intercepted);
      if (!intercepted && !clickStopped) handlersRun += 1;
    }
    return {prevented, handlersRun, captured, nativeSubmissions};
  }
  if (scenario === 'navigationLabels') {
    const navigationPrevented: any = [];
    for (const text of ['Download', 'ダウンロード']) {
      for (const href of [
        '../campussquare.do?_eventId=reportList',
        '../campusportal.do?_eventId=display',
        '../campussquare.do?page=main&tabId=kj',
        '../message/detail.do?seqNo=42',
        '../campussquare.do?_eventId=displayMidoku',
        '../campussquare.do?_eventId=confirm'
      ]) navigationPrevented.push(click(anchor(href, text)));
    }
    const downloadPrevented: any = [
      '../campussquare.do?_eventId=download',
      '../campussquare.do?_eventId=infoDownLoad',
      '../campussquare.do?_flowId=SDW-filerefer-flow&fileId=41475',
      'exports/form.pdf?seqNo=42'
    ].map(href => click(anchor(href, 'Download')));
    downloadPrevented.push(click(anchor('../campussquare.do?fileId=42', '', 'file.pdf')));
    return {navigationPrevented, downloadPrevented, captured};
  }
  if (scenario === 'pageHandlers') {
    const handlerPrevented: any = [], handlerStopped: any = [];
    let handlersRun = 0;
    const controls: any = [
      anchor('prepare.do', 'Download', null, {onclick: 'prepareDownload()'}),
      anchor('#', 'ダウンロード'),
      anchor('#attachment', 'Download'),
      anchor('javascript:prepareDownload()', 'Download'),
      submitterWithForm('Download', 'campussquare.do', {}, {onclick: 'prepareDownload()'}),
      submitterWithForm('Download', 'campussquare.do', {}, {onclick: 'openDownload()'})
    ];
    controls[5].form = null;
    const closest = controls[5].closest;
    controls[5].closest = selector => selector === 'form' ? null : closest(selector);
    for (const [index, control] of controls.entries()) {
      clickStopped = false;
      const prevented: any = click(control);
      handlerPrevented.push(prevented);
      handlerStopped.push(clickStopped);
      if (!prevented && !clickStopped) {
        handlersRun += 1;
        const button = control.form ? control : submitterWithForm('', 'campussquare.do');
        button.form.fields = {_eventId: 'download', fileId: String(index)};
        button.form.getAttribute = name => name === 'action'
          ? 'campussquare.do?fileId=' + index : name === 'method' ? 'POST' : null;
        button.form.submit();
      }
    }
    const plainPrevented: any = [
      '../campussquare.do?_eventId=download&fileId=plain',
      '../campussquare.do?_flowId=SDW-filerefer-flow&fileId=41475'
    ].map(href => click(anchor(href, 'Download')));
    return {handlerPrevented, handlerStopped, handlersRun, plainPrevented,
      captured, nativeSubmissions};
  }
  if (scenario === 'submitterOverrides') {
    const prevented: any = [];
    for (const submit of [button => click(button),
      button => submitEvent(button.form, button)]) {
      for (const attributes of [
        {formaction: 'exports/override.pdf', formmethod: 'POST',
          formenctype: 'application/x-www-form-urlencoded', formtarget: '_self'},
        {formmethod: 'POST', formenctype: 'text/plain', formtarget: '_self'},
        {formenctype: 'application/x-www-form-urlencoded', formtarget: '_blank'},
        {formaction: '', formmethod: '', formenctype: '', formtarget: ''}
      ]) {
        const button: any = submitterWithForm('Download', 'exports/wrong.pdf',
          {_eventId: 'download'}, attributes);
        const original = button.form.getAttribute;
        button.form.getAttribute = name => name === 'enctype' ? 'multipart/form-data'
          : name === 'target' ? '_blank' : name === 'method' ? 'GET' : original(name);
        prevented.push(submit(button));
      }
    }
    return {prevented, captured};
  }
  if (scenario === 'namedWorkflowSubmit') {
    const form = submitterWithForm('', 'exports/form.pdf',
      {_eventId_submit: 'Submit'}).form;
    form.submit();
    return {nativeSubmissions, captured};
  }
  if (scenario === 'namedEventSubmissions') {
    const workflowPrevented: any = [];
    for (const event of ['confirm', 'entry', 'submit', 'save', 'regist', 'register',
      'update', 'delete', 'back', 'clear', 'cancel', 'next', 'prev', 'complete', 'finish']) {
      const form = submitterWithForm('', 'exports/form.pdf',
        {['_eventId_' + event]: 'Continue'}).form;
      form.submit();
      workflowPrevented.push(submitEvent(form));
      const button: any = submitterWithForm('Download', 'exports/form.pdf');
      button.name = '_eventId_' + event;
      button.value = 'Continue';
      workflowPrevented.push(click(button), submitEvent(button.form, button));
    }
    const download = submitterWithForm('Confirm', 'campussquare.do',
      {_eventId_download: 'Get file'}).form;
    download.submit();
    const downloadPrevented: any = [submitEvent(download)];
    const button: any = submitterWithForm('Confirm', 'campussquare.do');
    button.name = '_eventId_download';
    button.value = 'Get file';
    downloadPrevented.push(click(button), submitEvent(button.form, button));
    const query = submitterWithForm('', 'campussquare.do?_eventId_download=Get').form;
    query.submit();
    return {workflowPrevented, downloadPrevented, captured, nativeSubmissions,
      workflowSubmissions: 45};
  }
  if (scenario === 'listenerConfirm') {
    const confirm: any = submitterWithForm('確認', 'campussquare.do', {_eventId: 'confirm'});
    confirm.form.innerText = 'レポート提出 添付ファイル ダウンロード 確認';
    // Gakujo registers this handler without an inline onclick or submitter.
    const listeners: any = [];
    confirm.addEventListener = (type, handler) => listeners.push(handler);
    confirm.addEventListener('click', () => confirm.form.submit());
    const prevented: any = [click(confirm)];
    if (!prevented[0]) listeners.forEach(handler => handler());
    return {prevented, nativeSubmissions, expectedSubmissions: 1, captured};
  }
  if (scenario === 'workflowSubmissions') {
    const prevented: any = [];
    const values: any = ['', 'confirm', 'entry', 'submit', 'save', 'regist', 'register',
      'update', 'delete', 'back', 'clear', 'cancel', 'next', 'prev', 'complete', 'finish'];
    for (const value of values) {
      // Workflow fields win even over a download-looking action and parameter.
      const action = value ? 'download.do?fileDownload=1' : 'campussquare.do';
      const button: any = submitterWithForm('ダウンロード', action,
        value ? {_eventId: value} : {});
      button.form.innerText = '資料ダウンロード レポート提出 確認';
      if (value) prevented.push(click(button));
      button.form.submit();
      prevented.push(submitEvent(button.form, button));
    }
    return {prevented, nativeSubmissions, expectedSubmissions: values.length * 2, captured};
  }
  if (scenario === 'nonExplicitSubmissions') {
    const prevented: any = [];
    const actions: any = ['campussquare.do', 'exports/form.pdf/preview',
      'campussquare.do?fileId=42', 'campussquare.do?name=form.pdf',
      'campussquare.do#form.pdf'];
    for (const action of actions) {
      const button: any = submitterWithForm('ダウンロード', action);
      button.form.innerText = '資料ダウンロード レポート提出 確認';
      button.form.submit();
      prevented.push(submitEvent(button.form, button));
    }
    const button: any = submitterWithForm('Download', 'campussquare.do');
    button.name = '_eventId';
    button.value = '';
    prevented.push(submitEvent(button.form, button));
    return {prevented, nativeSubmissions, expectedSubmissions: actions.length * 2 + 1, captured};
  }
  if (scenario === 'explicitSubmissions') {
    const prevented: any = [];
    for (const [action, fields] of [
      ['campussquare.do', {_eventId: 'infoDownLoad'}],
      ['DOWNLOAD.do', {}],
      ['campussquare.do?fileDownload=1', {}],
      ['campussquare.do', {downloadFile: '42'}]
    ]) {
      const button: any = submitterWithForm('確認', action, fields);
      button.form.submit();
      prevented.push(submitEvent(button.form, button));
    }
    return {prevented, nativeSubmissions, captured};
  }
  if (scenario === 'fileActionSubmissions') {
    const prevented: any = [], workflowPrevented: any = [];
    for (const extension of ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
      'zip', 'csv', 'txt', 'png', 'jpg', 'jpeg']) {
      // Exercise both submission hooks with no remembered click/submitter.
      const form = submitterWithForm('', `exports/form.${extension}?id=42#file`,
        {selectedFileId: 'current-file'}).form;
      form.submit();
      prevented.push(submitEvent(form));
    }
    const upper = submitterWithForm('', 'exports/form.PDF',
      {selectedFileId: 'current-file'}).form;
    upper.submit();
    prevented.push(submitEvent(upper));
    for (const event of ['confirm', 'entry', 'submit', 'save', 'regist', 'register',
      'update', 'delete', 'back', 'clear', 'cancel', 'next', 'prev', 'complete', 'finish']) {
      for (const [action, fields] of [
        ['exports/form.pdf', {_eventId: event}],
        [`exports/form.pdf?_EVENTID=${event.toUpperCase()}`, {}]
      ]) {
        const form = submitterWithForm('確認', action, fields).form;
        form.submit();
        workflowPrevented.push(submitEvent(form));
      }
    }
    return {prevented, workflowPrevented, captured, nativeSubmissions,
      workflowSubmissions: 60};
  }
  if (scenario === 'inlineSubmit' || scenario === 'inlineSubmitEvent') {
    const button: any = submitterWithForm('ダウンロード', 'campussquare.do', {
      _eventId: 'confirm', selectedFileId: 'stale-file'
    }, {onclick: 'prepareDownload(this.form)'});
    const clickPrevented: any = click(button);
    if (!clickPrevented && !clickStopped) {
      button.form.fields._eventId = 'download';
      button.form.fields.selectedFileId = 'current-file';
      if (scenario === 'inlineSubmit') button.form.submit();
      else submitEvent(button.form, button);
    }
    return {clickPrevented, clickStopped, submitPrevented: captured.length === 1,
      nativeSubmissions, captured};
  }
  if (scenario === 'workflow') {
    const labels: any = ['確認', '提出', '確定保存', '一時保存', '保存', '戻る', 'クリア', '削除', '送信', '登録', 'キャンセル'];
    const action = 'campussquare.do?_flowId=SDW-filerefer-flow&fileId=41475';
    const weakPrevented: any = labels.map(label => click(submitterWithForm(label, action)));
    weakPrevented.push(click(submitterWithForm('確認', action, {
      _eventId: 'confirm', downloadFileName: '添付資料.pdf'
    })));
    // Inline workflow buttons still prepare and submit normally.
    const confirm: any = submitterWithForm('確認', action, {_eventId: 'confirm'}, {onclick: 'prepareConfirm()'});
    weakPrevented.push(click(confirm), submitEvent(confirm.form, confirm));
    const explicitPrevented: any = [
      click(submitterWithForm('確認', action, {_eventId: 'download'})),
      click(submitterWithForm('保存', 'campussquare.do?_eventId=download')),
      click(submitterWithForm('確認', 'campussquare.do?fileDownload=1')),
      click(submitterWithForm('保存', 'exports/form.pdf'))
    ];
    return {weakPrevented, explicitPrevented, captured};
  }
  if (scenario === 'appOwned') {
    const prevented: any = [];
    for (const ownership of [{id: 'mbg-star'}, {class: 'other mbg-star'}, {'data-mbg-message-star': 'true'}]) {
      const star: any = submitterWithForm('', 'campussquare.do', {}, {
        title: 'スター: 資料ダウンロードのお知らせ', ...ownership
      });
      prevented.push(click(star));
      const link: any = anchor('exports/form.pdf', '資料.pdf', null, ownership);
      prevented.push(click(link));
      const nested: any = anchor('exports/form.pdf', '資料.pdf');
      nested.parentElement = star;
      prevented.push(click(nested));
      prevented.push(submitEvent(star.form, star));
    }
    return {prevented, captured};
  }
  if (scenario === 'external') {
    const url = 'https://www.niigata-u.ac.jp/handbook.pdf';
    const prevented: any = [click(anchor(url, 'ダウンロード', 'handbook.pdf')),
      click(submitterWithForm('ダウンロード', url))];
    const button: any = submitterWithForm('ダウンロード', url, {_eventId: 'download'}, {onclick: 'prepare()'});
    prevented.push(click(button), submitEvent(button.form, button));
    button.form.submit();
    return {prevented, captured};
  }
  if (scenario === 'submissionLifecycle') {
    const oldPrototype = childDocument.defaultView.HTMLFormElement.prototype;
    const topPrototype = topDocument.defaultView.HTMLFormElement.prototype;
    const oldOriginal = window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_PROTOTYPES.find(e => e.prototype === oldPrototype).original;
    const topOriginal = window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_PROTOTYPES.find(e => e.prototype === topPrototype).original;
    vm.runInContext(buildScript, context);
    for (const doc of [topDocument, childDocument]) {
      multiDownloadForm(doc).submit();
    }
    const ordinary: any = submitterWithForm('確認', 'campussquare.do', {_eventId: 'confirm'});
    ordinary.form.submit();
    const ordinarySubmitPrevented: any = submitEvent(ordinary.form, ordinary);
    const newDocument: any = createDocument(childDocument.baseURI);
    const newPrototype = newDocument.defaultView.HTMLFormElement.prototype;
    const newOriginal = newPrototype.submit;
    childWindow.document = newDocument;
    topDocument.listeners.get('load')({target: {tagName: 'IFRAME'}});
    const oldPrototypeRestored = oldPrototype.submit === oldOriginal;
    const oldSubmitListenerRemoved = !childDocument.listeners.has('submit');
    multiDownloadForm(newDocument).submit();
    vm.runInContext(teardownScript, context);
    vm.runInContext(teardownScript, context);
    ordinary.form.submit();
    multiDownloadForm(newDocument).submit();
    return {oldPrototypeRestored, oldSubmitListenerRemoved, ordinarySubmitPrevented,
      topPrototypeRestored: topPrototype.submit === topOriginal,
      newPrototypeRestored: newPrototype.submit === newOriginal,
      submitListenersAfterTeardown: [topDocument, newDocument].filter(d => d.listeners.has('submit')).length,
      nativeSubmissions, captured};
  }

  const normalNavigationPrevented: any = click(anchor(
    '../campussquare.do?_eventId=reportList',
    'レポート一覧'
  ));
  click(anchor(
    '../campussquare.do?_eventId=infoDownLoad',
    '画面表示の資料名',
    'internal_002913.bin'
  ));
  click(submitterWithForm());

  return {
    normalNavigationPrevented,
    capturedUrls: captured.map((payload) => payload.url),
    capturedNames: captured.map((payload) => payload.fileName)
  };
}
process.stdout.write(JSON.stringify(behavior()));

