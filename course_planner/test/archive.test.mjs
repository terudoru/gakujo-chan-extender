import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { buildHistoricalIndex, confirmHistoricalMatch, courseSource, dentalSource, economicsTable,
  resolveHistoricalGrade, retainedHistoricalMatch, searchSource } from "../src/archive/identity.mjs";
import { archiveYears, loadHistoricalIndex, matchHistoricalGrades, unpackYear } from "../src/archive/packs.mjs";
import { reviewPublicRecord } from "../src/archive/manual.mjs";
import current from "../src/catalog-2026.json" with { type: "json" };

const pack = async (year) => unpackYear(year, JSON.parse(await readFile(
  new URL(`../src/archive/packs/${year}.json`, import.meta.url), "utf8")));
const catalog = await loadHistoricalIndex("2026", current);
const past = await pack("2025");
const raw = { year: "2025", title: "英語基礎 L", credits: 1 };

test("each annual pack retains its own year, offering department, title and field index", async () => {
  for (const year of archiveYears) {
    const index = await pack(year);
    assert.ok(index.byCode.size > 4000);
    for (const entries of index.byCode.values()) for (const c of entries) {
      assert.equal(c.year, year);
      assert.ok(index.byTitle.size > 1000);
      assert.ok(c.code.startsWith(year.slice(-2)));
      assert.ok([searchSource, courseSource(year, c.department, c.code), courseSource(year, c.department, c.code, "en_US")].includes(c.sourceUrl));
    }
  }
  assert.throws(() => unpackYear("2024", { year: "2025", rows: [] }));
});

