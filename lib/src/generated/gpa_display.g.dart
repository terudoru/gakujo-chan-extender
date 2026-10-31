// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/gpa_display/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoGpaDisplayJs = r'''
"use strict";
(() => {
  // web_scripts/src/gpa_display/main.ts
  function gpaDisplay() {
    var version = 10;
    if (window.__MBG_GPA_DISPLAY_VERSION === version) {
      if (window.__MBG_UPDATE_GPA_DISPLAY) {
        window.__MBG_UPDATE_GPA_DISPLAY();
      }
      return;
    }
    window.__MBG_GPA_DISPLAY_VERSION = version;
    window.clearTimeout(window.__MBG_GPA_DISPLAY_TIMER);
    var previousStartupTimers = window.__MBG_GPA_DISPLAY_STARTUP_TIMERS || [];
    for (var timerIndex = 0; timerIndex < previousStartupTimers.length; timerIndex += 1) {
      window.clearTimeout(previousStartupTimers[timerIndex]);
    }
    window.__MBG_GPA_DISPLAY_STARTUP_TIMERS = [];
    window.clearInterval(window.__MBG_GPA_DISPLAY_INTERVAL);
    if (window.__MBG_GPA_DISPLAY_OBSERVERS) {
      for (var observerIndex = 0; observerIndex < window.__MBG_GPA_DISPLAY_OBSERVERS.length; observerIndex += 1) {
        window.__MBG_GPA_DISPLAY_OBSERVERS[observerIndex].disconnect();
      }
    }
    window.__MBG_GPA_DISPLAY_OBSERVERS = [];
    window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS = [];
    var gradeTableSearchCache = /* @__PURE__ */ new WeakMap();
    function textOf(element) {
      return (element && (element.innerText || element.textContent) || "").replace(/\s+/g, "").trim();
    }
    function labelOf(element) {
      if (!element) {
        return "";
      }
      var clone = element.cloneNode(true);
      var displays = clone.querySelectorAll(".mbg-gpa-display");
      for (var i = 0; i < displays.length; i += 1) {
        displays[i].remove();
      }
      var text = textOf(clone).replace(/[Ａ-Ｚａ-ｚ０-９]/g, function(ch) {
        return String.fromCharCode(ch.charCodeAt(0) - 65248);
      }).replace(/．/g, ".").toUpperCase();
      return text.replace(/GPA:?\d*(?:\.\d+)?/g, "");
    }
    function toAsciiNumber(text) {
      return (text || "").replace(/[０-９]/g, function(ch) {
        return String.fromCharCode(ch.charCodeAt(0) - 65248);
      }).replace(/[．]/g, ".").replace(/,/g, "").trim();
    }
    function numberFromCell(cell) {
      var match = toAsciiNumber(textOf(cell)).match(/-?\d+(?:\.\d+)?/);
      if (!match) {
        return NaN;
      }
      return Number(match[0]);
    }
    function collectDocuments() {
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
      try {
        var mainFrame = window.document.getElementById("main-frame-if");
        if (mainFrame && mainFrame.contentWindow && mainFrame.contentWindow.document) {
          documents.push(mainFrame.contentWindow.document);
        }
      } catch (e) {
      }
      return documents;
    }
    function expandedCells(row) {
      var slots = [];
      var cells = row ? row.children : [];
      for (var i = 0; i < cells.length; i += 1) {
        var span = Number(cells[i].getAttribute("colspan") || "1");
        if (!isFinite(span) || span < 1 || span > 100 || Math.floor(span) !== span) {
          span = 1;
        }
        for (var j = 0; j < span; j += 1) {
          slots.push(cells[i]);
        }
      }
      return slots;
    }
    function findGradeTable(documentRef) {
      var tableCount = documentRef.getElementsByTagName("table").length;
      var rowCount = documentRef.getElementsByTagName("tr").length;
      var previous = gradeTableSearchCache.get(documentRef);
      if (previous && !previous.found && previous.tableCount === tableCount && previous.rowCount === rowCount) {
        return null;
      }
      var gradeTable = searchGradeTable(documentRef);
      gradeTableSearchCache.set(documentRef, {
        tableCount,
        rowCount,
        found: !!gradeTable
      });
      return gradeTable;
    }
    function searchGradeTable(documentRef) {
      var directTable = directGradeTable(documentRef);
      if (directTable) {
        return directTable;
      }
      var tables = documentRef.querySelectorAll("table");
      for (var tableIndex = 0; tableIndex < tables.length; tableIndex += 1) {
        var rows = tables[tableIndex].querySelectorAll("tr");
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
          var cells = expandedCells(rows[rowIndex]);
          var unitIndex = -1;
          var gpIndex = -1;
          var numberIndex = -1;
          var openNumberIndex = -1;
          var scoreIndex = -1;
          var labels = [];
          for (var cellIndex = 0; cellIndex < cells.length; cellIndex += 1) {
            var label = labelOf(cells[cellIndex]);
            labels.push(label);
            if (isNumberLabel(label)) {
              numberIndex = cellIndex;
            } else if (label.indexOf("開講番号") >= 0) {
              openNumberIndex = cellIndex;
            } else if (isScoreLabel(label)) {
              scoreIndex = cellIndex;
            } else if (label.indexOf("単位数") >= 0) {
              unitIndex = cellIndex;
            } else if (label === "GP") {
              gpIndex = cellIndex;
            }
          }
          if (unitIndex >= 0 && gpIndex >= 0 && labels.join("|").indexOf("科目") >= 0 && labels.join("|").indexOf("得点") >= 0 && labels.join("|").indexOf("評価") >= 0) {
            return {
              table: tables[tableIndex],
              headerCell: cells[gpIndex],
              headerRowIndex: rowIndex,
              numberIndex,
              openNumberIndex,
              scoreIndex,
              unitIndex,
              gpIndex
            };
          }
        }
      }
      return null;
    }
    function directGradeTable(documentRef) {
      try {
        var table = documentRef.querySelector("#taniReferListForm+table");
        if (!table || !table.rows || !table.rows.length) {
          return null;
        }
        var headerCells = table.rows[0].cells;
        if (!headerCells || headerCells.length <= 12) {
          return null;
        }
        if (labelOf(headerCells[12]) !== "GP") {
          return null;
        }
        return {
          table,
          headerCell: headerCells[12],
          headerRowIndex: 0,
          numberIndex: 0,
          openNumberIndex: 3,
          scoreIndex: 9,
          unitIndex: 8,
          gpIndex: 12,
          useDirectCells: true
        };
      } catch (e) {
        return null;
      }
    }
    function isNumberLabel(label) {
      return label === "NO." || label === "NO" || label === "番号";
    }
    function isScoreLabel(label) {
      return label === "得点" || label === "評点" || label === "点" || label.indexOf("得点") >= 0 || label.indexOf("評点") >= 0;
    }
    function removeGpaDisplay(headerCell) {
      if (!headerCell) {
        return;
      }
      var displays = headerCell.querySelectorAll(".mbg-gpa-display");
      for (var i = 0; i < displays.length; i += 1) {
        displays[i].remove();
      }
    }
    function renderGpaDisplay(headerCell, gpa, credits) {
      var text = "GPA:" + gpa.toFixed(4);
      var title = "GPが入力されている科目の加重平均 GPA: " + gpa.toFixed(4) + " / 対象単位数: " + credits.toFixed(1);
      var display = headerCell.querySelector(".mbg-gpa-display");
      if (display) {
        display.setAttribute("data-mbg-gpa-display-owned", "true");
      }
      if (display && display.textContent === text && display.title === title) {
        return;
      }
      if (display) {
        display.textContent = text;
        display.title = title;
        return;
      }
      display = headerCell.ownerDocument.createElement("div");
      display.className = "mbg-gpa-display";
      display.setAttribute("data-mbg-gpa-display-owned", "true");
      display.textContent = text;
      display.title = title;
      display.style.marginTop = "1px";
      display.style.padding = "0";
      display.style.border = "0";
      display.style.background = "transparent";
      display.style.color = "inherit";
      display.style.fontSize = "10px";
      display.style.fontWeight = "700";
      display.style.lineHeight = "1.1";
      display.style.whiteSpace = "nowrap";
      display.style.display = "block";
      headerCell.appendChild(display);
    }
    function rewriteRows(table, rows) {
      var parent = table.tBodies && table.tBodies.length ? table.tBodies[0] : table;
      for (var i = 0; i < rows.length; i += 1) {
        parent.appendChild(rows[i]);
      }
    }
    function cellsForGradeRow(row, gradeTable) {
      return gradeTable.useDirectCells ? row.cells : expandedCells(row);
    }
    function compareNumbers(left, right) {
      var leftFinite = isFinite(left);
      var rightFinite = isFinite(right);
      if (leftFinite && rightFinite) {
        return left - right;
      }
      if (leftFinite) {
        return -1;
      }
      if (rightFinite) {
        return 1;
      }
      return 0;
    }
    function sortGradeRows(compare) {
      var documents = collectDocuments();
      for (var i = 0; i < documents.length; i += 1) {
        var gradeTable = findGradeTable(documents[i]);
        if (!gradeTable) {
          continue;
        }
        var rows = Array.prototype.slice.call(
          gradeTable.table.rows,
          gradeTable.headerRowIndex + 1
        );
        rows.sort(function(a, b) {
          return compare(a, b, gradeTable);
        });
        rewriteRows(gradeTable.table, rows);
        updateDocument(documents[i]);
        return;
      }
    }
    function sortByNumber() {
      sortGradeRows(function(a, b, gradeTable) {
        var index = gradeTable.numberIndex;
        if (index < 0) {
          return 0;
        }
        return compareNumbers(
          numberFromCell(cellsForGradeRow(a, gradeTable)[index]),
          numberFromCell(cellsForGradeRow(b, gradeTable)[index])
        );
      });
    }
    function sortByOpenNumber() {
      sortGradeRows(function(a, b, gradeTable) {
        var index = gradeTable.openNumberIndex;
        if (index < 0) {
          return 0;
        }
        return textOf(cellsForGradeRow(a, gradeTable)[index]).localeCompare(textOf(cellsForGradeRow(b, gradeTable)[index]), "ja");
      });
    }
    function sortByScore() {
      sortGradeRows(function(a, b, gradeTable) {
        var index = gradeTable.scoreIndex;
        if (index < 0) {
          return 0;
        }
        return compareNumbers(
          numberFromCell(cellsForGradeRow(a, gradeTable)[index]),
          numberFromCell(cellsForGradeRow(b, gradeTable)[index])
        );
      });
    }
    function addGradeSortButton(id, label, handler) {
      var target = document.getElementById("tabmenutable");
      if (!target || document.getElementById(id)) {
        return;
      }
      var button = document.createElement("button");
      button.id = id;
      button.type = "button";
      button.setAttribute("data-mbg-gpa-display-owned", "true");
      button.textContent = label;
      button.addEventListener("click", handler);
      target.appendChild(button);
    }
    function addGradeSortButtons() {
      var documents = collectDocuments();
      var hasGradeTable = false;
      for (var i = 0; i < documents.length; i += 1) {
        if (findGradeTable(documents[i])) {
          hasGradeTable = true;
          break;
        }
      }
      if (!hasGradeTable) {
        return;
      }
      addGradeSortButton("mbg-grade-no-button", "No.でソート", sortByNumber);
      addGradeSortButton(
        "mbg-grade-open-number-button",
        "開講番号でソート",
        sortByOpenNumber
      );
      addGradeSortButton("mbg-grade-score-button", "得点でソート", sortByScore);
    }
    function isOutsideGpa(cells) {
      for (var i = 0; i < cells.length; i += 1) {
        var text = String(cells[i] && (cells[i].innerText || cells[i].textContent) || "").replace(/\s+/g, "");
        if (/^(認定|取消|履修取消|履修中|保留)$/.test(text)) {
          return true;
        }
      }
      return false;
    }
    function updateDocument(documentRef) {
      var gradeTable = findGradeTable(documentRef);
      if (!gradeTable) {
        return;
      }
      var weightedGp = 0;
      var totalCredits = 0;
      var rows = gradeTable.table.querySelectorAll("tr");
      for (var rowIndex = gradeTable.headerRowIndex + 1; rowIndex < rows.length; rowIndex += 1) {
        var cells = gradeTable.useDirectCells ? rows[rowIndex].cells : expandedCells(rows[rowIndex]);
        var unitCell = cells[gradeTable.unitIndex];
        var gpCell = cells[gradeTable.gpIndex];
        var credits = numberFromCell(unitCell);
        var gp = numberFromCell(gpCell);
        if (!isFinite(credits) || credits <= 0 || !isFinite(gp) || isOutsideGpa(cells)) {
          continue;
        }
        weightedGp += credits * gp;
        totalCredits += credits;
      }
      if (totalCredits <= 0) {
        removeGpaDisplay(gradeTable.headerCell);
        return;
      }
      var gpa = weightedGp / totalCredits;
      renderGpaDisplay(gradeTable.headerCell, gpa, totalCredits);
      try {
        if (window.GakujoGpaReport && window.GakujoGpaReport.postMessage && window.__MBG_GPA_LAST_REPORTED !== gpa) {
          window.GakujoGpaReport.postMessage(JSON.stringify({ gpa }));
          window.__MBG_GPA_LAST_REPORTED = gpa;
        }
      } catch (e) {
      }
    }
    function updateAll() {
      var documents = collectDocuments();
      var observedDocuments = window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS;
      var observers = window.__MBG_GPA_DISPLAY_OBSERVERS;
      for (var observerIndex2 = observedDocuments.length - 1; observerIndex2 >= 0; observerIndex2 -= 1) {
        var documentRef = observedDocuments[observerIndex2];
        if (documents.indexOf(documentRef) < 0 || documentRef.defaultView === null) {
          observers[observerIndex2].disconnect();
          observers.splice(observerIndex2, 1);
          observedDocuments.splice(observerIndex2, 1);
        }
      }
      for (var i = 0; i < documents.length; i += 1) {
        observeDocument(documents[i]);
        updateDocument(documents[i]);
      }
      addGradeSortButtons();
    }
    function scheduleUpdate() {
      window.clearTimeout(window.__MBG_GPA_DISPLAY_TIMER);
      window.__MBG_GPA_DISPLAY_TIMER = window.setTimeout(updateAll, 100);
    }
    function observeDocument(documentRef) {
      if (!documentRef || documentRef.defaultView === null || !documentRef.documentElement || window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS.indexOf(documentRef) >= 0) {
        return;
      }
      try {
        var observer = new MutationObserver(function() {
          gradeTableSearchCache.delete(documentRef);
          scheduleUpdate();
        });
        observer.observe(documentRef.documentElement, {
          childList: true,
          subtree: true,
          characterData: true
        });
        window.__MBG_GPA_DISPLAY_OBSERVERS.push(observer);
        window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS.push(documentRef);
      } catch (e) {
      }
    }
    window.__MBG_UPDATE_GPA_DISPLAY = updateAll;
    updateAll();
    window.__MBG_GPA_DISPLAY_STARTUP_TIMERS = [
      window.setTimeout(updateAll, 500),
      window.setTimeout(updateAll, 1500),
      window.setTimeout(updateAll, 3e3)
    ];
    window.__MBG_GPA_DISPLAY_INTERVAL = window.setInterval(updateAll, 500);
  }
  gpaDisplay();
})();
''';
