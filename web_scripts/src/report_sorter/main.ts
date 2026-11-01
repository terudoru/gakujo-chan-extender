export {};
function reportSorter() {
  var version = 3;
  if (window.__MBG_REPORT_SORTER_VERSION === version) {
    if (window.__MBG_REPORT_SORTER_UPDATE) {
      window.__MBG_REPORT_SORTER_UPDATE();
    }
    return;
  }
  window.__MBG_REPORT_SORTER_VERSION = version;
  var sortedTables = new WeakSet();

  function mainFrameDocument() {
    try {
      var frame = document.getElementById('main-frame-if') as HTMLIFrameElement | null;
      return frame && frame.contentWindow && frame.contentWindow.document || document;
    } catch (e) {
      return document;
    }
  }

  function reportTable() {
    var doc = mainFrameDocument();
    return doc.querySelector<HTMLTableElement>('#enqListForm table:nth-of-type(2)') ||
      document.querySelector<HTMLTableElement>('#enqListForm table:nth-of-type(2)');
  }

  function textOf(element: HTMLElement | null | undefined) {
    return (element && (element.innerText || element.textContent) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function normalizeDateNumber(text: string) {
    var normalized = (text || '').replace(/[０-９／：　]/g, function(character) {
      return character === '　' ? ' ' :
        String.fromCharCode(character.charCodeAt(0) - 0xFEE0);
    });
    var parts = normalized.split('～');
    var end = parts.pop() || '';
    // Parse Y/M/D and optional H:M explicitly so the comparable value is always
    // YYYYMMDDhhmm (12 digits), regardless of separators or trailing seconds.
    var pattern = /(\d{4})\D+(\d{1,2})\D+(\d{1,2})(?:\D+(\d{1,2})\D+(\d{1,2}))?/;
    var match: (string | number)[] | null = end.match(pattern);
    function dateNumber(value: (string | number)[]) {
      // UTC arithmetic normalizes 24:00 across days, months and years.
      var date = new Date(Date.UTC(+value[1], +value[2] - 1, +value[3],
        +(value[4] || 0), +(value[5] || 0)));
      function pad(value: number) {
        return ('0' + value).slice(-2);
      }
      return Number(String(date.getUTCFullYear()) + pad(date.getUTCMonth() + 1) +
        pad(date.getUTCDate()) + pad(date.getUTCHours()) + pad(date.getUTCMinutes()));
    }
    if (!match && parts.length) {
      var start = parts[0].match(pattern);
      var shortEnd = end.match(/^\s*(\d{1,2})\D+(\d{1,2})(?:\D+(\d{1,2})\D+(\d{1,2}))?/);
      if (start && shortEnd) {
        match = [shortEnd[0], start[1]].concat(shortEnd.slice(1));
        if (dateNumber(match) < dateNumber(start)) match[1] = +start[1] + 1;
      }
    }
    if (match) return dateNumber(match);
    var digits = end.replace(/[^\d]/g, '');
    return Number(digits || '0');
  }

  function statusRank(row: HTMLTableRowElement) {
    var text = textOf(row.cells[2]);
    if (/未提出|Not submitted/i.test(text)) {
      return 1;
    }
    if (/一時保存|Temporarily saved/i.test(text)) {
      return 2;
    }
    if (/提出済|Submitted/i.test(text)) {
      return 3;
    }
    return 9;
  }

  function deadlineValue(row: HTMLTableRowElement) {
    return normalizeDateNumber(textOf(row.cells[7]));
  }

  function isExpired(row: HTMLTableRowElement) {
    var deadline = deadlineValue(row);
    if (!deadline) {
      return false;
    }
    var now = new Date(Date.now() + 9 * 60 * 60 * 1000);
    var nowValue = Number(
      String(now.getUTCFullYear()) +
      String(now.getUTCMonth() + 1).padStart(2, '0') +
      String(now.getUTCDate()).padStart(2, '0') +
      String(now.getUTCHours()).padStart(2, '0') +
      String(now.getUTCMinutes()).padStart(2, '0')
    );
    return deadline < nowValue;
  }

  function bodyRows(table: HTMLTableElement) {
    return Array.prototype.slice.call(table.rows, 1) as HTMLTableRowElement[];
  }

  function rewriteRows(table: HTMLTableElement, rows: HTMLTableRowElement[]) {
    var parent = table.tBodies && table.tBodies.length ? table.tBodies[0] : table;
    for (var i = 0; i < rows.length; i += 1) {
      parent.appendChild(rows[i]);
    }
    colorTemporarySaved(table);
  }

  function colorTemporarySaved(table: HTMLTableElement) {
    var rows = bodyRows(table);
    for (var i = 0; i < rows.length; i += 1) {
      var cell = rows[i].cells[2];
      if (!cell) {
        continue;
      }
      if (/一時保存|Temporarily saved/i.test(textOf(cell))) {
        cell.style.color = 'blue';
      }
    }
  }

  function sortByDate() {
    var table = reportTable();
    if (!table) {
      return;
    }
    var rows = bodyRows(table);
    rows.sort(function(a, b) {
      return Number(isExpired(a)) - Number(isExpired(b)) ||
        statusRank(a) - statusRank(b) ||
        deadlineValue(a) - deadlineValue(b);
    });
    rewriteRows(table, rows);
  }

  function sortByNumber() {
    var table = reportTable();
    if (!table) {
      return;
    }
    var rows = bodyRows(table);
    rows.sort(function(a, b) {
      return textOf(a.cells[3]).localeCompare(textOf(b.cells[3]), 'ja');
    });
    rewriteRows(table, rows);
  }

  function sortByTitle() {
    var table = reportTable();
    if (!table) {
      return;
    }
    var rows = bodyRows(table);
    rows.sort(function(a, b) {
      return textOf(a.cells[1]).localeCompare(textOf(b.cells[1]), 'ja');
    });
    rewriteRows(table, rows);
  }

  function addButton(id: string, label: string, handler: EventListener) {
    var target = document.getElementById('tabmenutable');
    if (!target || document.getElementById(id)) {
      return;
    }
    var button = document.createElement('button');
    button.id = id;
    button.type = 'button';
    button.setAttribute('data-mbg-report-sorter-owned', 'true');
    button.textContent = label;
    button.addEventListener('click', handler);
    target.appendChild(button);
  }

  function update() {
    var table = reportTable();
    if (!table) {
      return false;
    }
    addButton('mbg-report-title-button', 'タイトルでソート', sortByTitle);
    addButton('mbg-report-number-button', '開講番号でソート', sortByNumber);
    addButton('mbg-report-date-button', '提出期間でソート', sortByDate);
    colorTemporarySaved(table);
    if (!sortedTables.has(table)) {
      sortedTables.add(table);
      sortByDate();
    }
    return true;
  }

  window.__MBG_REPORT_SORTER_UPDATE = update;
  update();
  window.clearInterval(window.__MBG_REPORT_SORTER_INTERVAL);
  window.__MBG_REPORT_SORTER_INTERVAL = window.setInterval(update, 500);
}

reportSorter();
