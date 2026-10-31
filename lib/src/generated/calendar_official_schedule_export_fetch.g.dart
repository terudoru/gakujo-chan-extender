// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/calendar_official_schedule_export_fetch/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoCalendarOfficialScheduleExportFetchJs(
  Map<String, Object?> config,
) =>
    _gakujoCalendarOfficialScheduleExportFetchJsPrefix +
    jsonEncode(config) +
    _gakujoCalendarOfficialScheduleExportFetchJsSuffix;

const String _gakujoCalendarOfficialScheduleExportFetchJsPrefix =
    r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/calendar_official_schedule_export_fetch/main.ts
  function calendarOfficialScheduleExportFetch() {
    var startDate = __mbgConfig.startDate;
    var endDate = __mbgConfig.endDate;
    function textOf(node) {
      if (!node) {
        return "";
      }
      return [
        node.innerText || node.textContent || "",
        node.value || "",
        node.name || "",
        node.id || "",
        node.className || "",
        node.getAttribute && node.getAttribute("onclick") || "",
        node.getAttribute && node.getAttribute("href") || "",
        node.getAttribute && node.getAttribute("title") || ""
      ].join(" ").replace(/\s+/g, " ").trim();
    }
    function normalize(text) {
      return String(text || "").replace(/\s+/g, "").toLowerCase();
    }
    function isExportForm(form) {
      var value = normalize(textOf(form));
      return value.indexOf("scheduleexportform") >= 0 || value.indexOf("カテゴリ") >= 0 && value.indexOf("対象期間") >= 0 && value.indexOf("時間割コマ情報") >= 0;
    }
    function visibleDateInputs(form) {
      return Array.prototype.slice.call(
        form.querySelectorAll("input")
      ).filter(function(input) {
        var type = String(input.getAttribute("type") || "text").toLowerCase();
        return type !== "hidden" && type !== "button" && type !== "submit" && type !== "checkbox" && type !== "radio" && type !== "image";
      });
    }
    function setDateValue(input, value) {
      if (!input || !value) {
        return;
      }
      input.value = value;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
    }
    function configureCategories(form) {
      var checkboxes = Array.prototype.slice.call(
        form.querySelectorAll('input[type="checkbox"]')
      );
      for (var i = 0; i < checkboxes.length; i += 1) {
        var checkbox = checkboxes[i];
        checkbox.checked = checkbox.name === "check2" || checkbox.id === "check21";
      }
    }
    function configureForm(form) {
      var dates = visibleDateInputs(form);
      setDateValue(dates[0], startDate);
      setDateValue(dates[1], endDate);
      configureCategories(form);
      var eventId = form.querySelector('input[name="_eventId"]');
      if (eventId) {
        eventId.value = "executeExport";
      }
    }
    function diagnosticsFor(doc, form) {
      return {
        url: String(doc.location.href || "").split("?")[0],
        title: doc.title || "",
        formTextLength: textOf(form).length,
        controls: Array.prototype.slice.call(
          form.querySelectorAll("button,input,a,[onclick]")
        ).slice(0, 32).map(function(control) {
          return String(control.tagName || "").toLowerCase() + ":" + textOf(control).slice(0, 120);
        })
      };
    }
    function exportFileAfter(xhr) {
      var page = new DOMParser().parseFromString(
        xhr.responseText || "",
        "text/html"
      );
      var metas = Array.prototype.slice.call(page.querySelectorAll("meta"));
      for (var i = 0; i < metas.length; i += 1) {
        var equiv = String(metas[i].getAttribute("http-equiv") || "");
        var match = String(metas[i].getAttribute("content") || "").match(/url\s*=\s*(.+)$/i);
        if (equiv.toLowerCase() !== "refresh" || !match) {
          continue;
        }
        var next = new XMLHttpRequest();
        next.open("GET", new URL(match[1].trim(), xhr.responseURL).href, false);
        next.send(null);
        return next;
      }
      return xhr;
    }
    function requestForm(doc, form) {
      configureForm(form);
      var method = String(form.method || "POST").toUpperCase();
      var action = form.action || doc.location.href;
      var data = new URLSearchParams(new FormData(form)).toString();
      var url = new URL(action, doc.location.href);
      var body = null;
      if (method === "GET") {
        url.search += (url.search ? "&" : "?") + data;
      } else {
        body = data;
      }
      var xhr = new XMLHttpRequest();
      xhr.open(method, url.href, false);
      if (method !== "GET") {
        xhr.setRequestHeader(
          "Content-Type",
          "application/x-www-form-urlencoded; charset=UTF-8"
        );
      }
      xhr.send(body);
      xhr = exportFileAfter(xhr);
      return {
        status: xhr.status >= 200 && xhr.status < 400 ? "fetched" : "http_error",
        httpStatus: xhr.status,
        url: xhr.responseURL || url.href,
        contentType: xhr.getResponseHeader("Content-Type") || "",
        text: xhr.responseText || "",
        diagnostics: diagnosticsFor(doc, form)
      };
    }
    function inspectDocument(doc) {
      var forms = Array.prototype.slice.call(doc.querySelectorAll("form"));
      for (var f = 0; f < forms.length; f += 1) {
        var form = forms[f];
        if (!isExportForm(form)) {
          continue;
        }
        var hasExecute = !!form.querySelector('input[name="_eventId"]');
        var controls = textOf(form);
        if (!hasExecute && controls.indexOf("エクスポート実行") < 0) {
          continue;
        }
        return requestForm(doc, form);
      }
      return null;
    }
    function collect(win) {
      try {
        if (!win || !win.document) {
          return null;
        }
        var found = inspectDocument(win.document);
        if (found) {
          return found;
        }
        for (var i = 0; i < win.frames.length; i += 1) {
          found = collect(win.frames[i]);
          if (found) {
            return found;
          }
        }
      } catch (e) {
        return {
          status: "exception",
          httpStatus: 0,
          url: "",
          contentType: "",
          text: String(e && e.message || e),
          diagnostics: {}
        };
      }
      return null;
    }
    return JSON.stringify(collect(window) || {
      status: "not_found",
      httpStatus: 0,
      url: "",
      contentType: "",
      text: "",
      diagnostics: {}
    });
  }
  __mbgEntryResult = calendarOfficialScheduleExportFetch();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoCalendarOfficialScheduleExportFetchJsSuffix = r''')
''';
