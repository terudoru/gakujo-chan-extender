// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/page_text_activity/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoPageTextActivityJs = r'''
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

  // web_scripts/src/shared/assignment_rows.ts
  function readAssignmentRows(doc) {
    function text(node) {
      return String(node && (node.innerText || node.textContent) || "").replace(/\s+/g, " ").trim();
    }
    var rows = [];
    var table = doc.querySelector("#enqListForm table:nth-of-type(2)");
    if (table && table.rows) {
      for (var i = 1; i < table.rows.length; i += 1) {
        var cells = table.rows[i].cells;
        if (!cells || cells.length < 8 || !text(cells[1]) || !text(cells[7])) {
          continue;
        }
        rows.push({
          kind: text(cells[0]),
          title: text(cells[1]),
          status: text(cells[2]),
          code: text(cells[3]),
          course: text(cells[4]),
          period: text(cells[7])
        });
      }
    }
    var groups = doc.querySelectorAll("#enqListForm ul.campussmart-list");
    for (var g = 0; g < groups.length; g += 1) {
      var kind = text(groups[g].querySelector("li.header"));
      var titles = groups[g].querySelectorAll("span.h3");
      for (var t = 0; t < titles.length; t += 1) {
        var block = titles[t].closest("td") || titles[t].parentElement;
        var all = text(block);
        var beforePeriod = all.split("実施期間")[0];
        var courses = beforePeriod.match(/\([^()]* \/ [^()]*\)/g) || [];
        var course = courses.length ? courses[courses.length - 1].slice(1, -1) : (beforePeriod.match(/\(([^()]*)\)\s*$/) || [])[1] || "";
        var period = (all.match(/実施期間[：:]\s*(.+?)\s*(?:状態|$)/) || [])[1] || "";
        var row = titles[t].closest("tr") || block;
        var action = row.querySelector('[onclick*="callEnqInfoSearch"]');
        var code = (String(action && action.getAttribute("onclick") || "").match(/'([0-9]{3}[A-Z][0-9]{4})'\s*\)/) || [])[1] || "";
        if (!text(titles[t]) || !period) {
          continue;
        }
        rows.push({
          kind,
          title: text(titles[t]),
          status: (all.match(/状態[：:]\s*(\S+)/) || [])[1] || "",
          code,
          course: course.split(" / ")[0].trim(),
          period
        });
      }
    }
    return rows;
  }

  // web_scripts/src/page_text_activity/main.ts
  function pageTextActivity() {
    var texts = [];
    var messageItems = [];
    var reportItems = [];
    var seenMessageItems = {};
    var datePattern = /((?:令和[0-9]{1,2}年|(?:20)?[0-9]{2}(?:[\/.\-]|年))[0-9]{1,2}(?:[\/.\-]|月)[0-9]{1,2}日?(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?|[0-9]{1,2}[\/.][0-9]{1,2}(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?|[0-9]{1,2}月[0-9]{1,2}日(?:\s*[（(]?[月火水木金土日]?[）)]?)?(?:\s*[0-9]{1,2}:[0-9]{2})?)/;
    function compactText(element) {
      return (element && (element.innerText || element.textContent || element.value) || "").replace(/\s+/g, " ").trim();
    }
    function compactRawText(text) {
      return String(text || "").replace(/\s+/g, " ").trim();
    }
    function normalizeDateText(text) {
      return String(text || "").replace(/[０-９]/g, function(ch) {
        return String.fromCharCode(ch.charCodeAt(0) - 65248);
      }).replace(/：/g, ":").replace(/／/g, "/").replace(/．/g, ".").replace(/[－−]/g, "-");
    }
    function isPortalNoiseText(text) {
      var normalized = normalizeDateText(compactRawText(text));
      if (!normalized) {
        return true;
      }
      if (normalized.indexOf("MYスケジュール") >= 0 || normalized.indexOf("前回ログイン日時") >= 0 || normalized.indexOf("ログアウト") >= 0 || normalized.indexOf("残り約") >= 0 || /^Copyright/.test(normalized)) {
        return true;
      }
      if (/^[0-9]{4}\/[0-9]{1,2}\/[0-9]{1,2}\([A-Za-z]+\)$/.test(normalized)) {
        return true;
      }
      if (/^[0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日\s*[0-9]{1,2}時[0-9]{1,2}分\s*(から|まで)?$/.test(normalized)) {
        return true;
      }
      return false;
    }
    function hasDate(text) {
      return datePattern.test(normalizeDateText(text));
    }
    function messageTable(doc) {
      var direct = doc.querySelector("table.normal:nth-child(9)");
      if (direct) {
        return direct;
      }
      var tables = doc.querySelectorAll("table");
      for (var i = 0; i < tables.length; i += 1) {
        var text = compactText(tables[i]);
        if ((text.indexOf("掲示") >= 0 || text.indexOf("連絡") >= 0) && tables[i].querySelector("a[href]")) {
          return tables[i];
        }
      }
      return null;
    }
    function messageUrl(doc, node) {
      var link = node && node.closest && node.closest("a[href]");
      if (!link && node && node.querySelector) {
        link = node.querySelector("a[href]");
      }
      var href = link && link.href || "";
      if (href && !/^javascript:/i.test(href)) {
        return href;
      }
      try {
        return doc.location.href || document.location.href;
      } catch (e) {
        return document.location.href;
      }
    }
    function messageTitle(node, text) {
      var link = node && node.querySelector && node.querySelector("a, button:not([data-mbg-message-star]), input");
      var label = compactText(link || node);
      if (!label || label.length > 120) {
        label = text.split(/(?:\s{2,}| \/ |\n)/)[0] || text;
      }
      return label.length > 120 ? label.substring(0, 120) + "..." : label;
    }
    function addMessageData(doc, title, url, text) {
      text = compactRawText(text);
      title = compactRawText(title);
      if (text.length < 6 || isPortalNoiseText(text) || !hasDate(text)) {
        return;
      }
      if (!title || title.length > 120) {
        title = text.split(/(?:\s{2,}| \/ |\n)/)[0] || text;
      }
      if (title.length > 120) {
        title = title.substring(0, 120) + "...";
      }
      url = url || doc.location.href || document.location.href;
      var key = title + "|" + url + "|" + text;
      if (seenMessageItems[key]) {
        return;
      }
      seenMessageItems[key] = true;
      messageItems.push({
        title,
        url,
        text
      });
    }
    function addMessageItem(doc, node) {
      var text = compactText(node);
      addMessageData(doc, messageTitle(node, text), messageUrl(doc, node), text);
    }
    function collectNoticeDetail(doc) {
      var raw = doc.body && (doc.body.innerText || doc.body.textContent) || "";
      if (!raw || raw.indexOf("連絡通知元") < 0) {
        return false;
      }
      var lines = raw.split(/\r?\n/).map(function(line) {
        return line.replace(/\s+/g, " ").trim();
      }).filter(Boolean);
      var start = -1;
      for (var i = 0; i < lines.length; i += 1) {
        if (lines[i] === "連絡通知") {
          start = i + 1;
          break;
        }
      }
      if (start < 0) {
        start = 0;
      }
      while (start < lines.length && (lines[start] === "[image]" || lines[start] === "連絡通知" || lines[start].indexOf("指定した個数を既読") >= 0)) {
        start += 1;
      }
      if (start >= lines.length) {
        return false;
      }
      var end = lines.findIndex(function(line, index) {
        return index > start && (line === "連絡通知元" || line === "連絡通知期間" || line === "メール送信" || line === "送信日時" || line === "対象学生所属");
      });
      if (end < 0) {
        end = lines.length;
      }
      var title = lines[start].replace(/\s*\[[^\]]+\]\s*$/g, "").trim();
      var body = lines.slice(start, end).join(" ");
      if (!hasDate(body)) {
        return false;
      }
      addMessageData(doc, title, doc.location.href, body);
      return true;
    }
    function collectMessageItems(doc) {
      try {
        var mobile = doc.querySelectorAll('div.button[onclick*="seqNo="]');
        if (mobile.length && compactText(doc.body).indexOf("連絡通知") >= 0) {
          for (var m = 0; m < mobile.length; m += 1) {
            var item = readSmartphoneMessageRow(mobile[m], doc.baseURI || doc.location.href);
            if (item) addMessageData(doc, item.title, item.url, item.text);
          }
          return;
        }
        if (collectNoticeDetail(doc)) {
          return;
        }
        var table = messageTable(doc);
        var candidates = table ? table.querySelectorAll("tr") : doc.querySelectorAll("tr, li, a, button:not([data-mbg-message-star])");
        for (var i = 0; i < candidates.length; i += 1) {
          addMessageItem(doc, candidates[i]);
        }
      } catch (e) {
      }
    }
    function collectReportRows(doc) {
      var rows = [];
      try {
        var items = readAssignmentRows(doc);
        for (var i = 0; i < items.length; i += 1) {
          var item = items[i];
          reportItems.push(item);
          rows.push(
            "レポート課題: " + item.title + (item.code ? " / 開講番号: " + item.code : "") + (item.status ? " / 状態: " + item.status : "") + " / 提出期間: " + item.period
          );
        }
      } catch (e) {
      }
      return rows;
    }
    function collect(win) {
      try {
        if (win.document && win.document.body) {
          texts.push(win.document.body.innerText || "");
          collectMessageItems(win.document);
          var reportRows = collectReportRows(win.document);
          if (reportRows.length) {
            texts.push(reportRows.join("\n"));
          }
        }
        for (var i = 0; i < win.frames.length; i += 1) {
          collect(win.frames[i]);
        }
      } catch (e) {
      }
    }
    collect(window);
    return JSON.stringify({
      title: document.title || "",
      text: texts.join("\n"),
      messageItems,
      reportItems
    });
  }
  __mbgEntryResult = pageTextActivity();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
