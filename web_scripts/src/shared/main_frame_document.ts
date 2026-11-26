export function mainFrameDocument(): Document | null {
  try {
    var frame = document.getElementById('main-frame-if') as HTMLIFrameElement | null;
    return frame && frame.contentWindow && frame.contentWindow.document || null;
  } catch (e) {
    return null;
  }
}

export function mainFrameFirstDocuments(): Document[] {
  var frame = mainFrameDocument();
  return frame && frame !== document ? [frame, document] : [document];
}
