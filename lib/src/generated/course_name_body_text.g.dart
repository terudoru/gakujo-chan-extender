// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/course_name_body_text/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoCourseNameBodyTextJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/course_name_body_text/main.ts
  function courseNameBodyText() {
    var texts = [];
    function collect(win) {
      try {
        if (win.document && win.document.body) {
          texts.push(win.document.body.innerText || "");
        }
        for (var i = 0; i < win.frames.length; i += 1) {
          collect(win.frames[i]);
        }
      } catch (e) {
      }
    }
    collect(window);
    return texts.join("\n\n");
  }
  __mbgEntryResult = courseNameBodyText();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
