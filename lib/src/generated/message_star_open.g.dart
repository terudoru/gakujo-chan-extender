// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/message_star/open.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoMessageStarOpenJs(Map<String, Object?> config) =>
    _gakujoMessageStarOpenJsPrefix +
    jsonEncode(config) +
    _gakujoMessageStarOpenJsSuffix;

const String _gakujoMessageStarOpenJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
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
  function nextMessageListPage(doc, base) {
    var controls = doc.querySelectorAll('a,button,input[type="button"],input[type="submit"]');
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = String(control.textContent || control.value || "") + " " + (control.getAttribute("aria-label") || control.getAttribute("title") || "");
      if (!/次へ|次のページ|次ページ|next/i.test(label) && control.getAttribute("rel") !== "next" || control.disabled || control.getAttribute("aria-disabled") === "true") continue;
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
    return "";
  }

  // web_scripts/src/message_star/open.ts
  function messageStarOpen() {
    var message = __mbgConfig.message;
    var base = location.origin + "/campusweb/";
    function result(status, url2) {
      return JSON.stringify({ status, url: url2 });
    }
    function get(url2) {
      var xhr = new XMLHttpRequest();
      xhr.open("GET", url2, false);
      xhr.send(null);
      if (xhr.status < 200 || xhr.status >= 400) throw new Error("http");
      var doc2 = new DOMParser().parseFromString(xhr.responseText, "text/html");
      var body = String(doc2.body && (doc2.body.innerText || doc2.body.textContent) || "");
      if (/実行権限エラー|SYSTEM ERROR/.test(String(doc2.title)) || /^\s*(実行権限エラー|SYSTEM ERROR)/.test(body)) throw new Error("system");
      if (String(doc2.title || "").indexOf("連絡通知") < 0 && body.indexOf("連絡通知") < 0) throw new Error("missing");
      return doc2;
    }
    function url(flowKey, event) {
      if (!flowKey) throw new Error("key");
      return base + "campussquare.do?_flowExecutionKey=" + encodeURIComponent(flowKey) + "&_eventId=" + event;
    }
    try {
      if (location.origin !== "https://gakujo.iess.niigata-u.ac.jp") return result("missing");
      for (var name of ["keijitype", "genrecd", "seqNo"]) {
        if (!/^[0-9]+$/.test(message[name])) return result("error");
      }
      var genre = "&keijitype=" + encodeURIComponent(message.keijitype) + "&genrecd=" + encodeURIComponent(message.genrecd);
      var doc = get(base + "campussquare.do?_flowId=KJW0001100-flow");
      doc = get(url(messageListFlowKey(doc, base), "dispKeijiListGenre") + genre);
      doc = get(url(messageListFlowKey(doc, base), "paging") + "&_displayCount=500");
      var found;
      var seenPages = /* @__PURE__ */ new Set();
      for (var page = 0; page < 20; page += 1) {
        var links = Array.from(doc.querySelectorAll('a[href*="seqNo="]')).concat(
          Array.from(doc.querySelectorAll('[onclick*="seqNo="]'))
        );
        var identities = [];
        for (var i = 0; i < links.length; i += 1) {
          var href = links[i].getAttribute("href") || messageOnclickUrl(links[i]);
          if (!href) continue;
          var params = new URL(href, base).searchParams;
          identities.push([params.get("keijitype"), params.get("genrecd"), params.get("seqNo")]);
          if (params.get("seqNo") === message.seqNo && params.get("keijitype") === message.keijitype && params.get("genrecd") === message.genrecd) {
            found = links[i];
            break;
          }
        }
        if (found) break;
        var next = nextMessageListPage(doc, base);
        if (!next) return result("gone");
        var signature = JSON.stringify(identities);
        if (seenPages.has(signature) || page === 19) return result("error");
        seenPages.add(signature);
        doc = get(next);
      }
      if (!found) return result("gone");
      var targetUrl = url(messageListFlowKey(doc, base), "confirm") + genre + "&seqNo=" + encodeURIComponent(message.seqNo);
      if (found.getAttribute("onclick") && found.querySelector) found = found.querySelector("p") || found;
      message.title = String(found.innerText || found.textContent || "").replace(/\s+/g, " ").trim().replace(/\s*\[新着\]\s*$/, "");
      try {
        window.top.sessionStorage.setItem("__MBG_MESSAGE_STARS_OPEN_MESSAGE", JSON.stringify(message));
      } catch (e) {
      }
      return result("ok", targetUrl);
    } catch (e) {
      return result(e.message === "missing" ? "missing" : "error");
    }
  }
  __mbgEntryResult = messageStarOpen();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoMessageStarOpenJsSuffix = r''')
''';
