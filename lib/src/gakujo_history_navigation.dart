enum GakujoHistoryAction { preview, dialog, reopenPreview, webView, none }

GakujoHistoryAction decideGakujoHistoryAction({
  required bool forward,
  required String previewState,
  required bool hasDialog,
  required String? activeToken,
  required String? markerToken,
  required String? detachedToken,
  required bool canGoForward,
  required bool canGoBack,
}) {
  if (forward) {
    if (previewState == 'visible') return GakujoHistoryAction.none;
    if (previewState == 'hidden') {
      if (activeToken != null && markerToken != activeToken && canGoForward) {
        return GakujoHistoryAction.webView;
      }
      return GakujoHistoryAction.preview;
    }
    if (previewState == 'none' && markerToken != null &&
        markerToken == detachedToken) {
      return GakujoHistoryAction.reopenPreview;
    }
    return canGoForward ? GakujoHistoryAction.webView : GakujoHistoryAction.none;
  }
  if (previewState == 'visible') return GakujoHistoryAction.preview;
  if (hasDialog) return GakujoHistoryAction.dialog;
  return canGoBack ? GakujoHistoryAction.webView : GakujoHistoryAction.none;
}
