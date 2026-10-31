// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/upload_compression/teardown.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoUploadCompressionTeardownJs = r'''
"use strict";
(() => {
  // web_scripts/src/upload_compression/teardown.ts
  function uploadCompressionTeardown() {
    window.__MBG_UPLOAD_COMPRESSION_ENABLED = false;
    window.__MBG_UPLOAD_COMPRESSION_GENERATION = (window.__MBG_UPLOAD_COMPRESSION_GENERATION || 0) + 1;
    var hooks = window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES || [];
    hooks.forEach(function(entry) {
      var owner = entry.prototype;
      var key = entry.method;
      while (owner[key] && owner[key] !== entry.wrapper && owner[key].__mbgFormSubmitHook) {
        owner = owner[key].__mbgFormSubmitHook;
        key = "original";
      }
      if (owner[key] === entry.wrapper) owner[key] = entry.original;
    });
    window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES = [];
    var docs = [document];
    var frames = document.querySelectorAll("iframe,frame");
    for (var i = 0; i < frames.length; i += 1) {
      try {
        if (frames[i].contentWindow && frames[i].contentWindow.document) {
          docs.push(frames[i].contentWindow.document);
        }
      } catch (e) {
      }
    }
    for (var d = 0; d < docs.length; d += 1) {
      var inputs = docs[d].querySelectorAll('input[type="file"]');
      for (var k = 0; k < inputs.length; k += 1) {
        if (inputs[k].__mbgPdfCompressionCancel) inputs[k].__mbgPdfCompressionCancel();
        if (inputs[k].__mbgOfficeCompressionCancel) inputs[k].__mbgOfficeCompressionCancel();
        delete inputs[k].__mbgUploadCompressionPending;
      }
      var owned = docs[d].querySelectorAll('[data-mbg-upload-compression-owned="true"]');
      for (var j = 0; j < owned.length; j += 1) {
        owned[j].remove();
      }
    }
  }
  uploadCompressionTeardown();
})();
''';
