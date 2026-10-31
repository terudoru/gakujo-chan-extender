import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/desktop_page_zoom_script.dart';
import 'package:test/test.dart';

void main() {
  test('wheel zoom follows delta size and ignores horizontal-only input', () {
    expect(desktopWheelZoom(1, 0), 1);
    expect(desktopWheelZoom(1, -1), closeTo(1.001, .0001));
    expect(desktopWheelZoom(1, -100), closeTo(1.105, .001));
    expect(desktopWheelZoom(1, 100), closeTo(.905, .001));
    expect(desktopWheelZoom(1, -10000), lessThan(1.3));
  });
  test('uses visual transform zoom without relayout zoom CSS', () {
    final script = DesktopPageZoomScript.build(
      1.25,
      originX: 320,
      originY: 180,
    );

    expect(
        script,
        contains(
          'body.style.transform = "scale(" + effectiveZoom + ")"',
        ));
    expect(script, contains('element.style.minWidth'));
    expect(script, contains('element.style.minHeight'));
    expect(script, isNot(contains('appendChild')));
    expect(script, isNot(contains('insertBefore')));
    expect(script, contains('body.style.transformOrigin = "0 0"'));
    expect(script, isNot(contains('style.zoom = Math.round')));
    expect(script, isNot(contains('__MBG_REFLOW_WEB_VIEW')));
    expect(script, isNot(contains('__MBG_STEP_PAGE_ZOOM')));
  });

  test('blocks native webview zoom handlers without changing zoom internally',
      () {
    final script = DesktopPageZoomScript.build(1.25);

    expect(script, contains('attachNativeZoomBlockers'));
    expect(script, contains('event.preventDefault()'));
    expect(script, isNot(contains('stepZoom')));
  });

  test('focused WebView shortcuts post app zoom actions from all frames',
      () async {
    final result = await Process.run(
      'node',
      ['-e', _shortcutHarness, DesktopPageZoomScript.build(1.25)],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(data['actions'], ['in', 'in', 'out', 'out', 'reset', 'in']);
    expect(
        data['prevented'], [true, true, true, true, true, true, false, false]);
    expect(data['zoom'], 1.25,
        reason: 'the app owns zoom state and applies the toolbar step logic');
    expect(data['keydownListeners'], [1, 1],
        reason: 'reapplying zoom must not multiply shortcut messages');
  });

  test('clears visual zoom state at 100 percent', () {
    final script = DesktopPageZoomScript.build(1);

    expect(script, contains('if (Math.abs(effectiveZoom - 1) < 1e-3)'));
    expect(script, contains('body.style.transform = ""'));
    expect(script, contains('body.style.minWidth = ""'));
    expect(script, contains('body.style.minHeight = ""'));
    expect(script, contains('element.style.minWidth = ""'));
    expect(script, contains('element.style.minHeight = ""'));
  });

  test('fits the 100 percent baseline to the current desktop viewport', () {
    final script = DesktopPageZoomScript.build(1);

    expect(script, contains('function fitScaleFor(win, size)'));
    expect(script, contains('var scale = viewportWidth / size.width'));
    expect(script, contains('return Math.max(0.5, Math.min(1, scale))'));
    expect(script, contains('var effectiveZoom = zoom * baseScale'));
  });

  test('reapplies baseline when the desktop page shape changes', () {
    final script = DesktopPageZoomScript.build(1);

    expect(script, contains('addEventListener("resize"'));
    expect(script, contains('new win.MutationObserver'));
    expect(script, contains('scheduleReapply(win)'));
  });

  test('applies visual zoom only to the top document', () {
    final script = DesktopPageZoomScript.build(1.2);

    expect(script, contains('function applyEverywhere(zoom)'));
    expect(script, contains('applyZoom(window, zoom);'));
    expect(script, isNot(contains('applyZoom(wins[i], zoom)')));
  });

  test('keeps the pointer position stable by compensating scroll', () {
    final script = DesktopPageZoomScript.build(
      1.2,
      originX: 123.4,
      originY: 567.8,
    );

    expect(script, contains('"originX":123.4'));
    expect(script, contains('"originY":567.8'));
    expect(script, contains('function originFor(win)'));
    expect(
        script, contains('var previousZoom = win.__MBG_PAGE_EFFECTIVE_ZOOM'));
    expect(script, contains('win.__MBG_PAGE_EFFECTIVE_ZOOM = effectiveZoom'));
    expect(script,
        contains('var contentX = (previousScrollX + origin.x - bodyOriginX) / previousZoom'));
    expect(
        script,
        contains(
            'var nextScrollX = Math.max(0, bodyOriginX + contentX * effectiveZoom - origin.x)'));
    expect(script, contains('win.scrollTo(nextScrollX, nextScrollY)'));
    expect(script, contains('window.__MBG_PAGE_ZOOM_ORIGIN = initialOrigin'));
  });

  test('restores position when measurement clamps the browser scroll', () async {
    for (final zoom in [0.8, 1.4]) {
      final result = await Process.run('node', [
        '-e',
        _scrollClampHarness,
        DesktopPageZoomScript.build(zoom, originX: 400, originY: 300),
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final position = jsonDecode(result.stdout as String) as num;
      expect(position, closeTo(zoom == 0.8 ? 1700 : 3200, 0.01));
    }
  });

  test('preserves the visible position on first zoom application', () async {
    final result = await Process.run('node', [
      '-e',
      _scrollClampHarness,
      DesktopPageZoomScript.build(1.0, originX: 400, originY: 300),
      'first',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(jsonDecode(result.stdout as String), closeTo(3200, 0.01));
  });
}

const _scrollClampHarness = r'''
const vm = require('node:vm');
const win = {frames: [], innerWidth: 900, innerHeight: 700,
  scrollX: 0, scrollY: 3200, __MBG_PAGE_EFFECTIVE_ZOOM: 1.4,
  addEventListener() {}, clearTimeout() {}, setTimeout() {},
  scrollTo(x,y) { this.scrollX=x; this.scrollY=y; }};
if (process.argv[2] === 'first') delete win.__MBG_PAGE_EFFECTIVE_ZOOM;
const style = new Proxy({}, {set(target,key,value) {
  if (key === 'transform' && value === 'none') win.scrollY=Math.min(win.scrollY,2900);
  target[key]=value; return true;
}});
win.document = {body:{style,scrollWidth:900,offsetWidth:900,scrollHeight:3600,offsetHeight:3600},
  documentElement:{style:{},clientWidth:900,scrollWidth:900,offsetWidth:900,scrollHeight:3600,offsetHeight:3600}};
vm.runInNewContext(process.argv[1], {window:win});
process.stdout.write(JSON.stringify(win.scrollY));
''';

const _shortcutHarness = r'''
const vm = require('node:vm');
const script = process.argv[1];
const actions = [];
function page() {
  const listeners = {};
  return {
    document: {
      body: {style: {}, scrollWidth: 800, scrollHeight: 600},
      documentElement: {style: {}, clientWidth: 800}
    },
    frames: [], innerWidth: 800, innerHeight: 600,
    addEventListener(type, callback) {
      (listeners[type] ||= []).push(callback);
    },
    listeners,
    scrollTo() {}, clearTimeout() {}, setTimeout() {}
  };
}
const window = page();
const frame = page();
window.frames.push(frame);
window.MoreBetterGakujoDesktopZoom = {postMessage: action => actions.push(action)};
const context = vm.createContext({window});
vm.runInContext(script, context);
vm.runInContext(script, context);
const prevented = [];
for (const [target, key, ctrlKey, metaKey] of [
  [window, '+', true, false],
  [window, '=', true, false],
  [window, '-', true, false],
  [window, '_', true, false],
  [window, '0', true, false],
  [frame, '+', false, true],
  [window, '+', false, false],
  [window, 'a', true, false]
]) {
  let blocked = false;
  const event = {key, ctrlKey, metaKey, preventDefault() { blocked = true; }};
  for (const listener of target.listeners.keydown) listener(event);
  prevented.push(blocked);
}
process.stdout.write(JSON.stringify({
  actions, prevented, zoom: window.__MBG_PAGE_ZOOM_VALUE,
  keydownListeners: [window, frame].map(win => win.listeners.keydown.length)
}));
''';
