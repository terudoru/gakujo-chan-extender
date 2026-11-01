// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/message_reader/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoMessageReaderJs = r'''
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

  // web_scripts/src/message_reader/main.ts
  function messageReader() {
    var version = 8;
    if (window.__MBG_MESSAGE_READER_VERSION === version) {
      if (window.__MBG_MESSAGE_READER_UPDATE) {
        window.__MBG_MESSAGE_READER_UPDATE();
      }
      return;
    }
    if (window.__MBG_MESSAGE_READER_DISPOSE) {
      window.__MBG_MESSAGE_READER_DISPOSE();
    }
    window.__MBG_MESSAGE_READER_VERSION = version;
    var disposed = false;
    var reading = false;
    var reloadTimeout;
    var cancelPendingFrame;
    var controlsDocument = document;
    window.__MBG_MESSAGE_READER_DISPOSE = function() {
      disposed = true;
      window.clearTimeout(reloadTimeout);
      window.clearTimeout(confirmTimer);
      if (cancelPendingFrame) {
        cancelPendingFrame();
      }
    };
    function mainFrameDocument() {
      try {
        var frame = document.getElementById("main-frame-if");
        return frame && frame.contentWindow && frame.contentWindow.document || document;
      } catch (e) {
        return document;
      }
    }
    function messageTable(doc) {
      doc = doc || mainFrameDocument();
      return doc.querySelector("table.normal:nth-child(9)");
    }
    function smartphoneUnreadList() {
      var docs = [mainFrameDocument()];
      if (docs[0] !== document) docs.push(document);
      for (var i = 0; i < docs.length; i += 1) {
        var doc = docs[i];
        var text = doc.body && (doc.body.innerText || doc.body.textContent) || "";
        if (text.indexOf("未読一覧") < 0) continue;
        var items = doc.querySelectorAll('div.button[onclick*="seqNo="]');
        var table = items.length && items[0].closest("table");
        table = table && table.parentNode && table.parentNode.closest("table");
        while (table) {
          var containsAll = true;
          for (var j = 0; j < items.length; j += 1) {
            if (!table.contains(items[j])) {
              containsAll = false;
              break;
            }
          }
          if (containsAll) break;
          table = table.parentNode && table.parentNode.closest("table");
        }
        if (table && table.parentNode) {
          return { document: doc, table, items };
        }
      }
      return null;
    }
    function absoluteCampusUrl(url, doc) {
      var value = String(url || "").trim();
      if (!value || value.charAt(0) === "#") {
        return "";
      }
      var bases = [];
      try {
        bases.push(doc && doc.baseURI);
      } catch (e) {
      }
      try {
        bases.push(doc && doc.location && doc.location.href);
      } catch (e) {
      }
      bases.push("https://gakujo.iess.niigata-u.ac.jp/campusweb/");
      var parsed;
      for (var i = 0; i < bases.length; i += 1) {
        if (!bases[i]) {
          continue;
        }
        try {
          parsed = new URL(value, bases[i]);
          break;
        } catch (e) {
        }
      }
      if (!parsed || parsed.protocol !== "https:" || parsed.hostname !== "gakujo.iess.niigata-u.ac.jp" || parsed.port !== "" && parsed.port !== "443" || parsed.username !== "" || parsed.password !== "") {
        return "";
      }
      return parsed.href;
    }
    function unreadUrls(limit) {
      var doc = mainFrameDocument();
      var table = messageTable(doc);
      if (!table) {
        var list = smartphoneUnreadList();
        var mobileUrls = [];
        if (list) {
          for (var m = 0; m < list.items.length && mobileUrls.length < limit; m += 1) {
            var item = list.items[m];
            var match = String(item.getAttribute("onclick") || "").match(/\blocation\.href\s*=\s*(['"])(.*?)\1/);
            var mobileUrl = match && absoluteCampusUrl(
              match[2].replace(/&amp;/g, "&"),
              item.ownerDocument || list.document
            );
            if (mobileUrl) mobileUrls.push(mobileUrl);
          }
        }
        return mobileUrls;
      }
      var owningDocument = table.ownerDocument || doc;
      var urls = [];
      for (var i = 1; i < table.rows.length && urls.length < limit; i += 1) {
        var link = table.rows[i].querySelector("a[href]");
        if (link) {
          var url = absoluteCampusUrl(link.getAttribute("href"), owningDocument);
          if (url) {
            urls.push(url);
          }
        }
      }
      return urls;
    }
    function inputValue() {
      var input = controlsDocument.getElementById("mbg-read-num-input");
      var value = input ? Number(input.value) : 0;
      return isFinite(value) && value > 0 ? Math.floor(value) : 0;
    }
    function markReadWithFrame(url) {
      return new Promise(function(resolve) {
        var frame = document.createElement("iframe");
        var settled = false;
        var timeoutId;
        function finish(success) {
          if (settled) {
            return;
          }
          settled = true;
          cancelPendingFrame = null;
          window.clearTimeout(timeoutId);
          frame.remove();
          resolve(success);
        }
        frame.setAttribute("data-mbg-message-reader-owned", "true");
        cancelPendingFrame = function() {
          finish(false);
        };
        frame.style.display = "none";
        frame.onload = function() {
          var html = "";
          try {
            html = frame.contentDocument.documentElement.outerHTML;
          } catch (e) {
            html = "";
          }
          finish(!isSessionLostPage(html));
        };
        frame.onerror = function() {
          finish(false);
        };
        timeoutId = window.setTimeout(function() {
          finish(false);
        }, 5e3);
        frame.src = url;
        document.body.appendChild(frame);
      });
    }
    function isSessionLostPage(text) {
      return /ページの有効期限|有効期限が過ぎています|type=["']?password|name=["']?password/i.test(String(text || ""));
    }
    async function markRead(url) {
      var controller = typeof AbortController === "function" ? new AbortController() : null;
      var timeoutId;
      try {
        return await Promise.race([
          (async function() {
            var response = await fetch(url, {
              credentials: "include",
              signal: controller ? controller.signal : void 0
            });
            if (response.ok) {
              return !isSessionLostPage(await response.text());
            }
            return false;
          })(),
          new Promise(function(resolve) {
            timeoutId = window.setTimeout(function() {
              resolve(false);
              if (controller) controller.abort();
            }, 15e3);
          })
        ]);
      } catch (e) {
      } finally {
        window.clearTimeout(timeoutId);
      }
      if (disposed) {
        return false;
      }
      try {
        return await markReadWithFrame(url);
      } catch (e) {
        return false;
      }
    }
    function statusElement(target) {
      var status = controlsDocument.getElementById("mbg-read-status");
      if (status) {
        return status;
      }
      target = target || controlsDocument.getElementById("tabmenutable");
      if (!target) {
        return null;
      }
      status = controlsDocument.createElement("span");
      status.id = "mbg-read-status";
      status.setAttribute("data-mbg-message-reader-owned", "true");
      status.setAttribute("aria-live", "polite");
      target.appendChild(status);
      return status;
    }
    function showStatus(successCount, failureCount) {
      var status = statusElement();
      if (status) {
        status.textContent = successCount + "件を既読にしました（失敗" + failureCount + "件）";
      }
    }
    var confirmTimer = null;
    var confirmCount = null;
    function disarm(button) {
      window.clearTimeout(confirmTimer);
      confirmTimer = null;
      confirmCount = null;
      if (button) {
        button.textContent = "指定した個数を既読にする";
      }
    }
    async function readerCall() {
      if (disposed || reading || reloadTimeout) {
        return;
      }
      var urls = unreadUrls(inputValue());
      if (!urls.length) {
        return;
      }
      var confirmButton = controlsDocument.getElementById("mbg-read-button");
      if (!confirmTimer || confirmCount !== urls.length) {
        disarm(confirmButton);
        confirmCount = urls.length;
        if (confirmButton) {
          confirmButton.textContent = urls.length + "件を既読にする（もう一度押して確定）";
        }
        confirmTimer = window.setTimeout(function() {
          disarm(controlsDocument.getElementById("mbg-read-button"));
        }, 5e3);
        return;
      }
      disarm(confirmButton);
      reading = true;
      var button = controlsDocument.getElementById("mbg-read-button");
      if (button) {
        button.disabled = true;
      }
      var successCount = 0;
      var failureCount = 0;
      try {
        for (var i = 0; i < urls.length && !disposed; i += 1) {
          if (await markRead(urls[i])) {
            successCount += 1;
          } else {
            failureCount += 1;
          }
        }
        if (disposed) {
          return;
        }
        showStatus(successCount, failureCount);
        if (failureCount > 0) {
          return;
        }
        reloadTimeout = window.setTimeout(function() {
          reloadTimeout = null;
          if (!disposed) {
            location.reload();
          }
        }, 1e3);
      } finally {
        reading = false;
        if (button && !disposed && !reloadTimeout) {
          button.disabled = false;
        }
      }
    }
    function addControls() {
      if (disposed) {
        return false;
      }
      var table = messageTable();
      var list = table ? null : smartphoneUnreadList();
      if (!table && !list) {
        return false;
      }
      controlsDocument = list ? list.document : document;
      var target = controlsDocument.getElementById(
        list ? "mbg-read-controls" : "tabmenutable"
      );
      if (list && !target) {
        target = controlsDocument.createElement("div");
        target.id = "mbg-read-controls";
        target.setAttribute("data-mbg-message-reader-owned", "true");
        list.table.parentNode.insertBefore(target, list.table);
      }
      if (!target) {
        return false;
      }
      if (!controlsDocument.getElementById("mbg-read-button")) {
        var button = controlsDocument.createElement("button");
        button.id = "mbg-read-button";
        button.type = "button";
        button.setAttribute("data-mbg-message-reader-owned", "true");
        button.textContent = "指定した個数を既読にする";
        button.addEventListener("click", readerCall);
        target.appendChild(button);
      }
      if (!controlsDocument.getElementById("mbg-read-num-input")) {
        var input = controlsDocument.createElement("input");
        input.id = "mbg-read-num-input";
        input.type = "number";
        input.setAttribute("data-mbg-message-reader-owned", "true");
        input.defaultValue = "5";
        input.pattern = "\\d*";
        input.placeholder = "既読にする数(半角数字)";
        target.appendChild(input);
      }
      statusElement(target);
      return true;
    }
    window.__MBG_MESSAGE_READER_UPDATE = addControls;
    addControls();
    window.clearInterval(window.__MBG_MESSAGE_READER_INTERVAL);
    if (window.__MBG_MESSAGE_READER_WATCH_DISPOSE) window.__MBG_MESSAGE_READER_WATCH_DISPOSE();
    window.__MBG_MESSAGE_READER_WATCH_DISPOSE = watchPage(window, addControls, { fallbackMs: 5e3, legacyIntervalMs: 500 });
  }
  messageReader();
})();
''';
