import { normalize, validCode } from "../study.mjs";
import pairs from "./economics-aliases.json" with { type: "json" };
import { compareOfferingEvidence, offeringEvidence } from "./offering-evidence.mjs";

export const searchSource = "https://syllabus.niigata-u.ac.jp/campus-sy/";
export const dentalSource = "https://www.dent.niigata-u.ac.jp/student/syllabus/";
export const economicsTable = "https://www.econ.niigata-u.ac.jp/topics/files/elfinder/gakumu/" +
  encodeURIComponent("読替が可能な経済科学部授業科目一覧.pdf");
export const departments = {
  "01": "人文学部", "03": "教育学部", "04": "法学部", "05": "経済学部",
  "0C": "経済科学部", "06": "理学部", "07": "医学部", "08": "歯学部",
  "09": "工学部", "0A": "農学部", "0B": "創生学部", "84": "全学共通",
};
export const validYear = (year) => /^[1-9]\d{3}$/.test(String(year ?? ""));
export const departmentCode = (name) => Object.hasOwn(departments, name) ? name :
  Object.keys(departments).find((code) => departments[code] === name);
export function courseSource(year, department, code, locale = "ja_JP") {
  if (!validYear(year) || !Object.hasOwn(departments, department) ||
      !validCode(code) || !code.startsWith(String(year).slice(-2)) || !["ja_JP", "en_US"].includes(locale)) return null;
  return `https://syllabus.niigata-u.ac.jp/syllabusHtml/${year}/${department}/${department}_${code}_${locale}.html`;
}

function aliasPage(title, course) {
  const column = { "0C": 0, "05": 1 }[course.department];
  if (column == null) return null;
  return pairs.find((pair) => normalize(pair[column]) === normalize(course.title) &&
    normalize(pair[1 - column]) === normalize(title))?.[2] ?? null;
}

export function officialDocument(value) {
  try {
    const url = new URL(value);
    const host = /^(?:www\.)?(?:dent\.|eng\.|agr\.|sc\.|ed\.|human\.|econ\.|law\.|med\.|clg\.|create\.|iess\.)?niigata-u\.ac\.jp$/;
    return url.protocol === "https:" && host.test(url.hostname) && !url.username && !url.password &&
      !url.port && !url.search && /\.pdf$/i.test(url.pathname) && /^#page=[1-9]\d{0,3}$/.test(url.hash);
  } catch { return false; }
}

function sourceKind(course) {
  if (course.sourceKind) return course.sourceKind;
  // The common sync record guarantees sourceUrl; older peers may omit ancillary provenance fields.
  if (course.sourceUrl === searchSource) return "public-index";
  if (course.sourceUrl === dentalSource + "#p1-syl" + course.year) return "faculty-index";
  if (officialDocument(course.sourceUrl)) return "manual-record";
  return "syllabus";
}

export function validOffering(course) {
  if (!validYear(course?.year) || !Object.hasOwn(departments, course.department) ||
      typeof course.title !== "string" || !course.title.trim() || course.title.length > 300 ||
      !Array.isArray(course.fields) || !course.fields.every((f) => typeof f === "string" && /^\d{2}$/.test(f)) ||
      typeof course.category !== "string" || course.category.length > 100) return false;
  if (course.fieldSource && course.fieldSource !== course.sourceUrl && course.fieldSource !== searchSource &&
      !officialDocument(course.fieldSource)) return false;
  if (course.categorySource && !officialDocument(course.categorySource)) return false;
  const direct = courseSource(course.year, course.department, course.code);
  if (direct && (direct === course.sourceUrl || courseSource(course.year, course.department, course.code, "en_US") === course.sourceUrl)) return true;
  if (direct && course.sourceUrl === searchSource && sourceKind(course) === "public-index") return true;
  if (course.department === "08" && course.code === "" && !course.fields.length && !course.category &&
      course.sourceUrl === dentalSource + "#p1-syl" + course.year && sourceKind(course) === "faculty-index") return true;
  return sourceKind(course) === "manual-record" && officialDocument(course.sourceUrl) &&
    typeof course.code === "string" && /^[\p{L}\d._-]{0,25}$/u.test(course.code);
}

function sameIdentity(grade, course) {
  if (!validOffering(course)) return false;
  if (grade.year && String(grade.year) !== String(course.year)) return false;
  if (grade.code && normalize(grade.code) !== normalize(course.code)) return false;
  // This is the offering faculty printed on the record, independent of the student's faculty.
  for (const dept of [grade.offeringDepartment, grade.offeringFaculty, grade.department].filter(Boolean)) {
    if (departmentCode(dept) !== course.department) return false;
  }
  return grade.title ? normalize(grade.title) === normalize(course.title) || !!aliasPage(grade.title, course) :
    !!grade.code;
}

