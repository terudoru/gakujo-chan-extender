import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_history_navigation.dart';

void main() {
  GakujoHistoryAction decide({
    bool forward = false,
    String preview = 'none',
    bool dialog = false,
    bool detached = false,
    bool available = true,
  }) => decideGakujoHistoryAction(
    forward: forward,
    previewState: preview,
    hasDialog: dialog,
    virtualPreviewForward: detached,
    canNavigate: available,
  );

  test('preview takes precedence over a dialog and page history', () {
    expect(decide(preview: 'visible', dialog: true), GakujoHistoryAction.preview);
    expect(decide(forward: true, preview: 'hidden', detached: true),
        GakujoHistoryAction.preview);
    expect(decide(forward: true, preview: 'visible'), GakujoHistoryAction.none);
  });
  test('dialog and detached preview take precedence over page history', () {
    expect(decide(dialog: true), GakujoHistoryAction.dialog);
    expect(decide(forward: true, detached: true),
        GakujoHistoryAction.reopenPreview);
    expect(decide(), GakujoHistoryAction.webView);
    expect(decide(available: false), GakujoHistoryAction.none);
  });
}
