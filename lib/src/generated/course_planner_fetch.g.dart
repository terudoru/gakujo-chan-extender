// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/course_planner/fetch.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String coursePlannerFetchJs(Map<String, Object?> config) =>
    _coursePlannerFetchJsPrefix +
    jsonEncode(config) +
    _coursePlannerFetchJsSuffix;

const String _coursePlannerFetchJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  var __defProp = Object.defineProperty;
  var __defProps = Object.defineProperties;
  var __getOwnPropDescs = Object.getOwnPropertyDescriptors;
  var __getOwnPropSymbols = Object.getOwnPropertySymbols;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __propIsEnum = Object.prototype.propertyIsEnumerable;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __spreadValues = (a, b) => {
    for (var prop in b || (b = {}))
      if (__hasOwnProp.call(b, prop))
        __defNormalProp(a, prop, b[prop]);
    if (__getOwnPropSymbols)
      for (var prop of __getOwnPropSymbols(b)) {
        if (__propIsEnum.call(b, prop))
          __defNormalProp(a, prop, b[prop]);
      }
    return a;
  };
  var __spreadProps = (a, b) => __defProps(a, __getOwnPropDescs(b));
  var __objRest = (source, exclude) => {
    var target = {};
    for (var prop in source)
      if (__hasOwnProp.call(source, prop) && exclude.indexOf(prop) < 0)
        target[prop] = source[prop];
    if (source != null && __getOwnPropSymbols)
      for (var prop of __getOwnPropSymbols(source)) {
        if (exclude.indexOf(prop) < 0 && __propIsEnum.call(source, prop))
          target[prop] = source[prop];
      }
    return target;
  };

  // web_scripts/src/course_planner/extract.ts
  var origin = "https://gakujo.iess.niigata-u.ac.jp";
  var names = {
    grades: "単位修得状況照会",
    registration: "履修登録・登録状況照会",
    balances: "履修科目確認表",
    profile: "学生所属"
  };
  var studentInquiryName = "学籍情報照会";
  var rejected = "不許可となった科目";
  var codePattern = /^(\d{3}[A-Z][A-Z0-9]{4,5})(?:\s*\(T[\d,\s～~-]+\))?$/;
  var offeringColumns = ["開講所属", "クラス", "学期"];
  var columns = {
    開講番号: "開講番号",
    授業コード: "開講番号",
    科目コード: "開講番号",
    科目名: "科目名",
    授業科目名: "科目名",
    授業科目: "科目名",
    授業名: "科目名",
    講義名: "科目名",
    単位: "単位数",
    単位数: "単位数",
    評価: "評価",
    評語: "評価",
    成績: "評価",
    合否: "合否",
    開講年度: "年度",
    修得年度: "年度",
    履修年度: "年度",
    年度: "年度",
    // Only the faculty offering this course can disambiguate its syllabus.
    // A generic 所属 or 学部 column can describe the student.
    開講所属: "開講所属",
    開講所属コード: "開講所属",
    開講学部: "開講所属",
    開設学部: "開講所属",
    クラス: "クラス",
    クラス名: "クラス",
    クラス番号: "クラス",
    組: "クラス",
    学期: "学期",
    履修学期: "学期",
    修得学期: "学期",
    ターム: "学期",
    許可状況: "登録状況",
    登録状況: "登録状況",
    履修状況: "登録状況",
    申請状況: "登録状況",
    科目区分: "科目区分",
    単位区分: "科目区分",
    区分: "科目区分",
    既修得単位: "既修得単位数",
    既修得単位数: "既修得単位数",
    修得済単位数: "既修得単位数",
    修得単位数: "既修得単位数",
    重複: "重複"
  };
  var gradeColumns = __spreadProps(__spreadValues({}, columns), {
    配当単位: "単位数",
    配当単位数: "単位数",
    修得単位: "修得単位数",
    修得単位数: "修得単位数",
    取得単位数: "修得単位数"
  });
  var allowed = {
    grades: [
      "開講番号",
      "科目名",
      "単位数",
      "修得単位数",
      "評価",
      "合否",
      "年度",
      ...offeringColumns,
      "科目区分",
      "重複"
    ],
    registration: ["開講番号", "科目名", "単位数", "登録状況", "年度"],
    balances: ["科目区分", "既修得単位数"]
  };
  function normalized(value) {
    return (value || "").normalize("NFKC").replace(/\s+/g, " ").trim();
  }
  function safeText(value) {
    return value.length <= 140 && !/https?:|[@<>]|学籍番号|在籍番号|学生番号|氏名|メールアドレス|電話番号|\b\d{2}[A-Za-z]\d{4}[A-Za-z]\b|\d{7,}/i.test(
      value
    ) ? value : "";
  }
  function academicValue(header, value) {
    var _a, _b, _c;
    switch (header) {
      case "開講番号":
        return ((_a = value.match(codePattern)) == null ? void 0 : _a[1]) || "";
      case "年度":
        return ((_b = value.match(/^((?:19|20)\d\d)(?:年度)?$/)) == null ? void 0 : _b[1]) || "";
      case "単位数":
      case "修得単位数":
      case "既修得単位数":
        return ((_c = value.match(/^([*]?\s*\d{1,3}(?:\.\d{1,2})?)(?:\s*単位)?$/)) == null ? void 0 : _c[1].replace(/\s/g, "")) || "";
      case "合否":
      case "評価":
        return /^(秀|優|良|可|不可|合|否|合格|不合格|認定|履修中|未修得|未確定|欠席|放棄|保留|取消|履修取消|[SABCPFD][+-]?)$/.test(
          value
        ) ? value : "";
      case "登録状況":
        return /^(申請中|許可|不許可|要確認|許可済|履修許可)$/.test(value) ? value : "要確認";
      case "重複":
        return /^(\*|重複)$/.test(value) ? value : "";
      default:
        return safeText(value);
    }
  }
  var liveView = {
    url: (doc) => doc.URL,
    visible(el) {
      if (!el.getClientRects().length || el.closest('[hidden],[inert],[aria-hidden="true"]'))
        return false;
      const view = el.ownerDocument.defaultView;
      if (!view) return false;
      for (let parent = el; parent; parent = parent.parentElement) {
        const style = view.getComputedStyle(parent);
        if (style.display === "none" || style.visibility !== "visible" || style.opacity === "0")
          return false;
      }
      return true;
    },
    text: (el) => el.innerText,
    blue(el) {
      const view = el.ownerDocument.defaultView;
      if (!view) return false;
      const color = view.getComputedStyle(el).color;
      return color === "rgb(0, 0, 255)" || color === "rgb(0, 0, 238)";
    }
  };
  function inlineStyle(el) {
    return el.style;
  }
  function staticallyHidden(el) {
    if (/^(SCRIPT|STYLE|TEMPLATE|NOSCRIPT)$/.test(el.tagName)) return true;
    const style = inlineStyle(el);
    return !!style && (style.display === "none" || style.visibility === "hidden" || style.visibility === "collapse" || style.opacity === "0");
  }
  var blockTags = /^(ADDRESS|ARTICLE|ASIDE|BLOCKQUOTE|CAPTION|DD|DIV|DL|DT|FIELDSET|FIGCAPTION|FIGURE|FOOTER|FORM|H[1-6]|HEADER|HR|LEGEND|LI|MAIN|NAV|OL|P|PRE|SECTION|TABLE|TBODY|TD|TFOOT|TH|THEAD|TR|UL)$/;
  function staticText(node) {
    if (node.nodeType === 3) return node.textContent || "";
    if (node.nodeType !== 1) return "";
    const el = node;
    if (staticallyHidden(el)) return "";
    if (el.tagName === "BR") return "\n";
    let text = "";
    for (const child of Array.from(el.childNodes)) text += staticText(child);
    const style = inlineStyle(el);
    const isBlock = blockTags.test(el.tagName) || !!style && /^(block|flex|grid|list-item|table|table-row)$/.test(style.display);
    return isBlock ? "\n" + text + "\n" : text;
  }
  var blueColor = /^(blue|#00f|#0000ff|#0000ee|rgb\(0,0,(255|238)\))$/;
  function explicitColor(el) {
    const style = inlineStyle(el);
    if (style && style.color) return style.color;
    return el.tagName === "FONT" ? el.getAttribute("color") || "" : "";
  }
  function staticView(href) {
    return {
      url: () => href,
      visible(el) {
        if (el.closest('[hidden],[inert],[aria-hidden="true"]')) return false;
        for (let parent = el; parent; parent = parent.parentElement)
          if (staticallyHidden(parent)) return false;
        return true;
      },
      text(el) {
        let text = "";
        for (const child of Array.from(el.childNodes)) text += staticText(child);
        return text;
      },
      blue(el) {
        for (let parent = el; parent && !/^(TD|TH|TR|TABLE|BODY|HTML)$/.test(parent.tagName); parent = parent.parentElement) {
          const color = explicitColor(parent);
          if (color) return blueColor.test(color.toLowerCase().replace(/\s/g, ""));
        }
        return false;
      }
    };
  }
  function extractor(view) {
    const visible = (el) => view.visible(el);
    function leaf(el) {
      if (!el || el.querySelector(
        'table,form,input,textarea,select,iframe,script,style,[hidden],[aria-hidden="true"]'
      ))
        return "";
      return normalized(view.text(el));
    }
    function label(el) {
      return leaf(el).replace(/\s/g, "");
    }
    function hasHeading(doc, title) {
      return Array.from(
        doc.querySelectorAll("h1,h2,h3,h4,caption,th,td,legend,.title,.pageTitle")
      ).some(
        (el) => !el.closest('nav,a,button,[role="menu"]') && !el.querySelector("a,button,th,td") && label(el) === title && visible(el)
      );
    }
    function pageKinds(doc) {
      var _a;
      const kinds = [];
      const page = new URL(view.url(doc));
      const servlet2 = (_a = page.pathname.split("/").pop()) == null ? void 0 : _a.split(";")[0];
      const officialView = servlet2 === "campussquare.do" || servlet2 === "campusportal.do" || servlet2 === "campussmart.do";
      if (!officialView) return kinds;
      const grade = !!doc.querySelector("form#taniReferListForm + table") || hasHeading(doc, names.grades);
      const registration = page.searchParams.get("_flowId") === "RSW0001000-flow" || hasHeading(doc, names.registration) || !!doc.querySelector('div.tblDivNml a[onclick*="CallDetail("]');
      if (grade && Array.from(doc.querySelectorAll("table")).some((t) => !!header(t, "grades")))
        kinds.push("grades");
      if (registration && academicTables(doc, "registration").length) {
        kinds.push("registration");
      }
      if ((grade || registration || hasHeading(doc, names.balances)) && Array.from(doc.querySelectorAll("table")).some(
        (t) => !!header(t, "balances")
      ))
        kinds.push("balances");
      if ((grade || registration || hasHeading(doc, studentInquiryName)) && profile(doc)) kinds.push("profile");
      return kinds;
    }
    function header(table, kind) {
      const names2 = kind === "grades" ? gradeColumns : columns;
      for (const row of Array.from(table.rows).slice(0, 5)) {
        const cells = Array.from(row.cells);
        if (cells.some((c) => c.rowSpan !== 1)) continue;
        const labels = cells.map((c) => names2[label(c)] || "");
        const has = (s) => labels.includes(s);
        const courseGrade = (has("科目名") || has("開講番号")) && (has("評価") || has("合否"));
        const match = kind === "balances" ? !courseGrade && has("科目区分") && has("既修得単位数") : kind === "registration" ? has("開講番号") && (has("登録状況") || has("科目名") && isRejected(table, row)) : courseGrade && (has("単位数") || has("修得単位数"));
        if (match) return { row, labels };
      }
      return null;
    }
    function isRejected(table, headerRow) {
      if (label(table.caption) === rejected || label(table.previousElementSibling) === rejected)
        return true;
      return Array.from(table.rows).slice(0, headerRow.rowIndex).some((row) => row.cells.length === 1 && label(row.cells[0]) === rejected);
    }
    function tableData(table, kind) {
      if (!visible(table)) return null;
      const h = header(table, kind);
      if (!h) return null;
      const denied = kind === "registration" && isRejected(table, h.row);
      const projection = h.labels.map((name, i) => ({ name, i })).filter((c) => allowed[kind].includes(c.name));
      if (new Set(projection.map((c) => c.name)).size !== projection.length)
        return null;
      const headers = projection.map((c) => c.name);
      const rows = [headers];
      for (const row of Array.from(table.rows).slice(h.row.rowIndex + 1)) {
        const cells = Array.from(row.cells);
        if (cells.some(
          (c) => /^(学生情報|個人情報|氏名|学生氏名|学籍番号|在籍番号|学生番号|メールアドレス)$/.test(
            label(c)
          )
        ))
          break;
        if (cells.length !== h.labels.length || cells.some(
          (c, i) => c.colSpan !== h.row.cells[i].colSpan || c.rowSpan !== 1
        ) || !visible(row))
          continue;
        const vals = projection.map(({ name, i }) => {
          var _a;
          const cell = cells[i];
          const value = visible(cell) ? academicValue(name, leaf(cell)) : "";
          if (!value && offeringColumns.includes(name) && (cell.childElementCount || ((_a = cell.textContent) == null ? void 0 : _a.trim())))
            return "要確認";
          return value;
        });
        const get2 = (k) => vals[headers.indexOf(k)];
        if (kind === "balances" ? !(get2("科目区分") && get2("既修得単位数")) : kind === "registration" ? !get2("開講番号") : !((get2("単位数") || get2("修得単位数")) && (get2("科目名") || get2("開講番号")) && (get2("開講番号") || get2("評価") || get2("合否"))))
          continue;
        rows.push(vals);
      }
      return rows.length > 1 ? { heading: denied ? rejected : names[kind], rows } : null;
    }
    function registrationMeetings(doc) {
      const meetings = [];
      for (const link of Array.from(
        doc.querySelectorAll('table a[onclick*="CallDetail("]')
      )) {
        if (!visible(link)) continue;
        const args = (link.getAttribute("onclick") || "").match(
          /\bCallDetail\(\s*'(\d{4})'\s*,\s*'[A-Za-z0-9]+'\s*,\s*'(\d{3}[A-Z][A-Z0-9]{4,5})'\s*,\s*'([1-7])'\s*,\s*'([1-7])'\s*\)/
        );
        if (!args) continue;
        let shown = leaf(link);
        const prev = link.previousSibling;
        if (normalized(prev == null ? void 0 : prev.textContent) === "?") shown = "?" + shown;
        const displayed = shown.replace(/^\?\s*/, "").match(codePattern);
        if (!displayed || displayed[1] !== args[2]) continue;
        const blue = view.blue(link.querySelector("font,span") || link);
        const status = shown.startsWith("?") ? blue ? "要確認" : "申請中" : blue ? "許可" : "要確認";
        const br = link.nextElementSibling;
        const next = br == null ? void 0 : br.nextSibling;
        const parts = (br == null ? void 0 : br.tagName) === "BR" && (next == null ? void 0 : next.nodeType) === 3 ? (next.textContent || "").split(" ") : [];
        const title = parts.length >= 3 ? safeText(normalized(parts[0]).replace(/[◆◇]+$/, "")) : "";
        meetings.push({ year: args[1], code: args[2], title, status, day: Number(args[3]), period: Number(args[4]) });
      }
      return meetings;
    }
    function timetable(doc) {
      const rows = [["年度", "開講番号", "科目名", "登録状況"]];
      const seen = /* @__PURE__ */ new Set();
      for (const { year, code, title, status } of registrationMeetings(doc)) {
        const row = [year, code, title, status];
        const key = JSON.stringify(row);
        if (!seen.has(key)) {
          seen.add(key);
          rows.push(row);
        }
      }
      return rows.length > 1 ? { heading: names.registration, rows } : null;
    }
    function registrationTerm(doc) {
      const scopes = /* @__PURE__ */ new Map();
      for (const cell of Array.from(doc.querySelectorAll("th,td"))) {
        if (label(cell) !== "年度・学期" || !visible(cell)) continue;
        const value = cell.nextElementSibling;
        if (!value || !visible(value)) continue;
        const found = /^((?:19|20)\d{2})年度\s*第?([12一二])学期$/.exec(leaf(value));
        if (!found) continue;
        const year = found[1];
        const semester = ["1", "一"].includes(found[2]) ? "first" : "second";
        scopes.set(year + semester, { year, semester });
      }
      return scopes.size === 1 ? scopes.values().next().value : void 0;
    }
    function timetableSnapshot(doc) {
      const term = registrationTerm(doc);
      if (!term) return null;
      const slots = /* @__PURE__ */ new Map();
      for (const _a of registrationMeetings(doc)) {
        const _b = _a, { year } = _b, meeting = __objRest(_b, ["year"]);
        if (year !== term.year || !meeting.code.startsWith(year.slice(-2))) return null;
        const key = `${meeting.code}/${meeting.day}/${meeting.period}`;
        const previous = slots.get(key);
        if (previous && (previous.status !== meeting.status || previous.title !== meeting.title)) return null;
        slots.set(key, meeting);
      }
      return slots.size ? __spreadProps(__spreadValues({}, term), { meetings: [...slots.values()] }) : null;
    }
    function admissionYear(root) {
      var _a, _b, _c, _d, _e;
      const years = /* @__PURE__ */ new Set();
      for (const cell of Array.from(root.querySelectorAll("th,td,dt"))) {
        const name = label(cell);
        if (name !== "入学年度" && name !== "入学年月" && name !== "入学年月日") continue;
        const value = cell.nextElementSibling;
        if (!value || !visible(cell) || !visible(value)) continue;
        const printed = leaf(value).replace(/\s+/g, "");
        if (!printed) continue;
        if (name === "入学年度") {
          years.add(((_a = /^((?:19|20)\d{2})(?:年度)?$/.exec(printed)) == null ? void 0 : _a[1]) || "");
          continue;
        }
        const japanese = /^((?:19|20)\d{2})年(\d{1,2})月(?:(\d{1,2})日)?$/.exec(printed);
        const numeric = /^((?:19|20)\d{2})([-/.])(\d{1,2})(?:\2(\d{1,2}))?$/.exec(printed);
        const year = Number((_b = japanese == null ? void 0 : japanese[1]) != null ? _b : numeric == null ? void 0 : numeric[1]);
        const month = Number((_c = japanese == null ? void 0 : japanese[2]) != null ? _c : numeric == null ? void 0 : numeric[3]);
        const day = Number((_e = (_d = japanese == null ? void 0 : japanese[3]) != null ? _d : numeric == null ? void 0 : numeric[4]) != null ? _e : "1");
        const utc = new Date(Date.UTC(year, month - 1, day));
        const academicYear = month < 4 ? year - 1 : year;
        years.add(academicYear >= 1900 && utc.getUTCMonth() === month - 1 && utc.getUTCDate() === day ? String(academicYear) : "");
      }
      return years.size === 1 ? [...years][0] || void 0 : void 0;
    }
    function profile(doc) {
      const matches = [];
      for (const table of Array.from(doc.querySelectorAll("table")).filter(visible)) {
        if (header(table, "grades") || header(table, "registration") || header(table, "balances") || table.querySelector("form,table")) continue;
        const cells = Array.from(table.rows).flatMap((row) => Array.from(row.cells)).filter(visible);
        const values = (key) => cells.filter((cell) => label(cell) === key && cell.nextElementSibling && visible(cell.nextElementSibling)).map((cell) => leaf(cell.nextElementSibling));
        const affiliations = values("所属");
        const grades = values("学年");
        if (affiliations.length !== 1 || grades.length > 1) continue;
        const affiliation = safeText(affiliations[0]);
        if (!affiliation) continue;
        const grade = grades[0] || "";
        matches.push({ table, data: {
          heading: names.profile,
          rows: [["所属", "学年"], [affiliation, /^[1-6]$/.test(grade) ? grade : ""]]
        } });
      }
      return matches.length === 1 ? matches[0] : null;
    }
    function academicTables(doc, kind) {
      if (kind === "profile") {
        const projected = profile(doc);
        return projected ? [projected.table] : [];
      }
      return Array.from(doc.querySelectorAll("table")).filter(
        (table) => visible(table) && (header(table, kind) || kind === "registration" && Array.from(table.querySelectorAll('a[onclick*="CallDetail("]')).some(
          (a) => a.closest("table") === table
        ))
      );
    }
    function packet(doc, kind, current = academicTables(doc, kind)) {
      var _a;
      if (kind === "profile") {
        const projected = profile(doc);
        if (!projected) return null;
        const year2 = admissionYear(hasHeading(doc, studentInquiryName) ? doc : projected.table);
        return __spreadValues({ v: 1, kind, tables: [projected.data] }, year2 ? { year: year2 } : {});
      }
      const tables = current.map((t) => tableData(t, kind)).filter((t) => !!t);
      const grid = kind === "registration" ? timetable(doc) : null;
      if (grid) tables.unshift(grid);
      if (!withinBounds(tables)) return null;
      const year = kind === "registration" ? (_a = registrationTerm(doc)) == null ? void 0 : _a.year : void 0;
      return __spreadValues({
        v: 1,
        kind,
        tables: kind === "registration" && year ? tables.map(({ heading, rows }) => {
          if (rows[0].includes("年度")) return { heading, rows };
          return { heading, rows: [["年度", ...rows[0]], ...rows.slice(1).map((row) => [year, ...row])] };
        }) : tables
      }, year ? { year } : {});
    }
    return { visible, pageKinds, academicTables, profile, admissionYear, packet, registrationTerm, timetableSnapshot };
  }
  function withinBounds(tables) {
    return tables.length > 0 && tables.length <= 50 && tables.reduce((n, t) => n + t.rows.length, 0) <= 6e3;
  }

  // web_scripts/src/course_planner/fetch.ts
  var order = ["profile", "grades", "balances", "registration"];
  var registrationFallback = "/campusweb/campussquare.do?_flowId=RSW0001000-flow";
  var gradesFallback = "/campusweb/campussquare.do?_flowId=SIW0001300-flow";
  var maxPageLength = 4 * 1024 * 1024;
  var requestTimeout = 8e3;
  var captureTimeout = 6e4;
  var balancePdfLimit = 2 * 1024 * 1024;
  var host = window;
  function servlet(url) {
    return /^\/campusweb\/campussquare\.do(?:;jsessionid=[^/;]*)?$/i.test(
      url.pathname
    );
  }
  function parse(raw, base) {
    try {
      const url = new URL(raw.trim(), base);
      return url.origin === origin && !url.username && !url.password && servlet(url) ? url : null;
    } catch (e) {
      return null;
    }
  }
  function inquiryUrl(raw, base) {
    const url = parse(raw.replace(/&amp;/g, "&"), base);
    if (!url) return null;
    const keys = Array.from(url.searchParams.keys());
    const flows = url.searchParams.getAll("_flowId");
    if (keys.some((k) => /^_eventId/i.test(k) || /^_flowExecutionKey$/i.test(k)) || flows.length !== 1 || !/^[A-Za-z0-9_-]+-flow$/.test(flows[0]))
      return null;
    return { path: url.pathname + url.search, flow: flows[0] };
  }
  function semesterTarget(raw, base, year) {
    const clean = raw.trim().replace(/&amp;/g, "&");
    const url = parse(clean, base);
    const params = url == null ? void 0 : url.searchParams;
    const semester = params == null ? void 0 : params.get("gakkiKbnCode");
    if (!url || !params || !Array.from(params.keys()).every(
      (k) => /^(_flowExecutionKey|_flowId|_eventId|gakkiKbnCode|nendo|locale)$/.test(k) && params.getAll(k).length === 1
    ) || params.get("_eventId") !== "search" || semester !== "1" && semester !== "2" || params.has("nendo") && !/^(19|20)\d{2}$/.test(params.get("nendo") || "") || params.has("_flowId") && params.get("_flowId") !== "RSW0001000-flow" || params.has("_flowExecutionKey") && !/^e\d+s\d+$/.test(params.get("_flowExecutionKey") || "") || !params.has("_flowId") && !params.has("_flowExecutionKey"))
      return null;
    return {
      path: url.pathname + url.search,
      year: params.get("nendo") || year,
      semester: semester === "1" ? "first" : "second"
    };
  }
  function frameDocuments(doc, found, depth = 0) {
    let url;
    try {
      url = new URL(doc.URL);
    } catch (e) {
      return;
    }
    if (url.origin !== origin || !url.pathname.startsWith("/campusweb/")) return;
    found.push(doc);
    if (depth > 4) return;
    for (const frame of Array.from(
      doc.querySelectorAll("iframe,frame")
    )) {
      try {
        if (frame.contentDocument)
          frameDocuments(frame.contentDocument, found, depth + 1);
      } catch (e) {
      }
    }
  }
  function quoted(script) {
    const values = [];
    const pattern = /(['"])(.*?)\1/g;
    for (let match = pattern.exec(script); match; match = pattern.exec(script))
      values.push(match[2]);
    return values;
  }
  function discover(docs, title) {
    let found = null;
    const flows = /* @__PURE__ */ new Set();
    for (const doc of docs)
      for (const el of Array.from(
        doc.querySelectorAll(
          'a,button,input[type="button"],input[type="submit"],[onclick]'
        )
      )) {
        const text = el.tagName === "INPUT" ? el.value : el.textContent;
        if (normalized(text).replace(/\s/g, "") !== title) continue;
        const href = el.getAttribute("href") || "";
        const candidates = [
          .../^javascript:/i.test(href.trim()) ? quoted(href) : [href],
          ...quoted(el.getAttribute("onclick") || "")
        ];
        for (const raw of candidates) {
          const target = raw.includes("campussquare.do") ? inquiryUrl(raw, doc.URL) : null;
          if (!target) continue;
          flows.add(target.flow);
          found = found || target.path;
        }
      }
    return flows.size === 1 ? found : null;
  }
  var sessionExpired = new Error("session-expired");
  function advertisedBalancePdf(page) {
    const candidates = /* @__PURE__ */ new Set();
    const { visible } = staticView(page.href);
    for (const link of Array.from(page.doc.querySelectorAll("a[href]"))) {
      if (!visible(link)) continue;
      const namesOnLink = [
        link.textContent,
        link.title,
        link.getAttribute("aria-label"),
        ...Array.from(link.querySelectorAll("img[alt]"), (icon) => icon.getAttribute("alt"))
      ];
      if (!namesOnLink.some((value) => normalized(value).replace(/\s/g, "") === names.balances)) continue;
      const href = link.getAttribute("href") || "";
      try {
        const url = new URL(href, page.href);
        if (url.origin === origin && !url.username && !url.password && (/^\/campusweb\/.*\.pdf$/i.test(url.pathname) || servlet(url) && link.type.toLowerCase() === "application/pdf"))
          candidates.add(url.origin + url.pathname + url.search);
      } catch (e) {
      }
    }
    return candidates.size === 1 ? candidates.values().next().value : void 0;
  }
  async function readBalancePdf(url, signal, deadline) {
    var _a, _b;
    const remaining = deadline - Date.now();
    if (signal.aborted || remaining <= 0) return null;
    const controller = new AbortController();
    const abort = () => controller.abort();
    signal.addEventListener("abort", abort, { once: true });
    const timeout = setTimeout(abort, Math.min(remaining, requestTimeout));
    try {
      const response = await fetch(url, { credentials: "same-origin", redirect: "error", signal: controller.signal });
      if (!response.ok || ((_b = (_a = response.headers.get("Content-Type")) == null ? void 0 : _a.split(";")[0]) == null ? void 0 : _b.trim().toLowerCase()) !== "application/pdf" || Number(response.headers.get("Content-Length")) > balancePdfLimit || !response.body) return null;
      const reader = response.body.getReader();
      let length = 0;
      const chunks = [];
      for (; ; ) {
        const { done, value } = await reader.read();
        if (done) break;
        if ((length += value.length) > balancePdfLimit) return null;
        chunks.push(value);
      }
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
      if (String.fromCharCode(...bytes.subarray(0, 5)) !== "%PDF-") return null;
      let binary = "";
      for (let start2 = 0; start2 < length; start2 += 16384)
        binary += String.fromCharCode(...bytes.subarray(start2, start2 + 16384));
      return btoa(binary);
    } catch (e) {
      return null;
    } finally {
      abort();
      clearTimeout(timeout);
      signal.removeEventListener("abort", abort);
    }
  }
  async function get(path, signal, deadline) {
    const remaining = deadline - Date.now();
    if (signal.aborted || remaining <= 0) return null;
    const xhr = new XMLHttpRequest();
    const abort = () => xhr.abort();
    const loaded = await new Promise((resolve) => {
      xhr.open("GET", path);
      xhr.timeout = Math.min(remaining, requestTimeout);
      xhr.onload = () => resolve(true);
      xhr.onerror = xhr.ontimeout = xhr.onabort = () => resolve(false);
      signal.addEventListener("abort", abort, { once: true });
      try {
        xhr.send();
      } catch (e) {
        resolve(false);
      }
    }).finally(() => signal.removeEventListener("abort", abort));
    if (!loaded || xhr.status < 200 || xhr.status >= 300 || xhr.responseText.length > maxPageLength)
      return null;
    const href = xhr.responseURL || new URL(path, location.href).href;
    if (new URL(href).origin !== origin) throw sessionExpired;
    const doc = new DOMParser().parseFromString(xhr.responseText, "text/html");
    if (doc.querySelector('input[type="password"],input[name="ninshoCode"]'))
      throw sessionExpired;
    return parse(href, location.href) ? { doc, href } : null;
  }
  var termKey = ({ year, semester }) => (year != null ? year : "") + "/" + semester;
  async function fetchInquiries(signal) {
    var _a;
    const docs = [];
    frameDocuments(document, docs);
    if (!docs.length || docs.some(
      (d) => Array.from(
        d.querySelectorAll('input[type="password"],input[name="ninshoCode"]')
      ).some((el) => liveView.visible(el))
    ))
      return null;
    const deadline = Date.now() + captureTimeout;
    const read = (path) => get(path, signal, deadline);
    const pages = [];
    const grades = await read(discover(docs, names.grades) || gradesFallback);
    if (grades) pages.push(__spreadValues({ source: "grades" }, grades));
    const studentPath = discover(docs, studentInquiryName);
    const studentPage = studentPath ? await read(studentPath) : null;
    const first = await read(discover(docs, names.registration) || registrationFallback);
    const pending = /* @__PURE__ */ new Map();
    const confirmed = /* @__PURE__ */ new Set();
    const attempted = /* @__PURE__ */ new Map();
    const unresolved = /* @__PURE__ */ new Set();
    function includeRegistration(page, target) {
      const { registrationTerm, pageKinds } = extractor(staticView(page.href));
      const term = registrationTerm(page.doc);
      if (target && (!term || term.semester !== target.semester || target.year && term.year !== target.year)) return false;
      if (!term && !pageKinds(page.doc).includes("registration")) return false;
      pages.push(__spreadValues({ source: "registration" }, page));
      if (term) {
        const key = termKey(term);
        confirmed.add(key);
        unresolved.delete(key);
        pending.delete(key);
      }
      for (const link of Array.from(page.doc.querySelectorAll("a[href]"))) {
        const next = semesterTarget(link.getAttribute("href") || "", page.href, term == null ? void 0 : term.year);
        if (!next) continue;
        const key = termKey(next);
        const seen = attempted.get(key);
        if (confirmed.has(key) || (seen == null ? void 0 : seen.has(next.path)) || seen && seen.size >= 2) continue;
        pending.set(key, next);
      }
      return true;
    }
    const rootRead = first && includeRegistration(first);
    const balanceUrl = first && rootRead ? advertisedBalancePdf(first) : void 0;
    const balancePdf = balanceUrl ? await readBalancePdf(balanceUrl, signal, deadline) : null;
    for (const [key, next] of pending) {
      if (signal.aborted || Date.now() >= deadline) break;
      pending.delete(key);
      const seen = (_a = attempted.get(key)) != null ? _a : /* @__PURE__ */ new Set();
      seen.add(next.path);
      attempted.set(key, seen);
      const page = await read(next.path);
      if (page && includeRegistration(page, next)) unresolved.delete(key);
      else unresolved.add(key);
    }
    const packets = {};
    const registration = [];
    const timetable = /* @__PURE__ */ new Map();
    const tableKeys = /* @__PURE__ */ new Set();
    const years = /* @__PURE__ */ new Set();
    let yearless = false;
    for (const page of pages) {
      const { pageKinds, packet, timetableSnapshot } = extractor(staticView(page.href));
      if (page.source === "registration") {
        const snapshot = timetableSnapshot(page.doc);
        if (snapshot) {
          const key = snapshot.year + snapshot.semester;
          const previous = timetable.get(key);
          if (previous === void 0) timetable.set(key, snapshot);
          else if (JSON.stringify(previous) !== JSON.stringify(snapshot)) timetable.set(key, null);
        }
      }
      for (const kind of pageKinds(page.doc)) {
        if ((kind === "grades" || kind === "registration") && kind !== page.source)
          continue;
        if (kind !== "registration" && packets[kind]) continue;
        const found = packet(page.doc, kind);
        if (!found) continue;
        if (kind !== "registration") {
          packets[kind] = found;
          continue;
        }
        for (const table of found.tables) {
          const key = JSON.stringify(table);
          if (!tableKeys.has(key)) {
            tableKeys.add(key);
            registration.push(table);
          }
        }
        if (found.year) years.add(found.year);
        else yearless = true;
      }
    }
    const registrationFits = !registration.length || withinBounds(registration);
    if (registration.length && registrationFits)
      packets.registration = __spreadValues({
        v: 1,
        kind: "registration",
        tables: registration
      }, years.size === 1 && !yearless ? { year: Array.from(years)[0] } : {});
    if (studentPage) {
      const read2 = extractor(staticView(studentPage.href));
      const student = read2.packet(studentPage.doc, "profile");
      const previous = packets.profile;
      const profile = student || previous;
      const year = read2.admissionYear(studentPage.doc);
      if (profile) {
        const _b = profile, { year: oldYear } = _b, base = __objRest(_b, ["year"]);
        packets.profile = year ? __spreadProps(__spreadValues({}, base), { year }) : base;
      }
    }
    const ordered = {};
    for (const kind of order) if (packets[kind]) ordered[kind] = packets[kind];
    const gradePageRead = grades && extractor(staticView(grades.href)).pageKinds(grades.doc).includes("grades");
    const complete = !!gradePageRead && !!rootRead && (!studentPath || !!studentPage) && (!balanceUrl || !!balancePdf) && registrationFits && pending.size === 0 && unresolved.size === 0 && ![...timetable.values()].includes(null);
    return __spreadValues({
      v: 1,
      packets: ordered,
      timetable: [...timetable.values()].filter((value) => value !== null),
      complete
    }, balancePdf && { balancePdf });
  }
  function start() {
    var _a;
    if (window !== window.top || location.origin !== origin) return null;
    const { attempt } = __mbgConfig;
    (_a = host.__mbgPlannerFetch) == null ? void 0 : _a.cancel();
    const controller = new AbortController();
    let result = "pending";
    const cancel = (owner) => {
      if (owner !== void 0 && owner !== attempt) return;
      delete host.__mbgPlannerFetch;
      controller.abort();
      window.removeEventListener("pagehide", leave);
    };
    const leave = () => cancel();
    window.addEventListener("pagehide", leave, { once: true });
    host.__mbgPlannerFetch = {
      take(owner) {
        if (owner !== attempt) return null;
        if (result !== "pending") cancel(attempt);
        return result;
      },
      cancel
    };
    void fetchInquiries(controller.signal).then(
      (capture) => {
        result = JSON.stringify(capture);
        if ((capture == null ? void 0 : capture.balancePdf) && result.length > 7 * 1024 * 1024) {
          const _a2 = capture, { balancePdf } = _a2, inquiries = __objRest(_a2, ["balancePdf"]);
          result = JSON.stringify(__spreadProps(__spreadValues({}, inquiries), { complete: false }));
        }
      },
      () => {
        result = "null";
      }
    );
    return result;
  }
  __mbgEntryResult = start();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _coursePlannerFetchJsSuffix = r''')
''';
