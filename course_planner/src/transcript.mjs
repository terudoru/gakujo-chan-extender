import { normalize, validCode } from "./study.mjs";

const pass = /^(?:秀|優|良|可|合格|認定|S|A[+]?|B[+]?|C[+]?|P)$/i;
const fail = /^(?:不可|不合格|未修得|履修中|未確定|欠席|放棄|F|D)$/i;
const headers = {
  code: ["科目コード", "授業コード", "時間割コード", "開講番号"],
  title: ["科目名", "授業科目名", "授業名"],
  credits: ["単位数", "単位", "修得単位"],
  grade: ["評価", "成績", "評語", "合否"],
  year: ["修得年度", "開講年度", "年度"],
};
const numeric = (s) => /^(?:[0-9]|[1-9]\d)(?:\.[05])?$/.test(s);
export function reviewGradeRows(rows, byCode) {
  const candidates = [],
    missing = [];
  let ix = {};
  for (const raw of rows) {
    const cells = raw.map((v) => String(v).normalize("NFKC").trim());
    if (!cells.some(Boolean)) continue;
    const next = Object.fromEntries(
      Object.entries(headers).map(([key, labels]) => [
        key,
        cells.findIndex((v) =>
          labels.some((h) => normalize(v) === normalize(h)),
        ),
      ]),
    );
    if (
      next.grade >= 0 &&
      next.credits >= 0 &&
      (next.title >= 0 || next.code >= 0)
    ) {
      ix = next;
      continue;
    }
    const direct = cells.find(validCode),
      code = ix.code >= 0 ? cells[ix.code] : direct,
      title = ix.title >= 0 ? cells[ix.title] : undefined;
    const value =
      ix.grade >= 0
        ? cells[ix.grade]
        : cells.find((v) => pass.test(v) || fail.test(v));
    if (fail.test(value)) continue;
    if (!code && !title && !value) continue;
    const course = validCode(code) ? byCode.get(code) : null;
    const credits = ix.credits >= 0 ? cells[ix.credits] : undefined;
    if (
      !pass.test(value) ||
      !numeric(credits) ||
      (!course && !title) ||
      Number(credits) <= 0
    ) {
      missing.push({
        label:
          [code, title ?? course?.title].filter(Boolean).join(" ") ||
          "列を確認できない行",
      });
      continue;
    }
    const named = title || course.title;
    const yr = ix.year >= 0 ? cells[ix.year] : null;
    candidates.push({
      code: validCode(code) ? code : "",
      title: named,
      credits: Number(credits),
      year: /^\d{4}$/.test(yr) ? yr : "",
      grade: value,
      fields: course?.fields ?? [],
      category: course?.category ?? "",
      department: course?.department ?? "",
    });
  }
  return { candidates, missing };
}
export function mergeGrades(state, rows) {
  const key = (g) =>
    g.code ? "c:" + g.code : "t:" + normalize(g.title) + "/" + (g.year ?? "");
  const grades = new Map(state.grades.map((g) => [key(g), g]));
  for (const row of rows) grades.set(key(row), row);
  state.grades = [...grades.values()];
}
export function delimitedRows(text) {
  const separator = text.split(/\r?\n/)[0]?.includes("\t") ? "\t" : ",";
  const rows = [];
  let row = [],
    cell = "",
    quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') {
        cell += '"';
        i++;
      } else quoted = !quoted;
    } else if (!quoted && c === separator) {
      row.push(cell);
      cell = "";
    } else if (!quoted && c === "\n") {
      row.push(cell.trimEnd());
      rows.push(row);
      row = [];
      cell = "";
    } else cell += c;
  }
  if (quoted) throw Error("CSVの引用符を確認してください。");
  if (row.length || cell) {
    row.push(cell.trimEnd());
    rows.push(row);
  }
  return rows;
}
