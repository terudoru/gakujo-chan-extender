// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/calendar_schedule_month_navigation/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoCalendarScheduleMonthNavigationJs(Map<String, Object?> config) =>
    _gakujoCalendarScheduleMonthNavigationJsPrefix +
    jsonEncode(config) +
    _gakujoCalendarScheduleMonthNavigationJsSuffix;

const String _gakujoCalendarScheduleMonthNavigationJsPrefix =
    r'''(function(__mbgConfig) {
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
  function monthInDocument(doc) {
    const text = textOf(doc.body || doc);
    const match = text.match(/(20[0-9]{2})\s*年\s*([0-9]{1,2})\s*月/);
    return match ? { year: Number(match[1]), month: Number(match[2]) } : null;
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

  // web_scripts/src/calendar_schedule_month_navigation/main.ts
  function calendarScheduleMonthNavigation() {
    var targetYear = __mbgConfig.targetYear;
    var targetMonth = __mbgConfig.targetMonth;
    function clickControl(doc, direction) {
      var view = doc.defaultView || window;
      try {
        if (direction > 0 && typeof view.loadNextMonth === "function") {
          view.loadNextMonth();
          return true;
        }
        if (direction < 0 && typeof view.loadBeforeMonth === "function") {
          view.loadBeforeMonth();
          return true;
        }
      } catch (e) {
      }
      var controls = calendarControls(doc);
      var fallback = null;
      for (var i = 0; i < controls.length; i += 1) {
        var control = controls[i];
        var label = textOf(control).toLowerCase();
        var onclick = String(
          control.getAttribute && control.getAttribute("onclick") || ""
        ).toLowerCase();
        if (direction > 0) {
          if (onclick.indexOf("loadnextmonth") >= 0 || label.indexOf("loadnextmonth") >= 0) {
            control.click();
            return true;
          }
          if (!fallback && (label.indexOf("next") >= 0 || label.indexOf("次") >= 0)) {
            fallback = control;
          }
        } else if (direction < 0) {
          if (onclick.indexOf("loadbeforemonth") >= 0 || label.indexOf("loadbeforemonth") >= 0) {
            control.click();
            return true;
          }
          if (!fallback && (label.indexOf("prev") >= 0 || label.indexOf("前") >= 0)) {
            fallback = control;
          }
        }
      }
      if (fallback) {
        fallback.click();
        return true;
      }
      return false;
    }
    function inspect(doc) {
      var current = monthInDocument(doc);
      if (!current) {
        return null;
      }
      var diff = (targetYear - current.year) * 12 + (targetMonth - current.month);
      if (diff === 0) {
        return {
          status: "ready",
          year: current.year,
          month: current.month
        };
      }
      if (clickControl(doc, diff > 0 ? 1 : -1)) {
        return {
          status: "clicked",
          year: current.year,
          month: current.month,
          direction: diff > 0 ? "next" : "prev"
        };
      }
      return null;
    }
    return JSON.stringify(findInCalendarFrames(window, inspect) || {
      status: "not_found",
      year: 0,
      month: 0
    });
  }
  __mbgEntryResult = calendarScheduleMonthNavigation();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoCalendarScheduleMonthNavigationJsSuffix = r''')
''';
