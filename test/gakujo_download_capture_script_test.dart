import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_download_capture_script.dart';
import 'package:test/test.dart';

void main() {
  test('excludes submission workflow buttons from weak download capture', () {
    final script = GakujoDownloadCaptureScript.build();

    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_VERSION'));
    expect(script, contains('captureVersion = 8'));
    expect(script, contains('__MBG_ESTIMATE_COURSE_NAME'));
    expect(script, contains('removeEventListener'));
    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_HANDLER'));
    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_DOCUMENTS'));
    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_ATTACH'));
    expect(script, contains('function attachClickHandlers()'));
    expect(script, contains('documents[i].addEventListener'));
    expect(script, contains('removeEventListener'));
    expect(script, contains('firstMatchingCourseNameText'));
    expect(script, contains('sameRowValue'));
    expect(script, contains('科目名'));
    expect(script, contains(r'(?:[A-Z0-9]{4,}\s+)?'));
    expect(script, contains('isIgnoredCourseName'));
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
    expect(lifecycle['listenersAfterTeardown'], 0);
    expect(lifecycle['handlerCleared'], isTrue);
    expect(lifecycle['versionCleared'], isTrue);
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
  });
}

const _downloadCaptureLifecycleHarness = r'''
const vm = require('node:vm');
const buildScript = process.argv[1];
const teardownScript = process.argv[2];
const clickListeners = new Set();
const document = {
  addEventListener(type, handler) {
    if (type === 'click') clickListeners.add(handler);
  },
  removeEventListener(type, handler) {
    if (type === 'click') clickListeners.delete(handler);
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
vm.runInContext(teardownScript, context);
process.stdout.write(JSON.stringify({
  listenersAfterBuild,
  listenersAfterTeardown: clickListeners.size,
  handlerCleared: window.__MBG_DOWNLOAD_CAPTURE_HANDLER === null,
  versionCleared: window.__MBG_DOWNLOAD_CAPTURE_VERSION === null
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

function anchor(href, text) {
  const element = {
    ownerDocument: childDocument,
    innerText: text,
    textContent: text,
    value: '',
    getAttribute(name) { return name === 'href' ? href : null; },
    hasAttribute() { return false; },
    closest(selector) { return selector === 'a[href]' ? element : null; }
  };
  return element;
}

function submitterWithForm() {
  const form = {
    ownerDocument: childDocument,
    getAttribute(name) {
      if (name === 'action') return 'exports/form.pdf';
      if (name === 'method') return 'POST';
      return null;
    }
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
  '資料'
));
click(submitterWithForm());

process.stdout.write(JSON.stringify({
  normalNavigationPrevented,
  capturedUrls: captured.map((payload) => payload.url)
}));
''';
