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
  function collectPageDocuments(win) {
    var docs = [];
    function collect(current) {
      try {
        var doc = current.document;
        if (!doc || docs.indexOf(doc) >= 0 || doc.defaultView === null) return;
        docs.push(doc);
        for (var i = 0; i < current.frames.length; i += 1) {
          try {
            collect(current.frames[i]);
          } catch (_) {
          }
        }
      } catch (_) {
      }
    }
    collect(win);
    return docs;
  }
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
    function sync(docs) {
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
    function run(docs) {
      if (disposed) return false;
      if (timer !== void 0) {
        win.clearTimeout(timer);
        timer = void 0;
      }
      sync(docs || collectPageDocuments(win));
      running = true;
      state.running += 1;
      var changed = false;
      try {
        callback();
      } catch (_) {
      } finally {
        state.observers.forEach(function(observer) {
          if (observer.takeRecords().length) changed = true;
        });
        state.running -= 1;
        running = false;
      }
      return changed;
    }
    sync(collectPageDocuments(win));
    var fallbackKey = String(options.fallbackMs);
    var fallback = fallbacks[fallbackKey];
    if (!fallback) {
      fallback = { timer: win.setInterval(function() {
        var docs;
        fallback.runs.slice().forEach(function(registeredRun) {
          if (!docs) docs = collectPageDocuments(win);
          if (registeredRun(docs)) docs = void 0;
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

  // web_scripts/src/shared/smartphone_message_rows.ts
  function messageOnclickUrl(node) {
    var match = String(node && node.getAttribute("onclick") || "").match(/\blocation\.href\s*=\s*(['"])(.*?)\1/);
    return match ? match[2].replace(/&amp;/g, "&") : "";
  }

  // web_scripts/src/shared/message_list_paging.ts
  function messageListFlowKey(doc, base) {
    var link = doc.querySelector('a[href*="_flowExecutionKey="]');
    if (link) {
      var value = new URL(link.getAttribute("href"), base).searchParams.get("_flowExecutionKey");
      if (value) return value;
    }
    var input = doc.querySelector('input[name="_flowExecutionKey"]');
    if (input && input.value) return input.value;
    var actions = doc.querySelectorAll('[onclick*="_flowExecutionKey="]');
    for (var i = 0; i < actions.length; i += 1) {
      var href = messageOnclickUrl(actions[i]);
      if (!href) continue;
      var value = new URL(href, base).searchParams.get("_flowExecutionKey");
      if (value) return value;
    }
    return "";
  }
  function largerMessageListPage(doc, base) {
    const control = doc.querySelector('select[name="_displayCount"]');
    if (!control || control.disabled) return null;
    const sizes = Array.from(control.options, (option) => Number(option.value)).filter((size) => Number.isInteger(size) && size > 0 && size <= 500);
    const largest = Math.max(...sizes);
    if (!Number.isFinite(largest) || !(largest > Number(control.value))) return null;
    const flowKey = messageListFlowKey(doc, base);
    if (!flowKey) return null;
    const url = new URL("campussquare.do", base);
    url.searchParams.set("_flowExecutionKey", flowKey);
    url.searchParams.set("_eventId", "paging");
    url.searchParams.set("_displayCount", String(largest));
    url.searchParams.set("_displayOffset", "0");
    return { url: url.href, count: largest };
  }

  // web_scripts/src/message_filter/main.ts
  function messageFilter() {
    var version = 8;
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
      function hasMessageRows(table) {
        return Array.from(table.querySelectorAll('a[href*="seqNo="]')).some(function(link) {
          var _a;
          return ((_a = link.closest("tr")) == null ? void 0 : _a.closest("table")) === table;
        });
      }
      var direct = doc.querySelector("table.normal:nth-child(9)");
      if (direct && hasMessageRows(direct)) return direct;
      return Array.from(doc.querySelectorAll("table")).find(function(table) {
        if (table.matches("table.keiji-normal") || table.closest("aside") || table.closest("nav") || table.closest('[id="tabmenutable"]') || !hasMessageRows(table)) return false;
        var heading = table.querySelector("tr");
        if (!heading || heading.closest("table") !== table) return false;
        var headings = Array.from(heading.children, function(cell) {
          return cell.textContent || "";
        }).join(" ");
        var caption = table.querySelector("caption");
        return /連絡通知|掲示/.test(headings) || /掲載日時/.test(headings) && /表題|差出人/.test(headings) || (caption == null ? void 0 : caption.closest("table")) === table && caption.id !== "mbg-message-search" && /連絡通知|掲示/.test(caption.textContent || "");
      }) || null;
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
      ["mbg-message-filter-status", "mbg-message-search"].forEach(function(id) {
        Array.prototype.forEach.call(doc.querySelectorAll('[id="' + id + '"]'), function(status) {
          if (activeStatuses.indexOf(status) < 0) status.remove();
        });
      });
    }
    function searchText(text) {
      return text.normalize("NFKC").toLowerCase().replace(/\s+/g, " ").trim();
    }
    function searchToolbar(doc, table) {
      var _a;
      var toolbar = table.querySelector('caption[id="mbg-message-search"]');
      if (toolbar) return toolbar;
      toolbar = doc.createElement("caption");
      toolbar.id = "mbg-message-search";
      toolbar.style.textAlign = "start";
      toolbar.style.padding = "6px 0";
      toolbar.style.captionSide = "top";
      var input = doc.createElement("input");
      input.type = "search";
      input.placeholder = "連絡通知を検索";
      input.ariaLabel = "連絡通知を検索";
      input.style.font = "inherit";
      input.style.maxWidth = "100%";
      var storageKey = "mbg-message-search-query";
      try {
        input.value = window.sessionStorage.getItem(storageKey) || "";
      } catch (_) {
      }
      input.addEventListener("keydown", function(event) {
        if (event.key === "Enter" && !event.isComposing && event.keyCode !== 229) {
          event.preventDefault();
          event.stopPropagation();
        }
      });
      input.addEventListener("input", function() {
        var _a2;
        try {
          window.sessionStorage.setItem(storageKey, input.value);
        } catch (_) {
        }
        (_a2 = window.__MBG_MESSAGE_FILTER_UPDATE) == null ? void 0 : _a2.call(window);
      });
      toolbar.appendChild(input);
      var count = doc.createElement("span");
      count.ariaLive = "polite";
      count.style.marginInlineStart = "8px";
      toolbar.appendChild(count);
      var hint = doc.createElement("div");
      hint.textContent = "このページの表題・差出人・ジャンル・日付などを検索（本文を除く）";
      hint.style.fontSize = "12px";
      toolbar.appendChild(hint);
      if (((_a = doc.location) == null ? void 0 : _a.origin) === "https://gakujo.iess.niigata-u.ac.jp") {
        var larger = largerMessageListPage(doc, doc.location.origin + "/campusweb/");
        if (larger) {
          var link = doc.createElement("a");
          link.href = larger.url;
          link.textContent = larger.count + "件表示して検索";
          hint.appendChild(doc.createTextNode(" "));
          hint.appendChild(link);
        }
      }
      table.insertBefore(toolbar, table.firstChild);
      return toolbar;
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
      var rows = smartphoneMessageRows(doc);
      var table = rows.length ? null : messageTable(doc);
      var terms = [];
      var count = null;
      if (table) {
        rows = Array.from(table.querySelectorAll("tr")).filter(function(row) {
          return row.closest("table") === table && !!row.querySelector('a[href*="seqNo="]');
        });
        var toolbar = searchToolbar(doc, table);
        activeStatuses.push(toolbar);
        var query = searchText(toolbar.querySelector("input").value);
        if (query) terms = query.split(" ");
        count = toolbar.querySelector("span");
      }
      if (!keywords.length && !terms.length) restoreRows(doc);
      if (!rows.length) {
        return false;
      }
      var listTable = table ? null : rows[0].closest("table");
      var hiddenCount = 0;
      var totalCount = 0;
      var visibleCount = 0;
      rows.forEach(function(row) {
        var originalDisplay = row.getAttribute("data-mbg-message-filter-display");
        var pageShowsRow = (originalDisplay != null ? originalDisplay : row.style.display) !== "none" && !row.hidden;
        if (pageShowsRow) totalCount += 1;
        if (!keywords.length && !terms.length) {
          if (pageShowsRow) visibleCount += 1;
          return;
        }
        var cells = row.cells;
        var text = table && (cells == null ? void 0 : cells.length) ? Array.from(cells, function(cell) {
          return (cell.textContent || "").replace(/\s+/g, " ").trim();
        }).join(" ") : compactText(row);
        var excluded = shouldHide(text);
        var searchable = terms.length ? searchText(text) : "";
        var hide = excluded || terms.some(function(term) {
          return !searchable.includes(term);
        });
        if (pageShowsRow && excluded) hiddenCount += 1;
        if (pageShowsRow && !hide) visibleCount += 1;
        if (hide) {
          if (originalDisplay === null) {
            originalDisplay = row.style.display || "";
            row.setAttribute("data-mbg-message-filter-display", originalDisplay);
          }
          if (row.style.display !== "none") {
            row.style.display = "none";
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
      var label = totalCount + "件中" + visibleCount + "件";
      if (count && count.textContent !== label) count.textContent = label;
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
