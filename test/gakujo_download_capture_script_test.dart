import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_download_capture_script.dart';
import 'package:test/test.dart';

void main() {
  test('excludes submission workflow buttons from weak download capture', () {
    final script = GakujoDownloadCaptureScript.build();

    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_VERSION'));
    expect(script, contains('captureVersion = 12'));
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
        'isSubmissionWorkflowAction(submitter) && !hasStrongDownloadSignal',
      ),
    );
  });

  test('teardown removes the injected click handler', () async {
    final result = await Process.run(
        'node',
        [
          '-e',
          _downloadCaptureLifecycleHarness,
          GakujoDownloadCaptureScript.build(),
          GakujoDownloadCaptureScript.buildTeardown(),
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);

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
    final result = await Process.run(
        'node',
        [
          '-e',
          _downloadCaptureIframeReloadHarness,
          GakujoDownloadCaptureScript.build(),
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);

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
    final result = await Process.run(
        'node',
        [
          '-e',
          _downloadCaptureBehaviorHarness,
          GakujoDownloadCaptureScript.build(),
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8);

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
  set() {}
  forEach() {}
}

function anchor(href, text, downloadName) {
  const element = {
    ownerDocument: childDocument,
    innerText: text,
    textContent: text,
    value: '',
    getAttribute(name) {
      if (name === 'href') return href;
      if (name === 'download') return downloadName || null;
      return null;
    },
    hasAttribute(name) { return name === 'download' && !!downloadName; },
    closest(selector) { return selector === 'a[href]' ? element : null; }
  };
  return element;
}

function submitterWithForm() {
  const internalFileName = {
    name: 'fileName',
    id: 'fileName',
    value: 'internal_004281.pdf',
    getAttribute(name) {
      if (name === 'name' || name === 'id') return 'fileName';
      return null;
    }
  };
  const form = {
    ownerDocument: childDocument,
    querySelectorAll() { return [internalFileName]; },
    getAttribute(name) {
      if (name === 'action') return 'exports/form.pdf';
      if (name === 'method') return 'POST';
      return null;
    }
  };
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
    ownerDocument: childDocument,
    form,
    name: '',
    value: 'ダウンロード',
    innerText: 'ダウンロード',
    textContent: 'ダウンロード',
    getAttribute() { return null; },
    hasAttribute() { return false; },
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
  childDocument.listeners.get('click')({
    target,
    preventDefault() { prevented = true; },
    stopPropagation() {}
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

process.stdout.write(JSON.stringify({
  normalNavigationPrevented,
  capturedUrls: captured.map((payload) => payload.url),
  capturedNames: captured.map((payload) => payload.fileName)
}));
''';
