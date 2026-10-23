import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_expired_page_recovery_script.dart';
import 'package:test/test.dart';

const _origin = 'https://gakujo.iess.niigata-u.ac.jp';
const _flowStart = '$_origin/campusweb/campussquare.do?_flowId=KJW0001100-flow';
const _portal = '$_origin/campusweb/campusportal.do?page=main';

void main() {
  test('expired iframe replaces its location with the absolute flow start',
      () async {
    final result = await _evaluate('iframeExpired');
    expect(result['frameReplacements'], [_flowStart]);
    expect(result['topReplacements'], isEmpty);
    expect(result['stored'], {'target': _flowStart, 'at': 100000});
  });

  for (final scenario in [
    'iframeNormal',
    'executionKey',
    'otherOrigin',
    'missingSrc',
    'invalidSrc',
    'frameDenied',
    'topExpiredWithFrame',
  ]) {
    test('$scenario does not navigate or record a recovery', () async {
      final result = await _evaluate(scenario);
      expect(result['frameReplacements'], isEmpty);
      expect(result['topReplacements'], isEmpty);
      expect(result['stored'], isNull);
    });
  }

  test('reinjection attaches one listener and later iframe loads recover',
      () async {
    final result = await _evaluate('laterLoad', injections: 2);
    expect(result['listenerCount'], 1);
    expect(result['beforeLoad'], isEmpty);
    expect(result['frameReplacements'], [_flowStart]);
    expect(result['topReplacements'], isEmpty);
  });

  test('same target is recovered only once within ten seconds', () async {
    final result = await _evaluate('iframeExpired', injections: 2);
    expect(result['listenerCount'], 1);
    expect(result['frameReplacements'], [_flowStart]);
    expect(result['stored'], {'target': _flowStart, 'at': 100000});
  });

  test('loop guard allows recovery again after ten seconds', () async {
    final result = await _evaluate('guardElapsed', injections: 2);
    expect(result['beforeLoad'], [_flowStart]);
    expect(result['frameReplacements'], [_flowStart, _flowStart]);
    expect(result['stored'], {'target': _flowStart, 'at': 110000});
  });

  test('loop guard allows a different flow start immediately', () async {
    final result = await _evaluate('differentTarget');
    const otherFlow =
        '$_origin/campusweb/campussquare.do?_flowId=KJW0001200-flow';
    expect(result['frameReplacements'], [_flowStart, otherFlow]);
    expect(result['stored'], {'target': otherFlow, 'at': 100000});
  });

  for (final scenario in ['storageReadDenied', 'storageWriteDenied']) {
    test('$scenario still recovers the expired iframe', () async {
      final result = await _evaluate(scenario);
      expect(result['frameReplacements'], [_flowStart]);
      expect(result['topReplacements'], isEmpty);
    });
  }

  test('malformed stored recovery is replaced with a working loop guard',
      () async {
    final result = await _evaluate('malformedStorage', injections: 2);
    expect(result['frameReplacements'], [_flowStart]);
    expect(result['stored'], {'target': _flowStart, 'at': 100000});
  });

  for (final scenario in [
    'topExpired',
    'topKanjiExpired',
    'topTitleOnly',
    'topInnerTextExpired',
    'topTextContentExpired',
  ]) {
    test('$scenario without an iframe replaces the location with the portal',
        () async {
      final result = await _evaluate(scenario);
      expect(result['topReplacements'], [_portal]);
      expect(result['frameReplacements'], isEmpty);
      expect(result['stored'], {'target': _portal, 'at': 100000});
    });
  }

  test('top-level recovery uses the same loop guard', () async {
    final result = await _evaluate('topExpired', injections: 2);
    expect(result['topReplacements'], [_portal]);
  });

  for (final scenario in ['topNormal', 'topBodyBeyondLimit']) {
    test('$scenario does not navigate', () async {
      final result = await _evaluate(scenario);
      expect(result['topReplacements'], isEmpty);
      expect(result['frameReplacements'], isEmpty);
      expect(result['stored'], isNull);
    });
  }
}

