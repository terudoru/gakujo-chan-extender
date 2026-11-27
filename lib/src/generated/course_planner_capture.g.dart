// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/course_planner/capture.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String coursePlannerCaptureJs(Map<String, Object?> config) =>
    _coursePlannerCaptureJsPrefix +
    jsonEncode(config) +
    _coursePlannerCaptureJsSuffix;

const String _coursePlannerCaptureJsPrefix = r'''(function(__mbgConfig) {
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
  function extractor(view) {
    const visible2 = (el) => view.visible(el);
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
        (el) => !el.closest('nav,a,button,[role="menu"]') && !el.querySelector("a,button,th,td") && label(el) === title && visible2(el)
      );
    }
    function pageKinds2(doc) {
      var _a;
      const kinds = [];
      const page = new URL(view.url(doc));
      const servlet = (_a = page.pathname.split("/").pop()) == null ? void 0 : _a.split(";")[0];
      const officialView = servlet === "campussquare.do" || servlet === "campusportal.do" || servlet === "campussmart.do";
      if (!officialView) return kinds;
      const grade = !!doc.querySelector("form#taniReferListForm + table") || hasHeading(doc, names.grades);
      const registration = page.searchParams.get("_flowId") === "RSW0001000-flow" || hasHeading(doc, names.registration) || !!doc.querySelector('div.tblDivNml a[onclick*="CallDetail("]');
      if (grade && Array.from(doc.querySelectorAll("table")).some((t) => !!header(t, "grades")))
        kinds.push("grades");
      if (registration && academicTables2(doc, "registration").length) {
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
      if (!visible2(table)) return null;
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
        ) || !visible2(row))
          continue;
        const vals = projection.map(({ name, i }) => {
          var _a;
          const cell = cells[i];
          const value = visible2(cell) ? academicValue(name, leaf(cell)) : "";
          if (!value && offeringColumns.includes(name) && (cell.childElementCount || ((_a = cell.textContent) == null ? void 0 : _a.trim())))
            return "要確認";
          return value;
        });
        const get = (k) => vals[headers.indexOf(k)];
        if (kind === "balances" ? !(get("科目区分") && get("既修得単位数")) : kind === "registration" ? !get("開講番号") : !((get("単位数") || get("修得単位数")) && (get("科目名") || get("開講番号")) && (get("開講番号") || get("評価") || get("合否"))))
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
        if (!visible2(link)) continue;
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
        if (label(cell) !== "年度・学期" || !visible2(cell)) continue;
        const value = cell.nextElementSibling;
        if (!value || !visible2(value)) continue;
        const found = /^((?:19|20)\d{2})年度\s*第?([12一二])学期$/.exec(leaf(value));
        if (!found) continue;
        const year = found[1];
        const semester = ["1", "一"].includes(found[2]) ? "first" : "second";
        scopes.set(year + semester, { year, semester });
      }
      return scopes.size === 1 ? scopes.values().next().value : void 0;
    }
    function timetableSnapshot2(doc) {
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
        if (!value || !visible2(cell) || !visible2(value)) continue;
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
      for (const table of Array.from(doc.querySelectorAll("table")).filter(visible2)) {
        if (header(table, "grades") || header(table, "registration") || header(table, "balances") || table.querySelector("form,table")) continue;
        const cells = Array.from(table.rows).flatMap((row) => Array.from(row.cells)).filter(visible2);
        const values = (key) => cells.filter((cell) => label(cell) === key && cell.nextElementSibling && visible2(cell.nextElementSibling)).map((cell) => leaf(cell.nextElementSibling));
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
    function academicTables2(doc, kind) {
      if (kind === "profile") {
        const projected = profile(doc);
        return projected ? [projected.table] : [];
      }
      return Array.from(doc.querySelectorAll("table")).filter(
        (table) => visible2(table) && (header(table, kind) || kind === "registration" && Array.from(table.querySelectorAll('a[onclick*="CallDetail("]')).some(
          (a) => a.closest("table") === table
        ))
      );
    }
    function packet2(doc, kind, current = academicTables2(doc, kind)) {
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
    return { visible: visible2, pageKinds: pageKinds2, academicTables: academicTables2, profile, admissionYear, packet: packet2, registrationTerm, timetableSnapshot: timetableSnapshot2 };
  }
  function withinBounds(tables) {
    return tables.length > 0 && tables.length <= 50 && tables.reduce((n, t) => n + t.rows.length, 0) <= 6e3;
  }

  // web_scripts/src/course_planner/capture.ts
  var { visible, pageKinds, academicTables, packet, timetableSnapshot } = extractor(liveView);
  function sourceDocuments(doc, found) {
    if (new URL(doc.URL).origin !== origin || !new URL(doc.URL).pathname.startsWith("/campusweb/"))
      return;
    found.push(doc);
    for (const frame of Array.from(
      doc.querySelectorAll("iframe,frame")
    )) {
      try {
        if (visible(frame) && frame.contentDocument)
          sourceDocuments(frame.contentDocument, found);
      } catch (e) {
      }
    }
  }
  function capture() {
    if (window !== window.top || location.origin !== origin) return null;
    const docs = [];
    sourceDocuments(document, docs);
    if (docs.some(
      (d) => Array.from(
        d.querySelectorAll('input[type="password"],input[name="ninshoCode"]')
      ).some(visible)
    ))
      return null;
    const { attempt, kind } = __mbgConfig;
    const sources = docs.map((doc2) => ({ doc: doc2, kinds: pageKinds(doc2) }));
    if (!kind) {
      const offered = Object.keys(names).filter(
        (k) => sources.filter((s) => s.kinds.includes(k)).length === 1
      );
      for (const s of sources)
        if (s.kinds.some((k) => offered.includes(k))) {
          const tables = s.kinds.reduce(
            (all, k) => all.concat(academicTables(s.doc, k)),
            []
          );
          s.doc.__mbgPlannerSource = { attempt, href: s.doc.URL, tables };
        }
      return offered;
    }
    const matches = sources.filter((s) => s.kinds.includes(kind));
    if (matches.length !== 1) return null;
    const doc = matches[0].doc;
    const owner = doc.__mbgPlannerSource;
    const current = academicTables(doc, kind);
    if (!owner || owner.attempt !== attempt || owner.href !== doc.URL || current.some((t) => !owner.tables.includes(t)) || owner.tables.some((t) => !t.isConnected))
      return null;
    return __mbgConfig.timetable ? kind === "registration" ? timetableSnapshot(doc) : null : packet(doc, kind, current);
  }
  __mbgEntryResult = JSON.stringify(capture());
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _coursePlannerCaptureJsSuffix = r''')
''';
