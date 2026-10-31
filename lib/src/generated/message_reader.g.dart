// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/message_reader/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoMessageReaderJs = r'''
"use strict";
(() => {
  // web_scripts/src/message_reader/main.ts
  function messageReader() {
    var version = 7;
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
    window.__MBG_MESSAGE_READER_INTERVAL = window.setInterval(addControls, 500);
  }
  messageReader();
})();
''';
