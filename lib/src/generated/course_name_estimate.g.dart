// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/course_name_estimate/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoCourseNameEstimateJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/course_name_estimate/main.ts
  var hook = window.__MBG_ESTIMATE_COURSE_NAME;
  var estimate = typeof hook === "function" ? hook(true) : null;
  __mbgEntryResult = JSON.stringify(typeof estimate === "string" ? { courseName: estimate, courseNameAmbiguous: false } : estimate != null ? estimate : null);
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
