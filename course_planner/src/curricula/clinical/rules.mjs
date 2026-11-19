import { syllabusSection } from "./catalog-sections.mjs";
export const norm = (value) => String(value ?? "").normalize("NFKC").replace(/\s+/g, "").toLowerCase();
export const source = (title, url) => ({ title, url });
export const act = (id, anchor = "") => "https://public1.legalcrud.com/niigata_univ/act/" + id + ".html" + anchor;
export const credits = (key, label, required, match, source, extra = {}) => ({
  key,
  label,
  kind: "必修",
  required,
  unit: "credits",
  match,
  source,
  ...extra,
});
export const condition = (key, label, unknown, source) => ({
  key,
  label,
  kind: "確認",
  required: null,
  unit: "condition",
  unknown,
  source,
});
// A scoped official decision supplies current=1 (confirmed) or 0 (not met).
// Its result is independent of earned courses and of the student's other stages.
export const decision = (key, label, unknown, source) => ({
  ...condition(key, label, unknown, source),
  required: 1,
  profileValue: () => null,
});
export const unknownCredits = (key, label, unknown, source) => ({
  ...condition(key, label, unknown, source),
  unit: "credits",
});
export const stage = (id, label, goal, rows, sources) => ({ id, label, goal, rows, sources });
export const combined = (...matches) => (course, profile) => {
  let unknown = false;
  for (const match of matches) {
    const result = match(course, profile);
    if (result === true) return true;
    if (result == null) unknown = true;
  }
  return unknown ? null : false;
};

export function named(titles, department, creditValue, codeFamily) {
  const names = new Set([titles].flat().map(norm));
  return (c) => {
    if (!c.title) return null;
    if (!names.has(norm(c.title))) return false;
    if (department && c.department && !department.split("|").includes(c.department)) return false;
    if (creditValue != null && c.credits != null && Number(c.credits) !== creditValue) return false;
    if (codeFamily) {
      if (!c.code) return null;
      if (!codeFamily.test(c.code)) return false;
    }
    return c.department || (codeFamily && c.code) ? true : null;
  };
}

export function category(...categories) {
  return (c) => {
    if (!c.category) return null;
    if (!categories.includes(c.category)) return false;
    // A faculty subject can carry the same syllabus category as a general subject.
    return c.department ? c.department === "84" : null;
  };
}

export const generalCategories = [
  "英語",
  "初修外国語",
  "健康・スポーツ",
  "情報リテラシー",
  "新潟大学個性化科目",
  "留学生基本科目",
  "大学学習法",
  "自然系共通専門基礎",
  "自然科学",
  "人文社会・教育科学",
  "医歯学",
];
export function subcategory(main, sub, knownTitle) {
  return (c) => {
    const base = category(main)(c);
    if (base !== true) return base;
    if (c.subcategory) return c.subcategory === sub;
    if (knownTitle && knownTitle.test(norm(c.title))) return true;
    const official = syllabusSection(c);
    return official && !["心理学", "社会学"].includes(sub) ? official === sub : null;
  };
}
export function wholeNumber(value) {
  if (typeof value !== "number" && (typeof value !== "string" || !/^\d+$/.test(value.trim()))) return null;
  const n = Number(value);
  return Number.isSafeInteger(n) && n >= 0 ? n : null;
}
export function residency(key, label, required, source, year) {
  return {
    key,
    label,
    required,
    source,
    kind: "在学期間",
    unit: "months",
    note: year
      ? "休学を除く当該年次の認定月数を使用します。"
      : "休学を除く、当該課程で通算を認められた在学月数を使用します。",
    profileValue: (p) => {
      if (year == null) {
        return wholeNumber(Object.hasOwn(p, "attendanceMonths") ? p.attendanceMonths : p.enrolledMonths);
      }
      const raw = Object.hasOwn(p, "yearAttendanceMonths") ? p.yearAttendanceMonths?.[year] : p["monthsInYear" + year];
      return wholeNumber(raw);
    },
  };
}
export function assessmentInApril(p) {
  if (typeof p.assessmentDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(p.assessmentDate)) return null;
  const d = new Date(p.assessmentDate + "T00:00:00Z");
  if (!Number.isFinite(d.getTime()) || d.toISOString().slice(0, 10) !== p.assessmentDate) return null;
  return Number(d.getUTCMonth() === 3);
}
export function isSpecial(p) {
  return /編入|転部|再入学|転入/.test(p.entry ?? "");
}
export function recognition(p, office, src) {
  return isSpecial(p)
    ? [
      decision(
        "recognized-credits",
        "既修得単位の認定区分",
        office + "で認定された科目と算入区分を履修科目確認表で照合してください。",
        src,
      ),
      decision(
        "recognized-period",
        "通算を認められた在学期間",
        office + "で認定された在学期間を確認してください。",
        src,
      ),
    ]
    : [];
}
export function contribution(c, applied) {
  return { title: c.title, code: c.code ?? "", year: c.year ?? "", credits: c.credits, applied };
}

// The shared engine combines confirmed balances and course evidence. Each leaf
// contributes up to its own requirement, even when several categories overlap.
export function subtotal(key, label, required, leaves, src, extra = {}) {
  return credits(key, label, required, combined(...leaves.map((r) => r.match ?? (() => null))), src, {
    kind: "区分計",
    disjoint: true,
    pool: leaves.map((r) => ({ key: r.key, cap: r.required ?? undefined })),
    allocationKeys: leaves.flatMap((r) => [r.key, ...(r.allocationKeys ?? [])]),
    ...extra,
  });
}

export const stageApproval = (office, src) =>
  decision("graduation-review", "卒業の認定", office + "で教授会の議を経た卒業認定結果を確認してください。", src);
