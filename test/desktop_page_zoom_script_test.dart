import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:morebettergakujo_flutter/src/desktop_page_zoom_script.dart';
import 'package:test/test.dart';

void main() {
  test('pan gesture locks out scale drift and resets', () {
    final gesture = DesktopPanZoomGesture();
    expect(gesture.update(const Offset(12, 0), 1.01), isFalse);
    expect(gesture.update(const Offset(13, 0), 1.01), isFalse);
    expect(gesture.update(const Offset(1, 0), 1.05), isFalse);
    gesture.reset();
    expect(gesture.update(Offset.zero, 1.03), isTrue);
    expect(gesture.update(Offset.zero, 1), isTrue);
    gesture.reset();
    expect(gesture.update(Offset.zero, 1), isFalse);
  });

  test('history swipe is allowed only at baseline zoom', () {
    expect(desktopHistorySwipeAllowed(0.5), isTrue);
    expect(desktopHistorySwipeAllowed(1.001), isTrue);
    expect(desktopHistorySwipeAllowed(1.002), isFalse);
  });

  test('reapply preserves position and waits for scrolling', () async {
    final result = await Process.run('node', [
      'test/support/desktop_page_zoom_script_reapply_harness.cts',
      DesktopPageZoomScript.build(1.5, originX: 400, originY: 300),
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    for (final name in ['shape', 'scroll']) {
      expect(data[name]['zoom'], closeTo(1.5, 0.0001));
      expect(data[name]['x'], closeTo(300, 0.0001));
      expect(data[name]['y'], closeTo(1500, 0.0001));
      expect(data[name]['minWidth'], '2025px');
      expect(data[name]['scrollCalls'], 0);
    }
    expect(data['unscrolled']['zoom'], closeTo(1, 0.0001));
    expect(data['unscrolled']['x'], 0);
    expect(data['unscrolled']['y'], 0);
    for (final name in ['resize', 'sticky']) {
      expect(data[name]['zoom'], closeTo(1, 0.0001));
      expect(data[name]['x'], closeTo(200, 0.0001));
      expect(data[name]['y'], closeTo(1000, 0.0001));
      expect(data[name]['scrollCalls'], 1);
    }
  });

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
      ['test/support/desktop_page_zoom_script_shortcut_harness.cts', DesktopPageZoomScript.build(1.25)],
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
    expect(script, contains('scheduleReapply(win, "shape")'));
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
        'test/support/desktop_page_zoom_script_scroll_clamp_harness.cts',
        DesktopPageZoomScript.build(zoom, originX: 400, originY: 300),
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final position = jsonDecode(result.stdout as String) as num;
      expect(position, closeTo(zoom == 0.8 ? 1700 : 3200, 0.01));
    }
  });

  test('preserves the visible position on first zoom application', () async {
    final result = await Process.run('node', [
      'test/support/desktop_page_zoom_script_scroll_clamp_harness.cts',
      DesktopPageZoomScript.build(1.0, originX: 400, originY: 300),
      'first',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(jsonDecode(result.stdout as String), closeTo(3200, 0.01));
  });
}
