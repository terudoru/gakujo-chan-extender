import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { buildHistoricalIndex, confirmHistoricalMatch, courseSource, dentalSource, economicsTable,
  resolveHistoricalGrade, retainedHistoricalMatch, searchSource } from "../src/archive/identity.mjs";
import { archiveYears, currentOffering, loadHistoricalIndex, matchHistoricalGrades, revalidateGradeMatch, unpackYear } from "../src/archive/packs.mjs";
import { compareOfferingEvidence } from "../src/archive/offering-evidence.mjs";
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
  const result = resolveHistoricalGrade(row, past);
  assert.equal(result.status, "review"); // The annual index verifies the code and term, but does not publish units.
  assert.equal(result.match, null);
  assert.equal(result.candidates[0].code, row.code);
  for (const change of [{ title: "英語基礎 R" }, { department: "09" }, { offeringFaculty: "工学部" }]) {
    assert.equal(resolveHistoricalGrade({ ...row, ...change }, past).status, "mismatch");
  }
  assert.equal(resolveHistoricalGrade({ ...row, faculty: "工学部" }, past).status, "review");
  assert.equal(resolveHistoricalGrade({ ...row, credits: undefined }, past).status, "exact");
  assert.throws(() => confirmHistoricalMatch({ ...row, year: "2024" }, result.candidates[0]));
});

test("current fields are corroborated by the exact detail page and the category retains its own evidence", () => {
  for (const c of current.courses) {
    const row = currentOffering(c, current);
    assert.equal(row.sourceKind, "syllabus", c.code);
    assert.equal(row.fieldSource, row.sourceUrl, c.code);
    assert.equal(row.categorySource, c.page ? current.listing + "#page=" + c.page : undefined, c.code);
  }
  const row = catalog.byCode.get("260ds217")[0];
  assert.equal(row.category, "英語");
  assert.equal(row.categorySource, current.listing + "#page=13");
  const english = catalog.byCode.get("260h2049")[0];
  assert.match(english.fieldSource, /_en_US\.html$/);
  const normal = current.courses.find((c) => c.code === "260DS217");
  const unchecked = currentOffering({ ...normal, code: "260DS999" }, current);
  assert.equal(unchecked.fieldSource, row.categorySource);
  assert.equal(unchecked.sourceUrl, searchSource);
  assert.equal(unchecked.sourceKind, "public-index");
  const wrongFields = currentOffering({ ...normal, fields: ["00"] }, current);
  assert.equal(wrongFields.fieldSource, row.categorySource);
  const indexOnly = currentOffering({ ...normal, sourceKind: "public-index" }, current);
  assert.equal(indexOnly.sourceUrl, searchSource);
  assert.equal(indexOnly.fieldSource, searchSource);
  assert.equal(indexOnly.categorySource, row.categorySource);
  const noPage = currentOffering({ ...normal, code: "260DS999", page: null }, current);
  assert.equal(noPage.fieldSource, "");
  assert.deepEqual(noPage.fields, []);
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
  const exact = { ...wrong, title: input.title, credits: 2, code: "190L1234", sourceUrl: courseSource("2019", "04", "190L1234") };
  const index = buildHistoricalIndex("2019", [...review.candidates, exact]);
  assert.equal(resolveHistoricalGrade(input, index).match.code, exact.code);
});

