import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import resolve, { handbooks } from "../src/curricula/sciences.mjs";

const catalog = JSON.parse(
  readFileSync(new URL("../src/catalog-2026.json", import.meta.url)),
).courses;
const course = (code) => {
  const item = catalog.find((c) => c.code === code);
  assert.ok(item, code);
  return item;
};
const profile = (faculty, program, handbook = "2026", extra = {}) => ({
  faculty,
  program,
  handbook,
  entry: "1年次入学",
  ...extra,
});
const rows = (p, id = "graduation") =>
  Object.fromEntries(
    resolve(p)
      .stages.find((s) => s.id === id)
      .rows.map((r) => [r.key, r]),
  );
const evaluate = (r, courses) =>
  r.evaluate({ courses, profile: {}, baseline: {} });
const eng = (p = "機械システム工学", y, x) => profile("工学部", p, y, x);
const agr = (p = "応用生命科学", y, x) => profile("農学部", p, y, x);
const sci = (p = "物理学（総合力）", y, x) => profile("理学部", p, y, x);

test("progress defaults follow the next published gate and keep explicit choices available", () => {
  const pick = "progress-selection";
  const biological = agr("生物資源科学（植物資源科学分野）");
  for (const [student, expected] of [
    [sci(), ["year2", pick, "year4", pick]],
    [sci("数学科", "2016"), ["year2", "year3", "year4", pick]],
    [eng("機械システム工学プログラム"), ["year2", "year4", "year4", pick]],
    [biological, ["field-assignment", "field-assignment", "thesis", "thesis"]],
    [
      agr("食品科学プログラム"),
      ["research-guidance", "research-guidance", pick, "thesis"],
    ],
    [
      agr("応用生命科学プログラム"),
      ["research-guidance", "research-guidance", pick, "thesis"],
    ],
  ]) {
    for (const [i, stageId] of expected.entries()) {
      const info = resolve({ ...student, yearOfStudy: String(i + 1) });
      assert.equal(info.defaultStage, stageId);
      assert.deepEqual(
        info.stages.filter((s) => s.default).map((s) => s.id),
        [stageId],
      );
      const choice = info.stages.find((s) => s.id === pick);
      if (stageId === pick) {
        assert.equal(choice.rows[0].required, null);
        assert.equal(choice.rows[0].officialDecision, undefined);
        assert.ok(choice.rows[0].unknown);
      } else assert.equal(choice, undefined);
    }
  }
  for (const yearOfStudy of [undefined, "", 0, 5, "3.5"]) {
    assert.equal(resolve({ ...sci(), yearOfStudy }).defaultStage, pick);
  }
  const fourth = resolve({ ...sci(), yearOfStudy: 4 });
  assert.deepEqual(
    fourth.stages.slice(1).map((s) => s.id),
    ["year2", "assignment", "year3", "year4", "graduation"],
  );
  assert.equal(rows(biological, "field-assignment").total.required, 46);
});

test("single progress gates stay selectable and saved transfer entry grades control exceptions", () => {
  const transfer = { entry: "編入", entryGrade: 3, yearOfStudy: 4 };
  for (const [p, expected] of [
    [sci("物理学（総合力）", "2026", transfer), "year4"],
    [eng("機械システム工学プログラム", "2026", transfer), "year4"],
    [agr("食品科学プログラム", "2026", transfer), "thesis"],
    [agr("流域環境学プログラム", "2026", { yearOfStudy: 4 }), "thesis"],
  ]) {
    assert.deepEqual(
      resolve(p)
        .stages.filter((s) => s.goal === "progress")
        .map((s) => s.id),
      [expected],
    );
  }
  const p = eng("機械システム工学プログラム", "2026", transfer);
  assert.equal(rows(p, "year4").general.required, 28);
  assert.equal(rows(p, "year4").recognition.officialDecision, true);
  assert.equal(rows(p, "graduation").recognition.officialDecision, true);
  for (const entry of ["転部", "再入学", "編入・転部・再入学"]) {
    assert.ok(resolve({ ...p, entry }).stages.some((s) => s.id === "year2"));
  }
  assert.ok(
    resolve({ ...p, entryGrade: "" }).stages.some((s) => s.id === "year2"),
  );
  assert.equal(
    rows(sci(), "year4")["program-progress-4"].officialDecision,
    undefined,
  );
  assert.equal(rows(agr(), "thesis").guidance.officialDecision, true);
});