Future<Map<String, dynamic>> _evaluate(String scenario,
    {int injections = 1}) async {
  final directory =
      Directory.systemTemp.createTempSync('gakujo_expired_page_recovery_');
  try {
    final harnessFile = File.fromUri(directory.uri.resolve('harness.js'))
      ..writeAsStringSync(_domHarness, encoding: utf8);
    final inputFile = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
          jsonEncode({
            'scripts': List.filled(
                injections, GakujoExpiredPageRecoveryScript.build()),
            'scenario': scenario,
          }),
          encoding: utf8);
    final result = await Process.run('node', [harnessFile.path, inputFile.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(result.exitCode, 0, reason: 'Node failed: ${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } finally {
    directory.deleteSync(recursive: true);
  }
}

const _domHarness = r'''
const vm = require('node:vm');
const {scripts, scenario} = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const origin = 'https://gakujo.iess.niigata-u.ac.jp';
const expiredTitle = 'ページの有効期限ぎれ';
const normalDoc = () => ({title: '連絡通知', body: {innerText: 'メッセージの本文'}});
const expiredDoc = () => ({
  title: expiredTitle,
  body: {innerText: 'ページの有効期限が過ぎています。 メニューから再度操作を行なってください。'}
});
const frameReplacements = [], topReplacements = [], listeners = [];
let now = 100000;
let stored = scenario === 'malformedStorage' ? '{invalid json' : null;
const frameWindow = {
  document: expiredDoc(),
  location: {replace: target => frameReplacements.push(target)}
};
let src = '/campusweb/campussquare.do?_flowId=KJW0001100-flow';
const frame = {
  contentWindow: frameWindow,
  get contentDocument() { return frameWindow.document; },
  getAttribute(name) { return name === 'src' ? src : null; },
  addEventListener(name, callback) {
    if (name !== 'load') throw new Error('Unexpected event: ' + name);
    listeners.push(callback);
  }
};
const hasFrame = !scenario.startsWith('top') || scenario === 'topExpiredWithFrame';
let doc = normalDoc();
if (scenario === 'iframeNormal' || scenario === 'laterLoad' ||
    scenario === 'topExpiredWithFrame') frameWindow.document = normalDoc();
if (scenario === 'executionKey') src = '/campusweb/campussquare.do?_flowExecutionKey=stale-key';
if (scenario === 'otherOrigin') src = 'https://example.com/campusweb/campussquare.do?_flowId=flow';
if (scenario === 'missingSrc') src = null;
if (scenario === 'invalidSrc') src = 'https://[';
if (scenario === 'frameDenied') {
  Object.defineProperty(frame, 'contentDocument', {get() { return null; }});
  Object.defineProperty(frameWindow, 'document', {get() { throw new Error('Access denied'); }});
}
if (scenario === 'topExpired' || scenario === 'topExpiredWithFrame') doc = expiredDoc();
if (scenario === 'topKanjiExpired') doc.title = 'ページの有効期限切れ';
if (scenario === 'topTitleOnly') {
  doc.title = expiredTitle;
  Object.defineProperty(doc, 'body', {get() { throw new Error('Body must not be read'); }});
}
if (scenario === 'topInnerTextExpired') doc.body.innerText = 'ページの有効期限切れ';
if (scenario === 'topTextContentExpired') doc.body = {textContent: expiredTitle};
if (scenario === 'topBodyBeyondLimit') doc.body.innerText = 'x'.repeat(200) + expiredTitle;
doc.getElementById = id => id === 'main-frame-if' && hasFrame ? frame : null;
const location = {
  origin,
  href: origin + (hasFrame ? '/campusweb/campusportal.do?page=main&tabId=XX'
    : '/campusweb/campussquare.do?_flowExecutionKey=stale-key'),
  replace: target => topReplacements.push(target)
};
const sessionStorage = {
  getItem(key) {
    if (key !== '__MBG_EXPIRED_RECOVERY') throw new Error('Unexpected storage key');
    if (scenario === 'storageReadDenied') throw new Error('Storage read denied');
    return stored;
  },
  setItem(key, value) {
    if (key !== '__MBG_EXPIRED_RECOVERY') throw new Error('Unexpected storage key');
    if (scenario === 'storageWriteDenied') throw new Error('Storage write denied');
    stored = value;
  }
};
const context = {document: doc, location, sessionStorage, URL, Date: {now: () => now}};
context.window = context;
vm.createContext(context);
for (const script of scripts) vm.runInContext(script, context);
const beforeLoad = frameReplacements.slice();
if (scenario === 'laterLoad') frameWindow.document = expiredDoc();
if (scenario === 'guardElapsed') now += 10000;
if (scenario === 'differentTarget') src = '/campusweb/campussquare.do?_flowId=KJW0001200-flow';
if (['laterLoad', 'guardElapsed', 'differentTarget'].includes(scenario)) {
  for (const listener of listeners) listener();
}
process.stdout.write(JSON.stringify({
  frameReplacements, topReplacements, beforeLoad,
  listenerCount: listeners.length,
  stored: stored ? JSON.parse(stored) : null
}));
''';
