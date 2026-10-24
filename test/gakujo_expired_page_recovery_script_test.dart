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
    expect(result['stored'], {
      'iframe': _recovery(_flowStart, [100000])
    });
  });

  test('expiry text never navigates away from nonempty student edits',
      () async {
    for (final scenario in ['iframeExpired', 'topExpired']) {
      for (final field in [
        {'tagName': 'TEXTAREA', 'value': 'draft', 'defaultValue': 'draft'},
        {'tagName': 'DIV', 'textContent': 'draft'},
        {'tagName': 'DIV', 'innerText': 'draft'},
        for (final type in [
          'text',
          'search',
          'email',
          'url',
          'tel',
          'password',
          'number',
        ])
          {'tagName': 'INPUT', 'type': type, 'value': '42', 'defaultValue': ''},
      ]) {
        final result = await _evaluate(scenario, field: field);
        expect(result['frameReplacements'], isEmpty,
            reason: '$scenario $field');
        expect(result['topReplacements'], isEmpty, reason: '$scenario $field');
        expect(result['stored'], isNull);
      }
      for (final field in [
        {'tagName': 'TEXTAREA', 'value': ''},
        {'tagName': 'DIV', 'textContent': ''},
        {
          'tagName': 'INPUT',
          'type': 'text',
          'value': 'default',
          'defaultValue': 'default',
        },
        {
          'tagName': 'INPUT',
          'type': 'hidden',
          'value': 'token',
          'defaultValue': '',
        },
      ]) {
        final result = await _evaluate(scenario, field: field);
        final replacements = scenario == 'iframeExpired'
            ? 'frameReplacements'
            : 'topReplacements';
        expect(result[replacements], hasLength(1));
      }
    }
  });

  test(
      'recovery guards survive storage errors and cap each target for two minutes',
      () async {
    for (final scope in ['iframe', 'top']) {
      for (final storageMode in [
        'available',
        'readDenied',
        'writeDenied',
        'denied',
        'deniedTop',
      ]) {
        final result = await _evaluate('${scope}RecoveryLimit',
            injections: 2, storageMode: storageMode);
        expect(result['recoveryCounts'], [1, 1, 2, 3, 3, 4],
            reason: '$scope $storageMode');
        expect(result['otherTargetRecoveries'], 1,
            reason: '$scope $storageMode');
        expect(result['listenerCount'], 1);
      }
    }
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
    expect(result['stored'], {
      'iframe': _recovery(_flowStart, [100000])
    });
  });

  test('loop guard allows recovery again after ten seconds', () async {
    final result = await _evaluate('guardElapsed', injections: 2);
    expect(result['beforeLoad'], [_flowStart]);
    expect(result['frameReplacements'], [_flowStart, _flowStart]);
    expect(result['stored'], {
      'iframe': _recovery(_flowStart, [100000, 110000])
    });
  });

  test('loop guard allows a different flow start immediately', () async {
    final result = await _evaluate('differentTarget');
    const otherFlow =
        '$_origin/campusweb/campussquare.do?_flowId=KJW0001200-flow';
    expect(result['frameReplacements'], [_flowStart, otherFlow]);
    expect(result['stored'], {
      'iframe': _recovery(otherFlow, [100000, 100000])
    });
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
    expect(result['stored'], {
      'iframe': _recovery(_flowStart, [100000])
    });
  });

  for (final scenario in [
    'topExpired',
    'topKanjiExpired',
    'topTitleOnly',
    'topInnerTextExpired',
    'topTextContentExpired',
    'topShortExpiryBody',
  ]) {
    test('$scenario without an iframe replaces the location with the portal',
        () async {
      final result = await _evaluate(scenario);
      expect(result['topReplacements'], [_portal]);
      expect(result['frameReplacements'], isEmpty);
      expect(result['stored'], {
        'top': _recovery(_portal, [100000])
      });
    });
  }

  test('top-level recovery uses the same loop guard', () async {
    final result = await _evaluate('topExpired', injections: 2);
    expect(result['topReplacements'], [_portal]);
  });

  for (final scenario in [
    'topNormal',
    'topBodyBeyondLimit',
    'topExpiryNotice',
    'topLongExpiryBody',
  ]) {
    test('$scenario does not navigate', () async {
      final result = await _evaluate(scenario);
      expect(result['topReplacements'], isEmpty);
      expect(result['frameReplacements'], isEmpty);
      expect(result['stored'], isNull);
    });
  }
}

Map<String, dynamic> _recovery(String target, List<int> attempts) => {
      'target': target,
      'at': attempts.last,
      'attempts': attempts,
    };

