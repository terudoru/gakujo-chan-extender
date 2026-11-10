import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_history_navigation.dart';

void main() {
  GakujoHistoryAction decide({
    bool forward = false,
    String preview = 'none',
    bool dialog = false,
    String? activeToken,
    String? markerToken,
    String? detachedToken,
    bool canGoForward = true,
    bool canGoBack = true,
  }) => decideGakujoHistoryAction(
    forward: forward,
    previewState: preview,
    hasDialog: dialog,
    activeToken: activeToken,
    markerToken: markerToken,
    detachedToken: detachedToken,
    canGoForward: canGoForward,
    canGoBack: canGoBack,
  );

  test('hidden tokened preview on list advances to notice first', () {
    expect(decide(forward: true, preview: 'hidden', activeToken: 'token123'),
        GakujoHistoryAction.webView);
    expect(decide(forward: true, preview: 'hidden', activeToken: 'token123',
        markerToken: 'other123'), GakujoHistoryAction.webView);
    expect(decide(forward: true, preview: 'hidden', activeToken: 'token123',
        canGoForward: false), GakujoHistoryAction.preview);
  });
  test('hidden preview on notice or without token is shown', () {
    expect(decide(forward: true, preview: 'hidden', activeToken: 'token123',
        markerToken: 'token123'), GakujoHistoryAction.preview);
    expect(decide(forward: true, preview: 'hidden'), GakujoHistoryAction.preview);
  });
  test('detached preview reopens only on its matching entry', () {
    expect(decide(forward: true, markerToken: 'token123', detachedToken: 'token123'),
        GakujoHistoryAction.reopenPreview);
    expect(decide(forward: true, markerToken: 'other123', detachedToken: 'token123'),
        GakujoHistoryAction.webView);
    expect(decide(forward: true), GakujoHistoryAction.webView);
  });
  test('visible preview and dialog take precedence on back', () {
    expect(decide(preview: 'visible', dialog: true), GakujoHistoryAction.preview);
    expect(decide(dialog: true), GakujoHistoryAction.dialog);
    expect(decide(), GakujoHistoryAction.webView);
    expect(decide(canGoBack: false), GakujoHistoryAction.none);
    expect(decide(forward: true, preview: 'visible'), GakujoHistoryAction.none);
    expect(decide(forward: true, canGoForward: false), GakujoHistoryAction.none);
  });
}
