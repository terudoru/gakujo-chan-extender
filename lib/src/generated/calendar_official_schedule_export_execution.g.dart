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
  // web_scripts/src/shared/calendar_export_form.ts
  function textOf(node) {
    if (!node) return "";
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
  function notifyInputChange(input) {
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }
  function configureInputs(form, startDate, endDate, notifyCategories) {
    var dates = Array.from(form.querySelectorAll("input")).filter(function(input) {
      var type = String(input.getAttribute("type") || "text").toLowerCase();
      return !["hidden", "button", "submit", "checkbox", "radio", "image"].includes(type);
    });
    [startDate, endDate].forEach(function(value, index) {
      var input = dates[index];
      if (input && value) {
        input.value = value;
        notifyInputChange(input);
      }
    });
    for (var checkbox of Array.from(form.querySelectorAll('input[type="checkbox"]'))) {
      checkbox.checked = checkbox.name === "check2" || checkbox.id === "check21";
      if (notifyCategories) notifyInputChange(checkbox);
    }
  }
  function diagnosticsFor(doc, form) {
    return {
      url: String(doc.location.href || "").split("?")[0],
      title: doc.title || "",
      formTextLength: textOf(form).length,
      controls: Array.from(
        form.querySelectorAll("button,input,a,[onclick]")
      ).slice(0, 32).map(function(control) {
        return String(control.tagName || "").toLowerCase() + ":" + textOf(control).slice(0, 120);
      })
    };
  }

  // web_scripts/src/shared/calendar_schedule_dom.ts
  function findInCalendarFrames(win, inspect) {
    try {
      if (!win || !win.document) {
        return null;
      }
      const result = inspect(win.document);
      if (result) {
        return result;
      }
      for (let i = 0; i < win.frames.length; i += 1) {
        const found = findInCalendarFrames(win.frames[i], inspect);
        if (found) {
          return found;
        }
      }
    } catch (e) {
    }
    return null;
  }

  // web_scripts/src/calendar_official_schedule_export_execution/main.ts
  function calendarOfficialScheduleExportExecution() {
    var shouldActivate = __mbgConfig.shouldActivate;
    var startDate = __mbgConfig.startDate;
    var endDate = __mbgConfig.endDate;
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
    function inspectDocument(doc) {
      var forms = Array.prototype.slice.call(doc.querySelectorAll("form"));
      var missingCandidate = null;
      for (var f = 0; f < forms.length; f += 1) {
        var form = forms[f];
        if (!isExportForm(form)) {
          continue;
        }
        configureInputs(form, startDate, endDate, true);
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
    return JSON.stringify(findInCalendarFrames(window, inspectDocument) || {
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
