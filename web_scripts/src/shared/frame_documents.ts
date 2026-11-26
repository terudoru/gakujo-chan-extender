export function collectFrameDocuments(): Document[] {
  var documents: Document[] = [];
  function collect(win: Window) {
    try {
      if (win.document) {
        documents.push(win.document);
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        collect(win.frames[i]);
      }
    } catch (e) {}
  }
  collect(window);
  return documents;
}
