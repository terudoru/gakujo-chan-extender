import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import resolve, { handbooks } from "../src/curricula/clinical.mjs";
import { requirementRows, satisfiesFilter, shortageFilter, stageStatus } from "../src/requirements.mjs";
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
const descriptor = (faculty, year, extra = {}) => {
  const profile = { faculty, handbook: String(year), entry: "1年次入学", ...extra };
  return { ...resolve(profile), profile };
};
const medicine = "医学部医学科",
  health = "医学部保健学科",
  dent = "歯学部歯学科",
  oral = "歯学部口腔生命福祉学科",
  creation = "創生学部";
const regular = { program: "創生学修コース" }, dx = { program: "DX共創コース" };
const projected = (d, key, courses, extra = {}) =>
  requirementRows({ profile: { ...d.profile, ...extra } }, new Map(), courses).find((r) => r.key === key).future;

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
test("only official determinations are editable as confirmed decisions", () => {
  const nursing = descriptor(health, 2026, { program: "看護学専攻" });
  const med = descriptor(medicine, 2026);
  const dental = descriptor(dent, 2026);
  const archive = descriptor(medicine, 1991);
  const decisions = [
    row(nursing, "faculty-review", "year-4"),
    row(med, "graduation-review"),
    row(med, "clinical-CBT", "clinical-practice"),
    row(med, "clinical-OSCE", "clinical-practice"),
    row(dental, "pre-clinical-CBT", "clinical-practice"),
    row(dental, "pre-clinical-OSCE", "clinical-practice"),
  ];
  for (const rule of decisions) assert.equal(rule.officialDecision, true, rule.key);

  const otherRules = [
    row(nursing, "assessment-month", "year-4"),
    row(nursing, "year-months", "year-4"),
    row(nursing, "residency"),
    row(archive, "year-table", "advancement"),
    row(archive, "major"),
    row(descriptor(health, 2026), "program"),
  ];
  for (const rule of otherRules) assert.equal(rule.officialDecision, undefined, rule.key);
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
  assert.equal(projected(d, "total", [c]), 0.5);
  assert.equal(row(d, "major").match({ title: "自己主導型臨床実習Ⅰ", department: "07" }), false);
  assert.equal(row(d, "clinical-CBT", "clinical-practice").required, 1);
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
    assert.equal(row(d, "year-months", "year-3").profileValue({ yearAttendanceMonths: { 2: 12 } }), 12);
    assert.equal(row(d, "faculty-review", "year-4").required, 1);
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
  const one = {
    category: "自然系共通専門基礎",
    subcategory: "物理学",
    department: "84",
    title: "物理学",
    credits: 2,
    year: 2026,
    code: "A",
  };
  assert.equal(projected(w, "science-breadth", [one, { ...one, code: "2" }]), 1);
  assert.equal(projected(w, "science-breadth", [one, { ...one, title: "化学", subcategory: "化学", code: "B" }]), 2);
  assert.equal(row(w, "science").match({ ...one, subcategory: "数学・統計学" }), false);
  assert.equal(row(d, "pre-clinical-OSCE", "clinical-practice").required, 1);
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
  assert.equal(row(d, "domain-foundation").required, 26);
  assert.equal(row(normal, "domain-foundation").required, 20);
  assert.equal(row(d, "domain-foundation").match(fromCode("263T0201")), true);
  assert.equal(row(d, "domain-foundation").match({ ...fromCode("263T0201"), year: 2024 }), null);
  assert.equal(row(normal, "domain-foundation").match(fromCode("263T0201")), null);
  assert.equal(row(d, "total").match(fromCode("260X0019"), {}), false);
  assert.equal(projected(d, "total", [course, fromCode("260X0019")]), 2);
  const late = { ...course, period: "春期休業" };
  assert.equal(projected(d, "total", [late], { graduationYear: 2027, graduationMonth: 3 }), 0);
  assert.equal(row(descriptor(creation, 2023, regular), "intro", "year-4").required, 16);
});
test("alternative P.A.C.E. and data routes reserve each course once", () => {
  const d = descriptor(creation, 2026, regular);
  const data = catalog.filter((c) => c.department === "0B" && /^データサイエンス実践\s*[ABC]$/.test(c.title));
  assert.equal(data.length, 3);
  for (const courses of [data, [...data].reverse()]) {
    assert.equal(projected(d, "skill", courses), 4);
    assert.equal(projected(d, "free", courses), 2);
    assert.equal(projected(d, "total", courses), 6);
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
  assert.equal(projected(d, "skill", english), 4);
  assert.equal(projected(d, "skill", english.map((c) => ({ ...c, credits: String(c.credits) }))), 4);
  assert.equal(projected(d, "english", english), 0);
  assert.equal(projected(d, "free", english), 0);
  assert.equal(projected(descriptor(creation, 2026, dx), "skill", english), 0);
});

test("printed syllabus subcategories and package cohort exceptions apply per offering", () => {
  const sociology = catalog.find((c) => c.title === "アクターネットワークの社会学");
  assert.equal(syllabusSection(sociology), "人文科学");
  assert.equal(syllabusSection({ ...sociology, year: 2025 }), null);
  const cutoff = fromCode("260H1003");
  const old = descriptor(creation, 2024, { program: "創生学修課程（社会文化学）" });
  const modern = descriptor(creation, 2026, { program: "創生学修コース（社会文化学）" });
  assert.equal(row(old, "domain-foundation").match(cutoff), true);
  assert.equal(row(modern, "domain-foundation").match(cutoff), false);
  const dx = descriptor(creation, 2026, { program: "DX共創コース" });
  assert.equal(row(dx, "domain-foundation").match({ ...cutoff, code: "253T0201", year: 2026 }), null);
  const unknown = descriptor(creation, 2018, { program: "創生学修課程（社会・地域文化学）" });
  assert.match(row(unknown, "old-package").unknown, /全員卒業/);
});

const audit = (profile, stageId, balances = [], grades = [], planned = []) =>
  requirementRows({ profile, balances, grades }, new Map(), planned, stageId);
const statement = (profile, stageId, goal, key, unit, current) => ({
  scope: { ...profile, stageId, goal },
  key,
  unit,
  current,
  confirmed: true,
});

test("saved months and the actual date decide each health progression gate", () => {
  const p = descriptor(health, 2026, { program: "看護学専攻", yearOfStudy: "2", attendanceMonths: 48 }).profile;
  const yes = { ...p, yearAttendanceMonths: { 1: 11, 2: "12", 3: 0 }, assessmentDate: "2027-04-01" };
  const status = (profile, stageId = "progress") => stageStatus(audit(profile, stageId));
  assert.equal(audit(yes, "progress")[0].stageId, "year-3");
  assert.equal(status(yes), "met");
  assert.equal(status({ ...p, monthsInYear2: 12, assessmentDate: yes.assessmentDate }), "met");
  assert.equal(status({ ...yes, monthsInYear2: 12, yearAttendanceMonths: {} }), "unknown");
  assert.equal(status(yes, "year-2"), "short");
  assert.equal(status({ ...yes, assessmentDate: "2027-05-01" }), "short");
  for (const date of [null, "04", "2027-04-31", "2027-04-30T10:00:00Z"]) {
    const rows = audit({ ...yes, assessmentDate: date }, "progress");
    assert.equal(stageStatus(rows), "unknown");
    assert.match(rows.find((r) => r.key === "assessment-month").reason, /日付/);
  }
  for (const value of [undefined, "", false, 1.5, -2]) {
    const rows = audit({ ...yes, yearAttendanceMonths: { 1: 12, 2: value } }, "progress");
    assert.equal(stageStatus(rows), "unknown");
    assert.match(rows.find((r) => r.key === "year-months").reason, /当該年次/);
  }
  for (
    const [faculty, program, period] of [[health, p.program, 48], [oral, "", 48], [dent, "", 72], [medicine, "", 72], [
      creation,
      dx.program,
      48,
    ]]
  ) {
    const profile =
      descriptor(faculty, 2026, { program, yearAttendanceMonths: { 1: 12, 2: 12, 3: 12, 4: 12, 5: 12, 6: 12 } })
        .profile;
    const duration = (months) =>
      audit({ ...profile, attendanceMonths: months }, "graduation").find((r) => r.key === "residency");
    assert.equal(duration(undefined).status, "unknown");
    assert.equal(duration(period - 1).status, "short");
    assert.equal(duration(String(period)).status, "met");
  }
  const stage = descriptor(creation, 2026, { ...dx, attendanceMonths: 36 }).profile;
  assert.equal(audit(stage, "year-4").find((r) => r.key === "residency").status, "met");
});

test("entry grade, actual admission and confirmed stage decisions remain independent", () => {
  const p = descriptor(health, 2022, {
    program: "看護学専攻",
    entry: "編入",
    admitted: "2024",
    yearOfStudy: 3,
    assessmentDate: "2027-04-15",
    yearAttendanceMonths: { 3: 12 },
  }).profile;
  const transfer = { ...p, entryGrade: "3" };
  assert.match(resolve(transfer).note, /国家試験の受験資格を取得できません/);
  assert.doesNotMatch(resolve({ ...transfer, admitted: "2023" }).note, /取得できません/);
  const decision = statement(transfer, "year-4", "progress", "faculty-review", "condition", 1);
  assert.deepEqual(resolve(transfer).stages.map((s) => s.id), ["year-4", "graduation"]);
  assert.equal(stageStatus(audit(transfer, "year-4")), "unknown");
  assert.equal(stageStatus(audit(transfer, "year-4", [decision])), "met");
  assert.equal(stageStatus(audit(transfer, "year-4", [{ ...decision, current: 0 }])), "short");
  for (
    const scope of [{ stageId: "year-3" }, { entry: "転部" }, { admitted: "2023" }, { program: "放射線技術科学専攻" }]
  ) {
    assert.equal(
      stageStatus(audit(transfer, "year-4", [{ ...decision, scope: { ...decision.scope, ...scope } }])),
      "unknown",
    );
  }
  assert.equal(audit(p, "year-4").find((r) => r.key === "required-through-year3").status, "unknown");
  assert.equal(audit(p, "year-2").find((r) => r.key === "entry-grade").status, "unknown");
  assert.equal(audit(transfer, "graduation").find((r) => r.key === "major").required, 98);
  for (const admitted of ["2023", undefined]) {
    const historical = audit({ ...transfer, admitted }, "graduation").find((r) => r.key === "major");
    assert.equal(historical.required, null);
    assert.match(historical.reason, /2024年度/);
  }
  for (const entry of ["転部", "再入学", "1年次入学"]) {
    const profile = { ...p, entry, entryGrade: 3 };
    assert.ok(audit(profile, "year-4").some((r) => r.key.startsWith("through-year3-")));
    const grad = audit(profile, "graduation");
    assert.equal(grad.some((r) => r.key === "recognized-credits"), entry !== "1年次入学");
    assert.equal(grad.some((r) => r.key === "transfer-limits"), false);
  }
});

test("year of study does not select between same-year clinical decisions or prove exam results", () => {
  for (const [faculty, year, exam] of [[medicine, 4, "clinical-"], [dent, 5, "pre-clinical-"]]) {
    const p = descriptor(faculty, 2026, { yearOfStudy: String(year) }).profile;
    for (const yearOfStudy of [undefined, year]) {
      const rows = audit({ ...p, yearOfStudy }, "progress");
      assert.equal(stageStatus(rows), "unknown");
      assert.match(rows[0].reason, /判定を選/);
    }
    assert.equal(audit({ ...p, yearOfStudy: 2 }, "progress")[0].stageId, "year-3");
    const exams = audit(p, "clinical-practice");
    const balances = exams.map((r) => statement(p, "clinical-practice", "progress", r.key, r.unit, r.required));
    assert.equal(stageStatus(audit(p, "clinical-practice", balances)), "met");
    const cbt = balances.find((r) => r.key === exam + "CBT");
    assert.equal(stageStatus(audit(p, "clinical-practice", balances.filter((r) => r !== cbt))), "unknown");
    assert.equal(
      stageStatus(audit(p, "clinical-practice", balances.map((r) => r === cbt ? { ...r, current: 0 } : r))),
      "short",
    );
  }
});

test("course evidence and official category balances reach the same capped totals", () => {
  const d = descriptor(medicine, 2026), c = fromCode("260M1208");
  const grade = { ...c, grade: "合格", matchedCourse: { ...c, confirmed: true } };
  const result = audit(d.profile, "graduation", [], [grade], [c]);
  assert.deepEqual(["major", "total"].map((k) => result.find((r) => r.key === k).current), [0.5, 0.5]);
  assert.deepEqual(result.find((r) => r.key === "total").earned.map((ref) => ref.applied), [0.5]);
  assert.equal(result.find((r) => r.key === "total").future, 0.5);
  const leaf = findStage(d).rows.find((r) => r.label === "倫理観と人間性Ⅰ");
  const scope = { ...d.profile, stageId: "graduation", goal: "graduation" };
  const award = {
    recordId: "synthetic-recognition",
    grade: "認定",
    year: "2024",
    credits: "0.5",
    title: "認定された旧課程科目",
    allocationKey: leaf.key,
    allocationScope: scope,
  };
  const recognized = audit(d.profile, "graduation", [], [award]);
  assert.deepEqual([leaf.key, "major", "total"].map((k) => recognized.find((r) => r.key === k).current), [
    0.5,
    0.5,
    0.5,
  ]);
  assert.equal(audit(d.profile, "year-3", [], [award]).find((r) => r.key === leaf.key).current, 0);
  const p = descriptor(health, 2026, { program: "看護学専攻" }).profile;
  const balances = [["general", 26], ["health-基礎必修", 15], ["health-基礎選択", 6], ["health-専門必修", 74], [
    "health-専門選択",
    3,
  ]]
    .map(([key, value]) => statement(p, "graduation", "graduation", key, "credits", value));
  const totals = audit(p, "graduation", balances);
  assert.equal(totals.find((r) => r.key === "major").current, 98);
  assert.equal(totals.find((r) => r.key === "total").current, 124);
  assert.equal(stageStatus(totals), "unknown");
  const known = row(descriptor(health, 2026, { program: p.program }), "health-専門必修").pool[0].key;
  const child = statement(p, "graduation", "graduation", known, "credits", 0.5);
  assert.equal(audit(p, "graduation", [child]).find((r) => r.key === "total").current, 0.5);
});

test("package discovery and graduation break exclusions use saved selections", () => {
  const c = fromCode("263T0201"), base = descriptor(creation, 2026, dx).profile;
  const key = "domain-foundation";
  assert.equal(satisfiesFilter(c, key, base), true);
  assert.equal(shortageFilter({ profile: base }, new Map(), [], { key, stageId: "graduation" })(c), true);
  assert.equal(satisfiesFilter(c, key, { ...base, program: "創生学修コース", field: "社会文化学" }), false);
  assert.equal(satisfiesFilter(c, key, { ...base, program: "創生学修コース", field: "情報社会デザイン科学" }), true);
  const course = { ...fromCode("261X0003"), period: "夏季休業", semester: "春学期" };
  const input = (profile, term = course) =>
    audit({ ...base, ...profile }, "graduation", [], [], [term]).find((r) => r.key === "total");
  assert.equal(input({ graduationMonth: "9", graduationYear: "2026" }).future, 0);
  assert.equal(input({ graduationMonth: 3, graduationYear: 2027 }).future, 2);
  assert.equal(input({ graduationMonth: 9, graduationYear: 2027 }).future, 2);
  assert.equal(input({ graduationMonth: 9, graduationYear: 2027 }, { ...course, period: "春期休業" }).future, 2);
  assert.equal(input({ graduationMonth: 3, graduationYear: 2027 }, { ...course, period: "春期休業" }).future, 0);
  for (const profile of [{}, { graduationMonth: 2, graduationYear: 2026 }, { assessmentDate: "2026-09-10" }]) {
    const r = input(profile);
    assert.equal(r.future, 0);
    assert.equal(r.futureStatus, "unknown");
    assert.match(r.note, /卒業予定の西暦年と月/);
  }
});

test("old oral welfare table specifies 107 mandatory credits and one two-credit elective", () => {
  const d = descriptor(oral, 2008), major = row(d, "major");
  assert.equal(major.pool.filter((p) => p.key !== "oral-choice").length, 39);
  assert.equal(major.pool.filter((p) => p.key !== "oral-choice").reduce((sum, p) => sum + p.cap, 0), 107);
  const oldChoice = row(d, "oral-choice");
  const course = { code: "081DA001", year: "2008", department: "08", title: "老人福祉論Ⅱ", credits: 2 };
  assert.equal(oldChoice.match(course), true);
  assert.equal(oldChoice.match({ ...course, title: "高齢者福祉論Ⅱ" }), false);
  assert.equal(projected(d, "major", [course, { ...course, code: "081DA002", title: "歯科予防処置Ⅲ" }]), 2);
  assert.match(oldChoice.source.url, /#page=8$/);
});

test("each named stage in every published handbook accepts sufficient evidence", () => {
  for (const book of handbooks) {
    const programs = book.programs?.filter((n) => n.includes("（") || n.endsWith("専攻") || n.startsWith("DX")) ?? [""];
    for (const program of programs) {
      const d = descriptor(book.faculty, book.year, {
        program,
        admitted: book.year,
        attendanceMonths: 72,
        yearAttendanceMonths: { 1: 12, 2: 12, 3: 12, 4: 12, 5: 12, 6: 12 },
        assessmentDate: "2027-04-01",
      });
      for (const s of d.stages.filter((s) => s.id !== "progress-selection")) {
        const balances = s.rows.filter((r) =>
          r.required != null && !r.pool && r.unit !== "months" && r.key !== "assessment-month"
        )
          .map((r) => statement(d.profile, s.id, s.goal, r.key, r.unit, r.required));
        const rows = audit(d.profile, s.id, balances);
        const label = book.faculty + " " + book.year + " " + program + " " + s.id;
        const missing = s.rows.filter((r) => r.required == null);
        if (!missing.length) {
          assert.deepEqual(
            rows.filter((r) => r.status !== "met").map((r) => [r.key, r.current, r.required]),
            [],
            label,
          );
          assert.equal(stageStatus(rows), "met", label);
          continue;
        }
        assert.equal(stageStatus(rows), "unknown", label);
        // Old appendices whose distribution is unavailable require the student's
        // actual official required/current figures. These splits are fictitious.
        const total = s.rows.find((r) => r.key === "total")?.required ?? 180;
        const synthetic = { total, general: 30, major: total - 30 };
        for (const r of missing) {
          assert.ok(Object.hasOwn(synthetic, r.key), label + " " + r.key);
          assert.match(r.unknown, /学務係/);
          balances.push({
            ...statement(d.profile, s.id, s.goal, r.key, r.unit, synthetic[r.key]),
            required: synthetic[r.key],
          });
        }
        assert.equal(stageStatus(audit(d.profile, s.id, balances)), "met", label);
      }
    }
  }
});
