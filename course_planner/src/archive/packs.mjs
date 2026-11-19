import dental from "./dental-index.json" with { type: "json" };
import currentSources from "./current-sources.json" with { type: "json" };
import checkedFields from "./content/field-evidence-2026.json" with { type: "json" };
import { normalize } from "../study.mjs";
import { compareOfferingEvidence } from "./offering-evidence.mjs";
import { buildHistoricalIndex, contradictsConfirmedOffering, courseSource, dentalSource, officialDocument, resolveHistoricalGrade,
  retainedHistoricalMatch, searchSource, validYear } from "./identity.mjs";

// Availability of the public search, independent of admission year or the selected handbook.
export const archiveYears = ["2016", "2017", "2018", "2019", "2020", "2021", "2022", "2023", "2024", "2025"];
const categories = ["英語", "初修外国語", "健康・スポーツ", "情報リテラシー", "新潟大学個性化科目",
  "留学生基本科目", "大学学習法", "自然系共通専門基礎", "自然科学", "人文社会・教育科学", "医歯学"];
const loaded = new Map();
const currentIndices = new WeakMap();

export function unpackYear(requested, pack) {
  if (pack?.year !== String(requested) || !Array.isArray(pack.rows)) throw Error("指定した年度の索引を確認できません。");
  return buildHistoricalIndex(pack.year, pack.rows.map(([department, code, title, period, schedule, fields, group, availability, page, detailFields]) => {
    if (!/^(?:\d{2})*$/.test(fields) || !/^[0-9A]?$/.test(group)) throw Error("索引の分野・科目区分を確認できません。");
    // The 2016 search still returns offerings and field filters, but its individual HTML links have expired.
    const indexOnly = pack.year === "2016" || availability === "index";
    const sourceUrl = indexOnly ? searchSource : courseSource(pack.year, department, code, availability === "en" ? "en_US" : "ja_JP");
    return { year: pack.year, department, code, title, period, schedule,
      fields: fields.match(/\d{2}/g) ?? [], category: group ? categories[parseInt(group, 16)] : "",
      fieldSource: detailFields ? sourceUrl : searchSource, sourceKind: indexOnly ? "public-index" : "syllabus",
      ...(page ? { categorySource: pack.listing + "#page=" + page } : {}), sourceUrl };
  }));
}

function verifiedFieldSet(year, { department, code }) {
  if (year !== "2026") return null;
  const parts = /^(\d{3}[A-Z]+)(\d+)$/.exec(code);
  if (!parts) return null;
  const ranges = checkedFields[[department, parts[1], parts[2].length].join("/")];
  const number = Number(parts[2]);
  return ranges?.find(([first, last]) => first <= number && number <= last)?.[2] ?? null;
}

export function currentOffering(course, catalog) {
  const year = String(catalog.year);
  const evidence = verifiedFieldSet(year, course);
  const extra = evidence !== null ? currentSources[course.code] : null;
  const indexOnly = course.sourceKind === "public-index" || extra?.locale === "index";
  const page = Number.isInteger(course.page) && catalog.listing + "#page=" + course.page;
  const categorySource = officialDocument(page) ? page :
    officialDocument(course.categorySource) ? course.categorySource : undefined;
  const fields = extra?.fields ?? course.fields ?? [];
  const specific = evidence !== null && !indexOnly && courseSource(year, course.department, course.code,
    extra?.locale === "en" ? "en_US" : "ja_JP");
  const corroborated = specific && [...new Set(fields)].sort().join("") === evidence;
  const sourceUrl = specific || searchSource;
  const fieldSource = corroborated ? specific : course.fieldSource || (indexOnly ? searchSource : categorySource) || "";
  return { ...course, year, fields: fieldSource ? fields : [], fieldSource, categorySource, sourceUrl,
    sourceKind: specific ? "syllabus" : "public-index" };
}

