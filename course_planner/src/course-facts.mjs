export const normalize = (text) =>
  String(text ?? "")
    .normalize("NFKC")
    .replace(/\s+/gu, "")
    .toLowerCase();

export function termsFor(course) {
  const period = course.period.normalize("NFKC");
  if (period === "通年") return [1, 2, 3, 4];
  if (period.includes("ターム")) {
    const ns = [...period.matchAll(/[1-4]/g)].map((m) => Number(m[0]));
    if (/[~〜～]/.test(period) && ns.length === 2) {
      return [1, 2, 3, 4].filter((n) => n >= ns[0] && n <= ns[1]);
    }
    return ns;
  }
  if (course.semester.includes("1")) return [1, 2];
  if (course.semester.includes("2")) return [3, 4];
  return [];
}

export function slotsFor(course) {
  return course.schedule
    .normalize("NFKC")
    .split(/[,、]/)
    .map((s) => s.trim())
    .filter((s) => /^[月火水木金土日][1-7]$/.test(s));
}
export function hasUnscheduled(course) {
  return course.schedule
    .normalize("NFKC")
    .split(/[,、]/)
    .some((s) => !/^[月火水木金土日][1-7]$/.test(s.trim()));
}
export function syllabusURL(course, year = 2026) {
  if (
    !/^\d{4}$/.test(String(year)) ||
    !/^[A-Z0-9]{2}$/.test(course.department) ||
    !/^\d{3}[A-Z][A-Z0-9]{4,5}$/.test(course.code)
  )
    return null;
  const prefix = `https://syllabus.niigata-u.ac.jp/syllabusHtml/${year}/${course.department}/${course.department}_${course.code}_`;
  if (course.sourceUrl === prefix + "en_US.html") return course.sourceUrl;
  if (course.sourceKind === "public-index" && course.sourceUrl === "https://syllabus.niigata-u.ac.jp/campus-sy/")
    return course.sourceUrl;
  return prefix + "ja_JP.html";
}

export function courseFields(earned, planned, catalogYear) {
  const rows = new Map();
  const countedOfferings = new Set();
  for (const [records, column] of [
    [earned, "earned"],
    [planned, "planned"],
  ]) {
    for (const course of records) {
      if (course.counts === false || course.duplicate === true) continue;
      const offering = course.matchedCourse?.confirmed ? course.matchedCourse : course;
      const year = offering.year || (column === "planned" ? catalogYear : null);
      if (offering.code && year) {
        const key = year + "/" + offering.code;
        if (column === "planned" && countedOfferings.has(key)) continue;
        countedOfferings.add(key);
      }
      const fields = offering.fields?.length ? offering.fields : ["?"];
      for (const field of new Set(fields)) {
        if (!rows.has(field))
          rows.set(field, { field, earned: 0, planned: 0, courses: [] });
        const row = rows.get(field);
        if (Number.isFinite(course.credits)) row[column] += course.credits;
        else row.needsReview = true;
        row.courses.push({ course, column });
      }
    }
  }
  return [...rows.values()].sort((a, b) => a.field.localeCompare(b.field));
}
