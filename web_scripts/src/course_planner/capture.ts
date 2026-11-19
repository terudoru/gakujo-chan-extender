export {};

type Kind = "grades" | "registration" | "balances";
type Table = { heading: string; rows: string[][] };
declare const __mbgConfig: { attempt: string; kind?: Kind };
type SourceDocument = Document & {
  __mbgPlannerSource?: {
    attempt: string;
    href: string;
    tables: HTMLTableElement[];
  };
};

const origin = "https://gakujo.iess.niigata-u.ac.jp";
const names = {
  grades: "単位修得状況照会",
  registration: "履修登録・登録状況照会",
  balances: "履修科目確認表",
};
const rejected = "不許可となった科目";
const codePattern = /^(\d{3}[A-Z][A-Z0-9]{4,5})(?:\s*\(T[\d,\s～~-]+\))?$/;
const offeringColumns = ["開講所属", "クラス", "学期"];
const columns: Record<string, string> = {
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
  重複: "重複",
};
// 修得単位数 is per course on a grade row and per category on a balance row.
const gradeColumns: Record<string, string> = {
  ...columns,
  配当単位: "単位数",
  配当単位数: "単位数",
  修得単位: "修得単位数",
  修得単位数: "修得単位数",
  取得単位数: "修得単位数",
};
const allowed: Record<Kind, string[]> = {
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
    "重複",
  ],
  registration: ["開講番号", "科目名", "単位数", "登録状況", "年度"],
  balances: ["科目区分", "既修得単位数"],
};

