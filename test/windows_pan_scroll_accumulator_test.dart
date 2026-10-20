import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

/// Mirrors `static_cast<short>(delta * kScrollMultiplier)` in webview.cc.
int nativeUnits(double delta) =>
    (delta * WebviewPanScrollAccumulator.unitsPerPixel).truncate();

void main() {
  test('slow pans accumulate instead of being truncated away', () {
    final accumulator = WebviewPanScrollAccumulator();
    var sentUnits = 0;
    // 0.4px per update would become 0 wheel units every time natively.
    for (var i = 0; i < 100; i += 1) {
      final delta = accumulator.add(const Offset(0, 0.4));
      if (delta != null) {
        sentUnits += nativeUnits(delta.dy);
      }
    }

    // 40px * 1.5 = 60 units, within one unit of carry-over.
    expect(sentUnits, inInclusiveRange(59, 60));
  });

  test('every whole unit survives the native round trip', () {
    final accumulator = WebviewPanScrollAccumulator();
    for (final pan in [1.0, 2.0, 3.0, 7.0, -5.0, 13.0]) {
      accumulator.reset();
      final delta = accumulator.add(Offset(0, pan))!;
      expect(nativeUnits(delta.dy), (pan * 1.5).truncate(), reason: '$pan');
    }
  });

  test('diagonal pans move both axes and straight pans are railed', () {
    final diagonal = WebviewPanScrollAccumulator().add(const Offset(-10, 10))!;
    expect(nativeUnits(diagonal.dx), 15);
    expect(nativeUnits(diagonal.dy), 15);

    final vertical = WebviewPanScrollAccumulator().add(const Offset(-2, 10))!;
    expect(vertical.dx, 0);
    expect(nativeUnits(vertical.dy), 15);
  });
}
