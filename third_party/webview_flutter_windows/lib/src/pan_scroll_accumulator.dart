import 'dart:ui' show Offset;

/// More Better Gakujo patch: converts trackpad pans into the wheel deltas the
/// native plugin expects without losing motion.
///
/// Native `SendScroll` multiplies each delta by [unitsPerPixel] and truncates
/// to a whole wheel unit, so small per-frame pans used to vanish. This keeps
/// the unsent remainder and returns deltas that survive that truncation.
class WebviewPanScrollAccumulator {
  /// Matches `kScrollMultiplier` in `windows/webview.cc`.
  static const double unitsPerPixel = 1.5;

  Offset _remainder = Offset.zero;

  /// Forgets motion left over from a previous gesture.
  void reset() {
    _remainder = Offset.zero;
  }

  /// Returns the scroll delta to send for [panDelta], or null when the motion
  /// so far is smaller than one wheel unit on both axes.
  Offset? add(Offset panDelta) {
    // Rail mostly-straight pans to their main axis so a vertical scroll does
    // not drift sideways, while diagonal pans still move both ways.
    var dx = -panDelta.dx;
    var dy = panDelta.dy;
    if (dx.abs() < dy.abs() * 0.5) {
      dx = 0;
    } else if (dy.abs() < dx.abs() * 0.5) {
      dy = 0;
    }
    final pending = _remainder + Offset(dx, dy);
    final xUnits = (pending.dx * unitsPerPixel).truncateToDouble();
    final yUnits = (pending.dy * unitsPerPixel).truncateToDouble();
    _remainder = Offset(
      pending.dx - xUnits / unitsPerPixel,
      pending.dy - yUnits / unitsPerPixel,
    );
    if (xUnits == 0 && yUnits == 0) {
      return null;
    }
    return Offset(_toNative(xUnits), _toNative(yUnits));
  }

  // Half a unit of headroom keeps native truncation from rounding a whole
  // unit down after the floating-point round trip.
  static double _toNative(double units) =>
      units == 0 ? 0 : (units + 0.5 * units.sign) / unitsPerPixel;
}
