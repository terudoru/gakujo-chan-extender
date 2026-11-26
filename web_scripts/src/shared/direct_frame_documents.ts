export function directFrameDocuments() {
  var docs = [document];
  var frames = document.querySelectorAll<HTMLIFrameElement | HTMLFrameElement>('iframe,frame');
  for (var i = 0; i < frames.length; i += 1) {
    try {
      if (frames[i].contentWindow && frames[i].contentWindow!.document) {
        docs.push(frames[i].contentWindow!.document);
      }
    } catch (e) {
      // Cross-origin frames cannot be inspected.
    }
  }
  return docs;
}
