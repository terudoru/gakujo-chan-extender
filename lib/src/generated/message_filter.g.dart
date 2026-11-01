// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/message_filter/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoMessageFilterJs(Map<String, Object?> config) =>
    _gakujoMessageFilterJsPrefix +
    jsonEncode(config) +
    _gakujoMessageFilterJsSuffix;

const String _gakujoMessageFilterJsPrefix = r'''(function(__mbgConfig) {
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
    var fallbacks = state.fallbacks || (state.fallbacks = {});
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
    var fallbackKey = String(options.fallbackMs);
    var fallback = fallbacks[fallbackKey];
    if (!fallback) {
      fallback = { timer: win.setInterval(function() {
        fallback.runs.slice().forEach(function(registeredRun) {
          registeredRun();
        });
      }, options.fallbackMs), runs: [] };
      fallbacks[fallbackKey] = fallback;
    }
    fallback.runs.push(run);
    return function() {
      if (disposed) return;
      disposed = true;
      if (timer !== void 0) win.clearTimeout(timer);
      var index = fallback.runs.indexOf(run);
      if (index >= 0) fallback.runs.splice(index, 1);
      if (!fallback.runs.length) {
        win.clearInterval(fallback.timer);
        delete fallbacks[fallbackKey];
      }
      entries.forEach(remove);
      entries = [];
      if (!state.observers.length && !Object.keys(fallbacks).length) delete win.__MBG_PAGE_WATCH_STATE;
    };
  }

  // web_scripts/src/message_filter/main.ts
  function messageFilter() {
    var version = 6;
    var keywords = __mbgConfig.keywords.map(function(keyword) {
      return String(keyword || "").trim().toLowerCase();
    }).filter(Boolean);
    var signature = JSON.stringify(keywords);
    if (window.__MBG_MESSAGE_FILTER_VERSION === version && window.__MBG_MESSAGE_FILTER_SIGNATURE === signature) {
      if (window.__MBG_MESSAGE_FILTER_UPDATE) {
        window.__MBG_MESSAGE_FILTER_UPDATE();
      }
      return;
    }
    window.__MBG_MESSAGE_FILTER_VERSION = version;
    window.__MBG_MESSAGE_FILTER_SIGNATURE = signature;
    function candidateDocuments() {
      var docs = [];
      try {
        var frame = document.getElementById("main-frame-if");
        var frameDoc = frame && frame.contentWindow && frame.contentWindow.document;
        if (frameDoc) docs.push(frameDoc);
      } catch (e) {
      }
      if (docs.indexOf(document) < 0) docs.push(document);
      return docs;
    }
    function compactText(element) {
      return (element && (element.innerText || element.textContent || element.value) || "").replace(/\s+/g, " ").trim();
    }
    function messageTable(doc) {
      var direct = doc.querySelector("table.normal:nth-child(9)");
      if (direct) {
        return direct;
      }
      var tables = doc.querySelectorAll("table");
      for (var i = 0; i < tables.length; i += 1) {
        var table = tables[i];
        var text = compactText(table);
        if ((text.indexOf("連絡通知") >= 0 || text.indexOf("全学連絡通知") >= 0 || text.indexOf("掲示") >= 0) && table.querySelector('a[href*="seqNo="]')) {
          return table;
        }
      }
      return null;
    }
    function smartphoneMessageRows(doc) {
      var rows = [];
      var buttons = doc.querySelectorAll('div.button[onclick*="seqNo="]');
      Array.prototype.forEach.call(buttons, function(button) {
        for (var row = button.parentNode; row; row = row.parentNode) {
          if (row.tagName === "TR" && row.querySelector("td.category-frame")) {
            if (rows.indexOf(row) < 0) rows.push(row);
            break;
          }
        }
      });
      return rows;
    }
    function shouldHide(text) {
      var normalized = String(text || "").toLowerCase();
      for (var i = 0; i < keywords.length; i += 1) {
        if (normalized.indexOf(keywords[i]) >= 0) {
          return true;
        }
      }
      return false;
    }
    function updateStatus(doc, hiddenCount, listTable) {
      if (!keywords.length || hiddenCount <= 0) {
        return null;
      }
      var statusDoc = listTable ? doc : document;
      var target = listTable ? listTable.parentNode : statusDoc.getElementById("tabmenutable");
      if (!target) {
        return null;
      }
      var status = statusDoc.getElementById("mbg-message-filter-status");
      if (!status) {
        status = statusDoc.createElement("span");
        status.id = "mbg-message-filter-status";
        status.style.marginLeft = "8px";
        status.style.fontSize = "12px";
        status.style.color = "#31543f";
      }
      if (status.parentNode !== target) {
        if (listTable) target.insertBefore(status, listTable);
        else target.appendChild(status);
      }
      var label = "除外中: " + hiddenCount + "件";
      if (status.textContent !== label) status.textContent = label;
      return status;
    }
    function removeStaleStatuses(doc, activeStatuses) {
      var statuses = doc.querySelectorAll('[id="mbg-message-filter-status"]');
      Array.prototype.forEach.call(statuses, function(status) {
        if (activeStatuses.indexOf(status) < 0) status.remove();
      });
    }
    function restoreRows(doc) {
      var hiddenRows = doc.querySelectorAll("tr[data-mbg-message-filter-display]");
      Array.prototype.forEach.call(hiddenRows, function(row) {
        var originalDisplay = row.getAttribute("data-mbg-message-filter-display");
        if (row.style.display !== originalDisplay) {
          row.style.display = originalDisplay;
        }
        row.removeAttribute("data-mbg-message-filter-display");
        if (row.getAttribute("data-mbg-message-filtered") !== "false") {
          row.setAttribute("data-mbg-message-filtered", "false");
        }
      });
    }
    function applyDocumentFilter(doc, activeStatuses) {
      if (!keywords.length) {
        restoreRows(doc);
        return true;
      }
      var rows = smartphoneMessageRows(doc);
      var table = rows.length ? null : messageTable(doc);
      if (table) {
        rows = Array.prototype.slice.call(table.querySelectorAll("tr"), 1);
      }
      if (!rows.length) {
        return false;
      }
      var listTable = table ? null : rows[0].closest("table");
      var hiddenCount = 0;
      rows.forEach(function(row) {
        var text = compactText(row);
        var hide = shouldHide(text);
        var originalDisplay = row.getAttribute("data-mbg-message-filter-display");
        if (hide) {
          if (originalDisplay === null) {
            originalDisplay = row.style.display || "";
            row.setAttribute("data-mbg-message-filter-display", originalDisplay);
          }
          if (row.style.display !== "none") {
            row.style.display = "none";
          }
          if (originalDisplay !== "none") {
            hiddenCount += 1;
          }
        } else if (originalDisplay !== null) {
          if (row.style.display !== originalDisplay) {
            row.style.display = originalDisplay;
          }
          row.removeAttribute("data-mbg-message-filter-display");
        }
        var filtered = hide ? "true" : "false";
        if (row.getAttribute("data-mbg-message-filtered") !== filtered) {
          row.setAttribute("data-mbg-message-filtered", filtered);
        }
      });
      var status = updateStatus(doc, hiddenCount, listTable);
      if (status) activeStatuses.push(status);
      return true;
    }
    function applyFilter() {
      var applied = false;
      var docs = candidateDocuments();
      var activeStatuses = [];
      docs.forEach(function(doc) {
        if (applyDocumentFilter(doc, activeStatuses)) applied = true;
      });
      docs.forEach(function(doc) {
        removeStaleStatuses(doc, activeStatuses);
      });
      return applied;
    }
    window.__MBG_MESSAGE_FILTER_DISPOSE = function() {
      if (window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE) window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE();
      delete window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE;
      window.clearInterval(window.__MBG_MESSAGE_FILTER_INTERVAL);
      candidateDocuments().forEach(function(doc) {
        restoreRows(doc);
        removeStaleStatuses(doc, []);
      });
      delete window.__MBG_MESSAGE_FILTER_VERSION;
      delete window.__MBG_MESSAGE_FILTER_SIGNATURE;
      delete window.__MBG_MESSAGE_FILTER_UPDATE;
      delete window.__MBG_MESSAGE_FILTER_INTERVAL;
      delete window.__MBG_MESSAGE_FILTER_DISPOSE;
    };
    window.__MBG_MESSAGE_FILTER_UPDATE = applyFilter;
    applyFilter();
    window.clearInterval(window.__MBG_MESSAGE_FILTER_INTERVAL);
    if (window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE) window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE();
    window.__MBG_MESSAGE_FILTER_WATCH_DISPOSE = watchPage(window, applyFilter, { fallbackMs: 5e3, legacyIntervalMs: 500 });
  }
  messageFilter();
})();
})(''';
const String _gakujoMessageFilterJsSuffix = r''');
''';
