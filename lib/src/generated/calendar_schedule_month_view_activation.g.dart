// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/calendar_schedule_month_view_activation/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoCalendarScheduleMonthViewActivationJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/shared/calendar_schedule_dom.ts
  function textOf(node) {
    if (!node) {
      return "";
    }
    return [
      node.innerText || node.textContent || "",
      node.value || "",
      node.getAttribute && node.getAttribute("title") || "",
      node.getAttribute && node.getAttribute("onclick") || "",
      node.getAttribute && node.getAttribute("href") || ""
    ].join(" ").replace(/\s+/g, " ").trim();
  }
  function calendarControls(doc) {
    return Array.prototype.slice.call(doc.querySelectorAll("a,button,input,[onclick]"));
  }
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

  // web_scripts/src/calendar_schedule_month_view_activation/main.ts
  function calendarScheduleMonthViewActivation() {
    function inspect(doc) {
      var controls = calendarControls(doc);
      var monthControl = null;
      var monthLabel = "";
      for (var i = 0; i < controls.length; i += 1) {
        var control = controls[i];
        var label = textOf(control);
        var normalized = label.toLowerCase();
        if (normalized.indexOf("changecalunitweek") >= 0 || label.indexOf("週単位") >= 0) {
          return {
            status: "ready",
            label,
            url: doc.location && doc.location.href || ""
          };
        }
        if (!monthControl && (normalized.indexOf("changecalunitmonth") >= 0 || label.indexOf("月単位") >= 0)) {
          monthControl = control;
          monthLabel = label;
        }
      }
      if (!monthControl) {
        return null;
      }
      try {
        monthControl.click();
        return {
          status: "clicked",
          label: monthLabel,
          url: doc.location && doc.location.href || ""
        };
      } catch (e) {
        return {
          status: "exception",
          label: monthLabel,
          url: doc.location && doc.location.href || "",
          message: String(e && e.message || e)
        };
      }
    }
    return JSON.stringify(findInCalendarFrames(window, inspect) || {
      status: "not_found",
      label: "",
      url: ""
    });
  }
  __mbgEntryResult = calendarScheduleMonthViewActivation();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