function visible(el: Element) {
  if (
    !el.getClientRects().length ||
    el.closest('[hidden],[inert],[aria-hidden="true"]')
  )
    return false;
  const view = el.ownerDocument.defaultView!;
  for (let parent: Element | null = el; parent; parent = parent.parentElement) {
    const style = view.getComputedStyle(parent);
    if (
      style.display === "none" ||
      style.visibility !== "visible" ||
      style.opacity === "0"
    )
      return false;
  }
  return true;
}
function normalized(value: string | null | undefined) {
  return (value || "").normalize("NFKC").replace(/\s+/g, " ").trim();
}
function leaf(el: Element | null) {
  if (
    !el ||
    el.querySelector(
      'table,form,input,textarea,select,iframe,script,style,[hidden],[aria-hidden="true"]',
    )
  )
    return "";
  return normalized((el as HTMLElement).innerText);
}
function label(el: Element | null) {
  return leaf(el).replace(/\s/g, "");
}
function safeText(value: string) {
  return value.length <= 140 &&
    !/https?:|[@<>]|学籍番号|在籍番号|学生番号|氏名|メールアドレス|電話番号|\b\d{2}[A-Za-z]\d{4}[A-Za-z]\b|\d{7,}/i.test(
      value,
    )
    ? value
    : "";
}
function academicValue(header: string, value: string) {
  switch (header) {
    case "開講番号":
      return value.match(codePattern)?.[1] || "";
    case "年度":
      return value.match(/^((?:19|20)\d\d)(?:年度)?$/)?.[1] || "";
    case "単位数":
    case "修得単位数":
    case "既修得単位数":
      return (
        value
          .match(/^([*]?\s*\d{1,3}(?:\.\d{1,2})?)(?:\s*単位)?$/)?.[1]
          .replace(/\s/g, "") || ""
      );
    case "合否":
    case "評価":
      return /^(秀|優|良|可|不可|合|否|合格|不合格|認定|履修中|未修得|未確定|欠席|放棄|保留|取消|履修取消|[SABCPFD][+-]?)$/.test(
        value,
      )
        ? value
        : "";
    case "登録状況":
      return /^(申請中|許可|不許可|要確認|許可済|履修許可)$/.test(value)
        ? value
        : "要確認";
    case "重複":
      return /^(\*|重複)$/.test(value) ? value : "";
    default:
      return safeText(value);
  }
}
function hasHeading(doc: Document, title: string) {
  return Array.from(
    doc.querySelectorAll("h1,h2,h3,h4,caption,th,td,legend,.title,.pageTitle"),
  ).some(
    (el) =>
      !el.closest('nav,a,button,[role="menu"]') &&
      !el.querySelector("a,button,th,td") &&
      label(el) === title &&
      visible(el),
  );
}
function pageKinds(doc: Document): Kind[] {
  const kinds: Kind[] = [];
  const page = new URL(doc.URL);
  const servlet = page.pathname.split("/").pop()?.split(";")[0];
  const officialView =
    servlet === "campussquare.do" ||
    servlet === "campusportal.do" ||
    servlet === "campussmart.do";
  // Portal attachments can contain arbitrary headings and form names.
  if (!officialView) return kinds;
  const grade =
    !!doc.querySelector("form#taniReferListForm + table") ||
    hasHeading(doc, names.grades);
  // Spring Web Flow later replaces the initial _flowId with an execution key.
  const registration =
    page.searchParams.get("_flowId") === "RSW0001000-flow" ||
    hasHeading(doc, names.registration) ||
    !!doc.querySelector('div.tblDivNml a[onclick*="CallDetail("]');
  if (
    grade &&
    Array.from(doc.querySelectorAll("table")).some((t) => !!header(t, "grades"))
  )
    kinds.push("grades");
  if (registration && academicTables(doc, "registration").length) {
    kinds.push("registration");
  }
  if (
    (grade || registration || hasHeading(doc, names.balances)) &&
    Array.from(doc.querySelectorAll("table")).some(
      (t) => !!header(t, "balances"),
    )
  )
    kinds.push("balances");
  return kinds;
}
function header(table: HTMLTableElement, kind: Kind) {
  const names = kind === "grades" ? gradeColumns : columns;
  for (const row of Array.from(table.rows).slice(0, 5)) {
    const cells = Array.from(row.cells);
    // Positional projection is valid only in a rectangular, single-header table.
    if (cells.some((c) => c.rowSpan !== 1)) continue;
    const labels = cells.map((c) => names[label(c)] || "");
    const has = (s: string) => labels.includes(s);
    const courseGrade =
      (has("科目名") || has("開講番号")) && (has("評価") || has("合否"));
    const match =
      kind === "balances"
        ? !courseGrade && has("科目区分") && has("既修得単位数")
        : kind === "registration"
          ? has("開講番号") &&
            (has("登録状況") || (has("科目名") && isRejected(table, row)))
          : courseGrade && (has("単位数") || has("修得単位数"));
    if (match) return { row, labels };
  }
  return null;
}
function isRejected(table: HTMLTableElement, headerRow: HTMLTableRowElement) {
  if (
    label(table.caption) === rejected ||
    label(table.previousElementSibling) === rejected
  )
    return true;
  return Array.from(table.rows)
    .slice(0, headerRow.rowIndex)
    .some((row) => row.cells.length === 1 && label(row.cells[0]) === rejected);
}
function tableData(table: HTMLTableElement, kind: Kind): Table | null {
  if (!visible(table)) return null;
  const h = header(table, kind);
  if (!h) return null;
  const denied = kind === "registration" && isRejected(table, h.row);
  const projection = h.labels
    .map((name, i) => ({ name, i }))
    .filter((c) => allowed[kind].includes(c.name));
  if (new Set(projection.map((c) => c.name)).size !== projection.length)
    return null;
  const headers = projection.map((c) => c.name);
  const rows = [headers];
  for (const row of Array.from(table.rows).slice(h.row.rowIndex + 1)) {
    const cells = Array.from(row.cells);
    // Some layouts reuse the same physical table for a second section.
    // Its positions cease to be evidence of the academic column meanings.
    if (
      cells.some((c) =>
        /^(学生情報|個人情報|氏名|学生氏名|学籍番号|在籍番号|学生番号|メールアドレス)$/.test(
          label(c),
        ),
      )
    )
      break;
    if (
      cells.length !== h.labels.length ||
      cells.some(
        (c, i) => c.colSpan !== h.row.cells[i].colSpan || c.rowSpan !== 1,
      ) ||
      !visible(row)
    )
      continue;
    const vals = projection.map(({ name, i }) => {
      const cell = cells[i];
      const value = visible(cell) ? academicValue(name, leaf(cell)) : "";
      // An unreadable identity field is not evidence of an unspecified offering.
      if (
        !value &&
        offeringColumns.includes(name) &&
        (cell.childElementCount || cell.textContent?.trim())
      )
        return "要確認";
      return value;
    });
    const get = (k: string) => vals[headers.indexOf(k)];
    if (
      kind === "balances"
        ? !(get("科目区分") && get("既修得単位数"))
        : kind === "registration"
          ? !get("開講番号")
          : !(
              (get("単位数") || get("修得単位数")) &&
              (get("科目名") || get("開講番号")) &&
              (get("開講番号") || get("評価") || get("合否"))
            )
    )
      continue;
    rows.push(vals);
  }
  return rows.length > 1
    ? { heading: denied ? rejected : names[kind], rows }
    : null;
}

