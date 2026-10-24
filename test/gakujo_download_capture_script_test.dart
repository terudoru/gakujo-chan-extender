import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_download_capture_script.dart';
import 'package:test/test.dart';

void main() {
  test('excludes submission workflow buttons from weak download capture', () {
    final script = GakujoDownloadCaptureScript.build();

    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_VERSION'));
    expect(script, contains('captureVersion = 13'));
    expect(script, contains('__MBG_ESTIMATE_COURSE_NAME'));
    expect(script, contains('removeEventListener'));
    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_HANDLER'));
    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_DOCUMENTS'));
    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_ATTACH'));
    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER'));
    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS'));
    expect(script, contains('function attachClickHandlers()'));
    expect(script, contains('documents[i].addEventListener'));
    expect(script, contains('removeEventListener'));
    expect(script, contains('firstMatchingCourseNameText'));
    expect(script, contains('sameRowValue'));
    expect(script, contains('科目名'));
    expect(script, contains(r'(?:[A-Z0-9]{4,}\s+)?'));
    expect(script, contains('isIgnoredCourseName'));
    expect(script, contains('text.length > 100'));
    expect(script, contains('extractCourseNameFromText'));
    expect(script, contains('trimAtKnownFieldLabel'));
    expect(script,
        contains('text && !isIgnoredCourseName(normalizeCourseName(text))'));
    expect(script, contains('campussquare'));
    expect(script, contains('isSubmissionWorkflowAction'));
    expect(script, contains('hasStrongDownloadSignal'));
    expect(script, contains('提出する'));
    expect(script, contains('取り消し'));
    expect(script, contains('提出(用)?(画面|ページ)'));
    expect(script, contains('downloadFileName'));
    expect(script, contains('nearbyDisplayedFileName'));
    expect(
      script,
      contains(
        'isSubmissionWorkflowAction(element) && !hasStrongDownloadSignal',
      ),
    );
  });

  test('teardown removes the injected click handler', () async {
    final result = await _runNode([
      _downloadCaptureLifecycleHarness,
      GakujoDownloadCaptureScript.build(),
      GakujoDownloadCaptureScript.buildTeardown(),
    ], stdoutEncoding: utf8, stderrEncoding: utf8);

    expect(
      result.exitCode,
      0,
      reason: 'Node JavaScript evaluation failed: ${result.stderr}',
    );
    final lifecycle =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(lifecycle['listenersAfterBuild'], 1);
    expect(lifecycle['loadListenersAfterBuild'], 1);
    expect(lifecycle['listenersAfterTeardown'], 0);
    expect(lifecycle['loadListenersAfterTeardown'], 0);
    expect(lifecycle['handlerCleared'], isTrue);
    expect(lifecycle['loadHandlerCleared'], isTrue);
    expect(lifecycle['versionCleared'], isTrue);
  });

  test('reattaches capture after a CampusSquare iframe document loads',
      () async {
    final result = await _runNode([
      _downloadCaptureIframeReloadHarness,
      GakujoDownloadCaptureScript.build(),
    ], stdoutEncoding: utf8, stderrEncoding: utf8);

    expect(
      result.exitCode,
      0,
      reason: 'Node JavaScript evaluation failed: ${result.stderr}',
    );
    final behavior =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(behavior['oldDocumentHadListener'], isTrue);
    expect(behavior['oldDocumentListenerRemoved'], isTrue);
    expect(behavior['newDocumentHasListener'], isTrue);
    expect(behavior['downloadPrevented'], isTrue);
    expect(
      behavior['capturedUrl'],
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'
      '?_flowId=SDW-filerefer-flow&fileId=41475',
    );
    expect(
      behavior['capturedName'],
      '大学等への修学支援の措置に係る学修計画書.docx',
    );
  });

  test('captures only download links and resolves iframe-relative urls',
      () async {
    final result = await _runNode([
      _downloadCaptureBehaviorHarness,
      GakujoDownloadCaptureScript.build(),
    ], stdoutEncoding: utf8, stderrEncoding: utf8);

    expect(
      result.exitCode,
      0,
      reason: 'Node JavaScript evaluation failed: ${result.stderr}',
    );
    final behavior =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(behavior['normalNavigationPrevented'], isFalse);
    expect(
      behavior['capturedUrls'],
      [
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'
            '?_eventId=infoDownLoad',
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/child/exports/form.pdf',
      ],
    );
    expect(
      behavior['capturedNames'],
      ['画面表示の資料名', '画面表示の第1回講義資料'],
    );
  });

  for (final scenario in ['inlineSubmit', 'inlineSubmitEvent']) {
    test('$scenario captures fields after the page onclick prepares the form',
        () async {
      final result = await _evaluateBehavior(scenario);
      expect(result['clickPrevented'], isFalse);
      expect(result['clickStopped'], isFalse);
      expect(result['submitPrevented'], isTrue);
      expect(result['nativeSubmissions'], 0);
      final payload = (result['captured'] as List).single as Map;
      expect(payload['method'], 'POST');
      expect(payload['formFields'], {
        '_eventId': 'download',
        'selectedFileId': 'current-file',
      });
    });
  }

  test('workflow exclusions win over file paths unless the request is explicit',
      () async {
    final result = await _evaluateBehavior('workflow');
    expect(result['weakPrevented'], everyElement(isFalse));
    expect(result['explicitPrevented'], everyElement(isTrue));
    expect((result['captured'] as List).length, 4);
  });

  test('does not capture app-owned stars or their nested targets', () async {
    final result = await _evaluateBehavior('appOwned');
    expect(result['prevented'], everyElement(isFalse));
    expect(result['captured'], isEmpty);
  });

  test('leaves external file links and form submissions to normal navigation',
      () async {
    final result = await _evaluateBehavior('external');
    expect(result['prevented'], everyElement(isFalse));
    expect(result['captured'], isEmpty);
  });

  test(
      'submission hooks survive reinjection and restore on navigation/teardown',
      () async {
    final result = await _evaluateBehavior('submissionLifecycle');
    expect(result['oldPrototypeRestored'], isTrue);
    expect(result['oldSubmitListenerRemoved'], isTrue);
    expect(result['topPrototypeRestored'], isTrue);
    expect(result['newPrototypeRestored'], isTrue);
    expect(result['submitListenersAfterTeardown'], 0);
    expect(result['ordinarySubmitPrevented'], isFalse);
    expect(result['nativeSubmissions'], 4);
    expect((result['captured'] as List).length, 2);
  });
}