Future<Map<String, dynamic>> _evaluate(String scenario,
    {int injections = 1,
    Map<String, String>? field,
    String? storageMode}) async {
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
            'field': field,
            'storageMode': storageMode,
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
const {scripts, scenario, field, storageMode} = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const origin = 'https://gakujo.iess.niigata-u.ac.jp';
const expiredTitle = 'ページの有効期限ぎれ';
const normalDoc = () => ({title: '連絡通知', body: {innerText: 'メッセージの本文'},
  querySelectorAll: () => field ? [field] : []});
const expiredDoc = () => ({
  title: expiredTitle,
  body: {innerText: 'ページの有効期限が過ぎています。 メニューから再度操作を行なってください。'},
  querySelectorAll: () => field ? [field] : []
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
let hasFrame = !scenario.startsWith('top') || scenario === 'topExpiredWithFrame';
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
if (scenario === 'topExpired' || scenario === 'topExpiredWithFrame' ||
    scenario === 'topRecoveryLimit') doc = expiredDoc();
if (scenario === 'topKanjiExpired') doc.title = 'ページの有効期限切れ';
if (scenario === 'topTitleOnly') {
  doc.title = expiredTitle;
  Object.defineProperty(doc, 'body', {get() { throw new Error('Body must not be read'); }});
}
const expiredMessage = 'ページの有効期限が過ぎています';
if (scenario === 'topInnerTextExpired') doc.body.innerText = expiredMessage;
if (scenario === 'topTextContentExpired') doc.body = {textContent: expiredMessage};
if (scenario === 'topBodyBeyondLimit') doc.body.innerText = 'x'.repeat(200) + expiredTitle;
if (scenario === 'topExpiryNotice') doc.body.innerText = 'ページの有効期限切れについてのお知らせ。通常の連絡通知です。';
if (scenario === 'topShortExpiryBody') doc.body.innerText = expiredMessage.padEnd(299, 'x');
if (scenario === 'topLongExpiryBody') doc.body.innerText = expiredMessage.padEnd(300, 'x');
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
    if (scenario === 'storageReadDenied' ||
        ['readDenied', 'denied', 'deniedTop'].includes(storageMode)) throw new Error('Storage read denied');
    return stored;
  },
  setItem(key, value) {
    if (key !== '__MBG_EXPIRED_RECOVERY') throw new Error('Unexpected storage key');
    if (scenario === 'storageWriteDenied' ||
        ['writeDenied', 'denied', 'deniedTop'].includes(storageMode)) throw new Error('Storage write denied');
    stored = value;
  }
};
const context = {document: doc, location, sessionStorage, URL, Date: {now: () => now}};
context.window = context;
context.top = {};
if (storageMode === 'deniedTop') {
  Object.defineProperty(context, 'top', {get() { throw new Error('Cross-origin top'); }});
}
// Use the same URL for both scopes to verify their budgets are independent.
if (scenario.endsWith('RecoveryLimit')) src = origin + '/campusweb/campusportal.do?page=main';
vm.createContext(context);
for (const script of scripts) vm.runInContext(script, context);
const beforeLoad = frameReplacements.slice();
if (scenario === 'laterLoad') frameWindow.document = expiredDoc();
if (scenario === 'guardElapsed') now += 10000;
if (scenario === 'differentTarget') src = '/campusweb/campussquare.do?_flowId=KJW0001200-flow';
if (['laterLoad', 'guardElapsed', 'differentTarget'].includes(scenario)) {
  for (const listener of listeners) listener();
}
let recoveryCounts = [], otherTargetRecoveries = 0;
if (scenario.endsWith('RecoveryLimit')) {
  const initialHasFrame = hasFrame;
  const replacements = hasFrame ? frameReplacements : topReplacements;
  recoveryCounts.push(replacements.length);
  for (const offset of [0, 40000, 80000, 119999]) {
    now = 100000 + offset;
    // A fresh iframe loses its own memory; the top window must retain the guard.
    if (storageMode !== 'deniedTop') delete context.__MBG_EXPIRED_RECOVERY;
    vm.runInContext(scripts[0], context);
    recoveryCounts.push(replacements.length);
  }
  hasFrame = !initialHasFrame;
  doc.title = expiredTitle;
  vm.runInContext(scripts[0], context);
  otherTargetRecoveries = (hasFrame ? frameReplacements : topReplacements).length;
  hasFrame = initialHasFrame;
  now = 220000;
  vm.runInContext(scripts[0], context);
  recoveryCounts.push(replacements.length);
}
process.stdout.write(JSON.stringify({
  frameReplacements, topReplacements, beforeLoad, recoveryCounts, otherTargetRecoveries,
  listenerCount: listeners.length,
  stored: stored ? JSON.parse(stored) : null
}));
''';
