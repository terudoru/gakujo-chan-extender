// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/calendar_official_google_schedule_integration/main.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String gakujoCalendarOfficialGoogleScheduleIntegrationJs(
  Map<String, Object?> config,
) =>
    _gakujoCalendarOfficialGoogleScheduleIntegrationJsPrefix +
    jsonEncode(config) +
    _gakujoCalendarOfficialGoogleScheduleIntegrationJsSuffix;

const String _gakujoCalendarOfficialGoogleScheduleIntegrationJsPrefix =
    r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/calendar_official_google_schedule_integration/main.ts
  function calendarOfficialGoogleScheduleIntegration() {
    var shouldActivate = __mbgConfig.shouldActivate;
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
        node.title || "",
        node.alt || "",
        node.getAttribute && node.getAttribute("aria-label") || "",
        node.getAttribute && node.getAttribute("href") || "",
        node.getAttribute && node.getAttribute("onclick") || "",
        node.getAttribute && node.getAttribute("src") || "",
        node.getAttribute && node.getAttribute("data-url") || "",
        node.getAttribute && node.getAttribute("data-href") || "",
        node.getAttribute && node.getAttribute("formaction") || "",
        node.getAttribute && node.getAttribute("action") || ""
      ].join(" ").replace(/\s+/g, " ").trim();
    }
    function normalize(text) {
      return String(text || "").replace(/\s+/g, "").toLowerCase();
    }
    function isGoogleScheduleLabel(text) {
      var value = normalize(text);
      return value.indexOf("googleスケジュール連携") >= 0 || value.indexOf("googleカレンダー連携") >= 0 || value.indexOf("googlecalendar") >= 0 || value.indexOf("googleカレンダー") >= 0;
    }
    function isGoogleScheduleExportControl(node) {
      var value = normalize([
        node && node.value || "",
        node && node.name || "",
        node && node.id || "",
        node && node.className || "",
        node && node.getAttribute && node.getAttribute("onclick") || "",
        node && node.getAttribute && node.getAttribute("aria-label") || "",
        node && node.getAttribute && node.getAttribute("title") || ""
      ].join(" "));
      if (value.indexOf("インポート") >= 0 || value.indexOf("import") >= 0 || value.indexOf("自分のスケジュール") >= 0 || value.indexOf("教職員") >= 0) {
        return false;
      }
      return value.indexOf("エクスポート") >= 0 || value.indexOf("export") >= 0 || value.indexOf("doexport") >= 0;
    }
    function actionableFor(node) {
      if (!node) {
        return null;
      }
      function isActionable(candidate2) {
        if (!candidate2 || !candidate2.tagName) {
          return false;
        }
        var tag = String(candidate2.tagName || "").toLowerCase();
        if (tag === "a" || tag === "button") {
          return true;
        }
        if (tag === "input") {
          var type = String(candidate2.getAttribute("type") || "").toLowerCase();
          return !type || type === "button" || type === "submit" || type === "image";
        }
        return !!(candidate2.getAttribute && (candidate2.getAttribute("onclick") || candidate2.getAttribute("data-url") || candidate2.getAttribute("data-href") || candidate2.getAttribute("formaction")));
      }
      if (node.closest) {
        var candidate = node.closest(
          "a,button,input,[onclick],[data-url],[data-href],[formaction]"
        );
        return isActionable(candidate) ? candidate : null;
      }
      return isActionable(node) ? node : null;
    }
    function hrefOf(doc, node) {
      var href = node && node.getAttribute && node.getAttribute("href");
      if (!href || /^javascript:/i.test(href)) {
        return "";
      }
      try {
        return new URL(href, doc.location.href).href;
      } catch (e) {
        return href;
      }
    }
    function googleCalendarUrlOf(doc, raw) {
      var text = String(raw || "").replace(/&amp;/g, "&").replace(/\u0026/g, "&");
      var matches = text.match(/https?:\/\/[^'"<>\s)]+/g) || [];
      if (/calendar/i.test(text) && /^https?:\/\//i.test(text)) {
        matches.push(text);
      }
      for (var i = 0; i < matches.length; i += 1) {
        try {
          var url = new URL(matches[i], doc.location.href);
          var host = url.hostname.toLowerCase();
          var path = url.pathname.toLowerCase();
          if (url.protocol === "https:" && host === "calendar.google.com" && path.indexOf("/calendar") >= 0 && (url.searchParams.has("text") || url.searchParams.has("details") || url.searchParams.has("dates"))) {
            return url.href;
          }
        } catch (e) {
        }
      }
      return "";
    }
    function sourcesOf(node) {
      var values = [
        textOf(node),
        node && node.getAttribute && node.getAttribute("href") || "",
        node && node.getAttribute && node.getAttribute("onclick") || "",
        node && node.getAttribute && node.getAttribute("formaction") || "",
        node && node.getAttribute && node.getAttribute("action") || "",
        node && node.value || ""
      ];
      var attrs = node && node.attributes || [];
      for (var i = 0; i < attrs.length; i += 1) {
        if (/^data-/i.test(attrs[i].name)) {
          values.push(attrs[i].value || "");
        }
      }
      return values;
    }
    function directGoogleCalendarUrl(doc, node, parent) {
      var sources = sourcesOf(node).concat(sourcesOf(parent));
      for (var i = 0; i < sources.length; i += 1) {
        var url = googleCalendarUrlOf(doc, sources[i]);
        if (url) {
          return url;
        }
      }
      return "";
    }
    function googleScheduleExportControl(node) {
      var root = node && node.closest && node.closest("form,table,div");
      if (!root || !isGoogleScheduleLabel(textOf(root))) {
        return null;
      }
      var controls = Array.prototype.slice.call(
        root.querySelectorAll("a,button,input,[onclick],[data-url],[data-href]")
      );
      for (var i = 0; i < controls.length; i += 1) {
        if (isGoogleScheduleExportControl(controls[i])) {
          return controls[i];
        }
      }
      return null;
    }
    function diagnosticsFor(doc) {
      var nodes = Array.prototype.slice.call(
        doc.querySelectorAll("a,button,input,img,form,[onclick],[data-url],[data-href]")
      );
      var googleLabelCount = 0;
      var directCalendarUrlCount = 0;
      var sampleLabels = [];
      var googleControlSamples = [];
      function controlSample(node2) {
        var attrs = [
          node2.getAttribute && node2.getAttribute("type") || "",
          node2.value || "",
          node2.name || "",
          node2.id || "",
          node2.className || "",
          node2.getAttribute && node2.getAttribute("onclick") || "",
          node2.getAttribute && node2.getAttribute("href") || "",
          node2.getAttribute && node2.getAttribute("src") || "",
          node2.getAttribute && node2.getAttribute("alt") || "",
          node2.getAttribute && node2.getAttribute("title") || ""
        ].join(" ").replace(/[\r\n]+/g, " ").replace(/\s+/g, " ").trim();
        return String(node2.tagName || "").toLowerCase() + ":" + attrs.slice(0, 120);
      }
      for (var i = 0; i < nodes.length; i += 1) {
        var node = nodes[i];
        var label = textOf(node);
        if (isGoogleScheduleLabel(label)) {
          googleLabelCount += 1;
          var root = node.closest && node.closest("form,table,div") || node;
          var controls = Array.prototype.slice.call(
            root.querySelectorAll("a,button,input,img,[onclick],[data-url],[data-href]")
          );
          for (var c = 0; c < controls.length && googleControlSamples.length < 24; c += 1) {
            googleControlSamples.push(controlSample(controls[c]));
          }
        }
        if (directGoogleCalendarUrl(doc, node, actionableFor(node))) {
          directCalendarUrlCount += 1;
        }
        if (sampleLabels.length < 16) {
          var compact = label.replace(/[\r\n]+/g, " ").trim();
          if (compact) {
            sampleLabels.push(
              String(node.tagName || "").toLowerCase() + ":" + compact.slice(0, 80)
            );
          }
        }
      }
      return {
        url: String(doc.location.href || "").split("?")[0],
        title: doc.title || "",
        nodeCount: nodes.length,
        googleLabelCount,
        directCalendarUrlCount,
        googleControls: googleControlSamples,
        samples: sampleLabels
      };
    }
    function inspectDocument(doc) {
      var candidates = Array.prototype.slice.call(
        doc.querySelectorAll("a,button,input,img,span,div,td,li,form,[onclick],[data-url],[data-href]")
      );
      for (var i = 0; i < candidates.length; i += 1) {
        var node = candidates[i];
        var label = textOf(node);
        var parent = actionableFor(node);
        var combined = [label, textOf(parent)].join(" ");
        var directUrl = directGoogleCalendarUrl(doc, node, parent);
        if (directUrl) {
          return {
            status: shouldActivate ? "url" : "available",
            label: label || textOf(parent),
            url: directUrl,
            diagnostics: diagnosticsFor(doc)
          };
        }
        if (!isGoogleScheduleLabel(combined)) {
          continue;
        }
        var googleExportControl = googleScheduleExportControl(node);
        if (!parent && googleExportControl) {
          parent = googleExportControl;
          label = "Googleスケジュール連携: " + textOf(googleExportControl);
        }
        var href = hrefOf(doc, parent);
        if (!parent) {
          continue;
        }
        if (shouldActivate) {
          if (href) {
            return {
              status: "url",
              label: label || textOf(parent),
              url: href,
              diagnostics: diagnosticsFor(doc)
            };
          }
          if (parent && parent.click) {
            parent.click();
            return {
              status: "clicked",
              label: label || textOf(parent),
              url: "",
              diagnostics: diagnosticsFor(doc)
            };
          }
        }
        return {
          status: href ? "available" : "clickable",
          label: label || textOf(parent),
          url: href,
          diagnostics: diagnosticsFor(doc)
        };
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
      }
      return null;
    }
    function allDiagnostics() {
      var values = [];
      function collectDiagnostics(win) {
        try {
          if (!win || !win.document) {
            return;
          }
          values.push(diagnosticsFor(win.document));
          for (var i = 0; i < win.frames.length; i += 1) {
            collectDiagnostics(win.frames[i]);
          }
        } catch (e) {
        }
      }
      collectDiagnostics(window);
      return values;
    }
    return JSON.stringify(collect(window) || {
      status: "not_found",
      label: "",
      url: "",
      diagnostics: {
        documents: allDiagnostics()
      }
    });
  }
  __mbgEntryResult = calendarOfficialGoogleScheduleIntegration();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _gakujoCalendarOfficialGoogleScheduleIntegrationJsSuffix = r''')
''';
