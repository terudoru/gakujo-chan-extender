import { normalize, syllabusURL } from "./study.mjs";
import { scanTables, readYear, readUnits } from "./imports/tables.mjs";
export { delimitedRows } from "./imports/tables.mjs";

const pass = /^(?:秀|優|良|可|合格|修得|認定|S|A\+?|B\+?|C\+?|P)$/i;
const notEarned = /^(?:不可|不合格|未修得|履修中|未確定|欠席|放棄|F|D)$/i;

function identity(row) {
  return JSON.stringify(
    [row.year, row.code, row.title, row.section, row.term, row.courseId].map(
      normalize,
    ),
  );
}
function evidence(row) {
  return JSON.stringify(
    [
      row.credits,
      row.grade,
      row.alternativeTitle,
      row.allocationLabel,
      !!row.duplicate,
    ].map(normalize),
  );
}
function namesIndex(records) {
  const titles = new Map(),
    aliases = new Map();
  function add(record) {
    for (const [index, name] of [
      [titles, record.title],
      [aliases, record.alternativeTitle],
    ]) {
      if (!name) continue;
      const key = normalize(name);
      if (!index.has(key)) index.set(key, new Set());
      index.get(key).add(record);
    }
  }
  function hasAlternative(row) {
    const oldNames = titles.get(normalize(row.alternativeTitle)) ?? [];
    const newNames = aliases.get(normalize(row.title)) ?? [];
    return [...oldNames, ...newNames].some(
      (other) =>
        identity(other) !== identity(row) &&
        (normalize(other.title) === normalize(row.alternativeTitle) ||
          normalize(other.alternativeTitle) === normalize(row.title)),
    );
  }
  records.forEach(add);
  return { titles, add, hasAlternative };
}
export function reviewGrades(
  packet,
  { byCode = new Map(), catalogYear = 2026, grades = [] } = {},
) {
  const rows = [];
  const nonEarned = new Set();
  const issue = (id, reason) => rows.push({ id, label: "要確認", reason });
  scanTables(
    packet,
    (v, origin) => {
      const year = v.year ? readYear(v.year) : origin.year;
      const code = v.code?.toUpperCase() || "";
      const lookup = year && byCode.get(code);
      const offering =
        lookup && String(lookup.year ?? catalogYear) === year ? lookup : null;
      const title = v.title || offering?.title;
      const label =
        [code, title].filter(Boolean).join(" ") || "科目を特定できない行";
      if (notEarned.test(v.grade)) {
        if (title) nonEarned.add(identity({ ...v, year, code, title }));
        rows.push({
          id: origin.id,
          label,
          skipped: true,
          reason: v.grade + "（修得単位に含みません）",
        });
        return;
      }
      const starred = /^\s*\*/.test(v.credits);
      const credits = readUnits(v.credits?.replace(/^\s*\*\s*/, ""), 99);
      if (
        !pass.test(v.grade) ||
        !credits ||
        !title ||
        (code && !/^[A-Z0-9][-A-Z0-9]{2,19}$/.test(code)) ||
        (v.year && !year)
      ) {
        rows.push({
          id: origin.id,
          label,
          reason: "科目・単位数・評価・履修年度の列を確認してください。",
        });
        return;
      }
      const recognized = v.grade === "認定";
      const duplicate =
        v.duplicate === "重複" ||
        v.duplicate === "重複単位" ||
        (starred && normalize(origin.heading) === "成績確認表");
      const starUnclear =
        (starred && !duplicate) ||
        (v.duplicate &&
          !["重複", "重複単位", "なし", "-", "無"].includes(v.duplicate));
      const match =
        offering &&
        normalize(offering.title) === normalize(title) &&
        (!v.section || normalize(offering.section) === normalize(v.section)) &&
        (!v.courseId ||
          normalize(offering.courseId) === normalize(v.courseId)) &&
        (offering.credits == null || offering.credits === credits);
      const grade = {
        year,
        code,
        title,
        credits,
        grade: v.grade,
        section: v.section || "",
        term: v.term || "",
        courseId: v.courseId || "",
        alternativeTitle: v.alternativeTitle || "",
        recognized,
        allocationLabel: v.category || "",
        duplicate,
        counts: !duplicate && !starUnclear,
        source: ["単位修得状況照会", "成績確認表"].includes(
          normalize(origin.heading),
        )
          ? normalize(origin.heading)
          : "成績表",
        fields: match ? [...(offering.fields ?? [])] : [],
        category: match ? offering.category || "" : "",
        department: match ? offering.department || "" : "",
      };
      if (match) {
        grade.matchedCourse = {
          year,
          code,
          title: offering.title,
          department: grade.department,
          fields: [...grade.fields],
          category: grade.category,
          sourceUrl: offering.sourceUrl || syllabusURL(offering, year),
          confirmed: true,
        };
      }
      const notes = [];
      if (duplicate) notes.push("重複単位のため算入しません。");
      if (starUnclear)
        notes.push("要確認：重複記号の意味を確認できないため算入しません。");
      if (!match)
        notes.push("要確認：履修年度のシラバスとの対応が未確認です。");
      if (recognized && !grade.allocationLabel)
        notes.push(
          "要確認：認定単位の算入先は所属学部の認定結果で確認してください。",
        );
      if (grade.alternativeTitle)
        notes.push(
          "読替科目「" +
            grade.alternativeTitle +
            "」との重複を確認してください。",
        );
      rows.push({
        id: origin.id,
        label,
        value: grade,
        reason: notes.join(" "),
      });
    },
    issue,
  );

  // Weak name-only entries can represent several sections. Keep the evidence
  // and each occurrence, without silently counting or overwriting either one.
  const groups = new Map();
  for (const row of rows) {
    if (!row.value) continue;
    const key = identity(row.value);
    if (nonEarned.has(key)) {
      delete row.value;
      row.reason =
        "要確認：同じ履修情報に修得と未修得の両方が記載されています。";
      continue;
    }
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  for (const [key, group] of groups) {
    const seen = new Map();
    const first = group[0].value;
    const repeated =
      (first.code || first.courseId) &&
      group.every((r) => evidence(r.value) === evidence(first));
    for (const row of group) {
      const g = row.value;
      if (group.length > 1 && repeated) {
        g.importId = key;
      } else if (group.length > 1 || (!g.code && !g.courseId)) {
        const variant = evidence(g),
          occurrence = seen.get(variant) ?? 0;
        seen.set(variant, occurrence + 1);
        g.importId = JSON.stringify([key, variant, occurrence]);
        if (group.length > 1) {
          g.identityUncertain = true;
          g.counts = false;
          row.reason +=
            " 要確認：同じ履修情報が複数あります。科目を識別できるまで算入しません。";
        }
      } else g.importId = key;
    }
  }
  const names = namesIndex([
    ...grades,
    ...rows.flatMap((r) => (r.value ? [r.value] : [])),
  ]);
  for (const row of rows) {
    const g = row.value;
    if (g && !g.duplicate && names.hasAlternative(g)) {
      g.possibleDuplicate = true;
      g.counts = false;
      row.reason +=
        " 要確認：読替名の科目も履歴にあります。同じ単位か照合してください。";
    }
  }
  return rows;
}

// Compatibility for the original transcript dialog.
export function reviewGradeRows(rows, byCode) {
  const parsed = reviewGrades(
    { v: 1, kind: "grades", tables: [{ heading: "成績確認表", rows }] },
    { byCode },
  );
  return {
    candidates: parsed.flatMap((r) => (r.value ? [r.value] : [])),
    missing: parsed.filter((r) => !r.value && !r.skipped),
  };
}

export function mergeGrades(state, rows) {
  const grades = state.grades.map((g) => ({ ...g }));
  const names = namesIndex(grades);
  for (const incoming of rows) {
    const row = { ...incoming };
    const key = identity(row);
    const sameTitle = [...(names.titles.get(normalize(row.title)) ?? [])];
    const related = sameTitle.filter((g) => identity(g) === key);
    let old = related.find((g) => g.importId && g.importId === row.importId);
    if (!old && (row.code || row.courseId)) {
      const identical = related.filter((g) => evidence(g) === evidence(row));
      if (identical.length === 1) old = identical[0];
    }
    // A PDF and a native table can disagree on which identifying columns are
    // printed. Merge only if they share an offering and no evidence conflicts.
    if (!old && !related.length) {
      const possible = sameTitle.filter((g) =>
        ["year", "code", "term", "section", "courseId"].every(
          (k) => !g[k] || !row[k] || normalize(g[k]) === normalize(row[k]),
        ),
      );
      const previous = possible.length === 1 ? possible[0] : null;
      const confirmed = previous?.matchedCourse;
      const sameOffering =
        previous &&
        row.year &&
        row.code &&
        ((row.year === previous.year && row.code === previous.code) ||
          (confirmed?.confirmed &&
            row.year === String(confirmed.year) &&
            row.code === confirmed.code));
      if (
        sameOffering &&
        row.credits === previous.credits &&
        row.grade === previous.grade &&
        !previous.identityUncertain &&
        !row.identityUncertain
      ) {
        old = previous;
        for (const k of ["section", "term", "courseId"])
          row[k] ||= old[k] || "";
        row.importId = identity(row);
      } else if (possible.length) {
        row.identityUncertain = true;
        row.counts = false;
      }
    }
    if (!old) {
      const legacy = related.filter(
        (g) =>
          !g.importId &&
          (g.code || g.courseId || evidence(g) === evidence(row)),
      );
      if (legacy.length === 1 && !row.identityUncertain) old = legacy[0];
    }
    if (
      !old &&
      related.length === 1 &&
      (row.code || row.courseId) &&
      row.importId === key &&
      !related[0].identityUncertain
    )
      old = related[0];
    if (
      !old &&
      !row.importId &&
      related.length === 1 &&
      (row.code || evidence(row) === evidence(related[0]))
    )
      old = related[0];
    if (!old) {
      if (related.length) {
        row.identityUncertain = true;
        row.counts = false;
      }
      if (!row.duplicateReviewed && names.hasAlternative(row)) {
        row.possibleDuplicate = true;
        row.counts = false;
      }
      grades.push(row);
      names.add(row);
      continue;
    }
    // A repeated file can add source evidence, but cannot undo a reviewed
    // archive association, category, or duplicate decision.
    const confirmed = old.matchedCourse?.confirmed
      ? old.matchedCourse
      : row.matchedCourse;
    const reviewed =
      old.duplicate || old.duplicateReviewed || old.identityUncertain
        ? { counts: old.counts, duplicate: old.duplicate }
        : {};
    const allocation =
      old.allocationKey &&
      (!row.allocationLabel ||
        normalize(old.allocationLabel) === normalize(row.allocationLabel))
        ? {
            allocationKey: old.allocationKey,
            allocationScope: old.allocationScope,
            allocationLabel: old.allocationLabel,
          }
        : {};
    if (
      row.allocationLabel &&
      normalize(old.allocationLabel) !== normalize(row.allocationLabel)
    ) {
      delete old.allocationKey;
      delete old.allocationScope;
    }
    Object.assign(
      old,
      row,
      {
        importId: old.importId || row.importId,
        title: old.title || row.title,
        code: old.code || row.code,
        year: old.year || row.year,
      },
      reviewed,
      allocation,
    );
    names.add(old);
    if (confirmed)
      Object.assign(old, {
        matchedCourse: confirmed,
        fields: confirmed.fields ?? [],
        category: confirmed.category || "",
        department: confirmed.department || "",
      });
    if (row.duplicate) old.duplicate = true;
    if (old.duplicate || old.identityUncertain) old.counts = false;
  }
  state.grades = grades;
}
