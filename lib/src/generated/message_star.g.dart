// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/message_star/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoMessageStarJs(Map<String, Object?> config) =>
    _gakujoMessageStarJsPrefix +
    jsonEncode(config) +
    _gakujoMessageStarJsSuffix;

const String _gakujoMessageStarJsPrefix = r'''(function(__mbgConfig) {
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

  // web_scripts/src/message_star/main.ts
  function messageStar() {
    var initialIds = __mbgConfig.initialIds;
    var version = 7;
    if (window.__MBG_MESSAGE_STARS_VERSION === version) {
      window.__MBG_MESSAGE_STARS_REFRESH(initialIds);
      return;
    }
    if (window.__MBG_MESSAGE_STARS_DISPOSE) window.__MBG_MESSAGE_STARS_DISPOSE();
    window.__MBG_MESSAGE_STARS_VERSION = version;
    var disposed = false;
    var ids = new Set(initialIds);
    var buttons = [];
    var buttonTargets = /* @__PURE__ */ new WeakSet();
    var styles = [];
    var lastDetailSignatures = /* @__PURE__ */ new WeakMap();
    var listDocuments = [];
    var openedMessageKey = "__MBG_MESSAGE_STARS_OPEN_MESSAGE";
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
    function text(node) {
      return String(node && (node.innerText || node.textContent) || "").replace(/\s+/g, " ").trim();
    }
    function title(node) {
      return text(node).replace(/\s*\[新着\]\s*$/, "");
    }
    function remember(data) {
      try {
        window.top.sessionStorage.setItem(openedMessageKey, JSON.stringify({
          keijitype: data.keijitype,
          genrecd: data.genrecd,
          seqNo: data.seqNo,
          title: data.title
        }));
      } catch (e) {
      }
    }
    function identity(href, doc) {
      try {
        var url = new URL(href, doc.baseURI || "https://gakujo.iess.niigata-u.ac.jp/campusweb/");
        var result = {};
        for (var key of ["keijitype", "genrecd", "seqNo"]) {
          var value = url.searchParams.get(key) || "";
          if (!/^[0-9]+$/.test(value)) return null;
          result[key] = value;
        }
        return result;
      } catch (e) {
        return null;
      }
    }
    function id(data) {
      return data.keijitype + "|" + data.genrecd + "|" + data.seqNo;
    }
    function send(action, data) {
      if (disposed) return;
      var channel = window.GakujoMessageStars;
      if (channel && channel.postMessage) {
        channel.postMessage(JSON.stringify(Object.assign({ action }, data)));
      }
    }
    function paint(entry, message) {
      var source = entry.target.getAttribute("href") || entry.target.getAttribute("onclick") || "";
      if (source) source += "\n" + title(entry.target);
      if (message === void 0 && (!source || source !== entry.source)) message = entry.data();
      if (message !== void 0) {
        entry.source = source;
        entry.id = message ? id(message) : null;
        entry.button.disabled = !message;
        var label = "スター: " + (message ? message.title : title(entry.target));
        entry.button.setAttribute("aria-label", label);
        entry.button.title = label;
      }
      var starred = ids.has(entry.id);
      entry.button.setAttribute("aria-pressed", String(starred));
    }
    function ensureStyle(doc) {
      if (doc.getElementById("mbg-message-star-style")) return;
      var style = doc.createElement("style");
      style.id = "mbg-message-star-style";
      style.textContent = 'button[data-mbg-message-star]::before { content: "☆"; }button[data-mbg-message-star][aria-pressed="true"]::before { content: "★"; }';
      (doc.head || doc.documentElement).appendChild(style);
      styles.push(style);
    }
    function addButton(target, data, doc, initialData, inside) {
      if (buttonTargets.has(target)) return;
      ensureStyle(doc);
      var message = initialData || data();
      var label = "スター: " + message.title;
      var button = doc.createElement("button");
      button.type = "button";
      button.setAttribute("data-mbg-message-star", "true");
      button.setAttribute("aria-label", label);
      button.title = label;
      button.style.cssText = "font:inherit;font-size:18px;line-height:1.2;padding:2px 5px;margin-right:4px;cursor:pointer;";
      button.addEventListener("click", function(event) {
        event.preventDefault();
        event.stopPropagation();
        if (disposed) return;
        var message2 = data();
        paint(entry, message2);
        if (message2) send("toggle", message2);
      });
      if (inside) target.insertBefore(button, target.firstChild);
      else target.parentNode.insertBefore(button, target);
      var entry = { button, target, data };
      buttons.push(entry);
      buttonTargets.add(target);
      paint(entry, message);
    }
    function rowData(link, doc, headersByTable) {
      var data = identity(link.getAttribute("href"), doc);
      var row = link.closest("tr");
      if (!data || !row || !row.cells) return null;
      var cells = row.cells;
      var table = row.closest("table");
      var headers = [];
      if (table) {
        headers = headersByTable && headersByTable.get(table);
        if (!headers) {
          headers = Array.from(table.querySelectorAll("th")).map(text);
          if (headersByTable) headersByTable.set(table, headers);
        }
      }
      function field(label) {
        var index = headers.indexOf(label);
        return index >= 0 ? text(cells[index]) : "";
      }
      data.genre = field("ジャンル");
      data.sender = [field("所属"), field("氏名") || field("担当者")].filter(Boolean).join(" ／ ");
      data.period = field("連絡通知期間");
      data.postedAt = field("掲載日時");
      data.title = title(link);
      data.body = "";
      return data;
    }
    function rememberClickedMessage(event) {
      var link = event.target && event.target.closest && event.target.closest('a[href*="seqNo="]');
      var mobile = !link && event.target && event.target.closest && event.target.closest('div.button[onclick*="seqNo="]');
      if (mobile) link = mobile;
      if (!link) return;
      var doc = link.ownerDocument;
      var href = mobile ? messageOnclickUrl(link) : link.getAttribute("href");
      if (!href) return;
      var params = new URL(href, doc.baseURI).searchParams;
      if (params.get("_eventId") !== "displayMidoku" && params.get("_eventId") !== "confirm") return;
      var data = identity(href, doc);
      if (data) {
        data.title = title(mobile ? link.querySelector("p") : link);
        remember(data);
      }
    }
    function smartphoneRowData(button, doc) {
      var data = identity(messageOnclickUrl(button), doc);
      if (!data) return null;
      var row = readSmartphoneMessageRow(button, doc.baseURI);
      if (!row) return null;
      data.title = title(button.querySelector("p"));
      data.genre = row.genre;
      data.sender = row.sender;
      data.period = row.period;
      data.postedAt = row.postedAt;
      data.body = "";
      return data;
    }
    function smartphoneDetailFields(doc) {
      var fields = {};
      var headers = doc.querySelectorAll("#main-portlet-body ul.campussmart-list li.header");
      for (var i = 0; i < headers.length; i += 1) {
        fields[text(headers[i])] = headers[i].nextElementSibling;
      }
      return fields;
    }
    function detailData(doc, heading, mobileFields) {
      var data = identity(doc.location && doc.location.href || doc.URL || "", doc);
      if (!data) {
        var attachments = doc.querySelectorAll('a[href*="_eventId=download"]');
        for (var i = 0; i < attachments.length && !data; i += 1) {
          data = identity(attachments[i].getAttribute("href"), doc);
        }
      }
      if (!data) {
        try {
          var remembered = JSON.parse(window.top.sessionStorage.getItem(openedMessageKey));
          if (remembered && typeof remembered.title === "string" && title({ textContent: remembered.title }) === title(heading) && ["keijitype", "genrecd", "seqNo"].every(function(key) {
            return typeof remembered[key] === "string" && /^[0-9]+$/.test(remembered[key]);
          })) {
            data = { keijitype: remembered.keijitype, genrecd: remembered.genrecd, seqNo: remembered.seqNo };
          }
        } catch (e) {
        }
      }
      if (!data) return null;
      data.title = title(heading);
      if (mobileFields) {
        data.genre = "";
        var body = mobileFields["内容"];
        data.body = String(body && (body.innerText || body.textContent) || "").trim().slice(0, 4e3);
        data.sender = [text(mobileFields["所属"]), text(mobileFields["氏名"])].filter(Boolean).join(" ／ ");
        data.period = "";
        data.postedAt = text(mobileFields["掲載日時"]);
        return data;
      }
      var genre = text(doc.querySelector("span.keiji-t-genre")).replace(/^\[|\]$/g, "").trim();
      var genres = genre.split(/\s+/);
      data.genre = genres.length === 2 && genres[0] === genres[1] ? genres[0] : genre;
      data.body = String((doc.querySelector("div.keiji-naiyo") || {}).innerText || (doc.querySelector("div.keiji-naiyo") || {}).textContent || "").trim().slice(0, 4e3);
      data.sender = "";
      data.period = "";
      data.postedAt = "";
      var fields = { "連絡通知元": "sender", "連絡通知期間": "period", "送信日時": "postedAt" };
      var tables = doc.querySelectorAll("table.keiji-normal");
      for (var j = 0; j < tables.length; j += 1) {
        var th = tables[j].querySelector("th");
        var field = fields[text(th)];
        var row = th && th.closest("tr");
        var next = row && row.nextElementSibling;
        if (field && next) data[field] = text(next.querySelector("td"));
      }
      return data;
    }
    function updateDocument(doc) {
      var links = doc.querySelectorAll('a[href*="seqNo="]');
      var headersByTable = /* @__PURE__ */ new Map();
      for (var i = 0; i < links.length; i += 1) {
        if (buttonTargets.has(links[i])) continue;
        var event = new URL(links[i].getAttribute("href"), doc.baseURI).searchParams.get("_eventId");
        if (event !== "displayMidoku" && event !== "confirm") continue;
        var data = rowData(links[i], doc, headersByTable);
        if (data) {
          (function(link) {
            addButton(link, function() {
              return rowData(link, doc);
            }, doc, data);
          })(links[i]);
        }
      }
      var mobile = doc.querySelectorAll('div.button[onclick*="seqNo="]');
      for (var m = 0; m < mobile.length; m += 1) {
        if (buttonTargets.has(mobile[m])) continue;
        var href = messageOnclickUrl(mobile[m]);
        if (!href) continue;
        var event = new URL(href, doc.baseURI).searchParams.get("_eventId");
        if (event !== "displayMidoku" && event !== "confirm") continue;
        var data = smartphoneRowData(mobile[m], doc);
        if (data) {
          (function(button) {
            addButton(button, function() {
              return smartphoneRowData(button, doc);
            }, doc, data, true);
          })(mobile[m]);
        }
      }
      var heading = doc.querySelector("span.keiji-title");
      var mobileFields = !heading && smartphoneDetailFields(doc);
      if (mobileFields) heading = mobileFields["表題"];
      var detail = heading && detailData(doc, heading, mobileFields);
      if (detail) {
        addButton(heading, function() {
          return detailData(doc, heading, mobileFields && smartphoneDetailFields(doc));
        }, doc, mobileFields ? detail : null, !!mobileFields);
        var signature = JSON.stringify(detail);
        if (ids.has(id(detail)) && signature !== lastDetailSignatures.get(doc)) {
          lastDetailSignatures.set(doc, signature);
          send("detail", detail);
        }
      }
    }
    function update() {
      if (disposed) return;
      var docs = candidateDocuments();
      listDocuments.forEach(function(doc) {
        if (docs.indexOf(doc) < 0) doc.removeEventListener("click", rememberClickedMessage, true);
      });
      docs.forEach(function(doc) {
        if (listDocuments.indexOf(doc) < 0) doc.addEventListener("click", rememberClickedMessage, true);
      });
      listDocuments = docs;
      styles = styles.filter(function(style) {
        if (docs.indexOf(style.ownerDocument) >= 0) return true;
        style.remove();
        return false;
      });
      buttons = buttons.filter(function(entry) {
        if (docs.indexOf(entry.target.ownerDocument) >= 0 && entry.target.isConnected !== false) return true;
        entry.button.remove();
        buttonTargets.delete(entry.target);
        return false;
      });
      docs.forEach(updateDocument);
      buttons.forEach(function(entry) {
        paint(entry);
      });
    }
    window.__MBG_MESSAGE_STARS_REFRESH = function(nextIds) {
      ids = new Set(nextIds);
      update();
    };
    var timer = window.setInterval(update, 700);
    window.__MBG_MESSAGE_STARS_DISPOSE = function() {
      disposed = true;
      window.clearInterval(timer);
      listDocuments.forEach(function(doc) {
        doc.removeEventListener("click", rememberClickedMessage, true);
      });
      listDocuments = [];
      buttons.forEach(function(entry) {
        entry.button.remove();
      });
      buttons = [];
      buttonTargets = /* @__PURE__ */ new WeakSet();
      styles.forEach(function(style) {
        style.remove();
      });
      styles = [];
      delete window.__MBG_MESSAGE_STARS_VERSION;
      delete window.__MBG_MESSAGE_STARS_REFRESH;
      delete window.__MBG_MESSAGE_STARS_DISPOSE;
    };
    update();
  }
  messageStar();
})();
})(''';
const String _gakujoMessageStarJsSuffix = r''');
''';