test("current examples retain actual fields and original transcript identity", async () => {
  const inputs = ["261G7011", "261G3008"].map((code, i) => ({
    id: "import-" + i, year: "2026", code, title: catalog.byCode.get(code.toLowerCase())[0].title,
    credits: i + 1, grade: "可",
  }));
  const rows = await matchHistoricalGrades(inputs, current);
  assert.deepEqual(rows.map((r) => [r.id, r.code, r.title, r.credits]), inputs.map((r) => [r.id, r.code, r.title, r.credits]));
  assert.deepEqual(rows.map((r) => r.matchedCourse.fields), [["70"], ["10"]]);
  assert.deepEqual(rows.map((r) => r.matchedCourse.sourceUrl),
    inputs.map((r) => courseSource("2026", "84", r.code)));
  const human = catalog.byCode.get("260h2016")[0];
  assert.deepEqual(human.fields, ["28", "30"]);
  assert.equal(human.fieldSource, human.sourceUrl);
  const medical = past.byCode.get("250m1101")[0];
  assert.equal(medical.category, "医歯学");
  assert.match(medical.categorySource, /\.pdf#page=\d+/);
});

test("require academic year, offering faculty and title agreement even for an exact code", () => {
  assert.equal(resolveHistoricalGrade(raw, catalog).status, "mismatch");
  assert.equal(resolveHistoricalGrade({ ...raw, year: "" }, catalog).status, "missing-year");
  assert.equal(resolveHistoricalGrade({ ...raw, code: "261G7011" }, past).match, null);
  const row = { ...raw, code: "250G7002" };
  assert.equal(resolveHistoricalGrade(row, past).match.code, row.code);
  for (const change of [{ title: "英語基礎 R" }, { department: "09" }, { offeringFaculty: "工学部" }]) {
    assert.equal(resolveHistoricalGrade({ ...row, ...change }, past).status, "mismatch");
  }
  assert.equal(resolveHistoricalGrade({ ...row, faculty: "工学部" }, past).status, "exact");
  assert.throws(() => confirmHistoricalMatch({ ...row, year: "2024" }, resolveHistoricalGrade(row, past).match));
});

test("same-name sections await an explicit choice; re-import retains it even with the pack offline", async () => {
  const review = resolveHistoricalGrade(raw, past);
  assert.equal(review.status, "ambiguous");
  assert.equal(review.match, null);
  assert.ok(review.candidates.length >= 2);
  const selected = review.candidates[1];
  const matchedCourse = confirmHistoricalMatch(raw, selected);
  assert.equal(matchedCourse.sourceUrl, courseSource(raw.year, selected.department, selected.code));
  assert.equal(matchedCourse.fieldSource, searchSource);
  const saved = { ...raw, id: "row-2", matchedCourse };
  assert.deepEqual(await matchHistoricalGrades([saved], current), [saved]);
  assert.deepEqual((await matchHistoricalGrades([{ ...raw, id: "row-2" }], current, [saved]))[0].matchedCourse, matchedCourse);
  // Two indistinguishable prior rows cannot donate a decision to the new transcript.
  const missing = { ...raw, year: "1993", code: "" };
  const former = { ...missing, matchedCourse: reviewPublicRecord({ year: missing.year, title: missing.title,
    department: "84", sourceUrl: "https://www.niigata-u.ac.jp/old.pdf#page=5" }, missing) };
  assert.equal((await matchHistoricalGrades([missing], current, [former, { ...former }]))[0].matchedCourse, null);
  assert.deepEqual((await matchHistoricalGrades([missing, { ...missing }], current, [former])).map((g) => g.matchedCourse), [null, null]);
  assert.equal(resolveHistoricalGrade(saved, null).status, "confirmed");
  assert.equal(retainedHistoricalMatch({ ...saved, year: "2024" }), null);
  assert.equal(retainedHistoricalMatch({ ...saved, offeringDepartment: "09" }), null);
});

test("approved economics equivalents are directional by offering faculty and subordinate to exact names", async () => {
  const old = await pack("2019");
  const input = { year: "2019", title: "社会思想史", credits: 2 };
  const review = resolveHistoricalGrade(input, old);
  assert.equal(review.status, "alias");
  assert.equal(review.match, null);
  const chosen = confirmHistoricalMatch(input, review.candidates[0]);
  assert.equal(chosen.code, "192E1064");
  assert.equal(chosen.aliasSource, economicsTable + "#page=1");
  const newer = resolveHistoricalGrade({ year: "2025", title: "経済学史Ⅰ" }, past);
  assert.ok(newer.candidates.some((c) => c.title === "社会思想史" && c.department === "0C"));
  const wrong = { ...review.candidates[0], department: "04", sourceUrl: courseSource("2019", "04", chosen.code) };
  assert.throws(() => confirmHistoricalMatch(input, wrong));
  const exact = { ...wrong, title: input.title, code: "190L1234", sourceUrl: courseSource("2019", "04", "190L1234") };
  const index = buildHistoricalIndex("2019", [...review.candidates, exact]);
  assert.equal(resolveHistoricalGrade(input, index).match.code, exact.code);
});

test("index-only records identify the source and never auto-assign a same-name credit", async () => {
  const index = await pack("2016");
  const [offering] = [...index.byCode.values()][0];
  const record = { year: "2016", code: offering.code, title: offering.title };
  const review = resolveHistoricalGrade(record, index);
  assert.equal(review.status, "review");
  assert.equal(confirmHistoricalMatch(record, review.candidates[0]).sourceUrl, searchSource);
  const dental = await loadHistoricalIndex("2001", current);
  const dentalGrade = { year: "2001", title: "口腔生命科学" };
  const dentistry = resolveHistoricalGrade(dentalGrade, dental);
  assert.equal(dentistry.status, "review");
  assert.deepEqual(dentistry.candidates[0].fields, []);
  assert.equal(dentistry.candidates[0].sourceUrl, dentalSource + "#p1-syl2001");
});

test("unavailable years allow a student-confirmed sourced record without inventing an academic field", async () => {
  const grade = { id: "legacy-1", year: "1988", title: "地域文化論", credits: 2 };
  assert.equal(await loadHistoricalIndex(grade.year, current), null);
  assert.equal(resolveHistoricalGrade(grade, null).status, "unavailable");
  // Synthetic document path. The browser never contacts the university to validate private grade rows.
  const record = { year: "1988", title: grade.title, department: "人文学部", code: "",
    sourceUrl: "https://www.human.niigata-u.ac.jp/archive/example.pdf#page=9" };
  const manual = reviewPublicRecord(record, grade);
  assert.deepEqual(manual.fields, []);
  assert.equal(manual.category, "");
  assert.equal(manual.sourceKind, "manual-record");
  assert.equal(manual.fieldSource, "");
  const { sourceKind, fieldSource, ...commonSyncRecord } = manual;
  assert.equal(retainedHistoricalMatch({ ...grade, matchedCourse: commonSyncRecord }).sourceKind, "manual-record");
  const withFields = reviewPublicRecord({ ...record, fields: "29、30" }, grade);
  assert.equal(withFields.fieldSource, record.sourceUrl);
  assert.deepEqual(withFields.fields, ["29", "30"]);
  for (const override of [{ year: "2026" }, { department: "不明" }, { title: "別の科目" }, { fields: "英語" },
    { sourceUrl: "https://www.niigata-u.ac.jp.example.com/file.pdf#page=7" },
    { sourceUrl: "https://outside.example@www.human.niigata-u.ac.jp/doc.pdf#page=7" },
    { sourceUrl: "https://www.human.niigata-u.ac.jp/doc.pdf?user=x#page=7" }]) {
    assert.throws(() => reviewPublicRecord({ ...record, ...override }, grade));
  }
});