// The university's 履修科目の登録 manual, p.9, identifies undecided
// entries by the red question mark and permitted entries by a blue number.
// Timetable CELL backgrounds describe term length, never permission.
function timetable(doc: Document): Table | null {
  const rows = [["年度", "開講番号", "科目名", "登録状況"]];
  const seen = new Set<string>();
  for (const link of Array.from(
    doc.querySelectorAll<HTMLAnchorElement>('table a[onclick*="CallDetail("]'),
  )) {
    if (!visible(link)) continue;
    const args = (link.getAttribute("onclick") || "").match(
      /\bCallDetail\(\s*'(\d{4})'\s*,\s*'[A-Za-z0-9]+'\s*,\s*'(\d{3}[A-Z][A-Z0-9]{4,5})'\s*,\s*'[1-7]'\s*,\s*'[1-7]'\s*\)/,
    );
    if (!args) continue;
    let shown = leaf(link);
    const prev = link.previousSibling;
    if (normalized(prev?.textContent) === "?") shown = "?" + shown;
    const displayed = shown.replace(/^\?\s*/, "").match(codePattern);
    if (!displayed || displayed[1] !== args[2]) continue;
    const color = doc.defaultView!.getComputedStyle(
      link.querySelector("font,span") || link,
    ).color;
    const blue = color === "rgb(0, 0, 255)" || color === "rgb(0, 0, 238)";
    const status = shown.startsWith("?")
      ? blue
        ? "要確認"
        : "申請中"
      : blue
        ? "許可"
        : "要確認";
    // Read only the course-name segment of the documented "title NBSP room NBSP credits" line.
    const br = link.nextElementSibling;
    const next = br?.nextSibling;
    const parts =
      br?.tagName === "BR" && next?.nodeType === 3
        ? (next.textContent || "").split("\u00a0")
        : [];
    const title =
      parts.length >= 3
        ? safeText(normalized(parts[0]).replace(/[◆◇]+$/, ""))
        : "";
    const row = [args[1], args[2], title, status];
    const key = JSON.stringify(row);
    if (!seen.has(key)) {
      seen.add(key);
      rows.push(row);
    }
  }
  return rows.length > 1 ? { heading: names.registration, rows } : null;
}
function sourceDocuments(doc: SourceDocument, found: SourceDocument[]) {
  if (
    new URL(doc.URL).origin !== origin ||
    !new URL(doc.URL).pathname.startsWith("/campusweb/")
  )
    return;
  found.push(doc);
  for (const frame of Array.from(
    doc.querySelectorAll<HTMLIFrameElement>("iframe,frame"),
  )) {
    try {
      if (visible(frame) && frame.contentDocument)
        sourceDocuments(frame.contentDocument, found);
    } catch {
      /* Other origins cannot own this capture. */
    }
  }
}
function academicTables(doc: Document, kind: Kind) {
  return Array.from(doc.querySelectorAll("table")).filter(
    (table) =>
      visible(table) &&
      (header(table, kind) ||
        (kind === "registration" &&
          Array.from(table.querySelectorAll('a[onclick*="CallDetail("]')).some(
            (a) => a.closest("table") === table,
          ))),
  );
}
function capture() {
  if (window !== window.top || location.origin !== origin) return null;
  const docs: SourceDocument[] = [];
  sourceDocuments(document, docs);
  if (
    docs.some((d) =>
      Array.from(
        d.querySelectorAll('input[type="password"],input[name="ninshoCode"]'),
      ).some(visible),
    )
  )
    return null;
  const { attempt, kind } = __mbgConfig;
  const sources = docs.map((doc) => ({ doc, kinds: pageKinds(doc) }));
  if (!kind) {
    const offered = (Object.keys(names) as Kind[]).filter(
      (k) => sources.filter((s) => s.kinds.includes(k)).length === 1,
    );
    for (const s of sources)
      if (s.kinds.some((k) => offered.includes(k))) {
        const tables = s.kinds.reduce<HTMLTableElement[]>(
          (all, k) => all.concat(academicTables(s.doc, k)),
          [],
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
  if (
    !owner ||
    owner.attempt !== attempt ||
    owner.href !== doc.URL ||
    current.some((t) => !owner.tables.includes(t)) ||
    owner.tables.some((t) => !t.isConnected)
  )
    return null;
  const tables = current
    .map((t) => tableData(t, kind))
    .filter((t): t is Table => !!t);
  const grid = kind === "registration" ? timetable(doc) : null;
  if (grid) tables.unshift(grid);
  if (
    !tables.length ||
    tables.length > 50 ||
    tables.reduce((n, t) => n + t.rows.length, 0) > 6000
  )
    return null;
  // Scope denied rows to the official selected year too, when explicitly shown.
  const years = new Set<string>();
  if (kind === "registration")
    for (const cell of Array.from(doc.querySelectorAll("th,td"))) {
      if (label(cell) !== "年度・学期" || !visible(cell)) continue;
      const year = leaf(cell.nextElementSibling).match(
        /^(\d{4})年度\s*第?[12一二]学期$/,
      )?.[1];
      if (year) years.add(year);
    }
  return {
    v: 1,
    kind,
    tables,
    ...(years.size === 1 ? { year: Array.from(years)[0] } : {}),
  };
}
__mbgEntryResult = JSON.stringify(capture());
