import 'dart:math' as math;

import 'generated/desktop_page_zoom.g.dart';

/// Converts a wheel delta to a smooth multiplicative zoom, with bounded input.
double desktopWheelZoom(double current, double deltaY) {
  if (!current.isFinite || !deltaY.isFinite || deltaY == 0) return current;
  return current * math.exp((-deltaY * .001).clamp(-.25, .25));
}

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
