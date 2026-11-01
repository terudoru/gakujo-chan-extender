export var retentionMs = 14 * 24 * 60 * 60 * 1000;
export function isDraftKey(key: unknown) {
    return typeof key === 'string' && /^mbg-report-draft:v[12]:/.test(key);
  }
export function draftDocuments() {
    var docs = [document];
    try {
      var frame = document.querySelector<HTMLIFrameElement>('iframe#main-frame-if');
      if (frame && frame.contentWindow && frame.contentWindow.document) {
        docs.push(frame.contentWindow.document);
      }
    } catch (e) {
      // Cross-origin frames cannot be inspected.
    }
    return docs;
  }
