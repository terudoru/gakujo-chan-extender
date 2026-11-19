import { normalize } from "../study.mjs";

const present = (value) => value != null && String(value).trim() !== "";
const textKeys = ["period", "semester", "term", "section", "courseId", "schedule"];

export function creditValue(value) {
  const text = normalize(value).replace(/単位$/, "");
  return /^\d+(?:\.\d+)?$/.test(text) && Number.isFinite(Number(text)) ? Number(text) : null;
}

// Only source values are copied into a saved offering. Transcript units stay on the grade.
export function offeringEvidence(course) {
  const evidence = {};
  for (const key of textKeys) {
    if (typeof course[key] === "string" && course[key].trim()) evidence[key] = course[key].trim();
  }
  const credits = creditValue(course.credits);
  if (credits != null) evidence.credits = credits;
  return evidence;
}

function periodInfo(value) {
  const label = normalize(value);
  if (!label) return null;
  if (label === "通年") return { label, terms: "1234" };
  if (/^(第?1学期|前期|前学期)$/.test(label)) return { label: "第1学期", terms: "12", semester: true };
  if (/^(第?2学期|後期|後学期)$/.test(label)) return { label: "第2学期", terms: "34", semester: true };
  const match = /^(?:第?([1-4](?:[,、・~〜～\-][1-4])*)ターム|t([1-4]))$/.exec(label);
  if (!match) return { label };
  const digits = match[1] || match[2];
  const numbers = [...digits.matchAll(/[1-4]/g)].map(([n]) => Number(n));
  if (/[~〜～\-]/.test(digits) && numbers.length === 2 && numbers[1] >= numbers[0]) {
    return { label, terms: "1234".slice(numbers[0] - 1, numbers[1]) };
  }
  return { label, terms: [...new Set(numbers)].sort().join("") };
}

function compareSpan(requested, actual) {
  if (!actual) return "unknown";
  if (actual.label === requested.label) return "match";
  if (!actual.terms || !requested.terms) return "unknown";
  if (![...requested.terms].some((n) => actual.terms.includes(n))) return "conflict";
  if (actual.terms === requested.terms ||
      (requested.semester && [...actual.terms].every((n) => requested.terms.includes(n)))) return "match";
  // Overlapping ranges and a semester-only source cannot corroborate the exact term on a transcript.
  return "unknown";
}

function comparePeriod(input, course) {
  const requested = periodInfo(input);
  if (!requested) return "match";
  const periods = [course.period, course.term].filter(present).map(periodInfo);
  // A full-year offering can be filed under the first semester. Prefer its actual teaching period.
  const results = periods.map((p) => compareSpan(requested, p));
  if (results.includes("conflict")) return "conflict";
  if (results.includes("match")) return "match";
  if (periods.some((p) => p.terms)) return "unknown";
  return compareSpan(requested, periodInfo(course.semester));
}

// "unknown" means the grade supplied a qualifier the source cannot corroborate, so only explicit review is possible.
export function compareOfferingEvidence(grade, course) {
  const checks = [grade.term, grade.period, grade.semester].map((value) => comparePeriod(value, course));
  for (const key of ["section", "courseId"]) {
    if (!present(grade[key])) continue;
    checks.push(!present(course[key]) ? "unknown" :
      normalize(grade[key]) === normalize(course[key]) ? "match" : "conflict");
  }
  if (present(grade.credits)) {
    const wanted = creditValue(grade.credits), actual = creditValue(course.credits);
    checks.push(wanted == null || actual == null ? "unknown" : wanted === actual ? "match" : "conflict");
  }
  return checks.includes("conflict") ? "conflict" : checks.includes("unknown") ? "unknown" : "match";
}
