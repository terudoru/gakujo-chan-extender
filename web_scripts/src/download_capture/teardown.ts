export {};
function teardownDownloadCapture() {
  var handler = window.__MBG_DOWNLOAD_CAPTURE_HANDLER;
  var documents = window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS || [];
  if (handler) {
    for (var index = 0; index < documents.length; index += 1) {
      try {
        documents[index].removeEventListener('click', handler, true);
        documents[index].removeEventListener(
          'submit', window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_HANDLER!, true
        );
      } catch (e) {}
    }
  }
  var prototypes = window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_PROTOTYPES || [];
  prototypes.forEach(function(entry) {
    var owner = entry.prototype as unknown as Record<string, MbgSubmitHookFunction>;
    var key = 'submit';
    while (owner[key] && owner[key] !== entry.wrapper && owner[key].__mbgFormSubmitHook) {
      owner = owner[key].__mbgFormSubmitHook as unknown as Record<string, MbgSubmitHookFunction>;
      key = 'original';
    }
    if (owner[key] === entry.wrapper) owner[key] = entry.original;
  });
  window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_PROTOTYPES = [];
  var loadHandler = window.__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER;
  var loadDocuments = window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS || [];
  if (loadHandler) {
    for (var loadIndex = 0; loadIndex < loadDocuments.length; loadIndex += 1) {
      try {
        loadDocuments[loadIndex].removeEventListener(
          'load',
          loadHandler,
          true
        );
      } catch (e) {}
    }
  }
  window.__MBG_DOWNLOAD_CAPTURE_DOCUMENTS = [];
  window.__MBG_DOWNLOAD_CAPTURE_LOAD_DOCUMENTS = [];
  window.__MBG_DOWNLOAD_CAPTURE_HANDLER = null;
  window.__MBG_DOWNLOAD_CAPTURE_SUBMIT_HANDLER = null;
  window.__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER = null;
  window.__MBG_DOWNLOAD_CAPTURE_ATTACH = null;
  window.__MBG_ESTIMATE_COURSE_NAME = null;
  window.__MBG_DOWNLOAD_CAPTURE_VERSION = null;
}

teardownDownloadCapture();
