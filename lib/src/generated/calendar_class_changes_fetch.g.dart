// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/calendar_class_changes_fetch/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoCalendarClassChangesFetchJs(Map<String, Object?> config) =>
    _gakujoCalendarClassChangesFetchJsPrefix +
    jsonEncode(config) +
    _gakujoCalendarClassChangesFetchJsSuffix;

const String _gakujoCalendarClassChangesFetchJsPrefix =
    r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/calendar_class_changes_fetch/main.ts
  function calendarClassChangesFetch() {
    var startDay = __mbgConfig.startDay;
    var endDay = __mbgConfig.endDay;
    function get(url) {
      var xhr = new XMLHttpRequest();
      xhr.open("GET", url, false);
      xhr.send(null);
      if (xhr.status < 200 || xhr.status >= 300) {
        throw new Error("HTTP " + xhr.status);
      }
      var doc2 = new DOMParser().parseFromString(xhr.responseText, "text/html");
      if (!keyOf(doc2)) {
        throw new Error("Invalid class changes page");
      }
      return doc2;
    }
    function keyOf(doc2) {
      var input = doc2.querySelector('input[name="_flowExecutionKey"]');
      return input ? input.value : "";
    }
    function text(node) {
      return String(node && node.textContent || "").replace(/\s+/g, " ").trim();
    }
    function pad(value) {
      return String(value).padStart(2, "0");
    }
    try {
      var key = keyOf(get("/campusweb/campussquare.do?_flowId=KHW0001100-flow"));
      var changes = [];
      var day = new Date(
        Number(startDay.slice(0, 4)),
        Number(startDay.slice(4, 6)) - 1,
        Number(startDay.slice(6, 8))
      );
      for (var week = 0; week < 60 && key; week += 1) {
        var stamp = day.getFullYear() + pad(day.getMonth() + 1) + pad(day.getDate());
        if (stamp > endDay) {
          break;
        }
        var doc = get(
          "/campusweb/campussquare.do?_flowExecutionKey=" + key + "&_eventId_linkSearch=_eventId_linkSearch&shozokuCode=&gakunen=&kyokanCode=&day=" + stamp + "&dispData=chg&dispType=list&jikanwaricd=&kamokunm="
        );
        key = keyOf(doc);
        var rows = doc.querySelectorAll(
          "tr.kyuko-kyuko, tr.kyuko-hoko, tr.kyuko-kyoshitsu"
        );
        for (var i = 0; i < rows.length; i += 1) {
          var cells = Array.prototype.slice.call(rows[i].cells || []).map(text);
          var date = "";
          var period = "";
          var code = "";
          var course = "";
          for (var c = 0; c < cells.length; c += 1) {
            var dateMatch = cells[c].match(/([0-9]{1,2})月([0-9]{1,2})日/);
            var periodMatch = cells[c].match(/^([1-7])限/);
            var codeMatch = cells[c].match(/^[0-9]{3}[A-Z][0-9]{4}$/);
            if (!date && dateMatch) {
              var month = Number(dateMatch[1]);
              var year = day.getFullYear() + (month < day.getMonth() + 1 - 6 ? 1 : 0);
              date = year + "-" + pad(month) + "-" + pad(dateMatch[2]);
            } else if (!period && periodMatch) {
              period = periodMatch[1];
            } else if (!code && codeMatch) {
              code = cells[c];
              course = cells[c + 1] || "";
            }
          }
          changes.push({
            kind: rows[i].className.trim(),
            date,
            period,
            code,
            course,
            room: cells[cells.length - 1] || ""
          });
        }
        day.setDate(day.getDate() + 7);
      }
      return JSON.stringify({ status: "ok", changes });
    } catch (e) {
      return JSON.stringify({ status: "error", changes: [] });
    }
  }
  __mbgEntryResult = calendarClassChangesFetch();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoCalendarClassChangesFetchJsSuffix = r''')
''';
