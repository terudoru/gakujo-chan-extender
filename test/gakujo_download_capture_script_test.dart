import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_download_capture_script.dart';
import 'package:test/test.dart';

void main() {
  test('excludes submission workflow buttons from weak download capture', () {
    final script = GakujoDownloadCaptureScript.build();

    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_VERSION'));
    expect(script, contains('captureVersion = 7'));
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
    final result = await Process.run('node', [
      '-e',
      _downloadCaptureLifecycleHarness,
      GakujoDownloadCaptureScript.build(),
      GakujoDownloadCaptureScript.buildTeardown(),
    ]);

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
