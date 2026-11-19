import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import resolve, { handbooks } from "../src/curricula/clinical.mjs";
import { syllabusSection } from "../src/curricula/clinical/catalog-sections.mjs";

const catalog = JSON.parse(readFileSync(new URL("../src/catalog-2026.json", import.meta.url))).courses;
const fromCode = (code) => {
  const course = catalog.find((c) => c.code === code);
  assert.ok(course, code);
  return { ...course, year: "2026" };
};
const findStage = (descriptor, id = "graduation") => descriptor.stages.find((s) => s.id === id);
const row = (descriptor, key, id) => {
  const item = findStage(descriptor, id)?.rows.find((r) => r.key === key);
  assert.ok(item, key + " / " + id);
  return item;
};
const descriptor = (faculty, year, extra = {}) =>
  resolve({ faculty, handbook: String(year), entry: "1年次入学", ...extra });
const medicine = "医学部医学科",
  health = "医学部保健学科",
  dent = "歯学部歯学科",
  oral = "歯学部口腔生命福祉学科",
  creation = "創生学部";
const regular = { program: "創生学修コース" }, dx = { program: "DX共創コース" };
const evalRow = (r, courses, profile = {}) => r.evaluate({ courses, profile, baseline: [] });

test("registered editions resolve without collisions, with explicit evidence", () => {
  assert.equal(resolve({ faculty: "工学部", handbook: "2026" }), null);
  for (const book of handbooks) {
    const d = descriptor(book.faculty, book.year, { program: book.programs?.[0] });
    assert.match(book.url, /^https:\/\//);
    assert.ok(d.stages.some((s) => s.goal === "graduation"));
    const ids = d.stages.map((s) => s.id);
    assert.equal(new Set(ids).size, ids.length);
    for (const s of d.stages) {
      assert.equal(new Set(s.rows.map((r) => r.key)).size, s.rows.length, book.title + " " + s.id);
      for (const r of s.rows) assert.match(r.source.url, /^https:\/\//);
    }
  }
  const d = descriptor(medicine, 1991);
  assert.match(row(d, "major").unknown, /1991.*医学科学務係/);
  assert.equal(row(d, "major").required, null);
  assert.equal(descriptor(oral, 2026).cap.limit, null);
});
test("medical cohort amendments, half units, exact department and exam decisions", () => {
  for (
    const [y, major, total] of [[2018, 185.5, 230.5], [2020, 186.5, 229.5], [2022, 186.5, 229.5], [2024, 183, 226], [
      2026,
      176,
      219,
    ]]
  ) {
    const d = descriptor(medicine, y);
    assert.equal(row(d, "major").required, major);
    assert.equal(row(d, "total").required, total);
    assert.equal(row(d, "residency").required, 72);
  }
  const d = descriptor(medicine, 2026, { entry: "2年次編入" }), c = fromCode("260M1208");
  const ethics = findStage(d, "year-3").rows.find((r) => r.label === "倫理観と人間性Ⅰ");
  assert.equal(ethics.required, 0.5);
  assert.equal(ethics.match(c), true);
  assert.equal(ethics.match({ ...c, code: "261M8136" }), false);
  assert.equal(ethics.match({ ...c, credits: 1 }), false);
  assert.equal(evalRow(row(d, "total"), [c]).value, 0.5);
  assert.equal(row(d, "major").match({ title: "自己主導型臨床実習Ⅰ", department: "07" }), false);
  assert.equal(row(d, "clinical-CBT", "clinical-practice").required, null);
  assert.match(row(d, "transfer-limits").unknown, /2～4年次通算6年/);
  assert.ok(row(descriptor(medicine, 2022), "transition-2024").source);
});
test("allied health program splits, positive catalogue mapping and transfer treatment", () => {
  for (
    const [program, counts] of [["看護学専攻", [15, 6, 74, 3]], ["放射線技術科学専攻", [12, 5, 79, 2]], [
      "検査技術科学専攻",
      [10, 8, 73, 7],
    ]]
  ) {
    const d = descriptor(health, 2026, { program });
    assert.deepEqual(
      ["基礎必修", "基礎選択", "専門必修", "専門選択"].map((k) => row(d, "health-" + k).required),
      counts,
    );
    assert.equal(row(d, "total").required, 124);
    assert.equal(row(d, "total").match({ title: "教職概論", category: "教職に関する科目", department: "03" }), false);
    assert.equal(row(d, "year-months", "year-3").profileValue({ monthsInYear2: 12 }), 12);
    assert.equal(row(d, "faculty-review", "year-4").required, null);
  }
  const d = descriptor(health, 2026, { program: "看護学専攻" }), c = fromCode("262M8121");
  assert.equal(row(d, "health-専門必修").match(c), true);
  assert.equal(row(d, "health-専門必修").match({ ...c, code: "262M8350" }), false);
  const transfer = descriptor(health, 2022, { program: "看護学専攻", entry: "3年次編入", admitted: "2024" });
  assert.deepEqual(transfer.stages.map((s) => s.id), ["year-4", "graduation"]);
  assert.equal(row(transfer, "major").required, 98);
  assert.ok(findStage(transfer, "year-4").rows.every((r) => !r.key.startsWith("through-year3")));
  assert.equal(
    row(descriptor(health, 2022, { program: "看護学専攻", entry: "3年次編入", admitted: "2023" }), "major").required,
    null,
  );
  assert.ok(row(descriptor(health, 2022, { entry: "編入・転部・再入学" }), "required-through-year3", "year-4").unknown);
  const historic = descriptor(health, 2021, { program: "検査技術科学専攻" });
  const prescribed = row(historic, "old-M5504", "legacy-year-2");
  assert.equal(prescribed.kind, "選択・履修指定");
  assert.equal(prescribed.match({ code: "222M5504", title: "生体機能学実習", year: 2022, department: "07" }), true);
  assert.equal(prescribed.match({ code: "262M5504", title: "生体機能学実習", year: 2026, department: "07" }), null);
});
test("dentistry stages and clinical gate; school and elective exclusions", () => {
  const d = descriptor(dent, 2026), w = descriptor(oral, 2026);
  assert.deepEqual([2, 3, 4].map((y) => row(d, "general", "year-" + y).required), [37, 2, 1]);
  assert.deepEqual([2, 3, 4, 5, 6].map((y) => row(d, "major", "year-" + y).required), [1, 30, 29, 36, 36]);
  assert.equal(row(d, "total").required, 192);
  assert.equal(row(w, "total").required, 150);
  assert.equal(row(descriptor(dent, 2024), "choice").required, 20);
  assert.equal(row(d, "choice").required, 22);
  assert.equal(row(w, "major").match(fromCode("260DA204")), true);
  assert.equal(row(w, "major").match(fromCode("260DS424")), false);
  assert.equal(row(w, "oral-choice").match({ department: "08", title: "短期海外派遣実習", credits: 2 }), false);
  const one = { category: "自然系共通専門基礎", subcategory: "物理学", department: "84", title: "物理学", credits: 2 };
  assert.equal(evalRow(row(w, "science-breadth"), [one, { ...one, code: "2" }]).value, 1);
  assert.equal(evalRow(row(w, "science-breadth"), [one, { ...one, subcategory: "化学" }]).value, 2);
  assert.equal(row(w, "science").match({ ...one, subcategory: "数学・統計学" }), false);
  assert.equal(row(d, "pre-clinical-OSCE", "clinical-practice").required, null);
  assert.match(row(d, "attendance").unknown, /4分の3/);
  assert.equal(row(descriptor(oral, 2008), "total").required, 140);
  assert.equal(row(descriptor(oral, 2010), "total").required, 147);
  assert.equal(row(descriptor(oral, 2010), "major").match(fromCode("260DS424")), false);
});
test("creation intake breaks, course options, package code and 24 credit CAP", () => {
  for (
    const [year, units, pool] of [
      [2018, 17, 41],
      [2019, 17, 41],
      [2020, 17, 41],
      [2021, 16, 40],
      [2022, 16, 40],
      [2023, 16, 40],
      [2024, 16, 40],
      [2025, 14, 44],
      [2026, 14, 44],
    ]
  ) {
    const d = descriptor(creation, year, regular);
    assert.equal(row(d, "intro", "year-4").required, units);
    assert.equal(row(d, "remaining-pool", "year-4").required, pool);
    assert.equal(row(d, "total", "year-4").required, 90);
    assert.equal(row(d, "total").required, 126);
    assert.equal(d.cap.limit, 24);
    assert.equal(
      d.cap.classify({ semester: "第1学期", title: "課題解決リテラシー", department: "0B", period: "集中" }),
      "exclude",
    );
  }
  const d = descriptor(creation, 2026, dx), normal = descriptor(creation, 2026, regular), course = fromCode("261X0003");
  assert.equal(d.cap.classify(course), "include");
  assert.equal(row(d, "field-foundation").required, 26);
  assert.equal(row(normal, "field-foundation").required, 20);
  assert.equal(row(d, "field-foundation").match(fromCode("263T0201")), true);
  assert.equal(row(d, "field-foundation").match({ ...fromCode("263T0201"), year: 2024 }), null);
  assert.equal(row(normal, "field-foundation").match(fromCode("263T0201")), null);
  assert.equal(row(d, "total").match(fromCode("260X0019"), {}), false);
  assert.equal(evalRow(row(d, "total"), [course, fromCode("260X0019")]).value, 2);
  const late = { ...course, period: "春期休業" };
  assert.equal(evalRow(row(d, "total"), [late], { graduationYear: 2027, graduationMonth: 3 }).value, 0);
  assert.equal(row(descriptor(creation, 2023, regular), "intro", "year-4").required, 16);
});
test("alternative P.A.C.E. and data routes reserve each course once", () => {
  const d = descriptor(creation, 2026, regular);
  const data = catalog.filter((c) => c.department === "0B" && /^データサイエンス実践\s*[ABC]$/.test(c.title));
  assert.equal(data.length, 3);
  for (const courses of [data, [...data].reverse()]) {
    assert.equal(evalRow(row(d, "skill"), courses).value, 4);
    assert.equal(evalRow(row(d, "free"), courses).value, 2);
    assert.equal(evalRow(row(d, "total"), courses).value, 6);
  }
  const half = [
    "Academic Listening & Speaking",
    "Academic Reading I",
    "Academic Writing I",
    "Oral Communication",
    "Academic Writing II",
    "Academic Reading II",
  ]
    .map((n) => ({ title: "P.A.C.E.(" + n + ")", department: "84", category: "英語", credits: 0.5 }));
  const english = [...half, fromCode("260G0664")];
  assert.equal(evalRow(row(d, "skill"), english).value, 4);
  assert.equal(evalRow(row(d, "english"), english).value, 0);
  assert.equal(evalRow(row(d, "free"), english).value, 0);
  assert.equal(evalRow(row(descriptor(creation, 2026, dx), "skill"), english).value, 0);
});

test("printed syllabus subcategories and package cohort exceptions apply per offering", () => {
  const sociology = catalog.find((c) => c.title === "アクターネットワークの社会学");
  assert.equal(syllabusSection(sociology), "人文科学");
  assert.equal(syllabusSection({ ...sociology, year: 2025 }), null);
  const cutoff = fromCode("260H1003");
  const old = descriptor(creation, 2024, { program: "創生学修課程（社会文化学）" });
  const modern = descriptor(creation, 2026, { program: "創生学修コース（社会文化学）" });
  assert.equal(row(old, "field-foundation").match(cutoff), true);
  assert.equal(row(modern, "field-foundation").match(cutoff), false);
  const dx = descriptor(creation, 2026, { program: "DX共創コース" });
  assert.equal(row(dx, "field-foundation").match({ ...cutoff, code: "253T0201", year: 2026 }), null);
  const unknown = descriptor(creation, 2018, { program: "創生学修課程（社会・地域文化学）" });
  assert.match(row(unknown, "old-package").unknown, /全員卒業/);
});