test("cohort and program descriptors have unique stages, row keys, public sources and valid thresholds", () => {
  assert.equal(handbooks.length, 62);
  for (const book of handbooks) {
    for (const program of book.programs) {
      const info = resolve(profile(book.faculty, program, book.year));
      assert.ok(info.stages.some((s) => s.goal === "graduation"));
      assert.equal(
        new Set(info.stages.map((s) => s.id)).size,
        info.stages.length,
      );
      for (const stage of info.stages) {
        assert.equal(
          new Set(stage.rows.map((r) => r.key)).size,
          stage.rows.length,
          book.title + program,
        );
        for (const r of stage.rows) {
          assert.ok(
            r.required === null || Number.isFinite(r.required),
            book.title + program + r.key,
          );
          assert.match(r.source.url, /^https:\/\//);
          assert.ok(
            r.match ||
              r.profileValue ||
              r.evaluate ||
              r.officialDecision ||
              r.unknown,
          );
        }
      }
    }
  }
  assert.equal(resolve(profile("法学部", "")), null);
  assert.equal(rows(eng("機械システム工学科", "2010")).total.required, null);
  assert.equal(resolve(sci("数学", "2040")).cap.limit, null);
});

test("engineering uses degree requirements for English Basics, field ownership, excluded G classes and night classes", () => {
  const r = rows(eng("協創経営"));
  for (const code of ["261G7011", "260G7002"]) {
    const c = { ...course(code), category: "英語" };
    assert.equal(r.human.match(c), true);
    assert.equal(r.english.match(c), false);
    assert.equal(r.socialPool.exclusive, r.human.exclusive);
    assert.equal(r.choice.exclusive, r.human.exclusive);
  }
  assert.equal(r.data.match(course("261G3008")), true);
  assert.equal(r.data.match(course("261G3001")), false);
  assert.equal(r.general.match(course("261G3023")), false);
  assert.equal(r.general.match(course("261G5003")), false);
  assert.equal(
    r.general.match({ ...course("261G7011"), nightCourse: true }),
    false,
  );
  assert.equal(
    r.human.match({ ...course("261G7011"), codeAmbiguous: true }),
    null,
  );
  assert.equal(rows(eng("力学分野", "2020")).english.required, 4);
  assert.equal(rows(eng("力学分野", "2021")).data.required, 1);
  assert.equal(
    rows(eng("力学分野", "2021")).data.match(course("261G3023")),
    true,
  );
});

test("engineering progression and program exceptions follow their own admission matrix", () => {
  const stage2 = rows(eng(), "year2");
  assert.equal(stage2.total.required, 32);
  assert.equal(
    stage2["engineering-first-five"].match(course("264T0004")),
    true,
  );
  const d = { code: "261T0009", title: "工場実習", credits: 2 };
  assert.equal(stage2.total.match(d), false);
  assert.equal(
    rows(eng("機械システム工学", "2022"), "year2").total.match(d),
    true,
  );
  const third = eng("化学システム工学（化学工学コース）", "2026", {
    entry: "第3年次編入学",
  });
  const fourth = rows(third, "year4");
  assert.equal(
    resolve(third).stages.some((s) => s.id === "year2"),
    false,
  );
  assert.deepEqual(
    [fourth.general.required, fourth.major.required, fourth.total.required],
    [28, 62, 104],
  );
  assert.equal(fourth["chem-■"].required, 4);
  assert.equal(fourth["chem-□"], undefined);
  assert.equal(
    rows(eng("化学システム工学（化学工学コース）", "2024"))["chem-□"].required,
    32,
  );
  assert.equal(
    rows(eng("化学システム工学（応用化学コース）", "2017"))["chem-●"].required,
    12,
  );
  assert.equal(
    rows(eng("化学システム工学（応用化学コース）", "2026"))["chem-○"].required,
    6,
  );
  assert.equal(rows(eng("機械システム工学"), "year4").major.required, 66);
  const e = [
    {
      title: "特設講義",
      code: "261T0009",
      year: "2026",
      credits: 8,
      engineeringGroup: "E",
    },
  ];
  assert.deepEqual(evaluate(fourth.major, e).contributions, [
    {
      title: "特設講義",
      code: "261T0009",
      year: "2026",
      credits: 8,
      applied: 6,
    },
  ]);
  assert.equal(evaluate(rows(third).major, e).value, 8);
});

test("engineering management packages distinguish lectures from labs and combine only a single old program", () => {
  const p = eng("協創経営（エネルギー・環境パッケージ）");
  const r = rows(p),
    lecture = { code: "261T1900", title: "電子情報通信概論", credits: 1 };
  assert.equal(r["eng-package"].match(lecture), true);
  const lab = { code: "261T1901", title: "化学工学実験Ⅰ", credits: 2 };
  assert.equal(r["eng-package"].match(lab), false);
  assert.equal(r["management-■"].match(lab), true);
  assert.equal(r["eng-B"].match(lab), true);
  const old = rows(eng("協創経営", "2018"))["eng-package"];
  assert.equal(old.required, 28);
  const input = ["機械工学概論", "社会基盤工学概論"].map((title, i) => ({
    title,
    code: "181T000" + i,
    credits: 2,
  }));
  assert.equal(evaluate(old, input).value, 2);
});

test("a validated semester split resolves only the timing of a CAP-eligible course", () => {
  const confirmed = { semesterSplitConfirmed: true };
  for (const [student, lecture] of [
    [eng(), course("261G3008")],
    [sci(), course("260G5016")],
    [agr(), { code: "261A0003", title: "例", format: "講義", credits: 2 }],
  ]) {
    const { classify } = resolve(student).cap;
    for (const period of ["通年", "第2・3ターム"]) {
      const annual = { ...lecture, period };
      assert.equal(classify(annual, student), "unknown");
      assert.equal(classify(annual, student, confirmed), "include");
      for (const value of [false, 0, "true"]) {
        assert.equal(
          classify(annual, student, { semesterSplitConfirmed: value }),
          "unknown",
        );
      }
      assert.equal(
        classify(annual, student, { first: -1, second: 3 }),
        "unknown",
      );
    }
  }

  const student = agr();
  const { classify } = resolve(student).cap;
  const annual = { code: "261A0003", title: "例", period: "通年", credits: 2 };
  assert.equal(
    classify({ ...annual, format: "講義・演習" }, student, confirmed),
    "unknown",
  );
  assert.equal(
    classify({ ...annual, format: "実験" }, student, confirmed),
    "exclude",
  );
  assert.equal(
    classify(
      { ...annual, format: "講義", failedRetake: true },
      student,
      confirmed,
    ),
    "exclude",
  );
});

test("agriculture checks each cohort's CAP and selected research stage instead of a year-wide promotion", () => {
  assert.equal(resolve(agr("食品科学", "2026", { gpa: "3.49" })).cap.limit, 24);
  const cap = resolve(agr("食品科学", "2026", { gpa: "3.5" })).cap;
  assert.equal(cap.limit, 28);
  const base = { title: "例", code: "261A0003" };
  assert.equal(cap.classify({ ...base, format: "講義・演習" }), "unknown");
  assert.equal(cap.classify({ ...base, format: "実験・実習" }), "exclude");
  assert.equal(cap.classify({ ...base, format: "講義" }), "include");
  assert.equal(
    cap.classify({ ...base, format: "講義", period: "第1～2ターム" }),
    "include",
  );
  assert.equal(
    cap.classify({ ...base, format: "講義", period: "通年" }),
    "unknown",
  );
  assert.equal(
    cap.classify({ ...base, format: "講義", period: "第2・3ターム" }),
    "unknown",
  );
  assert.equal(
    cap.classify({ ...base, format: "実験", period: "通年" }),
    "exclude",
  );
  assert.equal(
    cap.classify({ ...base, format: "講義", failedRetake: true }),
    "exclude",
  );
  assert.equal(
    resolve(agr("食品科学", "2022")).cap.classify({
      ...base,
      code: "221Q0003",
      format: "講義",
    }),
    "exclude",
  );
  const p = agr("流域環境学");
  assert.deepEqual(
    [
      rows(p, "thesis").general.required,
      rows(p, "thesis").major.required,
      rows(p, "thesis").total.required,
    ],
    [27, 68, 100],
  );
  assert.equal(
    resolve(p).stages.some((s) => s.label.includes("進級")),
    false,
  );
  const values = ["2022", "2023", "2024", "2025", "2026"].map(
    (year) => rows(agr("流域環境学", year))["ag-specialChoice"].required,
  );
  assert.deepEqual(values, [20, 22, 22, 24, 26]);
});

test("agriculture verifies course lists, admission-specific transfer and economics field conditions", () => {
  const r = rows(agr());
  assert.equal(r["ag-global"].match(course("260A4004")), null);
  assert.equal(
    r["ag-global"].match({
      ...course("260A4004"),
      code: "",
      title: "科学英語演習(応)",
    }),
    null,
  );
  const p = agr("生物資源科学（食料・資源経済学分野）", "2022");
  assert.equal(rows(p, "field-assignment").total.required, 46);
  assert.equal(
    rows(p, "thesis")["ag-economics-choice"].match({
      title: "環境保全型農業論",
      code: "221A0003",
    }),
    true,
  );
  assert.equal(
    rows({ ...p, handbook: "2026" }, "thesis")["ag-field-農業経営学"].required,
    1,
  );
  const transfer = agr("食品科学", "2026", { entry: "3年次編入" });
  assert.equal(
    resolve(transfer).stages.some((s) => s.id === "research-guidance"),
    false,
  );
  assert.equal(
    resolve({ ...transfer, handbook: "2022" }).stages.some(
      (s) => s.id === "research-guidance",
    ),
    true,
  );
});

test("science uses actual semester listings and applies two-class and subcap rules to contributions", () => {
  const r = rows(sci());
  const physics = [course("260G5016"), course("260G5018"), course("260G5512")];
  assert.equal(evaluate(r["sci-physics-I"], physics).value, 2);
  assert.equal(evaluate(r["sci-physics-II"], physics).value, 2);
  assert.equal(evaluate(r["sci-foundation"], physics).value, 4);
  const math = rows(sci("生物学（専門力）"))["sci-math-pair"];
  assert.equal(
    evaluate(math, [course("261G5003"), course("261G5004")]).value,
    1,
  );
  assert.equal(
    evaluate(math, [course("261G5003"), course("262G5005")]).value,
    2,
  );
  const labs = rows(sci("自然環境科学"))["sci-pool-指定実験・実習"];
  const core = ["262S6534", "263S6533", "260S6530", "260S6531"].map(course);
  assert.equal(evaluate(labs, core).value, 4);
  assert.equal(evaluate(labs, [...core, course("261S7536")]).value, 6);
  assert.equal(evaluate(labs, core.reverse()).value, 4);
});

test("science tracks cohort-specific read-across, admission and restricted academic evidence", () => {
  const old = rows(sci("数学科", "2016"));
  assert.equal(old.general.required, 25);
  assert.equal(old.major.required, 82);
  assert.equal(old["old-required-数学講究"].required, 8);
  assert.equal(rows(sci()).general.required, 21);
  assert.equal(rows(sci()).major.required, 84);
  const stage = rows(sci(), "year4");
  assert.equal(
    stage["year-3-months"].profileValue({ yearMonths: { 3: 11 } }),
    11,
  );
  assert.equal(stage["program-progress-4"].required, null);
  assert.match(stage["program-progress-4"].source.url, /rishu_guide/);
  const p = sci("生物学（総合力）", "2022"),
    physical = rows(p)["sci-pool-物理学"];
  assert.equal(physical.match(course("260G5015")), true);
  assert.equal(physical.match({ ...course("260G5015"), credits: 1 }), null);
  assert.equal(
    physical.match({ ...course("260G5015"), ambiguous: true }),
    null,
  );
  assert.equal(
    resolve({ ...p, entry: "3年次編入" }).cap.classify(course("260G5015")),
    "exclude",
  );
});

test("old engineering requires both successor courses, and retains admission-specific fields", () => {
  const r = rows(eng("機械システム工学科", "2015")),
    target = r["old-required-機械工作実習i"];
  assert.deepEqual(
    [r.general.required, r.major.required, r.total.required],
    [42, 82, 124],
  );
  const parts = ["Ⅰ", "Ⅱ"].map((suffix, i) => ({
    code: "181T010" + i,
    title: "機械工作実習" + suffix,
    year: "2018",
    credits: 1,
  }));
  assert.equal(evaluate(target, [parts[0]]).value, 0);
  assert.equal(evaluate(target, [parts[0], parts[0]]).value, 0);
  assert.equal(evaluate(target, parts).value, 2);
  assert.equal(
    evaluate(
      target,
      parts.map((c) => ({ ...c, ambiguous: true })),
    ).value,
    0,
  );
  const fusion = rows(eng("協創経営", "2019"), "year4")["eng-fusion"];
  const c = {
    code: "191T0100",
    title: "芸術コミュニケーション概論",
    credits: 2,
  };
  assert.equal(fusion.match(c), true);
  assert.equal(
    rows(eng("協創経営", "2021"), "year4")["eng-fusion"].match(c),
    false,
  );
});

test("agriculture records official legacy mandatory classes, transitional minima and the full GPA scale", () => {
  const r = rows(agr("食品科学", "2019"));
  assert.deepEqual(
    [
      r.general.required,
      r.major.required,
      r.english.required,
      r["ag-mandatory"].required,
    ],
    [35, 85, 4, 55],
  );
  const item = {
    code: "191A0001",
    title: "食品工学",
    credits: 2,
    format: "講義",
  };
  assert.equal(r["ag-mandatory"].match(item), true);
  assert.equal(r["base-lecture"].match(item), true);
  assert.equal(r["practice"].match(item), false);
  assert.equal(
    r["base-lecture"].match({ ...item, format: "講義・実習" }),
    null,
  );
  assert.equal(
    r["ag-mandatory"].match({ ...item, matchStatus: "ambiguous" }),
    null,
  );
  assert.equal(
    rows(agr("生物資源科学", "2021"))["retro-専門・選択必修"].required,
    34,
  );
  assert.equal(rows(agr("農業生産科学科", "2007")).general.required, 40);
  assert.match(
    rows(agr("農業生産科学科", "2008"))["former-2011教養"].label,
    /アグリビジネス論/,
  );
  for (const gpa of [4.5, 5])
    assert.equal(resolve(agr("食品科学", "2026", { gpa })).cap.limit, 28);
});

test("science distinguishes program research, published errata and the year of assessment", () => {
  const research = rows(sci("生物学（総合力）"))["sci-research-choice"];
  assert.equal(evaluate(research, [course("260S2566")]).value, 0);
  assert.equal(evaluate(research, [course("260S4536")]).value, 1);
  assert.equal(
    rows(sci("地質科学（専門力）", "2025"))["sci-pool-数学・統計学"].match(
      course("261G5007"),
    ),
    true,
  );
  assert.equal(
    rows(sci("地質科学（専門力）", "2026"))["sci-pool-数学・統計学"].match(
      course("261G5007"),
    ),
    false,
  );
  const modern = rows(sci(), "year4");
  assert.equal(
    modern["year-3-months"].profileValue({
      yearAttendanceMonths: { 3: 10 },
      attendanceMonths: 50,
    }),
    10,
  );
  assert.equal(
    modern["progress-month"].profileValue({ assessmentDate: "2026-10-01" }),
    1,
  );
  assert.equal(
    modern["progress-month"].profileValue({ assessmentDate: "2026-09-01" }),
    0,
  );
  assert.equal(
    modern["progress-month"].profileValue({ assessmentDate: "2026-02-31" }),
    null,
  );
  assert.equal(
    rows(sci("物理学（総合力）", "2024"), "year4")["progress-month"],
    undefined,
  );
  assert.equal(
    rows(sci("自然環境科学科", "2008"))["old-foundation"].required,
    22,
  );
  assert.equal(
    rows(sci("自然環境科学科", "2010"))["old-foundation"].required,
    20,
  );
  const study = rows(sci("数学（総合力）", "2021")).major;
  assert.equal(
    study.match({
      title: "理学スタディ・スキルズ",
      code: "211S0501",
      credits: 2,
    }),
    true,
  );
  assert.equal(
    study.match({ title: "別科目", code: "211S0501", credits: 2 }),
    null,
  );
  const fields = rows(sci("数学（総合力）", "2026"))["sci-practical-fields"];
  assert.equal(
    evaluate(fields, [course("263S0520"), course("264S0521")]).value,
    0,
  );
});