function checkedOffering(grade, course, index) {
  if (!sameIdentity(grade, course) || compareOfferingEvidence(grade, course) === "conflict") return null;
  if (!index) return course;
  if (String(course.year) !== index.year) return null;
  const possible = course.code ? index.byCode.get(normalize(course.code)) : index.byTitle.get(normalize(course.title));
  if (!possible?.length) return course;
  const scoped = possible.filter((c) => c.department === course.department);
  if (!scoped.length) return course.code ? null : course;
  const consistent = scoped.filter((c) => sameIdentity(grade, c) && normalize(c.title) === normalize(course.title) &&
    compareOfferingEvidence(grade, c) !== "conflict" && compareOfferingEvidence(course, c) !== "conflict");
  if (!consistent.length) return null;
  // A unique known code can restore evidence omitted by an older sync client. Never copy another section's facts.
  return course.code && consistent.length === 1
    ? { ...course, ...offeringEvidence(consistent[0]), ...offeringEvidence(course) } : course;
}

// Only the source's qualifying details are persisted. The original transcript stays on the grade.
export function confirmHistoricalMatch(grade, candidate, index) {
  const course = checkedOffering(grade, candidate, index);
  if (!course) throw Error("履修年度・開講所属・科目・学期・クラス・単位数の対応を確認してください。");
  const alias = aliasPage(grade.title, course);
  return {
    year: String(course.year), code: course.code, department: course.department,
    title: course.title, fields: [...new Set(course.fields)], category: course.category,
    sourceUrl: course.sourceUrl, sourceKind: sourceKind(course),
    fieldSource: course.fields.length ? course.fieldSource || course.sourceUrl : "",
    ...(course.categorySource ? { categorySource: course.categorySource } : {}),
    ...(alias ? { aliasSource: economicsTable + "#page=" + alias } : {}),
    ...offeringEvidence(course), confirmed: true,
  };
}

export function retainedHistoricalMatch(grade, index) {
  const saved = grade.matchedCourse;
  if (saved?.confirmed !== true) return null;
  const checked = checkedOffering(grade, saved, index);
  return checked ? confirmHistoricalMatch(grade, checked) : null;
}

// A failed lookup or missing qualifier is not evidence that an existing decision is wrong.
export function contradictsConfirmedOffering(grade, saved, index) {
  if (saved?.confirmed !== true || !sameIdentity(grade, saved)) return false;
  if (compareOfferingEvidence(grade, saved) === "conflict") return true;
  if (!saved.code || !index || index.year !== String(saved.year)) return false;
  const offerings = (index.byCode.get(normalize(saved.code)) ?? []).filter((c) =>
    c.department === saved.department && normalize(c.title) === normalize(saved.title));
  return offerings.length > 0 && offerings.every((c) => compareOfferingEvidence(grade, c) === "conflict" ||
    compareOfferingEvidence(saved, c) === "conflict");
}

export function buildHistoricalIndex(year, courses) {
  const byTitle = new Map(), byCode = new Map();
  for (const course of courses) {
    if (String(course.year) !== String(year) || !validOffering(course)) throw Error("年度別索引の授業情報が一致しません。");
    for (const [table, key] of [[byTitle, normalize(course.title)], [byCode, normalize(course.code)]]) {
      if (!key) continue;
      if (!table.has(key)) table.set(key, []);
      table.get(key).push(course);
    }
  }
  return { year: String(year), byTitle, byCode };
}

// A single exact result can be used immediately. All aliases, index-only entries and namesakes require selection.
export function resolveHistoricalGrade(grade, index, { year = grade.year, review = false } = {}) {
  const saved = review ? null : retainedHistoricalMatch(grade, index);
  if (saved) return { status: "confirmed", match: saved, candidates: [saved] };
  const empty = (status) => ({ status, match: null, candidates: [] });
  if (!validYear(year)) return empty("missing-year");
  if (grade.year && String(grade.year) !== String(year)) return empty("mismatch");
  if (!index) return empty("unavailable");
  if (String(year) !== index.year) return empty("mismatch");
  const raw = grade.code ? index.byCode.get(normalize(grade.code)) : index.byTitle.get(normalize(grade.title));
  let candidates = (raw ?? []).filter((course) => sameIdentity(grade, course));
  if (!raw?.length && !grade.code) {
    const aliases = new Set();
    for (const [newTitle, oldTitle] of pairs) {
      if (normalize(grade.title) === normalize(oldTitle)) aliases.add(normalize(newTitle));
      if (normalize(grade.title) === normalize(newTitle)) aliases.add(normalize(oldTitle));
    }
    candidates = [...aliases].flatMap((title) => index.byTitle.get(title) ?? []).filter((c) => sameIdentity(grade, c));
  }
  if (!candidates.length) return empty(raw?.length ? "mismatch" : "not-found");
  candidates = candidates.filter((c) => compareOfferingEvidence(grade, c) !== "conflict");
  if (!candidates.length) return empty("conflict");
  const exact = candidates.filter((c) => !grade.title || normalize(c.title) === normalize(grade.title));
  if (!exact.length) return { status: "alias", candidates, match: null };
  const first = exact[0];
  if (exact.length > 1) return { status: "ambiguous", candidates: exact, match: null };
  if (!grade.year || grade.recognized || (!grade.code && raw?.length > 1) ||
      compareOfferingEvidence(grade, first) !== "match" || ["public-index", "faculty-index"].includes(first.sourceKind)) {
    return { status: "review", candidates: exact, match: null };
  }
  return { status: "exact", candidates: exact, match: confirmHistoricalMatch(grade, first) };
}
