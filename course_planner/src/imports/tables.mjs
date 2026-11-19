import { normalize } from "../study.mjs";

export const kinds = ["grades", "registration", "balances"];

const labels = {
  code: ["開講番号", "開講コード", "科目コード", "授業コード", "時間割コード"],
  title: ["科目名", "授業科目", "授業科目名", "授業名", "講義名", "開講科目名"],
  credits: ["単位", "単位数", "修得単位", "修得単位数", "取得単位数"],
  grade: ["評価", "成績", "評語", "合否", "成績評価", "評価区分"],
  year: ["年度", "開講年度", "履修年度", "修得年度", "取得年度"],
  term: ["学期", "履修学期", "修得学期", "ターム"],
  section: ["クラス", "クラス名", "組", "クラス番号"],
  courseId: ["科目番号", "科目ID", "授業ID", "授業科目ID"],
  offeringDepartment: ["開講所属", "開講所属コード", "開講学部", "開設学部"],
  alternativeTitle: ["旧科目名", "旧名称", "読替科目名", "対応科目名"],
  duplicate: ["重複", "重複区分", "重複履修"],
  category: [
    "区分",
    "区分名",
    "科目区分",
    "単位区分",
    "要件区分",
    "算入区分",
    "認定区分",
    "要件名",
  ],
  status: [
    "状態",
    "状況",
    "登録状況",
    "履修状況",
    "申請状況",
    "許可状況",
    "許可区分",
    "履修許可",
    "履修許可状況",
    "結果",
    "抽選結果",
    "申請結果",
    "登録結果",
  ],
  current: [
    "既修得",
    "既修得単位",
    "既修得単位数",
    "修得済み",
    "修得済単位数",
    "修得済み単位数",
    "修得単位",
    "修得単位数",
    "修得単位計",
    "これまで修得した単位",
  ],
  day: ["既修得単位(昼間)", "既修得単位数(昼間)", "既修得単位昼間"],
  night: ["既修得単位(夜間)", "既修得単位数(夜間)", "既修得単位夜間"],
  required: [
    "必要単位",
    "必要単位数",
    "卒業要件単位",
    "所要単位数",
    "基準単位数",
  ],
  kind: ["履修区分", "必選区分", "必選"],
};
const columns = {
  grades: [
    "code",
    "title",
    "credits",
    "grade",
    "year",
    "section",
    "term",
    "courseId",
    "offeringDepartment",
    "alternativeTitle",
    "duplicate",
    "category",
  ],
  registration: ["code", "title", "year", "status"],
  balances: ["category", "current", "day", "night", "required", "kind"],
};
const headings = Object.fromEntries(
  Object.entries(columns).map(([kind, keys]) => [
    kind,
    new Map(
      keys.flatMap((key) =>
        labels[key].map((label) => [normalize(label), key]),
      ),
    ),
  ]),
);
export function headerColumns(kind, cells) {
  const keys = cells.map((cell) => headings[kind].get(normalize(cell)));
  const has = (key) => keys.includes(key);
  const enough =
    kind === "balances"
      ? has("category") && (has("current") || (has("day") && has("night")))
      : kind === "grades"
        ? (has("title") || has("code")) && has("grade") && has("credits")
        : has("code");
  if (!enough) return null;
  return {
    keys,
    ambiguous: keys.some((key, i) => key && keys.indexOf(key) !== i),
  };
}

const outcomes = {
  申請中: [
    "申請中",
    "申請済",
    "申請済み",
    "抽選待ち",
    "履修申請中",
    "許可待ち",
  ],
  許可: ["許可", "許可済", "許可済み", "履修許可"],
  不許可: ["不許可", "履修不許可"],
};
export function rowStatus(text) {
  return Object.keys(outcomes).find((key) =>
    outcomes[key].includes(normalize(text)),
  );
}
export function sectionStatus(heading) {
  const clean = normalize(heading).replace(/^[【\[■◆]+|[】\]:]+$/gu, "");
  if (
    /^(?:不許可となった|不許可の|不許可された|履修不許可の)科目(?:一覧)?$/.test(
      clean,
    )
  )
    return "不許可";
  if (
    /^(?:許可となった|許可された|許可の|履修許可された)科目(?:一覧)?$/.test(
      clean,
    )
  )
    return "許可";
  if (/^(?:申請中の?|申請済みの?|抽選待ちの?)科目(?:一覧)?$/.test(clean))
    return "申請中";
  return rowStatus(clean.replace(/科目(?:一覧)?$/, ""));
}
export function readYear(text) {
  return /^(\d{4})(?:年度)?$/.exec(normalize(text))?.[1] ?? "";
}
export function readUnits(text, max = 9999) {
  const value = normalize(text);
  if (!/^\d{1,4}(?:\.\d{1,2})?(?:単位)?$/.test(value)) return null;
  const n = Number(value.replace("単位", ""));
  return n <= max ? n : null;
}

