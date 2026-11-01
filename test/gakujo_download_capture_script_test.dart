import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_download_capture_script.dart';
import 'package:test/test.dart';

void main() {
  test('excludes submission workflow buttons from weak download capture', () {
    final script = GakujoDownloadCaptureScript.build();

    expect(script, contains('__MBG_DOWNLOAD_CAPTURE_VERSION'));
    expect(script, contains('captureVersion = 18'));
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
      'test/support/gakujo_download_capture_script_download_capture_lifecycle_harness.cts',
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
      'test/support/gakujo_download_capture_script_download_capture_iframe_reload_harness.cts',
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
      'test/support/gakujo_download_capture_script_download_capture_behavior_harness.cts',
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

  test('download labels cannot turn Gakujo page navigation into downloads',
      () async {
    final result = await _evaluateBehavior('navigationLabels');
    expect(result['navigationPrevented'], everyElement(isFalse));
    expect(result['downloadPrevented'], everyElement(isTrue));
    expect(result['captured'], hasLength(5));
  });

  test('page handlers run before capture and plain attachments capture once',
      () async {
    final result = await _evaluateBehavior('pageHandlers');
    expect(result['handlerPrevented'], everyElement(isFalse));
    expect(result['handlerStopped'], everyElement(isFalse));
    expect(result['handlersRun'], 6);
    expect(result['plainPrevented'], everyElement(isTrue));
    expect(result['captured'], hasLength(8));
    final urls = (result['captured'] as List)
        .cast<Map>()
        .map((payload) => payload['url']);
    expect(urls, everyElement(contains('fileId=')));
    expect(urls.toSet(), hasLength(8));
    expect(result['nativeSubmissions'], 0);
  });

  test('onclick anchors capture real download URLs exactly once', () async {
    final result = await _evaluateBehavior('onclickAttachments');
    expect(result['prevented'], [false, false, false, false, true, true, true]);
    expect(result['handlersRun'], 4);
    final urls = (result['captured'] as List)
        .cast<Map>()
        .map((payload) => payload['url']);
    expect(urls, hasLength(3));
    expect(urls.toSet(), hasLength(3));
    expect(urls.first, endsWith('SDW-filerefer-flow&fileId=41881'));
    expect(result['nativeSubmissions'], 0);
  });

  test('onclick filerefer details stay navigable and attachments capture once',
      () async {
    final result = await _evaluateBehavior('onclickFilereferDetails');
    expect(result['prevented'], [false, false, false, false, true, true]);
    expect(result['handlersRun'], 4);
    final urls = (result['captured'] as List)
        .cast<Map>()
        .map((payload) => payload['url']);
    expect(urls, hasLength(2));
    expect(urls.toSet(), hasLength(2));
    expect(urls.first, endsWith('SDW-filerefer-flow&fileId=41881'));
    expect(urls.last, endsWith('fileId=41882&_eventId=download'));
  });

  test('submitter overrides govern capture and native fallback', () async {
    final result = await _evaluateBehavior('submitterOverrides');
    expect(
      result['prevented'],
      [true, false, false, true, true, false, false, true],
    );
    final payloads = (result['captured'] as List).cast<Map>();
    expect(payloads, hasLength(4));
    expect(payloads.map((payload) => payload['method']),
        ['POST', 'GET', 'POST', 'GET']);
    for (final payload in payloads) {
      expect(payload['formFields'], {'_eventId': 'download'});
    }
    expect(payloads.map((payload) => payload['url']), [
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/child/exports/override.pdf',
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/child/page.do',
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/child/exports/override.pdf',
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/child/page.do',
    ]);
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

  for (final scenario in [
    'listenerConfirm',
    'workflowSubmissions',
    'nonExplicitSubmissions',
  ]) {
    test('$scenario submits natively without capturing form text', () async {
      final result = await _evaluateBehavior(scenario);
      expect(result['prevented'], everyElement(isFalse));
      expect(result['nativeSubmissions'], result['expectedSubmissions']);
      expect(result['captured'], isEmpty);
    });
  }

  test('submission hooks capture only explicit download requests', () async {
    final result = await _evaluateBehavior('explicitSubmissions');
    expect(result['prevented'], everyElement(isTrue));
    expect(result['nativeSubmissions'], 0);
    expect((result['captured'] as List).length, 8);
  });

  test('programmatic bulk downloads capture POST fields in top and frame',
      () async {
    final result = await _evaluateBehavior('multiDownloadSubmissions');
    expect(result['nativeSubmissions'], 0);
    expect(result['hookCount'], 2);
    final payloads = (result['captured'] as List).cast<Map>();
    expect(payloads, hasLength(2));
    for (final payload in payloads) {
      expect(payload['url'],
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do');
      expect(payload['method'], 'POST');
      expect(payload['fileName'], '');
      expect(payload['formFields'], {
        '_flowId': 'SDW-filerefer-flow',
        'downloadType': 'multi',
        'fileId': '41881,41882',
      });
    }
  });

  test('file refer and download type signals respect workflow vetoes',
      () async {
    final result = await _evaluateBehavior('fileReferSubmissions');
    expect(result['captured'], hasLength(6));
    expect(result['nativeSubmissions'], result['expectedSubmissions']);
  });

  test('app-owned bulk forms and unrelated programmatic submits stay native',
      () async {
    final result = await _evaluateBehavior('ownedMultiDownloadSubmissions');
    expect(result['captured'], isEmpty);
    expect(result['nativeSubmissions'], 7);
  });

  test('requestSubmit uses the submit handler without a prototype hook',
      () async {
    final result = await _evaluateBehavior('requestSubmit');
    expect(result['prototypeUnchanged'], isTrue);
    expect(result['captured'], hasLength(1));
    expect(result['nativeSubmissions'], 1);
  });

  test('file actions capture programmatic POST bodies and veto workflow events',
      () async {
    final result = await _evaluateBehavior('fileActionSubmissions');
    expect(result['prevented'], everyElement(isTrue));
    expect(result['workflowPrevented'], everyElement(isFalse));
    expect(result['nativeSubmissions'], result['workflowSubmissions']);
    final payloads = result['captured'] as List;
    expect(payloads, hasLength(28));
    for (final payload in payloads.cast<Map>()) {
      expect(payload['method'], 'POST');
      expect(payload['url'], contains('/child/exports/form.'));
      expect(payload['formFields'], {'selectedFileId': 'current-file'});
    }
  });

  test('named Spring Web Flow events veto workflows and allow downloads',
      () async {
    final submit = await _evaluateBehavior('namedWorkflowSubmit');
    expect(submit['nativeSubmissions'], 1);
    expect(submit['captured'], isEmpty);

    final result = await _evaluateBehavior('namedEventSubmissions');
    expect(result['workflowPrevented'], everyElement(isFalse));
    expect(result['nativeSubmissions'], result['workflowSubmissions']);
    expect(result['downloadPrevented'], everyElement(isTrue));
    expect(result['captured'], hasLength(5));
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
    expect((result['captured'] as List).length, 3);
  });
}

Future<Map<String, dynamic>> _evaluateBehavior(String scenario) async {
  final result = await _runNode([
    'test/support/gakujo_download_capture_script_download_capture_behavior_harness.cts',
    GakujoDownloadCaptureScript.build(),
    scenario,
    GakujoDownloadCaptureScript.buildTeardown(),
  ], stdoutEncoding: utf8, stderrEncoding: utf8);
  expect(result.exitCode, 0, reason: result.stderr as String);
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}







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
    for (var i = 1; i < harnessAndArgs.length; i += 1) {
      final file = File('${dir.path}${Platform.pathSeparator}arg$i.txt')
        ..writeAsStringSync(harnessAndArgs[i]);
      paths.add(file.path);
    }
    return await Process.run(
      'node',
      [harnessAndArgs.first, ...paths],
      stdoutEncoding: stdoutEncoding ?? utf8,
      stderrEncoding: stderrEncoding ?? utf8,
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}
