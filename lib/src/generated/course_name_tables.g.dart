// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/course_name_tables/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoCourseNameTablesJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/shared/frame_documents.ts
  function collectFrameDocuments() {
    var documents = [];
    function collect(win) {
      try {
        if (win.document) {
          documents.push(win.document);
        }
        for (var i = 0; i < win.frames.length; i += 1) {
          collect(win.frames[i]);
        }
      } catch (e) {
      }
    }
    collect(window);
    return documents;
  }

  // web_scripts/src/course_name_tables/main.ts
  function courseNameTables() {
    var _a;
    function textOf(element) {
      return (element && (element.innerText || element.textContent) || "").replace(/\s+/g, " ").trim();
    }
    function inlineCourseName(cells) {
      let sawValueCell = false;
      for (const cell of cells) {
        if (cell.tagName.toLowerCase() === "th") {
          if (sawValueCell) break;
          continue;
        }
        sawValueCell = true;
        const value = textOf(cell);
        if (value) return value;
      }
      return "";
    }
    const courseNameCandidates = [];
    for (const doc of collectFrameDocuments()) {
      for (const table of Array.from(doc.querySelectorAll("table"))) {
        let courseColumn = -1;
        for (const row of Array.from(table.rows)) {
          const cells = Array.from(row.cells);
          const label = cells.findIndex((cell) => textOf(cell) === "科目名");
          if (label >= 0) {
            const value = inlineCourseName(cells.slice(label + 1));
            if (value) courseNameCandidates.push(value);
            courseColumn = value ? -1 : label;
          } else if (courseColumn >= 0) {
            const cell = cells[courseColumn];
            if (!cell) continue;
            if (cell.scope === "col" || ((_a = row.parentElement) == null ? void 0 : _a.tagName) === "THEAD" || cells.length > 1 && cells.every((value2) => value2.tagName.toLowerCase() === "th")) {
              courseColumn = -1;
              continue;
            }
            const value = textOf(cell);
            if (value) courseNameCandidates.push(value);
          }
        }
      }
    }
    return JSON.stringify({ courseNameCandidates });
  }
  __mbgEntryResult = courseNameTables();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