export function validatePacket(packet) {
  const invalid = () => {
    throw Error("学務の表の形式またはサイズを確認してください。");
  };
  if (
    packet?.v !== 1 ||
    !kinds.includes(packet.kind) ||
    !Array.isArray(packet.tables) ||
    packet.tables.length > 300 ||
    (packet.year != null &&
      (typeof packet.year !== "string" || !/^\d{4}$/.test(packet.year)))
  )
    invalid();
  let count = 0,
    length = 0;
  for (const table of packet.tables) {
    if (
      typeof table?.heading !== "string" ||
      table.heading.length > 256 ||
      !Array.isArray(table.rows)
    )
      invalid();
    count += table.rows.length;
    if (count > 12000) invalid();
    for (const cells of table.rows) {
      if (!Array.isArray(cells) || cells.length > 120) invalid();
      for (const cell of cells) {
        if (typeof cell !== "string" || cell.length > 4096) invalid();
        length += cell.length;
      }
      if (length > 2000000) invalid();
    }
  }
  return packet;
}

// The published balance table has grouped 履修単位 and 既修得単位 columns,
// each split into 昼間 and 夜間. Never use the former as earned credits.
export function balanceHeader(first, second = []) {
  const top = first.map(normalize).filter(Boolean);
  const sub = second.map(normalize).filter(Boolean);
  if (
    !["区分", "科目区分"].includes(top[0]) ||
    top[1] !== "履修単位" ||
    !["既修得単位", "既修得単位数"].includes(top[2]) ||
    sub.join("/") !== "昼間/夜間/昼間/夜間"
  )
    return null;
  return [
    "区分",
    "履修単位(昼間)",
    "履修単位(夜間)",
    "既修得単位(昼間)",
    "既修得単位(夜間)",
    ...top.slice(3),
  ];
}

export function scanTables(packet, visit, issue) {
  validatePacket(packet);
  for (const [t, table] of packet.tables.entries()) {
    let header = null,
      status = sectionStatus(table.heading),
      heading = table.heading;
    let scopedYear = readYear(table.heading) || packet.year || "";
    for (let n = 0; n < table.rows.length; n++) {
      let cells = table.rows[n].map((s) => s.normalize("NFKC").trim());
      const id = t + 1 + "-" + (n + 1);
      const nonempty = cells.filter(Boolean);
      if (!nonempty.length) continue;
      if (packet.kind === "balances") {
        const expanded = balanceHeader(cells, table.rows[n + 1]);
        if (expanded) {
          cells = expanded;
          n++;
        }
      }
      const next = headerColumns(packet.kind, cells);
      if (next) {
        header = next;
        continue;
      }
      if (nonempty.length === 1) {
        const only = nonempty[0];
        if (packet.kind === "grades" && normalize(only) === "成績確認表") {
          heading = "成績確認表";
          header = null;
          continue;
        }
        if (/^\d{4}\s*年度$/.test(only)) {
          scopedYear = readYear(only);
          continue;
        }
        // A section boundary must never carry an earlier denial/approval on to its rows.
        if (
          packet.kind === "registration" &&
          !/^\d{3}[A-Z][A-Z0-9]{4,5}(?:\s*\(T[1-4, ]+\))?$/.test(only)
        ) {
          status = sectionStatus(only);
          if (!status) header = null;
          continue;
        }
      }
      if (!header || header.ambiguous) {
        issue(id, "列見出しを特定できません。");
        continue;
      }
      if (cells.length !== header.keys.length) {
        issue(id, "列数が見出しと一致しません。");
        continue;
      }
      const values = Object.fromEntries(
        header.keys.flatMap((key, i) => {
          if (!key) return [];
          // Keep the transcript spelling (e.g. Ⅰ vs I) on the durable record.
          const value =
            key === "title" || key === "alternativeTitle"
              ? table.rows[n][i].trim()
              : cells[i];
          return [[key, value]];
        }),
      );
      visit(values, { id, status, year: scopedYear, heading });
    }
  }
}

export function delimitedRows(text) {
  if (text.includes("\0"))
    throw Error("テキストの文字コードまたは形式を確認してください。");
  text = text.replace(/^\uFEFF/, "");
  if (text.length > 2000000) throw Error("テキストの表が大きすぎます。");
  let separator = ",";
  // Preambles need not use the table's delimiter. Find a labelled header
  // even when an earlier CSV title contains a literal tab.
  for (const [line] of text.matchAll(/[^\r\n]+/g)) {
    const delimiter = ["\t", ","].find((d) => {
      if (!line.includes(d)) return false;
      const cells = line
        .split(d, 121)
        .map((c) => c.trim().replace(/^"|"$/g, ""));
      return kinds.some((kind) => headerColumns(kind, cells));
    });
    if (delimiter) {
      separator = delimiter;
      break;
    }
  }
  if (separator === "," && !text.includes(",") && text.includes("\t"))
    separator = "\t";
  const rows = [];
  let row = [],
    cell = "",
    quoted = false,
    closed = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') {
        cell += '"';
        i++;
      } else if (quoted) {
        quoted = false;
        closed = true;
      } else if (!cell && !closed) quoted = true;
      else throw Error("CSVの引用符を確認してください。");
    } else if (!quoted && (c === separator || c === "\n" || c === "\r")) {
      row.push(cell);
      if (row.length > 120 || rows.length >= 12000)
        throw Error("表の行数または列数が多すぎます。");
      cell = "";
      closed = false;
      if (c !== separator) {
        rows.push(row);
        row = [];
        if (c === "\r" && text[i + 1] === "\n") i++;
      }
    } else if (closed && c.trim())
      throw Error("CSVの引用符を確認してください。");
    else cell += c;
  }
  if (quoted) throw Error("CSVの引用符を確認してください。");
  if (cell || row.length || closed) rows.push([...row, cell]);
  return rows;
}
