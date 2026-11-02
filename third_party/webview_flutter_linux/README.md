# webview_flutter_linux (vendored)

Upstream: https://github.com/abandoft/webview_all, `webview_all_linux` version
1.4.9, MIT (see `LICENSE`). The upstream `lib/`, `linux/` (including native
tests), `pubspec.yaml`, and `LICENSE` are kept.

Local changes, marked "More Better Gakujo patch":

- Register as a `webview_flutter` federated implementation and use its platform
  interface; align the package entry point, CMake target and public header.
- Remove the fork-only session, website-data, download delegate, async
  JavaScript, offscreen, title callback and user-script interfaces. The native implementation
  remains available for the supported WebView operations.
- Adapt JavaScript channel messages to the standard interface and return
  structured JavaScript results as JSON strings for app callers.

When upgrading, re-apply these changes or drop the vendored copy if upstream
covers them.
