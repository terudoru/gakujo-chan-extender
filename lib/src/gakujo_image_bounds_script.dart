import 'package:flutter/foundation.dart';

import 'generated/image_bounds.g.dart';

/// Shared JavaScript guard used before a WebView image decoder is invoked.
class GakujoImageBoundsScript {
  const GakujoImageBoundsScript._();

  /// Exposes the image bounds guard for its test.
  @visibleForTesting
  static const source = gakujoImageBoundsJs;
}
