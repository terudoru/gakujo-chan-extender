import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_timeout_popup_script.dart';
import 'package:test/test.dart';

const _origin = 'https://gakujo.iess.niigata-u.ac.jp';
const _warning = '学務のセッションは残り約5分で切れます。';
const _expired = '学務のセッションが切れました。入力中のレポートは下書きに保存されています。もう一度開くと復元されます。';

void main() {
  for (final page in ['TimeoutAlert', 'Timeout']) {
    for (final url in [
      '/campusweb/theme/default/$page.html',
      '$_origin/campusweb/theme/default/$page.html',
      '/campusweb/theme/default/$page.html?remaining=5',
      '$_origin/campusweb/theme/default/$page.html?remaining=5#timer',
      '/campusweb/theme/default/$page.html#timer',
    ]) {
      test('$url is intercepted with a harmless popup stub', () async {
        final result = await _evaluate('popup', url: url);
        expect(result['openCalls'], isEmpty);
        expect(result['stub'], {
          'closedBefore': false,
          'closedAfter': false,
          'focusResult': null,
          'blurResult': null,
          'document': null,
          'location': null,
        });
        expect(result['bannerCount'], 1);
        expect(result['message'], page == 'TimeoutAlert' ? _warning : _expired);
        expect(result['buttons'],
            page == 'TimeoutAlert' ? ['延長する', '閉じる'] : ['閉じる']);
        expect(result['alertUnchanged'], isTrue);
      });
    }
  }

  test('relative timeout URLs are resolved before interception', () async {
    for (final page in ['TimeoutAlert', 'Timeout']) {
      for (final prefix in ['theme/default/', './theme/default/']) {
        final result = await _evaluate('popup', url: '$prefix$page.html');
        expect(result['openCalls'], isEmpty);
        expect(result['bannerCount'], 1);
        expect(result['message'], page == 'TimeoutAlert' ? _warning : _expired);
      }
    }
  });

  test('extend uses the intercepted iframe before the top window', () async {
    for (final scenario in ['iframeOwnExtend', 'iframeOwnExtendWithTop']) {
      final result = await _evaluate(scenario);
      expect(result['extendCalls'], 1);
      expect(result['extendThisIsFrame'], isTrue);
      expect(result['bannerCount'], 0);
      expect(result['openCalls'], isEmpty);
    }
  });

  test('closing the fake popup removes its timeout banner', () async {
    for (final scenario in ['popupClose', 'iframePopupClose']) {
      final result = await _evaluate(scenario);
      expect(result['bannerBeforeClose'], isTrue);
      expect(result['stub']['closedBefore'], isFalse);
      expect(result['stub']['closedAfter'], isTrue);
      expect(result['bannerCount'], 0);
      expect(result['extendCalls'], 0);
    }
  });

  test('closing an older popup keeps a newer timeout message', () async {
    final result = await _evaluate('staleClose');
    expect(result['bannerCount'], 1);
    expect(result['message'], _expired);
  });

  test('extend button calls the portal function and removes the banner',
      () async {
    final result = await _evaluate('extend');
    expect(result['extendCalls'], 1);
    expect(result['extendThisIsWindow'], isTrue);
    expect(result['bannerCount'], 0);
    expect(result['openCalls'], isEmpty);
  });

  for (final scenario in ['extendMissing', 'extendNotFunction']) {
    test('$scenario keeps the warning without throwing', () async {
      final result = await _evaluate(scenario);
      expect(result['extendCalls'], 0);
      expect(result['message'], _warning);
      expect(result['bannerCount'], 1);
    });
  }

  for (final scenario in ['closeWarning', 'closeExpired']) {
    test('$scenario dismisses the banner', () async {
      final result = await _evaluate(scenario);
      expect(result['bannerCount'], 0);
      expect(result['extendCalls'], 0);
    });
  }

  for (final scenario in ['warningThenExpired', 'expiredThenWarning']) {
    test('$scenario replaces the existing message and buttons', () async {
      final result = await _evaluate(scenario);
      final isWarning = scenario == 'expiredThenWarning';
      expect(result['sameBanner'], isTrue);
      expect(result['bannerCount'], 1);
      expect(result['message'], isWarning ? _warning : _expired);
      expect(result['buttons'], isWarning ? ['延長する', '閉じる'] : ['閉じる']);
    });
  }

  for (final url in [
    '/campusweb/report.do',
    '$_origin/campusweb/theme/default/Help.html',
    '/campusweb/theme/default/Timeout.html.bak',
    '/campusweb/theme/default/TimeoutAlert.html/extra',
    '/campusweb/theme/other/Timeout.html',
    '',
  ]) {
    test('$url preserves the original open arguments and return value',
        () async {
      final result = await _evaluate('passthrough', url: url);
      expect(result['openCalls'], [
        {
          'window': 'top',
          'args': [url, 'report-window', 'width=750,height=240', true],
        },
      ]);
      expect(result['sameReturnValue'], isTrue);
      expect(result['sameArguments'], isTrue);
      expect(result['sameReceiver'], isTrue);
      expect(result['bannerCount'], 0);
    });
  }

  test('reinjection preserves both wrappers and attaches one load listener',
      () async {
    final result = await _evaluate('popup', injections: 2);
    expect(result['sameTopWrapper'], isTrue);
    expect(result['sameFrameWrapper'], isTrue);
    expect(result['listenerCount'], 1);
    expect(result['bannerCount'], 1);
    expect(result['openCalls'], isEmpty);
  });

  for (final scenario in ['iframePopup', 'iframeReload', 'iframeExtend']) {
    test('$scenario intercepts iframe popups in the top document', () async {
      final result = await _evaluate(scenario, injections: 2);
      expect(result['openCalls'], isEmpty);
      expect(result['frameBannerCount'], 0);
      expect(result['listenerCount'], 1);
      if (scenario == 'iframeExtend') {
        expect(result['extendCalls'], 1);
        expect(result['extendThisIsWindow'], isTrue);
        expect(result['bannerCount'], 0);
      } else {
        expect(result['message'], _warning);
        expect(result['bannerCount'], 1);
      }
    });
  }

  test('other iframe popups preserve arguments, receiver and return value',
      () async {
    final result = await _evaluate('iframePassthrough');
    expect(result['openCalls'], [
      {
        'window': 'frame',
        'args': [
          '/campusweb/report.do',
          'report-window',
          'width=750,height=240',
          true,
        ],
      },
    ]);
    expect(result['sameArguments'], isTrue);
    expect(result['sameReceiver'], isTrue);
    expect(result['sameReturnValue'], isTrue);
    expect(result['bannerCount'], 0);
  });

  for (final scenario in ['noFrame', 'frameDenied', 'frameDeniedOnLoad']) {
    test('$scenario still intercepts top document popups', () async {
      final result = await _evaluate(scenario);
      expect(result['openCalls'], isEmpty);
      expect(result['message'], _warning);
      expect(result['bannerCount'], 1);
    });
  }
}