Future<Map<String, dynamic>> _evaluateBehavior(String scenario) async {
  final result = await _runNode([
    _downloadCaptureBehaviorHarness,
    GakujoDownloadCaptureScript.build(),
    scenario,
    GakujoDownloadCaptureScript.buildTeardown(),
  ], stdoutEncoding: utf8, stderrEncoding: utf8);
  expect(result.exitCode, 0, reason: result.stderr as String);
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const _downloadCaptureLifecycleHarness = r'''
const vm = require('node:vm');
const buildScript = process.argv[1];
const teardownScript = process.argv[2];
const clickListeners = new Set();
const loadListeners = new Set();
const document = {
  addEventListener(type, handler) {
    if (type === 'click') clickListeners.add(handler);
    if (type === 'load') loadListeners.add(handler);
  },
  removeEventListener(type, handler) {
    if (type === 'click') clickListeners.delete(handler);
    if (type === 'load') loadListeners.delete(handler);
  }
};
const window = {
  document,
  frames: [],
  location: {
    href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do'
  }
};
window.window = window;
const context = vm.createContext({window, document, console, URL});
vm.runInContext(buildScript, context);
const listenersAfterBuild = clickListeners.size;
const loadListenersAfterBuild = loadListeners.size;
vm.runInContext(teardownScript, context);
process.stdout.write(JSON.stringify({
  listenersAfterBuild,
  loadListenersAfterBuild,
  listenersAfterTeardown: clickListeners.size,
  loadListenersAfterTeardown: loadListeners.size,
  handlerCleared: window.__MBG_DOWNLOAD_CAPTURE_HANDLER === null,
  loadHandlerCleared: window.__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER === null,
  versionCleared: window.__MBG_DOWNLOAD_CAPTURE_VERSION === null
}));
''';

const _downloadCaptureIframeReloadHarness = r'''
const vm = require('node:vm');
const buildScript = process.argv[1];
const captured = [];

function createDocument(baseURI) {
  const listeners = new Map();
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

const topDocument = createDocument(
  'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do'
);
const oldChildDocument = createDocument(
  'https://gakujo.iess.niigata-u.ac.jp/campusweb/loading.do'
);
const loadedChildDocument = createDocument(
  'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'
);
const childWindow = {document: oldChildDocument, frames: []};
const window = {
  document: topDocument,
  frames: [childWindow],
  location: {href: topDocument.baseURI},
  MoreBetterGakujoDownloads: {
    postMessage(message) { captured.push(JSON.parse(message)); }
  }
};
window.window = window;

class FakeFormData {
  set() {}
  forEach() {}
}

const context = vm.createContext({
  window,
  document: topDocument,
  console,
  URL,
  FormData: FakeFormData
});
vm.runInContext(buildScript, context);

const oldDocumentHadListener = oldChildDocument.listeners.has('click');
childWindow.document = loadedChildDocument;
topDocument.listeners.get('load')({target: {tagName: 'IFRAME'}});

const fileName = '大学等への修学支援の措置に係る学修計画書.docx';
const element = {
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
''';

const _downloadCaptureBehaviorHarness = r'''
const vm = require('node:vm');
const buildScript = process.argv[1];
const scenario = process.argv[2] || 'links';
const teardownScript = process.argv[3];
const captured = [];
let nativeSubmissions = 0, clickStopped = false;

function createDocument(baseURI) {
  const listeners = new Map();
  return {
    baseURI,
    defaultView: {HTMLFormElement: class {
      submit() { nativeSubmissions += 1; }
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

const topDocument = createDocument(
  'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do'
);
const childDocument = createDocument(
  'https://gakujo.iess.niigata-u.ac.jp/campusweb/child/page.do'
);
const childWindow = {document: childDocument, frames: []};
const window = {
  document: topDocument,
  frames: [childWindow],
  location: {href: topDocument.baseURI},
  MoreBetterGakujoDownloads: {
    postMessage(message) { captured.push(JSON.parse(message)); }
  }
};
window.window = window;

class FakeFormData {
  constructor(form) { this.fields = new Map(Object.entries(form.fields || {})); }
  set(key, value) { this.fields.set(key, value); }
  forEach(callback) { this.fields.forEach(callback); }
}

function anchor(href, text, downloadName, attributes = {}) {
  const element = {
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
    hasAttribute(name) { return name === 'download' && !!downloadName; },
    closest(selector) { return selector === 'a[href]' ? element : null; }
  };
  return element;
}

function submitterWithForm(text = 'ダウンロード', action = 'exports/form.pdf', fields = {}, attributes = {}, ownerDocument = childDocument) {
  const internalFileName = {
    name: 'fileName',
    id: 'fileName',
    value: 'internal_004281.pdf',
    getAttribute(name) {
      if (name === 'name' || name === 'id') return 'fileName';
      return null;
    }
  };
  const form = Object.assign(new ownerDocument.defaultView.HTMLFormElement(), {
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
  const rowNumber = {
    innerText: '1',
    textContent: '1',
    value: '',
    getAttribute() { return null; }
  };
  const fileLabel = {
    innerText: '画面表示の第1回講義資料',
    textContent: '画面表示の第1回講義資料',
    value: '',
    getAttribute() { return null; }
  };
  const publishedDate = {
    innerText: '2026/08/22',
    textContent: '2026/08/22',
    value: '',
    getAttribute() { return null; }
  };
  const row = {
    querySelectorAll() { return [rowNumber, fileLabel, publishedDate]; }
  };
  const element = {
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

function click(target) {
  let prevented = false;
  target.ownerDocument.listeners.get('click')({
    target,
    preventDefault() { prevented = true; },
    stopPropagation() { clickStopped = true; }
  });
  return prevented;
}

const context = vm.createContext({
  window,
  document: topDocument,
  console,
  URL,
  FormData: FakeFormData
});
vm.runInContext(buildScript, context);

function submitEvent(form, submitter) {
  let prevented = false;
  form.ownerDocument.listeners.get('submit')({
    target: form, submitter,
    preventDefault() { prevented = true; }, stopPropagation() {}
  });
  if (!prevented) nativeSubmissions += 1;
  return prevented;
}

function behavior() {
  if (scenario === 'inlineSubmit' || scenario === 'inlineSubmitEvent') {
    const button = submitterWithForm('ダウンロード', 'campussquare.do', {
      _eventId: 'confirm', selectedFileId: 'stale-file'
    }, {onclick: 'prepareDownload(this.form)'});
    const clickPrevented = click(button);
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
    const labels = ['確認', '提出', '確定保存', '一時保存', '保存', '戻る', 'クリア', '削除', '送信', '登録', 'キャンセル'];
    const action = 'campussquare.do?_flowId=SDW-filerefer-flow&fileId=41475';
    const weakPrevented = labels.map(label => click(submitterWithForm(label, action)));
    weakPrevented.push(click(submitterWithForm('確認', action, {
      _eventId: 'confirm', downloadFileName: '添付資料.pdf'
    })));
    // Inline workflow buttons still prepare and submit normally.
    const confirm = submitterWithForm('確認', action, {_eventId: 'confirm'}, {onclick: 'prepareConfirm()'});
    weakPrevented.push(click(confirm), submitEvent(confirm.form, confirm));
    const explicitPrevented = [
      click(submitterWithForm('確認', action, {_eventId: 'download'})),
      click(submitterWithForm('保存', 'campussquare.do?_eventId=download')),
      click(submitterWithForm('確認', 'campussquare.do?fileDownload=1')),
      click(submitterWithForm('保存', 'exports/form.pdf'))
    ];
    return {weakPrevented, explicitPrevented, captured};
  }
  if (scenario === 'appOwned') {
    const prevented = [];
    for (const ownership of [{id: 'mbg-star'}, {class: 'other mbg-star'}, {'data-mbg-message-star': 'true'}]) {
      const star = submitterWithForm('', 'campussquare.do', {}, {
        title: 'スター: 資料ダウンロードのお知らせ', ...ownership
      });
      prevented.push(click(star));
      const link = anchor('exports/form.pdf', '資料.pdf', null, ownership);
      prevented.push(click(link));
      const nested = anchor('exports/form.pdf', '資料.pdf');
      nested.parentElement = star;
      prevented.push(click(nested));
      prevented.push(submitEvent(star.form, star));
    }
    return {prevented, captured};
  }
  if (scenario === 'external') {
    const url = 'https://www.niigata-u.ac.jp/handbook.pdf';
    const prevented = [click(anchor(url, 'ダウンロード', 'handbook.pdf')),
      click(submitterWithForm('ダウンロード', url))];
    const button = submitterWithForm('ダウンロード', url, {_eventId: 'download'}, {onclick: 'prepare()'});
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
      submitterWithForm('Download', 'campussquare.do', {_eventId: 'download'}, {}, doc).form.submit();
    }
    const ordinary = submitterWithForm('確認', 'campussquare.do', {_eventId: 'confirm'});
    ordinary.form.submit();
    const ordinarySubmitPrevented = submitEvent(ordinary.form, ordinary);
    const newDocument = createDocument(childDocument.baseURI);
    const newPrototype = newDocument.defaultView.HTMLFormElement.prototype;
    const newOriginal = newPrototype.submit;
    childWindow.document = newDocument;
    topDocument.listeners.get('load')({target: {tagName: 'IFRAME'}});
    const oldPrototypeRestored = oldPrototype.submit === oldOriginal;
    const oldSubmitListenerRemoved = !childDocument.listeners.has('submit');
    vm.runInContext(teardownScript, context);
    vm.runInContext(teardownScript, context);
    ordinary.form.submit();
    submitterWithForm('Download', 'campussquare.do', {_eventId: 'download'}, {}, newDocument).form.submit();
    return {oldPrototypeRestored, oldSubmitListenerRemoved, ordinarySubmitPrevented,
      topPrototypeRestored: topPrototype.submit === topOriginal,
      newPrototypeRestored: newPrototype.submit === newOriginal,
      submitListenersAfterTeardown: [topDocument, newDocument].filter(d => d.listeners.has('submit')).length,
      nativeSubmissions, captured};
  }

  const normalNavigationPrevented = click(anchor(
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
''';

/// Runs a node harness with its arguments passed through temp files: the
/// scripts exceed Windows' command-line length limit when inlined.
Future<ProcessResult> _runNode(
  List<String> harnessAndArgs, {
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) async {
  final dir = Directory.systemTemp.createTempSync('gakujo_download_capture_');
  try {
    final paths = <String>[];
    for (var i = 0; i < harnessAndArgs.length; i += 1) {
      final file = File('${dir.path}${Platform.pathSeparator}arg$i.txt')
        ..writeAsStringSync(harnessAndArgs[i]);
      paths.add(file.path);
    }
    final wrapper = File('${dir.path}${Platform.pathSeparator}run.js')
      ..writeAsStringSync(
        "const fs = require('fs');\n"
        "const [harness, ...args] = process.argv.slice(2)\n"
        "  .map((path) => fs.readFileSync(path, 'utf8'));\n"
        "process.argv = [process.argv[0], ...args];\n"
        'eval(harness);\n',
      );
    return await Process.run(
      'node',
      [wrapper.path, ...paths],
      stdoutEncoding: stdoutEncoding ?? utf8,
      stderrEncoding: stderrEncoding ?? utf8,
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}
