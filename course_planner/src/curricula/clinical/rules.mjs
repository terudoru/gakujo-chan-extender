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
export function residency(key, label, required, source, field = "enrolledMonths") {
  return {
    key,
    label,
    required,
    source,
    kind: "在学期間",
    unit: "months",
    profileValue: (p) => {
      const raw = p[field];
      return raw != null && raw !== "" && Number.isInteger(Number(raw)) && Number(raw) >= 0 ? Number(raw) : null;
    },
  };
}
export function isSpecial(p) {
  return /編入|転部|再入学|転入/.test(p.entry ?? "");
}
export function recognition(p, office, src) {
  return isSpecial(p)
    ? [
      condition(
        "recognized-credits",
        "既修得単位の認定区分",
        office + "で認定された科目と算入区分を履修科目確認表で照合してください。",
        src,
      ),
      condition(
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

// One pool uses each credit once. Narrow rows precede the rows that take their surplus.
export function subtotal(key, label, required, leaves, src, extra = {}) {
  const match = combined(...leaves.map((r) => r.match));
  return credits(key, label, required, match, src, {
    kind: "区分計",
    evaluate: ({ courses, profile }) => {
      const available = courses.map((c) => Number(c.credits) || 0);
      const used = courses.map(() => 0);
      let uncertain = false;
      for (const row of leaves) {
        let need = row.required;
        for (let i = 0; i < courses.length && need > 0; i++) {
          if (!available[i]) continue;
          const result = row.match(courses[i], profile);
          if (result == null) uncertain = true;
          if (result !== true) continue;
          const units = Math.min(available[i], need);
          available[i] -= units;
          need -= units;
          used[i] += units;
        }
      }
      const value = used.reduce((sum, v) => sum + v, 0);
      return {
        value,
        contributions: courses.flatMap((c, i) => used[i] ? [contribution(c, used[i])] : []),
        ...(uncertain && value < required ? { unknown: "科目の開講元・便覧上の区分を学務係で確認してください。" } : {}),
      };
    },
    ...extra,
  });
}

export const stageApproval = (office, src) =>
  condition("graduation-review", "卒業の認定", office + "で教授会の議を経た卒業認定結果を確認してください。", src);