test("a unique name or code cannot overrule contradictory, missing or partially overlapping qualifiers", async () => {
  const course = catalog.byCode.get("261k0501")[0];
  assert.deepEqual([course.title, course.period, course.credits], ["情報通信技術教育論I", "第1ターム", 1]);
  const qualified = { year: "2026", title: course.title, grade: "優", credits: 1, term: "第１ターム" };
  for (const code of ["", course.code]) {
    const grade = { ...qualified, code };
    const match = resolveHistoricalGrade(grade, catalog).match;
    assert.equal(match.period, "第1ターム");
    assert.equal(match.credits, 1);
    assert.equal(match.semester, "第1学期");
    for (const changed of [{ credits: 3 }, { term: "第4ターム" }, { term: "第4ターム", credits: 3 }]) {
      const conflicting = { ...grade, ...changed };
      assert.deepEqual(resolveHistoricalGrade(conflicting, catalog), { status: "conflict", match: null, candidates: [] });
      assert.throws(() => confirmHistoricalMatch(conflicting, course));
      const [imported] = await matchHistoricalGrades([conflicting], current);
      assert.deepEqual(imported, { ...conflicting, matchedCourse: null });
    }
    assert.equal(resolveHistoricalGrade({ ...grade, section: "A" }, catalog).status, "review");
    const section = buildHistoricalIndex("2026", [{ ...course, section: "Ａ", courseId: "U-1" }]);
    assert.equal(resolveHistoricalGrade({ ...grade, section: "a", courseId: "Ｕ－１" }, section).status, "exact");
    for (const extra of [{ section: "B" }, { courseId: "U-2" }]) {
      assert.equal(resolveHistoricalGrade({ ...grade, ...extra }, section).status, "conflict");
    }
  }
  assert.equal(compareOfferingEvidence({ term: "後期" }, { period: "第3,4ターム" }), "match");
  assert.equal(compareOfferingEvidence({ term: "第1ターム" }, { period: "第1~3ターム" }), "unknown");
  assert.equal(compareOfferingEvidence({ term: "第4ターム" }, { period: "第1~3ターム" }), "conflict");
  assert.equal(compareOfferingEvidence({ term: "第2ターム" }, { period: "集中", semester: "第1学期" }), "unknown");
  assert.equal(compareOfferingEvidence({ term: "第3ターム" }, { period: "集中", semester: "第1学期" }), "conflict");
  assert.equal(compareOfferingEvidence({ credits: "０.５単位" }, { credits: 0.5 }), "match");
  assert.equal(compareOfferingEvidence({ credits: 1, term: "通年" }, {}), "unknown");
  const archived = past.byCode.get("250g7002")[0];
  assert.equal(archived.credits, undefined);
  const original = { ...raw, code: archived.code, term: archived.period };
  assert.equal(resolveHistoricalGrade(original, past).status, "review");
  const manual = confirmHistoricalMatch(original, archived);
  assert.equal(manual.period, archived.period);
  assert.equal(Object.hasOwn(manual, "credits"), false);
  assert.equal(retainedHistoricalMatch({ ...original, matchedCourse: manual }, past).code, archived.code);
  const document = { year: "2026", title: course.title, department: "03", code: course.code,
    sourceUrl: "https://www.niigata-u.ac.jp/example.pdf#page=1", fields: "10" };
  for (const record of [{ credits: "2" }, { period: "第2学期" }, { section: "B" }]) {
    assert.throws(() => reviewPublicRecord({ ...document, ...record }, { ...qualified, section: "A" }));
  }
  const scoped = reviewPublicRecord({ ...document, section: "A", credits: "１単位" }, { ...qualified, section: "A" });
  assert.deepEqual([scoped.section, scoped.credits, scoped.period], ["A", 1, undefined]);
});

test("stored and re-imported confirms are rechecked against known offering evidence; sparse offline decisions survive", async () => {
  const course = catalog.byCode.get("261k0501")[0];
  const input = { id: "exact-repro", year: "2026", code: "", title: course.title, credits: 3, term: "第4ターム" };
  const correctGrade = { ...input, credits: 1, term: "第1ターム" };
  const full = confirmHistoricalMatch(correctGrade, course);
  const { credits, period, semester, schedule, ...legacy } = full;
  for (const saved of [legacy, full]) {
    const old = { ...input, fields: ["10"], category: course.category, matchedCourse: saved };
    assert.equal(revalidateGradeMatch(old, current), null);
    assert.equal(resolveHistoricalGrade(old, catalog).match, null);
    const [projected] = await matchHistoricalGrades([old], current);
    assert.deepEqual([projected.credits, projected.term, projected.fields, projected.category, projected.matchedCourse],
      [3, "第4ターム", [], "", null]);
    const [reimported] = await matchHistoricalGrades([input], current, [old]);
    assert.equal(reimported.matchInvalidated, true);
    assert.equal(reimported.matchedCourse, null);
    assert.throws(() => confirmHistoricalMatch(input, saved, catalog));
    const restored = revalidateGradeMatch({ ...correctGrade, matchedCourse: saved }, current);
    assert.equal(restored.period, "第1ターム");
    assert.equal(restored.credits, 1);
    assert.equal(restored.fieldSource, saved.fieldSource);
  }
  const sparseOffline = { ...input, matchedCourse: legacy };
  assert.ok(revalidateGradeMatch(sparseOffline, null));
  assert.equal(revalidateGradeMatch({ ...input, matchedCourse: full }, null), null);
  const [retained] = await matchHistoricalGrades([input], null, [sparseOffline]);
  assert.deepEqual(retained.matchedCourse, legacy);
  assert.equal(retained.matchInvalidated, undefined);
  const [noPrior] = await matchHistoricalGrades([{ ...input, matchInvalidated: true }], current);
  assert.equal(noPrior.matchInvalidated, undefined);
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
