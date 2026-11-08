import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'generated/desktop_page_zoom.g.dart';

/// Converts a wheel delta to a smooth multiplicative zoom, with bounded input.
double desktopWheelZoom(double current, double deltaY) {
  if (!current.isFinite || !deltaY.isFinite || deltaY == 0) return current;
  return current * math.exp((-deltaY * .001).clamp(-.25, .25));
}

/// Tells a trackpad pinch from a pan whose finger spacing drifts: a gesture
/// that has already moved as a pan stays a pan until the fingers lift.
///
/// `WebviewPanScrollAccumulator` in the Windows plugin applies the same rule,
/// so the app never zooms a gesture the WebView is scrolling.
class DesktopPanZoomGesture {
  static const double pinchScaleDeadZone = 0.02;
  static const double panLockDistance = 24;

  bool _pinching = false;
  bool _panLocked = false;
  Offset _panTotal = Offset.zero;

  void reset() {
    _pinching = false;
    _panLocked = false;
    _panTotal = Offset.zero;
  }

  bool update(Offset panDelta, double scale) {
    if (_pinching) return true;
    if (!_panLocked && (scale - 1).abs() > pinchScaleDeadZone) {
      _pinching = true;
      return true;
    }
    _panTotal += panDelta;
    if (!_panLocked && _panTotal.distance > panLockDistance) _panLocked = true;
    return false;
  }
}

bool desktopHistorySwipeAllowed(double zoom) => zoom <= 1.001;

class DesktopPageZoomScript {
  const DesktopPageZoomScript._();

  // The TypeScript source hard-codes this channel name.
  static const channelName = 'MoreBetterGakujoDesktopZoom';

  static String build(double zoom, {double? originX, double? originY}) {
    return gakujoDesktopPageZoomJs({
      'zoom': double.parse(zoom.clamp(0.5, 2.0).toStringAsFixed(2)),
      'originX': originX == null
          ? null
          : double.parse(originX.toStringAsFixed(1)),
      'originY': originY == null
          ? null
          : double.parse(originY.toStringAsFixed(1)),
    });
  }
}
