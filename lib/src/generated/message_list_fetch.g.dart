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

  // web_scripts/src/message_list_fetch/main.ts
  function messageListFetch() {
    function text(node) {
      return String(node && (node.innerText || node.textContent) || "").replace(/\s+/g, " ").trim();
    }
    try {
      var xhr = new XMLHttpRequest();
      xhr.open("GET", "/campusweb/campussquare.do?_flowId=KJW0001100-flow", false);
      xhr.send(null);
      if (xhr.status < 200 || xhr.status >= 400) {
        return JSON.stringify({ status: "error", items: [] });
      }
      var doc = new DOMParser().parseFromString(xhr.responseText, "text/html");
      var mobile = doc.querySelectorAll('div.button[onclick*="seqNo="]');
      var smartphone = mobile.length > 0 && text(doc.body).indexOf("連絡通知") >= 0;
      if (String(doc.title || "").indexOf("連絡通知") < 0 && !smartphone) {
        return JSON.stringify({ status: "missing", items: [] });
      }
      var base = location.origin + "/campusweb/";
      var items = [];
      if (smartphone) {
        for (var m = 0; m < mobile.length && items.length < 60; m += 1) {
          var item = readSmartphoneMessageRow(mobile[m], base);
          if (item) items.push({ title: item.title, url: item.url, text: item.text });
        }
        return JSON.stringify({ status: "ok", items });
      }
      var rows = doc.querySelectorAll("tr");
      for (var i = 0; i < rows.length && items.length < 60; i += 1) {
        var cells = rows[i].cells;
        var link = rows[i].querySelector("a[href]");
        if (!cells || cells.length < 3 || !link || rows[i].querySelector("tr") || !/^[0-9]{4}\/[0-9]{1,2}\/[0-9]{1,2}/.test(text(cells[0]))) {
          continue;
        }
        items.push({
          title: text(link),
          url: new URL(link.getAttribute("href"), base).href,
          text: text(rows[i])
        });
      }
      return JSON.stringify({ status: "ok", items });
    } catch (e) {
      return JSON.stringify({ status: "error", items: [] });
    }
  }
  __mbgEntryResult = messageListFetch();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
