import { courseSource } from "../identity.mjs";

// Import asset URLs only. Even the smallest faculty pack is fetched when first needed.
const assets = import.meta.glob("./packs/*.json", { eager: true, import: "default", query: "?url&no-inline" });
const loaded = new Map();
const text = (value) => typeof value === "string" && Boolean(value.trim());
const terms = (value) => Array.isArray(value) && value.length > 0 && value.every(text);
function validRecord(record) {
  return record && typeof record === "object" && !Array.isArray(record) &&
    ["keywords", "topics", "remote", "methods"].every((key) => !(key in record) || terms(record[key])) &&
    ["mode", "language"].every((key) => !(key in record) || text(record[key])) &&
    (!("en" in record) || record.en === true) &&
    (!("weights" in record) || (Array.isArray(record.weights) && record.weights.length > 0 &&
      record.weights.every((pair) => Array.isArray(pair) && pair.length === 2 && text(pair[0]) &&
        typeof pair[1] === "string" && /^\d+(?:\.\d+)?%$/.test(pair[1]))));
}

export function contentIdentity(course, year = course?.year) {
  if (String(year) !== "2026" || (course?.year != null && String(course.year) !== String(year)) ||
      !courseSource(year, course?.department, course?.code)) return null;
  return { year: String(year), department: course.department, code: course.code };
}

function readPack(year, department) {
  const url = assets[`./packs/${year}-${department}.json`];
  if (!url) return Promise.resolve(null);
  if (!loaded.has(url)) {
    const pending = fetch(url, { credentials: "omit", referrerPolicy: "no-referrer" })
      .then(async (response) => {
        if (!response.ok) throw Error("比較用データの読み込みに失敗しました。");
        const pack = await response.json();
        if (pack?.year !== year || pack.department !== department || !pack.courses ||
            typeof pack.courses !== "object" || Array.isArray(pack.courses) ||
            !Object.values(pack.courses).every(validRecord)) throw Error("年度別データが一致しません。");
        return pack.courses;
      })
      .catch((error) => { loaded.delete(url); throw error; });
    loaded.set(url, pending);
  }
  return loaded.get(url);
}

export async function loadSyllabusContent(offering) {
  const identity = contentIdentity(offering);
  if (!identity) return null;
  const { year, department, code } = identity;
  const records = await readPack(year, department);
  if (!records || !Object.hasOwn(records, code)) return null;
  const record = records[code];
  return { record, sourceUrl: courseSource(year, department, code, record.en ? "en_US" : "ja_JP") };
}
