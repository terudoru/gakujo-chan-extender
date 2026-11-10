enum GakujoHistoryAction { preview, dialog, reopenPreview, webView, none }

GakujoHistoryAction decideGakujoHistoryAction({
  required bool forward,
  required String previewState,
  required bool hasDialog,
  required bool virtualPreviewForward,
  required bool canNavigate,
}) {
  if (forward ? previewState == 'hidden' : previewState == 'visible') {
    return GakujoHistoryAction.preview;
  }
  if (forward && previewState == 'visible') return GakujoHistoryAction.none;
  if (!forward && hasDialog) return GakujoHistoryAction.dialog;
  if (forward && virtualPreviewForward) return GakujoHistoryAction.reopenPreview;
  return canNavigate ? GakujoHistoryAction.webView : GakujoHistoryAction.none;
}
