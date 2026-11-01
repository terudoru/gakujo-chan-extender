// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/assignment_list_fetch/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoAssignmentListFetchJs = r'''
(function() {
"use strict";
(() => {
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

  // web_scripts/src/assignment_list_fetch/main.ts
  function assignmentListFetch() {
    try {
      var base = location.origin + "/campusweb/campussquare.do";
      var url = "/campusweb/campussquare.do?_flowId=ENW3411100-flow";
      var rows = [];
      var seenRows = /* @__PURE__ */ new Set();
      var visited = /* @__PURE__ */ new Set();
      var total = -1;
      var complete = false;
      var expanded = false;
      for (var page = 0; page < 10 && url && !visited.has(url); page += 1) {
        visited.add(url);
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, false);
        xhr.send(null);
        if (xhr.status < 200 || xhr.status >= 400) {
          if (!page) return JSON.stringify({ status: "error", rows: [] });
          break;
        }
        var doc = new DOMParser().parseFromString(xhr.responseText, "text/html");
        var form = doc.querySelector("#enqListForm");
        if (!form) {
          if (!page) return JSON.stringify({ status: "missing", rows: [] });
          break;
        }
        var content = String(form.textContent || "");
        var counts = content.match(/([0-9]+)件/g) || [];
        total = counts.length ? parseInt(counts[0], 10) : -1;
        var pageRows = readAssignmentRows(doc);
        var previousLength = rows.length;
        pageRows.forEach(function(row) {
          var key = JSON.stringify(row);
          if (!seenRows.has(key)) {
            seenRows.add(key);
            rows.push(row);
          }
        });
        if (total >= 0 && rows.length === total) {
          complete = true;
          break;
        }
        if (page && rows.length === previousLength) break;
        var next = "";
        var controls = form.querySelectorAll('a, button, input[type="submit"]');
        for (var c = 0; c < controls.length; c += 1) {
          var control = controls[c];
          var label = String(control.textContent || control.value || "");
          if (!/次へ/.test(label) || control.disabled || control.getAttribute("aria-disabled") === "true") continue;
          var href = control.getAttribute("href") || "";
          var onclick = control.getAttribute("onclick") || "";
          var target = ((onclick || href).match(/['"]([^'"]*[?&]_eventId=[^'"]+)['"]/) || [])[1];
          if (!target && href && !/^(?:javascript:|#)/i.test(href)) target = href;
          if (target) {
            var candidate = new URL(target.replace(/&amp;/g, "&"), base);
            if (candidate.origin === location.origin && candidate.pathname === "/campusweb/campussquare.do") {
              next = candidate.href;
              break;
            }
          }
        }
        var displayCount = form.querySelector('select[name="_displayCount"], input[name="_displayCount"]');
        var paging = /次へ|前へ/.test(content) || form.querySelector('[onclick*="paging"], [href*="paging"]') || displayCount;
        if (!next && !expanded && displayCount) {
          var target = new URL(form.getAttribute("action") || url, base);
          var hidden = form.querySelectorAll('input[type="hidden"]');
          for (var h = 0; h < hidden.length; h += 1) {
            if (hidden[h].name) target.searchParams.set(hidden[h].name, hidden[h].value);
          }
          var sizes = Array.from(displayCount.options || []).map(function(option) {
            return parseInt(option.value, 10);
          }).filter(function(size2) {
            return size2 > pageRows.length && size2 <= 500;
          });
          var size = displayCount.options ? Math.max.apply(null, sizes) : 500;
          if (target.searchParams.has("_flowExecutionKey") && size > pageRows.length && target.origin === location.origin && target.pathname === "/campusweb/campussquare.do") {
            target.searchParams.set("_eventId", "paging");
            target.searchParams.set("_displayCount", String(size));
            next = target.href;
            expanded = true;
          }
        }
        if (total < 0 && !next && !paging && form.querySelector("ul.campussmart-list")) {
          total = rows.length;
          complete = true;
        }
        url = next;
      }
      return JSON.stringify({
        status: "ok",
        total: complete ? total : -1,
        rows
      });
    } catch (e) {
      return JSON.stringify({ status: "error", rows: [] });
    }
  }
  __mbgEntryResult = assignmentListFetch();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
