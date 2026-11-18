export {};
const hook = window.__MBG_ESTIMATE_COURSE_NAME;
const estimate = typeof hook === 'function' ? hook(true) : null;
// Older capture installations only return the course name.
__mbgEntryResult = JSON.stringify(typeof estimate === 'string'
  ? {courseName: estimate, courseNameAmbiguous: false}
  : estimate ?? null);
