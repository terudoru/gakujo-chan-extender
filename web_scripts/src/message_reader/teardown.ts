export {};
function teardownMessageReader() {
  if (window.__MBG_MESSAGE_READER_DISPOSE) {
    window.__MBG_MESSAGE_READER_DISPOSE();
  }
  delete window.__MBG_MESSAGE_READER_DISPOSE;
  window.clearInterval(window.__MBG_MESSAGE_READER_INTERVAL);
  delete window.__MBG_MESSAGE_READER_INTERVAL;
  delete window.__MBG_MESSAGE_READER_VERSION;
  delete window.__MBG_MESSAGE_READER_UPDATE;

  var docs = [document];
  try {
    var frame = document.getElementById('main-frame-if') as HTMLIFrameElement | null;
    var frameDoc = frame && frame.contentWindow && frame.contentWindow.document;
    if (frameDoc && frameDoc !== document) docs.push(frameDoc);
  } catch (e) {}
  for (var d = 0; d < docs.length; d += 1) {
    var controls = docs[d].querySelectorAll(
      '[data-mbg-message-reader-owned="true"]'
    );
    for (var i = 0; i < controls.length; i += 1) {
      controls[i].remove();
    }
  }
}

teardownMessageReader();
