class GakujoReportSorterScript {
  const GakujoReportSorterScript._();

  static String build() {
    return r'''
(function() {
  var version = 1;
  if (window.__MBG_REPORT_SORTER_VERSION === version) {
    if (window.__MBG_REPORT_SORTER_UPDATE) {
      window.__MBG_REPORT_SORTER_UPDATE();
    }
    return;
  }
  window.__MBG_REPORT_SORTER_VERSION = version;

  function mainFrameDocument() {
    try {
      var frame = document.getElementById('main-frame-if');
      return frame && frame.contentWindow && frame.contentWindow.document || document;
    } catch (e) {
      return document;
    }
  }

  function reportTable() {
    var doc = mainFrameDocument();
    return doc.querySelector('#enqListForm table:nth-of-type(2)');
  }

  function textOf(element) {
    return (element && (element.innerText || element.textContent) || '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function normalizeDateNumber(text) {
    var end = (text || '').split('～').pop() || '';
    // Parse Y/M/D and optional H:M explicitly so the comparable value is always
    // YYYYMMDDhhmm (12 digits), regardless of separators or trailing seconds.
    var match = end.match(
      /(\d{4})\D+(\d{1,2})\D+(\d{1,2})(?:\D+(\d{1,2})\D+(\d{1,2}))?/
    );
    if (match) {
      function pad(value) {
        return ('0' + (value || '0')).slice(-2);
      }
      return Number(
        match[1] + pad(match[2]) + pad(match[3]) + pad(match[4]) + pad(match[5])
      );
    }
    var digits = end.replace(/[^\d]/g, '');
    return Number(digits || '0');
  }

  function statusRank(row) {
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

  function deadlineValue(row) {
    return normalizeDateNumber(textOf(row.cells[7]));
  }

  function isExpired(row) {
    var deadline = deadlineValue(row);
    if (!deadline) {
      return false;
    }
    var now = new Date();
    var nowValue = Number(
      String(now.getFullYear()) +
      String(now.getMonth() + 1).padStart(2, '0') +
      String(now.getDate()).padStart(2, '0') +
      String(now.getHours()).padStart(2, '0') +
      String(now.getMinutes()).padStart(2, '0')
    );
    return deadline < nowValue;
  }

  function bodyRows(table) {
    return Array.prototype.slice.call(table.rows, 1);
  }

  function rewriteRows(table, rows) {
    var parent = table.tBodies && table.tBodies.length ? table.tBodies[0] : table;
    for (var i = 0; i < rows.length; i += 1) {
      parent.appendChild(rows[i]);
    }
    colorTemporarySaved(table);
  }

  function colorTemporarySaved(table) {
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

  function addButton(id, label, handler) {
    var target = document.getElementById('tabmenutable');
    if (!target || document.getElementById(id)) {
      return;
    }
    var button = document.createElement('button');
    button.id = id;
    button.type = 'button';
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
    if (!window.__MBG_REPORT_SORTER_DID_INITIAL_SORT) {
      window.__MBG_REPORT_SORTER_DID_INITIAL_SORT = true;
      sortByDate();
    }
    return true;
  }

  window.__MBG_REPORT_SORTER_UPDATE = update;
  update();
  window.clearInterval(window.__MBG_REPORT_SORTER_INTERVAL);
  window.__MBG_REPORT_SORTER_INTERVAL = window.setInterval(update, 500);
})();
''';
  }
}
