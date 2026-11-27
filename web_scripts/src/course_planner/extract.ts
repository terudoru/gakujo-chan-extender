// Table extraction shared by the displayed-page capture and the background
// fetch. Only the way a document is observed differs between them: a live
// document is read through layout and computed style, a parsed document
// only through its markup.

export type AcademicKind = "grades" | "registration" | "balances";
export type Kind = AcademicKind | "profile";
export type Table = { heading: string; rows: string[][] };
export type Packet = { v: 1; kind: Kind; tables: Table[]; year?: string };

export type View = {
  /** The page address; a parsed document does not carry its own. */
  url(doc: Document): string;
  visible(el: Element): boolean;
  /** Rendered text, before normalization. */
  text(el: Element): string;
  /** Whether the timetable entry is shown in the manual's blue. */
  blue(el: Element): boolean;
};

export const origin = "https://gakujo.iess.niigata-u.ac.jp";
export const names = {
  grades: "単位修得状況照会",
  registration: "履修登録・登録状況照会",
  balances: "履修科目確認表",
  profile: "学生所属",
};
export const studentInquiryName = "学籍情報照会";
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
const allowed: Record<AcademicKind, string[]> = {
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

export function normalized(value: string | null | undefined) {
  return (value || "").normalize("NFKC").replace(/\s+/g, " ").trim();
}
export function safeText(value: string) {
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

/** The displayed page, observed through layout and computed style. */
export const liveView: View = {
  url: (doc) => doc.URL,
  visible(el) {
    if (
      !el.getClientRects().length ||
      el.closest('[hidden],[inert],[aria-hidden="true"]')
    )
      return false;
    const view = el.ownerDocument.defaultView;
    if (!view) return false;
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
  },
  text: (el) => (el as HTMLElement).innerText,
  blue(el) {
    const view = el.ownerDocument.defaultView;
    if (!view) return false;
    const color = view.getComputedStyle(el).color;
    return color === "rgb(0, 0, 255)" || color === "rgb(0, 0, 238)";
  },
};

function inlineStyle(el: Element) {
  return (el as HTMLElement).style as CSSStyleDeclaration | undefined;
}
function staticallyHidden(el: Element) {
  if (/^(SCRIPT|STYLE|TEMPLATE|NOSCRIPT)$/.test(el.tagName)) return true;
  const style = inlineStyle(el);
  return (
    !!style &&
    (style.display === "none" ||
      style.visibility === "hidden" ||
      style.visibility === "collapse" ||
      style.opacity === "0")
  );
}
const blockTags =
  /^(ADDRESS|ARTICLE|ASIDE|BLOCKQUOTE|CAPTION|DD|DIV|DL|DT|FIELDSET|FIGCAPTION|FIGURE|FOOTER|FORM|H[1-6]|HEADER|HR|LEGEND|LI|MAIN|NAV|OL|P|PRE|SECTION|TABLE|TBODY|TD|TFOOT|TH|THEAD|TR|UL)$/;
function staticText(node: Node): string {
  if (node.nodeType === 3) return node.textContent || "";
  if (node.nodeType !== 1) return "";
  const el = node as Element;
  if (staticallyHidden(el)) return "";
  if (el.tagName === "BR") return "\n";
  let text = "";
  for (const child of Array.from(el.childNodes)) text += staticText(child);
  const style = inlineStyle(el);
  const isBlock =
    blockTags.test(el.tagName) ||
    (!!style &&
      /^(block|flex|grid|list-item|table|table-row)$/.test(style.display));
  return isBlock ? "\n" + text + "\n" : text;
}
const blueColor = /^(blue|#00f|#0000ff|#0000ee|rgb\(0,0,(255|238)\))$/;
function explicitColor(el: Element) {
  const style = inlineStyle(el);
  if (style && style.color) return style.color;
  return el.tagName === "FONT" ? el.getAttribute("color") || "" : "";
}

/** A fetched page, observed only through its markup. */
export function staticView(href: string): View {
  return {
    url: () => href,
    visible(el) {
      if (el.closest('[hidden],[inert],[aria-hidden="true"]')) return false;
      for (let parent: Element | null = el; parent; parent = parent.parentElement)
        if (staticallyHidden(parent)) return false;
      return true;
    },
    text(el) {
      // Mirror innerText: a hidden descendant contributes nothing and a
      // line break or block boundary separates words.
      let text = "";
      for (const child of Array.from(el.childNodes)) text += staticText(child);
      return text;
    },
    blue(el) {
      // Without explicit markup on the entry itself there is no evidence of permission.
      for (
        let parent: Element | null = el;
        parent && !/^(TD|TH|TR|TABLE|BODY|HTML)$/.test(parent.tagName);
        parent = parent.parentElement
      ) {
        const color = explicitColor(parent);
        if (color) return blueColor.test(color.toLowerCase().replace(/\s/g, ""));
      }
      return false;
    },
  };
}

export function extractor(view: View) {
  const visible = (el: Element) => view.visible(el);
  function leaf(el: Element | null) {
    if (
      !el ||
      el.querySelector(
        'table,form,input,textarea,select,iframe,script,style,[hidden],[aria-hidden="true"]',
      )
    )
      return "";
    return normalized(view.text(el));
  }
  function label(el: Element | null) {
    return leaf(el).replace(/\s/g, "");
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
    const page = new URL(view.url(doc));
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
    if ((grade || registration || hasHeading(doc, studentInquiryName)) && profile(doc)) kinds.push("profile");
    return kinds;
  }
  function header(table: HTMLTableElement, kind: AcademicKind) {
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
  function tableData(table: HTMLTableElement, kind: AcademicKind): Table | null {
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
      const blue = view.blue(link.querySelector("font,span") || link);
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
  function admissionYear(root: ParentNode) {
    const years = new Set<string>();
    for (const cell of Array.from(root.querySelectorAll("th,td,dt"))) {
      const name = label(cell);
      if (name !== "入学年度" && name !== "入学年月" && name !== "入学年月日") continue;
      const value = cell.nextElementSibling;
      if (!value || !visible(cell) || !visible(value)) continue;
      const printed = leaf(value).replace(/\s+/g, "");
      if (!printed) continue;
      if (name === "入学年度") {
        years.add(/^((?:19|20)\d{2})(?:年度)?$/.exec(printed)?.[1] || "");
        continue;
      }
      const japanese = /^((?:19|20)\d{2})年(\d{1,2})月(?:(\d{1,2})日)?$/.exec(printed);
      const numeric = /^((?:19|20)\d{2})([-/.])(\d{1,2})(?:\2(\d{1,2}))?$/.exec(printed);
      const year = Number(japanese?.[1] ?? numeric?.[1]);
      const month = Number(japanese?.[2] ?? numeric?.[3]);
      const day = Number(japanese?.[3] ?? numeric?.[4] ?? "1");
      const utc = new Date(Date.UTC(year, month - 1, day));
      const academicYear = month < 4 ? year - 1 : year;
      years.add(academicYear >= 1900 && utc.getUTCMonth() === month - 1 && utc.getUTCDate() === day ? String(academicYear) : "");
    }
    return years.size === 1 ? [...years][0] || undefined : undefined;
  }

  function profile(doc: Document) {
    const matches: { table: HTMLTableElement; data: Table }[] = [];
    for (const table of Array.from(doc.querySelectorAll("table")).filter(visible)) {
      if (header(table, "grades") || header(table, "registration") ||
          header(table, "balances") || table.querySelector("form,table")) continue;
      const cells = Array.from(table.rows).flatMap((row) => Array.from(row.cells))
        .filter(visible);
      const values = (key: string) => cells
        .filter((cell) => label(cell) === key && cell.nextElementSibling && visible(cell.nextElementSibling))
        .map((cell) => leaf(cell.nextElementSibling));
      const affiliations = values("所属");
      const grades = values("学年");
      if (affiliations.length !== 1 || grades.length > 1) continue;
      const affiliation = safeText(affiliations[0]);
      if (!affiliation) continue;
      const grade = grades[0] || "";
      matches.push({ table, data: {
        heading: names.profile,
        rows: [["所属", "学年"], [affiliation, /^[1-6]$/.test(grade) ? grade : ""]],
      } });
    }
    return matches.length === 1 ? matches[0] : null;
  }

  function academicTables(doc: Document, kind: Kind) {
    if (kind === "profile") {
      const projected = profile(doc);
      return projected ? [projected.table] : [];
    }
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
  function packet(
    doc: Document,
    kind: Kind,
    current = academicTables(doc, kind),
  ): Packet | null {
    if (kind === "profile") {
      const projected = profile(doc);
      if (!projected) return null;
      const year = admissionYear(hasHeading(doc, studentInquiryName) ? doc : projected.table);
      return { v: 1, kind, tables: [projected.data], ...(year ? { year } : {}) };
    }
    const tables = current
      .map((t) => tableData(t, kind))
      .filter((t): t is Table => !!t);
    const grid = kind === "registration" ? timetable(doc) : null;
    if (grid) tables.unshift(grid);
    if (!withinBounds(tables)) return null;
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
    const year = years.size === 1 ? Array.from(years)[0] : undefined;
    return {
      v: 1,
      kind,
      tables: kind === "registration" && year ? tables.map(({ heading, rows }) => {
        if (rows[0].includes("年度")) return { heading, rows };
        // A combined capture can drop its packet-level year. Keep the printed
        // scope on tables such as denials that carry no year in the original row.
        return { heading, rows: [["年度", ...rows[0]], ...rows.slice(1).map(row => [year, ...row])] };
      }) : tables,
      ...(year ? { year } : {}),
    };
  }
  return { visible, pageKinds, academicTables, profile, admissionYear, packet };
}

export function withinBounds(tables: Table[]) {
  return (
    tables.length > 0 &&
    tables.length <= 50 &&
    tables.reduce((n, t) => n + t.rows.length, 0) <= 6000
  );
}
