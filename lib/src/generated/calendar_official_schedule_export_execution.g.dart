// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/calendar_official_schedule_export_execution/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoCalendarOfficialScheduleExportExecutionJs(
  Map<String, Object?> config,
) =>
    _gakujoCalendarOfficialScheduleExportExecutionJsPrefix +
    jsonEncode(config) +
    _gakujoCalendarOfficialScheduleExportExecutionJsSuffix;

const String _gakujoCalendarOfficialScheduleExportExecutionJsPrefix =
    r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/calendar_official_schedule_export_execution/main.ts
  function calendarOfficialScheduleExportExecution() {
    var shouldActivate = __mbgConfig.shouldActivate;
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
        if (type === "hidden" || type === "button" || type === "submit" || type === "checkbox" || type === "radio" || type === "image") {
          return false;
        }
        return true;
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
        checkbox.dispatchEvent(new Event("input", { bubbles: true }));
        checkbox.dispatchEvent(new Event("change", { bubbles: true }));
      }
    }
    function exportButton(form) {
      var controls = Array.prototype.slice.call(
        form.querySelectorAll("button,input,a,[onclick]")
      );
      for (var i = 0; i < controls.length; i += 1) {
        var control = controls[i];
        var label = normalize(textOf(control));
        var type = String(control.getAttribute && control.getAttribute("type") || "").toLowerCase();
        if (type === "hidden") {
          continue;
        }
        if (label.indexOf("クリア") >= 0 || label.indexOf("戻る") >= 0 || label.indexOf("back") >= 0 || label.indexOf("clear") >= 0) {
          continue;
        }
        if (label.indexOf("エクスポート実行") >= 0 || label.indexOf("executeexport") >= 0 || label.indexOf("エクスポート") >= 0) {
          return control;
        }
      }
      return null;
    }
    function diagnosticsFor(doc, form) {
      var controls = Array.prototype.slice.call(
        form.querySelectorAll("button,input,a,[onclick]")
      );
      return {
        url: String(doc.location.href || "").split("?")[0],
        title: doc.title || "",
        formTextLength: textOf(form).length,
        controls: controls.slice(0, 32).map(function(control) {
          return String(control.tagName || "").toLowerCase() + ":" + textOf(control).slice(0, 120);
        })
      };
    }
    function inspectDocument(doc) {
      var forms = Array.prototype.slice.call(doc.querySelectorAll("form"));
      var missingCandidate = null;
      for (var f = 0; f < forms.length; f += 1) {
        var form = forms[f];
        if (!isExportForm(form)) {
          continue;
        }
        var dates = visibleDateInputs(form);
        setDateValue(dates[0], startDate);
        setDateValue(dates[1], endDate);
        configureCategories(form);
        var eventId = form.querySelector('input[name="_eventId"]');
        if (eventId && !eventId.value) {
          eventId.value = "executeExport";
        }
        var button = exportButton(form);
        if (!button) {
          missingCandidate = missingCandidate || {
            status: "not_found",
            label: "",
            url: "",
            diagnostics: diagnosticsFor(doc, form)
          };
          continue;
        }
        if (shouldActivate) {
          button.click();
          return {
            status: "clicked",
            label: textOf(button),
            url: "",
            diagnostics: diagnosticsFor(doc, form)
          };
        }
        return {
          status: "clickable",
          label: textOf(button),
          url: "",
          diagnostics: diagnosticsFor(doc, form)
        };
      }
      return missingCandidate;
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
      }
      return null;
    }
    function formCounts() {
      var values = [];
      function collectCounts(win) {
        try {
          if (!win || !win.document) {
            return;
          }
          values.push({
            url: String(win.document.location.href || "").split("?")[0],
            title: win.document.title || "",
            formCount: win.document.querySelectorAll("form").length
          });
          for (var i = 0; i < win.frames.length; i += 1) {
            collectCounts(win.frames[i]);
          }
        } catch (e) {
        }
      }
      collectCounts(window);
      return values;
    }
    return JSON.stringify(collect(window) || {
      status: "not_found",
      label: "",
      url: "",
      diagnostics: {
        documents: formCounts()
      }
    });
  }
  __mbgEntryResult = calendarOfficialScheduleExportExecution();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoCalendarOfficialScheduleExportExecutionJsSuffix = r''')
''';
