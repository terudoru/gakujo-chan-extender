class GakujoGpaDisplayScript {
  const GakujoGpaDisplayScript._();

  static String build() {
    return r'''
(function() {
  var version = 7;
  if (window.__MBG_GPA_DISPLAY_VERSION === version) {
    if (window.__MBG_UPDATE_GPA_DISPLAY) {
      window.__MBG_UPDATE_GPA_DISPLAY();
    }
    return;
  }
  window.__MBG_GPA_DISPLAY_VERSION = version;
  window.clearTimeout(window.__MBG_GPA_DISPLAY_TIMER);
  var previousStartupTimers = window.__MBG_GPA_DISPLAY_STARTUP_TIMERS || [];
  for (var timerIndex = 0;
      timerIndex < previousStartupTimers.length;
      timerIndex += 1) {
    window.clearTimeout(previousStartupTimers[timerIndex]);
  }
  window.__MBG_GPA_DISPLAY_STARTUP_TIMERS = [];
  window.clearInterval(window.__MBG_GPA_DISPLAY_INTERVAL);
  if (window.__MBG_GPA_DISPLAY_OBSERVERS) {
    for (var observerIndex = 0;
        observerIndex < window.__MBG_GPA_DISPLAY_OBSERVERS.length;
        observerIndex += 1) {
      window.__MBG_GPA_DISPLAY_OBSERVERS[observerIndex].disconnect();
    }
  }
  window.__MBG_GPA_DISPLAY_OBSERVERS = [];
  window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS = [];

  function textOf(element) {
    return (element && (element.innerText || element.textContent) || '')
      .replace(/\s+/g, '')
      .trim();
  }

  function labelOf(element) {
    if (!element) {
      return '';
    }
    var clone = element.cloneNode(true);
    var displays = clone.querySelectorAll('.mbg-gpa-display');
    for (var i = 0; i < displays.length; i += 1) {
      displays[i].remove();
    }
    var text = textOf(clone)
      .replace(/[Ａ-Ｚａ-ｚ０-９]/g, function(ch) {
        return String.fromCharCode(ch.charCodeAt(0) - 0xFEE0);
      })
      .replace(/．/g, '.')
      .toUpperCase();
    return text.replace(/GPA:?\d*(?:\.\d+)?/g, '');
  }

  function toAsciiNumber(text) {
    return (text || '')
      .replace(/[０-９]/g, function(ch) {
        return String.fromCharCode(ch.charCodeAt(0) - 0xFEE0);
      })
      .replace(/[．]/g, '.')
      .replace(/,/g, '')
      .trim();
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
      } catch (e) {}
    }
    collect(window);
    try {
      var mainFrame = window.document.getElementById('main-frame-if');
      if (mainFrame && mainFrame.contentWindow && mainFrame.contentWindow.document) {
        documents.push(mainFrame.contentWindow.document);
      }
    } catch (e) {}
    return documents;
  }

  function expandedCells(row) {
    var slots = [];
    var cells = row ? row.children : [];
    for (var i = 0; i < cells.length; i += 1) {
      var span = Number(cells[i].getAttribute('colspan') || '1');
      if (!isFinite(span) || span < 1) {
        span = 1;
      }
      for (var j = 0; j < span; j += 1) {
        slots.push(cells[i]);
      }
    }
    return slots;
  }

  function findGradeTable(documentRef) {
    var directTable = directGradeTable(documentRef);
    if (directTable) {
      return directTable;
    }

    var tables = documentRef.querySelectorAll('table');
    for (var tableIndex = 0; tableIndex < tables.length; tableIndex += 1) {
      var rows = tables[tableIndex].querySelectorAll('tr');
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
          } else if (label.indexOf('開講番号') >= 0) {
            openNumberIndex = cellIndex;
          } else if (isScoreLabel(label)) {
            scoreIndex = cellIndex;
          } else if (label.indexOf('単位数') >= 0) {
            unitIndex = cellIndex;
          } else if (label === 'GP') {
            gpIndex = cellIndex;
          }
        }
        if (unitIndex >= 0 && gpIndex >= 0 &&
            labels.join('|').indexOf('科目') >= 0 &&
            labels.join('|').indexOf('得点') >= 0 &&
            labels.join('|').indexOf('評価') >= 0) {
          return {
            table: tables[tableIndex],
            headerCell: cells[gpIndex],
            headerRowIndex: rowIndex,
            numberIndex: numberIndex,
            openNumberIndex: openNumberIndex,
            scoreIndex: scoreIndex,
            unitIndex: unitIndex,
            gpIndex: gpIndex
          };
        }
      }
    }
    return null;
  }

  function directGradeTable(documentRef) {
    try {
      var table = documentRef.querySelector('#taniReferListForm+table');
      if (!table || !table.rows || !table.rows.length) {
        return null;
      }
      var headerCells = table.rows[0].cells;
      if (!headerCells || headerCells.length <= 12) {
        return null;
      }
      if (labelOf(headerCells[12]) !== 'GP') {
        return null;
      }
      return {
        table: table,
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
    return label === 'NO.' || label === 'NO' || label === '番号';
  }

  function isScoreLabel(label) {
    return label === '得点' ||
      label === '評点' ||
      label === '点' ||
      label.indexOf('得点') >= 0 ||
      label.indexOf('評点') >= 0;
  }

  function removeGpaDisplay(headerCell) {
    if (!headerCell) {
      return;
    }
    var displays = headerCell.querySelectorAll('.mbg-gpa-display');
    for (var i = 0; i < displays.length; i += 1) {
      displays[i].remove();
    }
  }

  function renderGpaDisplay(headerCell, gpa, credits) {
    var text = 'GPA:' + gpa.toFixed(4);
    var title = 'GPが入力されている科目の加重平均 GPA: ' +
      gpa.toFixed(4) + ' / 対象単位数: ' + credits.toFixed(1);
    var display = headerCell.querySelector('.mbg-gpa-display');
    if (display) {
      display.setAttribute('data-mbg-gpa-display-owned', 'true');
    }
    if (display && display.textContent === text && display.title === title) {
      return;
    }
    if (display) {
      display.textContent = text;
      display.title = title;
      return;
    }
    display = headerCell.ownerDocument.createElement('div');
    display.className = 'mbg-gpa-display';
    display.setAttribute('data-mbg-gpa-display-owned', 'true');
    display.textContent = text;
    display.title = title;
    display.style.marginTop = '1px';
    display.style.padding = '0';
    display.style.border = '0';
    display.style.background = 'transparent';
    display.style.color = 'inherit';
    display.style.fontSize = '10px';
    display.style.fontWeight = '700';
    display.style.lineHeight = '1.1';
    display.style.whiteSpace = 'nowrap';
    display.style.display = 'block';
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
      return textOf(cellsForGradeRow(a, gradeTable)[index])
        .localeCompare(textOf(cellsForGradeRow(b, gradeTable)[index]), 'ja');
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
    var target = document.getElementById('tabmenutable');
    if (!target || document.getElementById(id)) {
      return;
    }
    var button = document.createElement('button');
    button.id = id;
    button.type = 'button';
    button.setAttribute('data-mbg-gpa-display-owned', 'true');
    button.textContent = label;
    button.addEventListener('click', handler);
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
    addGradeSortButton('mbg-grade-no-button', 'No.でソート', sortByNumber);
    addGradeSortButton(
      'mbg-grade-open-number-button',
      '開講番号でソート',
      sortByOpenNumber
    );
    addGradeSortButton('mbg-grade-score-button', '得点でソート', sortByScore);
  }

  function updateDocument(documentRef) {
    var gradeTable = findGradeTable(documentRef);
    if (!gradeTable) {
      return;
    }

    var weightedGp = 0;
    var totalCredits = 0;
    var rows = gradeTable.table.querySelectorAll('tr');
    for (var rowIndex = gradeTable.headerRowIndex + 1;
        rowIndex < rows.length;
        rowIndex += 1) {
      var cells = gradeTable.useDirectCells
        ? rows[rowIndex].cells
        : expandedCells(rows[rowIndex]);
      var unitCell = cells[gradeTable.unitIndex];
      var gpCell = cells[gradeTable.gpIndex];
      var credits = numberFromCell(unitCell);
      var gp = numberFromCell(gpCell);
      if (!isFinite(credits) || credits <= 0 || !isFinite(gp)) {
        continue;
      }
      weightedGp += credits * gp;
      totalCredits += credits;
    }

    if (totalCredits <= 0) {
      removeGpaDisplay(gradeTable.headerCell);
      return;
    }
    renderGpaDisplay(
      gradeTable.headerCell,
      weightedGp / totalCredits,
      totalCredits
    );
  }

  function updateAll() {
    var documents = collectDocuments();
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
    if (!documentRef || !documentRef.documentElement ||
        window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS.indexOf(documentRef) >= 0) {
      return;
    }
    try {
      var observer = new MutationObserver(scheduleUpdate);
      observer.observe(documentRef.documentElement, {
        childList: true,
        subtree: true,
        characterData: true
      });
      window.__MBG_GPA_DISPLAY_OBSERVERS.push(observer);
      window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS.push(documentRef);
    } catch (e) {}
  }

  window.__MBG_UPDATE_GPA_DISPLAY = updateAll;
  updateAll();
  window.__MBG_GPA_DISPLAY_STARTUP_TIMERS = [
    window.setTimeout(updateAll, 500),
    window.setTimeout(updateAll, 1500),
    window.setTimeout(updateAll, 3000)
  ];
  window.__MBG_GPA_DISPLAY_INTERVAL = window.setInterval(updateAll, 500);
})();
''';
  }

  static String buildTeardown() {
    return r'''
(function() {
  window.clearTimeout(window.__MBG_GPA_DISPLAY_TIMER);
  var startupTimers = window.__MBG_GPA_DISPLAY_STARTUP_TIMERS || [];
  for (var timerIndex = 0;
      timerIndex < startupTimers.length;
      timerIndex += 1) {
    window.clearTimeout(startupTimers[timerIndex]);
  }
  window.clearInterval(window.__MBG_GPA_DISPLAY_INTERVAL);

  var observers = window.__MBG_GPA_DISPLAY_OBSERVERS || [];
  for (var observerIndex = 0;
      observerIndex < observers.length;
      observerIndex += 1) {
    try {
      observers[observerIndex].disconnect();
    } catch (e) {}
  }

  var documents = [];
  function addDocument(documentRef) {
    if (documentRef && documents.indexOf(documentRef) < 0) {
      documents.push(documentRef);
    }
  }

  var observedDocuments = window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS || [];
  for (var documentIndex = 0;
      documentIndex < observedDocuments.length;
      documentIndex += 1) {
    addDocument(observedDocuments[documentIndex]);
  }

  function collectDocuments(win) {
    try {
      addDocument(win.document);
      for (var frameIndex = 0; frameIndex < win.frames.length; frameIndex += 1) {
        collectDocuments(win.frames[frameIndex]);
      }
    } catch (e) {}
  }
  collectDocuments(window);
  try {
    var mainFrame = window.document.getElementById('main-frame-if');
    if (mainFrame && mainFrame.contentWindow) {
      addDocument(mainFrame.contentWindow.document);
    }
  } catch (e) {}

  var controlIds = [
    'mbg-grade-no-button',
    'mbg-grade-open-number-button',
    'mbg-grade-score-button'
  ];
  for (var i = 0; i < documents.length; i += 1) {
    try {
      var ownedElements = documents[i].querySelectorAll(
        '[data-mbg-gpa-display-owned="true"]'
      );
      for (var ownedIndex = 0;
          ownedIndex < ownedElements.length;
          ownedIndex += 1) {
        ownedElements[ownedIndex].remove();
      }

      var legacyDisplays = documents[i].querySelectorAll('.mbg-gpa-display');
      for (var displayIndex = 0;
          displayIndex < legacyDisplays.length;
          displayIndex += 1) {
        legacyDisplays[displayIndex].remove();
      }

      for (var controlIndex = 0;
          controlIndex < controlIds.length;
          controlIndex += 1) {
        var legacyControl = documents[i].getElementById(
          controlIds[controlIndex]
        );
        if (legacyControl) {
          legacyControl.remove();
        }
      }
    } catch (e) {}
  }

  delete window.__MBG_GPA_DISPLAY_TIMER;
  delete window.__MBG_GPA_DISPLAY_STARTUP_TIMERS;
  delete window.__MBG_GPA_DISPLAY_INTERVAL;
  delete window.__MBG_GPA_DISPLAY_OBSERVERS;
  delete window.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS;
  delete window.__MBG_UPDATE_GPA_DISPLAY;
  delete window.__MBG_GPA_DISPLAY_VERSION;
})();
''';
  }
}
