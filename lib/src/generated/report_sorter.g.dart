// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/report_sorter/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoReportSorterJs = r'''
"use strict";
(() => {
  // web_scripts/src/shared/page_watch.ts
  function watchPage(win, callback, options) {
    var Observer = win.MutationObserver;
    if (typeof Observer !== "function") {
      var legacyTimer = win.setInterval(callback, options.legacyIntervalMs);
      return function() {
        win.clearInterval(legacyTimer);
      };
    }
    var entries = [];
    var state = win.__MBG_PAGE_WATCH_STATE || { running: 0, observers: [] };
    win.__MBG_PAGE_WATCH_STATE = state;
    var timer;
    var disposed = false;
    var running = false;
    function schedule() {
      if (disposed || running || state.running || timer !== void 0) return;
      timer = win.setTimeout(function() {
        timer = void 0;
        run();
      }, 100);
    }
    function sync() {
      var docs = [];
      function collect(current) {
        try {
          var doc = current.document;
          if (!doc || docs.indexOf(doc) >= 0 || doc.defaultView === null) return;
          docs.push(doc);
          for (var i2 = 0; i2 < current.frames.length; i2 += 1) {
            try {
              collect(current.frames[i2]);
            } catch (_) {
            }
          }
        } catch (_) {
        }
      }
      collect(win);
      for (var i = entries.length - 1; i >= 0; i -= 1) {
        if (docs.indexOf(entries[i].doc) < 0) {
          remove(entries[i]);
          entries.splice(i, 1);
        }
      }
      docs.forEach(function(doc) {
        if (!doc.documentElement || entries.some(function(entry) {
          return entry.doc === doc;
        })) return;
        try {
          var observer = new Observer(function() {
            if (options.onMutation) options.onMutation(doc);
            schedule();
          });
          observer.observe(doc.documentElement, { childList: true, subtree: true, characterData: true, attributes: true });
          doc.addEventListener("load", schedule, true);
          doc.addEventListener("input", schedule, true);
          doc.addEventListener("change", schedule, true);
          entries.push({ doc, observer });
          state.observers.push(observer);
        } catch (_) {
        }
      });
    }
    function remove(entry) {
      entry.observer.disconnect();
      var index = state.observers.indexOf(entry.observer);
      if (index >= 0) state.observers.splice(index, 1);
      entry.doc.removeEventListener("load", schedule, true);
      entry.doc.removeEventListener("input", schedule, true);
      entry.doc.removeEventListener("change", schedule, true);
    }
    function run() {
      if (disposed) return;
      if (timer !== void 0) {
        win.clearTimeout(timer);
        timer = void 0;
      }
      sync();
      running = true;
      state.running += 1;
      try {
        callback();
      } catch (_) {
      } finally {
        state.observers.forEach(function(observer) {
          observer.takeRecords();
        });
        state.running -= 1;
        running = false;
      }
    }
    sync();
    var fallbackTimer = win.setInterval(run, options.fallbackMs);
    return function() {
      disposed = true;
      if (timer !== void 0) win.clearTimeout(timer);
      win.clearInterval(fallbackTimer);
      entries.forEach(remove);
      entries = [];
      if (!state.observers.length) delete win.__MBG_PAGE_WATCH_STATE;
    };
  }

  // web_scripts/src/report_sorter/main.ts
  function reportSorter() {
    var version = 4;
    if (window.__MBG_REPORT_SORTER_VERSION === version) {
      if (window.__MBG_REPORT_SORTER_UPDATE) {
        window.__MBG_REPORT_SORTER_UPDATE();
      }
      return;
    }
    window.__MBG_REPORT_SORTER_VERSION = version;
    var sortedTables = /* @__PURE__ */ new WeakSet();
    function mainFrameDocument() {
      try {
        var frame = document.getElementById("main-frame-if");
        return frame && frame.contentWindow && frame.contentWindow.document || document;
      } catch (e) {
        return document;
      }
    }
    function reportTable() {
      var doc = mainFrameDocument();
      return doc.querySelector("#enqListForm table:nth-of-type(2)") || document.querySelector("#enqListForm table:nth-of-type(2)");
    }
    function textOf(element) {
      return (element && (element.innerText || element.textContent) || "").replace(/\s+/g, " ").trim();
    }
    function normalizeDateNumber(text) {
      var normalized = (text || "").replace(/[０-９／：　]/g, function(character) {
        return character === "　" ? " " : String.fromCharCode(character.charCodeAt(0) - 65248);
      });
      var parts = normalized.split("～");
      var end = parts.pop() || "";
      var pattern = /(\d{4})\D+(\d{1,2})\D+(\d{1,2})(?:\D+(\d{1,2})\D+(\d{1,2}))?/;
      var match = end.match(pattern);
      function dateNumber(value) {
        var date = new Date(Date.UTC(
          +value[1],
          +value[2] - 1,
          +value[3],
          +(value[4] || 0),
          +(value[5] || 0)
        ));
        function pad(value2) {
          return ("0" + value2).slice(-2);
        }
        return Number(String(date.getUTCFullYear()) + pad(date.getUTCMonth() + 1) + pad(date.getUTCDate()) + pad(date.getUTCHours()) + pad(date.getUTCMinutes()));
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
      var digits = end.replace(/[^\d]/g, "");
      return Number(digits || "0");
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
      var now = new Date(Date.now() + 9 * 60 * 60 * 1e3);
      var nowValue = Number(
        String(now.getUTCFullYear()) + String(now.getUTCMonth() + 1).padStart(2, "0") + String(now.getUTCDate()).padStart(2, "0") + String(now.getUTCHours()).padStart(2, "0") + String(now.getUTCMinutes()).padStart(2, "0")
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
          cell.style.color = "blue";
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
        return Number(isExpired(a)) - Number(isExpired(b)) || statusRank(a) - statusRank(b) || deadlineValue(a) - deadlineValue(b);
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
        return textOf(a.cells[3]).localeCompare(textOf(b.cells[3]), "ja");
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
        return textOf(a.cells[1]).localeCompare(textOf(b.cells[1]), "ja");
      });
      rewriteRows(table, rows);
    }
    function addButton(id, label, handler) {
      var target = document.getElementById("tabmenutable");
      if (!target || document.getElementById(id)) {
        return;
      }
      var button = document.createElement("button");
      button.id = id;
      button.type = "button";
      button.setAttribute("data-mbg-report-sorter-owned", "true");
      button.textContent = label;
      button.addEventListener("click", handler);
      target.appendChild(button);
    }
    function update() {
      var table = reportTable();
      if (!table) {
        return false;
      }
      addButton("mbg-report-title-button", "タイトルでソート", sortByTitle);
      addButton("mbg-report-number-button", "開講番号でソート", sortByNumber);
      addButton("mbg-report-date-button", "提出期間でソート", sortByDate);
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
    if (window.__MBG_REPORT_SORTER_WATCH_DISPOSE) window.__MBG_REPORT_SORTER_WATCH_DISPOSE();
    window.__MBG_REPORT_SORTER_WATCH_DISPOSE = watchPage(window, update, { fallbackMs: 5e3, legacyIntervalMs: 500 });
  }
  reportSorter();
})();
''';
