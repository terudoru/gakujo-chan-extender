export function sessionValue(key: string) {
  try {
    return window.sessionStorage && window.sessionStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

export function setSessionValue(key: string, value: string) {
  try {
    if (window.sessionStorage) {
      window.sessionStorage.setItem(key, value);
    }
  } catch (_) {
  }
}

export function allDocuments() {
  var documents: Document[] = [];
  function collect(win: Window | null) {
    try {
      if (!win || !win.document || documents.indexOf(win.document) !== -1) {
        return;
      }
      documents.push(win.document);
      var frames = Array.prototype.slice.call(win.document.querySelectorAll('iframe, frame'));
      for (var i = 0; i < frames.length; i += 1) {
        collect(frames[i].contentWindow);
      }
    } catch (_) {
    }
  }
  collect(window);
  return documents;
}