Future<Map<String, dynamic>> _evaluate(String scenario,
    {String? url, int injections = 1}) async {
  final directory =
      Directory.systemTemp.createTempSync('gakujo_timeout_popup_');
  try {
    final harnessFile = File.fromUri(directory.uri.resolve('harness.js'))
      ..writeAsStringSync(_domHarness, encoding: utf8);
    final inputFile = File.fromUri(directory.uri.resolve('input.json'))
      ..writeAsStringSync(
          jsonEncode({
            'scripts':
                List.filled(injections, GakujoTimeoutPopupScript.build()),
            'scenario': scenario,
            'url': url,
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
const {scripts, scenario, url} = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const origin = 'https://gakujo.iess.niigata-u.ac.jp';
class Element {
  constructor(tagName) {
    this.tagName = tagName;
    this.children = [];
    this.style = {};
    this.listeners = {};
    this.attributes = {};
    this.parentNode = null;
    this.text = '';
  }
  set textContent(value) {
    for (const child of this.children) child.parentNode = null;
    this.children = [];
    this.text = value;
  }
  get textContent() {
    return this.text + this.children.map(child => child.textContent).join('');
  }
  appendChild(child) {
    child.parentNode = this;
    this.children.push(child);
    return child;
  }
  remove() {
    if (!this.parentNode) return;
    const siblings = this.parentNode.children;
    siblings.splice(siblings.indexOf(this), 1);
    this.parentNode = null;
  }
  setAttribute(name, value) { this.attributes[name] = value; }
  addEventListener(name, callback) {
    (this.listeners[name] ||= []).push(callback);
  }
  click() {
    for (const callback of this.listeners.click || []) callback();
  }
}
function descendants(element) {
  return element.children.flatMap(child => [child, ...descendants(child)]);
}
function createDocument() {
  const body = new Element('body');
  return {
    body,
    createElement: tagName => new Element(tagName),
    getElementById: id => descendants(body).find(element => element.id === id) || null
  };
}
const doc = createDocument();
const openCalls = [], listeners = [];
const originalResult = {originalPopup: true};
let receivedArgs, receivedThis;
function originalOpen(name) {
  return function(...args) {
    receivedArgs = args;
    receivedThis = this;
    openCalls.push({window: name, args});
    return originalResult;
  };
}
function createFrameWindow() {
  return {document: createDocument(), open: originalOpen('frame'),
    location: {href: origin + '/campusweb/campussquare.do?_flowId=flow'}};
}
const frameDocument = createDocument();
let frameWindow = createFrameWindow();
let denyFrame = scenario === 'frameDenied';
const frame = {
  get contentWindow() { return frameWindow; },
  addEventListener(name, callback) {
    if (name !== 'load') throw new Error('Unexpected event: ' + name);
    listeners.push(callback);
  }
};
Object.defineProperty(frameWindow, 'document', {
  configurable: true,
  get() {
    if (denyFrame) throw new Error('Access denied');
    return frameDocument;
  }
});
const getElementById = doc.getElementById;
doc.getElementById = id => id === 'main-frame-if' && scenario !== 'noFrame'
  ? frame : getElementById(id);
const originalAlert = function() {};
const context = {document: doc, open: originalOpen('top'), alert: originalAlert,
  URL, location: {href: origin + '/campusweb/campusportal.do?page=main'}};
context.window = context;
context.top = context.parent = context;
vm.createContext(context);
let extendCalls = 0, extendThisIsWindow = false, extendThisIsFrame = false;
context.recordExtend = function(receiver) {
  extendCalls += 1;
  extendThisIsWindow = receiver === vm.runInContext('window', context);
  extendThisIsFrame = receiver === frameWindow;
};
if (scenario !== 'extendMissing' && scenario !== 'iframeOwnExtend') {
  vm.runInContext(scenario === 'extendNotFunction'
    ? 'window.extendSession = true;'
    : 'window.extendSession = function() { recordExtend(this); };', context);
}
if (scenario.startsWith('iframeOwnExtend')) {
  frameWindow.extendSession = function() { context.recordExtend(this); };
}
let topWrapper, frameWrapper;
for (const script of scripts) {
  vm.runInContext(script, context);
  if (!topWrapper) {
    topWrapper = context.open;
    frameWrapper = frameWindow.open;
  }
}
const sameTopWrapper = context.open === topWrapper;
const sameFrameWrapper = frameWindow.open === frameWrapper;
if (scenario === 'iframeReload') {
  frameWindow = createFrameWindow();
  for (const listener of listeners) listener();
}
if (scenario === 'frameDeniedOnLoad') {
  denyFrame = true;
  for (const listener of listeners) listener();
}
const warningUrl = '/campusweb/theme/default/TimeoutAlert.html';
const expiredUrl = '/campusweb/theme/default/Timeout.html';
const passthrough = scenario === 'passthrough' || scenario === 'iframePassthrough';
const target = scenario.startsWith('iframe') ? frameWindow : context;
const args = [url ?? (passthrough ? '/campusweb/report.do'
  : scenario === 'closeExpired' || scenario === 'expiredThenWarning' ? expiredUrl : warningUrl),
  'report-window', 'width=750,height=240', true];
const result = target.open(...args);
const bannerBeforeClose = !!doc.getElementById('mbg-timeout-banner');
let stub = null;
if (!passthrough && result !== originalResult) {
  const closedBefore = result.closed;
  const focusResult = result.focus();
  const blurResult = result.blur();
  if (scenario === 'popupClose' || scenario === 'iframePopupClose') {
    result.close();
    result.close();
  }
  stub = {closedBefore, closedAfter: result.closed,
    focusResult: focusResult ?? null, blurResult: blurResult ?? null,
    document: result.document, location: result.location};
}
const firstBanner = doc.getElementById('mbg-timeout-banner');
if (scenario === 'warningThenExpired') context.open(expiredUrl);
if (scenario === 'staleClose') {
  context.open(expiredUrl);
  result.close();
}
if (scenario === 'expiredThenWarning') context.open(warningUrl);
if (['extend', 'extendMissing', 'extendNotFunction', 'iframeExtend'].includes(scenario) ||
    scenario.startsWith('iframeOwnExtend')) {
  firstBanner.children.find(child => child.textContent === '延長する').click();
}
if (scenario === 'closeWarning' || scenario === 'closeExpired') {
  firstBanner.children.find(child => child.textContent === '閉じる').click();
}
const banner = doc.getElementById('mbg-timeout-banner');
process.stdout.write(JSON.stringify({
  openCalls, stub, extendCalls, extendThisIsWindow, extendThisIsFrame, bannerBeforeClose,
  bannerCount: descendants(doc.body).filter(element => element.id === 'mbg-timeout-banner').length,
  frameBannerCount: scenario === 'frameDenied' || scenario === 'frameDeniedOnLoad' ? null
    : descendants(frameWindow.document.body).filter(element => element.id === 'mbg-timeout-banner').length,
  message: banner ? banner.children[0].textContent : null,
  buttons: banner ? banner.children.filter(child => child.tagName === 'button').map(child => child.textContent) : [],
  sameBanner: banner === firstBanner,
  sameTopWrapper, sameFrameWrapper, listenerCount: listeners.length,
  sameReturnValue: result === originalResult,
  sameArguments: !!receivedArgs && receivedArgs.length === args.length && receivedArgs.every((arg, i) => arg === args[i]),
  sameReceiver: receivedThis === target,
  alertUnchanged: context.alert === originalAlert
}));
''';
