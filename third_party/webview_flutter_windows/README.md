# webview_flutter_windows (vendored)

Upstream: https://github.com/omar-hanafy/webview_flutter_windows, version 1.2.0,
BSD 3-Clause (see `LICENSE`). Only `lib/`, `windows/` (without native tests),
`pubspec.yaml` and `LICENSE` are kept.

Local changes, all marked "More Better Gakujo patch":

- Trackpad pans were forwarded on one axis per update and each wheel delta was
  truncated to a whole WebView2 unit in native code, which made slow and
  diagonal scrolling stutter. Pans now keep the sub-unit remainder and move both
  axes, with a rail for mostly-straight gestures
  (`lib/src/pan_scroll_accumulator.dart`, `lib/src/webview.dart`).
- Upstream exposes no cancellable `NavigationStarting`, so blocked sites were
  only stopped after the request had been sent. `setNavigationAllowlist`
  cancels disallowed main-frame navigations and redirects natively and reports
  them on `navigationBlocked` (`windows/util/navigation_allowlist.h`,
  `windows/webview.{h,cc}`, `windows/webview_bridge.cc`, `lib/src/webview.dart`).
- `setDevToolsEnabled` so release builds can turn off WebView2 DevTools
  (`windows/webview.{h,cc}`, `windows/webview_bridge.cc`, `lib/src/webview.dart`).
- `processFailed` stream from WebView2's `ProcessFailed` so a crashed renderer
  can be reloaded (`windows/webview.{h,cc}`, `windows/webview_bridge.cc`,
  `lib/src/webview.dart`).

When upgrading, re-apply these changes or drop the vendored copy if upstream
covers them.