function currentIndex(catalog) {
  if (!currentIndices.has(catalog)) {
    const index = buildHistoricalIndex(catalog.year, catalog.courses.map((course) => currentOffering(course, catalog)));
    currentIndices.set(catalog, index);
  }
  return currentIndices.get(catalog);
}

// Safe read projection before allocating a local or synced confirmed row. No storage write or network request.
export function revalidateGradeMatch(grade, currentCatalog, historicalIndex) {
  if (grade?.matchedCourse?.confirmed !== true) return null;
  const year = String(grade.matchedCourse.year);
  const index = currentCatalog && String(currentCatalog.year) === year ? currentIndex(currentCatalog) :
    historicalIndex?.year === year ? historicalIndex : null;
  return retainedHistoricalMatch(grade, index);
}

export async function loadHistoricalIndex(year, currentCatalog) {
  year = String(year ?? "");
  if (!validYear(year)) return null;
  if (currentCatalog && String(currentCatalog.year) === year) {
    return currentIndex(currentCatalog);
  }
  if (dental[year]?.length && !loaded.has(year)) {
    loaded.set(year, buildHistoricalIndex(year, dental[year].map((title) => ({
      year, title, code: "", department: "08", fields: [], category: "", sourceKind: "faculty-index",
      sourceUrl: dentalSource + "#p1-syl" + year,
    }))));
  }
  if (!loaded.has(year) && archiveYears.includes(year)) {
    const url = new URL(`./packs/${year}.json`, import.meta.url);
    const pending = fetch(url, { credentials: "omit", referrerPolicy: "no-referrer" })
      .then((response) => {
        if (!response.ok) throw Error("年度別索引を読み込めませんでした。");
        return response.json();
      }).then((pack) => unpackYear(year, pack)).catch((error) => { loaded.delete(year); throw error; });
    loaded.set(year, pending);
  }
  return loaded.get(year) ?? null;
}

function importKey(g) {
  const stable = g.recordId || g.id || g.importId;
  if (stable) return JSON.stringify(["record", stable]);
  if (!g.year || (!g.code && !g.title)) return null;
  return JSON.stringify(["offering", String(g.year), normalize(g.code), normalize(g.title), g.offeringDepartment ?? ""]);
}

function uniqueRows(grades) {
  const rows = new Map();
  for (const grade of grades) {
    const key = importKey(grade);
    if (key) rows.set(key, rows.has(key) ? null : grade);
  }
  return rows;
}

// Normal import/re-import entry point. Persist the returned rows only after import confirmation.
// A prior decision survives a unique row identity on both sides and the original offering checks.
export async function matchHistoricalGrades(grades, currentCatalog, previousGrades = []) {
  const previous = uniqueRows(previousGrades), incoming = uniqueRows(grades);
  return Promise.all(grades.map(async ({ matchInvalidated: previousSignal, ...grade }) => {
    const key = importKey(grade);
    const prior = incoming.get(key) && previous.get(key);
    // An offline/missing pack leaves only this row for review. The original credit record remains importable.
    const index = await loadHistoricalIndex(grade.year || grade.matchedCourse?.year || prior?.matchedCourse?.year,
      currentCatalog).catch(() => null);
    const retained = retainedHistoricalMatch(grade, index) ||
      (prior && compareOfferingEvidence(grade, { ...prior.matchedCourse, ...prior }) === "match" &&
        retainedHistoricalMatch({ ...grade, matchedCourse: prior.matchedCourse }, index));
    if (retained) return { ...grade, matchedCourse: retained };
    const invalidated = contradictsConfirmedOffering(grade, prior?.matchedCourse, index);
    const match = invalidated ? null : resolveHistoricalGrade(grade, index, { review: true }).match;
    return { ...grade, matchedCourse: match,
      ...(!match && (grade.fields?.length || grade.category) ? { fields: [], category: "" } : {}),
      ...(invalidated ? { matchInvalidated: true } : {}) };
  }));
}
