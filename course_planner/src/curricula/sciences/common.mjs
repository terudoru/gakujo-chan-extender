// Rule predicates distinguish a known mismatch from missing course identity.
export const norm = (value) =>
  String(value ?? "")
    .normalize("NFKC")
    .replace(/\s/g, "")
    .toLowerCase();
export const name = (c) => norm(c.title);
export const urlPage = (book, page, title) => ({
  title,
  url: book.url + (page ? "#page=" + page : ""),
});
export const row = (
  key,
  label,
  kind,
  required,
  match,
  source,
  options = {},
) => ({ key, label, kind, required, match, source, ...options });
export const check = (key, label, reason, source) => ({
  key,
  label,
  kind: "要確認",
  required: null,
  unit: "condition",
  unknown: reason,
  source,
});
export const decision = (key, label, note, source) => ({
  key,
  label,
  kind: "学務判定",
  unit: "condition",
  required: 1,
  officialDecision: true,
  note,
  source,
});
export const months = (n, source, year) => ({
  key: year ? "year-" + year + "-months" : "months",
  label: year ? year + "年次での在学期間" : "通算在学期間",
  kind: "在学",
  unit: "months",
  required: n,
  source,
  profileValue(p) {
    const v = year
      ? (p.yearAttendanceMonths?.[year] ??
        p.yearMonths?.[year] ??
        (Number(p.yearOfStudy ?? p.currentYear) === year
          ? p.currentYearMonths
          : null))
      : (p.attendanceMonths ?? p.enrolledMonths ?? p.enrollmentMonths);
    return v != null && /^\d+$/.test(String(v)) ? Number(v) : null;
  },
});
export const stage = (id, label, rows) => ({
  id,
  label,
  goal: id === "graduation" ? "graduation" : "progress",
  rows,
});
export const isThirdTransfer = (p) =>
  /^(?:第)?3年次編入(?:学)?(?:生)?$/.test(norm(p.entry)) ||
  (p.entry === "編入" && String(p.entryGrade) === "3");
export const irregular = (p) =>
  !!p.entry && !["1年次入学", "一般入学", "通常入学"].includes(p.entry);
export function confirmed(c) {
  return (
    !!c.code &&
    !c.ambiguous &&
    !c.codeAmbiguous &&
    !c.needsConfirmation &&
    !["ambiguous", "unmatched"].includes(c.matchStatus) &&
    c.counts !== false
  );
}
export function type(c) {
  return confirmed(c)
    ? String(c.code)
        .match(/^\d{3}([A-Z])[A-Z\d]{4,5}$/i)?.[1]
        ?.toUpperCase()
    : null;
}
export const night = (c) =>
  !!(
    c.nightCourse ||
    c.category?.includes("夜間主") ||
    c.title?.includes("夜間主")
  );
export const categories = [
  "大学学習法",
  "英語",
  "初修外国語",
  "健康・スポーツ",
  "情報リテラシー",
  "自然系共通専門基礎",
  "自然科学",
  "人文社会・教育科学",
  "新潟大学個性化科目",
  "医歯学",
  "留学生基本科目",
];
export const category = (c) =>
  c.category === "健康とスポーツ" ? "健康・スポーツ" : c.category;
export function record(c, applied, reason) {
  return {
    title: c.title,
    code: c.code ?? "",
    year: String(c.year || courseYear(c) || ""),
    credits: c.credits,
    applied,
    ...(reason && { reason }),
  };
}
// Group caps (e.g. six E credits for fourth-year progression) apply to the
// entire transcript. Output carries the course and only the part actually used.
export function capped(classify, caps = {}) {
  return ({ courses }) => {
    const used = new Map(),
      contributions = [];
    let missing = false;
    for (const c of [...courses].sort((a, b) =>
      String(a.code).localeCompare(String(b.code)),
    )) {
      const bucket = classify(c);
      if (bucket == null) {
        missing = true;
        continue;
      }
      if (bucket === false) continue;
      if (c.credits == null || !Number.isFinite(Number(c.credits))) {
        missing = true;
        continue;
      }
      const prior = used.get(bucket) ?? 0;
      const limit = Object.hasOwn(caps, bucket) ? caps[bucket] : Infinity;
      const amount = Math.min(Number(c.credits), Math.max(0, limit - prior));
      if (amount > 0) {
        used.set(bucket, prior + amount);
        contributions.push(record(c, amount));
      }
    }
    return {
      value: [...used.values()].reduce((a, b) => a + b, 0),
      contributions,
      ...(missing && {
        unknown:
          "算入区分または単位数を確認できない科目があります。学部学務係の確認表と照合してください。",
      }),
    };
  };
}
export function programFor(p, list) {
  const str = norm(p.program);
  return list.find((key) => str.includes(norm(key))) ?? "";
}
export function courseYear(c) {
  const explicit = Number(c.catalogYear || c.year);
  return explicit || (type(c) ? 2000 + Number(c.code.slice(0, 2)) : null);
}
export function intensive(c) {
  return c.period === "集中" || c.schedule === "集中" || c.intensive === true;
}
export function transferRow(p, source, faculty) {
  return irregular(p)
    ? [
        decision(
          "recognition",
          "既修得単位と在学期間の認定",
          faculty +
            "学務係の認定通知で適用年度・在学期間・各科目の充当区分を確認してください。",
          source,
        ),
      ]
    : [];
}
