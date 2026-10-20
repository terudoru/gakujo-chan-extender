# webview_flutter_windows (vendored)

Upstream: https://github.com/omar-hanafy/webview_flutter_windows, version 1.2.0,
BSD 3-Clause (see `LICENSE`). Only `lib/`, `windows/` (without native tests),
`pubspec.yaml` and `LICENSE` are kept.

Local change, marked "More Better Gakujo patch" (`lib/src/webview.dart`,
`lib/src/pan_scroll_accumulator.dart`):

- Trackpad pans were forwarded on one axis per update and each wheel delta was
  truncated to a whole WebView2 unit in native code, which made slow and
  diagonal scrolling stutter. Pans now keep the sub-unit remainder and move both
  axes, with a rail for mostly-straight gestures.

When upgrading, re-apply this change or drop the vendored copy if upstream
fixes it.
