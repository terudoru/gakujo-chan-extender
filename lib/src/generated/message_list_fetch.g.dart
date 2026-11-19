// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/message_list_fetch/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoMessageListFetchJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/shared/smartphone_message_rows.ts
  function messageOnclickUrl(node) {
    var match = String(node && node.getAttribute("onclick") || "").match(/\blocation\.href\s*=\s*(['"])(.*?)\1/);
    return match ? match[2].replace(/&amp;/g, "&") : "";
  }
  function readSmartphoneMessageRow(button, base) {
    function text(node2) {
      return String(node2 && (node2.innerText || node2.textContent) || "").replace(/\s+/g, " ").trim();
    }
    var heading = button.querySelector("p");
    var href = messageOnclickUrl(button);
    if (!heading || !text(heading) || !href) return null;
    var row = button.closest("tr");
    var table = button.closest("table.bgnone");
    var dateCell = row && row.cells && row.cells[0];
    var dateRows = dateCell ? dateCell.querySelectorAll("tr") : [];
    var month = text(dateRows[0]).match(/([0-9]{4})\s*\/\s*([0-9]{1,2})/);
    var day = text(dateCell && dateCell.querySelector("b")).match(/^[0-9]{1,2}$/);
    var time = text(dateRows[1]).match(/[0-9]{1,2}:[0-9]{2}:[0-9]{2}/);
    var postedAt = month && day && time ? month[1] + "/" + month[2].padStart(2, "0") + "/" + day[0].padStart(2, "0") + " " + time[0] : "";
    var genre = text(table && table.querySelector("td.category-frame"));
    var sender = "";
    for (var node = heading.nextSibling; node; node = node.nextSibling) {
      if (node.nodeName === "BR") break;
      sender += node.textContent || "";
    }
    sender = sender.replace(/\s+/g, " ").trim();
    var period = (text(button).match(/掲示期間[：:]\s*(.*)/) || [])[1] || "";
    period = period.replace(/\s*[～〜~]\s*/, "から ") + (period ? "まで" : "");
    var label = text(heading);
    return {
      title: label,
      url: new URL(href, base).href,
      text: [postedAt, label, "-", genre, sender, period].filter(Boolean).join(" "),
      genre,
      sender,
      period,
      postedAt
    };
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
  function nextMessageListPage(doc, base) {
    var controls = doc.querySelectorAll('a,button,input[type="button"],input[type="submit"]');
    var hasNextControl = false;
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = String(control.textContent || control.value || "") + " " + (control.getAttribute("aria-label") || control.getAttribute("title") || "");
      if (!/次へ|次のページ|次ページ|next/i.test(label) && control.getAttribute("rel") !== "next" || control.disabled || control.getAttribute("aria-disabled") === "true") continue;
      hasNextControl = true;
      var href = control.getAttribute("href") || "";
      if (!href || /^(?:javascript:|#)/i.test(href)) {
        href = messageOnclickUrl(control) || ((control.getAttribute("onclick") || href).match(
          /['"]([^'"]*[?&](?:_eventId=paging|_displayOffset=)[^'"]*)['"]/
        ) || [])[1];
      }
      if (!href) continue;
      var target = new URL(href.replace(/&amp;/g, "&"), base + "campussquare.do");
      if (target.origin !== new URL(base).origin || target.pathname !== "/campusweb/campussquare.do" || target.searchParams.get("_eventId") !== "paging" && !target.searchParams.has("_displayOffset")) continue;
      const flowKey = messageListFlowKey(doc, base);
      if (!flowKey || target.searchParams.has("seqNo") || target.username || target.password) continue;
      target.searchParams.set("_flowExecutionKey", flowKey);
      target.searchParams.set("_eventId", "paging");
      return target.href;
    }
    return hasNextControl ? null : "";
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

  // web_scripts/src/message_list_fetch/main.ts
  function messageListFetch() {
    var expanded = typeof __mbgExpandMessageList !== "undefined" && __mbgExpandMessageList;
    var complete = false;
    function result(status, items2) {
      return JSON.stringify(expanded ? { status, items: items2, complete } : { status, items: items2 });
    }
    function text(node) {
      return String(node && (node.innerText || node.textContent) || "").replace(/\s+/g, " ").trim();
    }
    function fetchList(url) {
      var xhr = new XMLHttpRequest();
      xhr.open("GET", url, false);
      xhr.send(null);
      if (xhr.status < 200 || xhr.status >= 400) throw new Error("http");
      var doc = new DOMParser().parseFromString(xhr.responseText, "text/html");
      var mobile = doc.querySelectorAll('div.button[onclick*="seqNo="]');
      var smartphone = mobile.length > 0 && text(doc.body).indexOf("連絡通知") >= 0;
      if (String(doc.title || "").indexOf("連絡通知") < 0 && !smartphone) return null;
      return { doc, mobile, smartphone };
    }
    try {
      let add2 = function(item2) {
        if (expanded) {
          var params = new URL(item2.url).searchParams;
          var identity = JSON.stringify([params.get("keijitype"), params.get("genrecd"), params.get("seqNo")]);
          if (params.has("seqNo") && seen.has(identity)) return;
          seen.add(identity);
        }
        items.push({ title: item2.title, url: item2.url, text: item2.text });
      };
      var add = add2;
      var base = location.origin + "/campusweb/";
      var page = fetchList("/campusweb/campussquare.do?_flowId=KJW0001100-flow");
      if (!page) return result("missing", []);
      var items = [];
      var seen = /* @__PURE__ */ new Set();
      var limit = expanded ? 500 : 60;
      var partial = false;
      for (var index = 0; page && index < 4; index += 1) {
        var previousCount = items.length;
        if (page.smartphone) {
          for (var m = 0; m < page.mobile.length && items.length < limit; m += 1) {
            var item = readSmartphoneMessageRow(page.mobile[m], base);
            if (item) add2(item);
          }
        } else {
          var rows = page.doc.querySelectorAll("tr");
          for (var i = 0; i < rows.length && items.length < limit; i += 1) {
            var cells = rows[i].cells;
            var link = rows[i].querySelector("a[href]");
            if (!cells || cells.length < 3 || !link || rows[i].querySelector("tr") || !/^[0-9]{4}\/[0-9]{1,2}\/[0-9]{1,2}/.test(text(cells[0]))) continue;
            add2({
              title: text(link),
              url: new URL(link.getAttribute("href"), base).href,
              // In a detached document, textContent does not separate cells.
              text: expanded ? Array.from(cells, text).filter(Boolean).join(" ") : text(rows[i])
            });
          }
        }
        if (!expanded || items.length >= limit || index === 3 || location.origin !== "https://gakujo.iess.niigata-u.ac.jp") break;
        if (items.length === previousCount && index > 0) break;
        try {
          var larger = index === 0 ? largerMessageListPage(page.doc, base) : null;
          var next = (larger == null ? void 0 : larger.url) || nextMessageListPage(page.doc, base);
          if (!next) {
            complete = next === "";
            break;
          }
          page = fetchList(next);
          if (!page) partial = true;
        } catch (_) {
          partial = true;
          break;
        }
      }
      return result(partial ? "partial" : "ok", items);
    } catch (e) {
      return result("error", []);
    }
  }
  __mbgEntryResult = messageListFetch();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
