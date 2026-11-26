// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/course_name_body_text/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoCourseNameBodyTextJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/shared/visit_window_frames.ts
  function visitWindowFrames(win, visit) {
    try {
      if (visit(win) === false) return;
      for (var i = 0; i < win.frames.length; i += 1) {
        visitWindowFrames(win.frames[i], visit);
      }
    } catch (_) {
    }
  }

  // web_scripts/src/course_name_body_text/main.ts
  function courseNameBodyText() {
    var texts = [];
    visitWindowFrames(window, function(win) {
      if (win.document && win.document.body) {
        texts.push(win.document.body.innerText || "");
      }
    });
    return texts.join("\n\n");
  }
  __mbgEntryResult = courseNameBodyText();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
