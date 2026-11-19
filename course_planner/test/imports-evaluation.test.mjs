import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { buildHistoricalIndex, resolveHistoricalGrade } from "../src/archive/identity.mjs";
import { unpackYear } from "../src/archive/packs.mjs";
import { initialState } from "../src/study.mjs";
import { reviewGradeRows } from "../src/transcript.mjs";
import {
  applyPlannerImport,
  confirmPlannerImport,
  reviewPlannerImport,
} from "../src/imports/review.mjs";
import catalog from "../src/catalog-2026.json" with { type: "json" };

const course = catalog.courses.find((c) => c.code === "260K9202");
const byCode = new Map([[course.code, course]]);
const headers = [
  "開講番号",
  "科目名",
  "年度",
  "配当単位",
  "修得単位",
  "評価",
  "合否",
  "履修状況",
];
const failed = [
  course.code,
  course.title,
  "2026",
  "2",
  "0",
  "不可",
  "不合格",
  "確定",
];
const review = (rows, options = {}) =>
  reviewPlannerImport(
    {
      v: 1,
      kind: "grades",
      tables: [{ heading: "成績確認表", rows }],
    },
    { byCode, deferMatch: true, ...options },
  );
const confirm = (r) => [{ id: r.rows[0].id, confirmFinalEvaluation: true }];
const save = (s) => (update) => {
  update(s);
  return true;
};

test("code-only grade imports recover a title and validate allocated credits from the same offering", async () => {
  const pack = JSON.parse(await readFile(new URL("../src/archive/packs/2025.json", import.meta.url), "utf8"));
  const past = unpackYear("2025", pack);
  const options = { byCode: new Map(catalog.courses.map((c) => [c.code, c])),
    evaluationIndices: new Map([["2025", past]]), deferMatch: false };
  const title = "現代教育学概論";
  const make = (cells, opts = {}) => review([Object.keys(cells), Object.values(cells)], { ...options, ...opts });
  const base = { 履修年度: "2025", 開講番号: "250K0363", 開講所属: "教育学部", 評価: "不可", 修得単位: "0" };
  for (const year of ["2025", "2026"]) {
    const code = year.slice(2) + "0K0363";
    for (const dept of ["03", "教育学部"]) {
      const id = { 履修年度: year, 開講番号: code, 開講所属: dept };
      for (const source of [{}, { 科目名: title }]) {
        for (const units of [{ 評価: "不可", 修得単位: "0" }, { 評価: "不可", 配当単位: "2", 修得単位: "0" },
          { 評価: "優", 配当単位: "2" }, { 評価: "優", 修得単位: "2" }]) {
          const r = make({ ...id, ...source, ...units });
          const final = units.評価 === "不可";
          const g = final ? r.rows[0].finalEvaluationCandidate : r.rows[0].value;
          assert.deepEqual([g.year, g.code, g.offeringDepartment, g.title, g.credits, g.grade, g.counts, g.duplicate],
            [year, code, dept, title, 2, units.評価, !final, false]);
          if (!source.科目名 || (final && !units.配当単位)) {
            assert.equal(g.matchedCourse.code, code);
            assert.equal(g.matchedCourse.year, year);
            if (year === "2025") assert.match(g.matchedCourse.creditSource, /\.pdf#page=90$/);
          }
          if (final) {
            assert.equal(r.rows[0].value, undefined);
            assert.throws(() => applyPlannerImport(initialState(), r, [{ id: r.rows[0].id }]), /最終評価/);
          }
        }
      }
      const titleOnly = make({ 履修年度: year, 科目名: "教育実践研究Ⅰ", 開講所属: dept, 評価: "不可", 修得単位: "0" });
      const g = titleOnly.rows[0].finalEvaluationCandidate;
      assert.deepEqual([g.title, g.code, g.credits, g.matchedCourse.code], ["教育実践研究Ⅰ", "", 2, year.slice(2) + "0K0018"]);
      assert.equal(make({ 履修年度: year, 科目名: title, 開講所属: dept, 評価: "不可", 修得単位: "0" })
        .rows[0].finalEvaluationCandidate, undefined);
    }
  }
  const passRow = { 履修年度: "2025", 開講番号: "250K0363", 開講所属: "教育学部", 配当単位: "2", 評価: "優" };
  const mismatch = make({ ...passRow, 配当単位: "3" }).rows[0];
  assert.equal(mismatch.value, undefined);
  assert.match(mismatch.reason, /要確認.*3単位/);
  for (const row of [
    { ...base, 開講番号: "260K0363" }, { ...base, 開講番号: "" }, { ...base, 履修年度: "" },
    { ...base, 科目名: "異なる科目名" }, { ...passRow, 開講所属: "工学部" }, { ...base, 学期: "後期" },
    { ...passRow, クラス: "B" }, { ...base, 配当単位: "3" }, { ...passRow, 評価: "認定" },
    { ...passRow, 修得単位: "1" }, { ...passRow, 履修年度: "2015", 開講番号: "150K0363" },
  ]) {
    const r = make(row).rows[0];
    assert.ok(!r.value && !r.finalEvaluationCandidate && !r.evaluationYear, JSON.stringify(row));
  }
  const actual = past.byCode.get("250k0363")[0];
  for (const index of [null, buildHistoricalIndex("2025", [actual, actual]),
    buildHistoricalIndex("2025", [{ ...actual, creditSource: undefined }])]) {
    for (const row of [base, passRow]) {
      const r = make(row, { evaluationIndices: new Map([["2025", index]]) }).rows[0];
      assert.ok(!r.value && !r.finalEvaluationCandidate && !r.evaluationYear);
    }
  }
  for (const row of [base, { ...base, 配当単位: "2" }, passRow]) {
    const r = make(row, { evaluationIndices: undefined }).rows[0];
    assert.ok(!r.value && !r.finalEvaluationCandidate);
    assert.equal(r.evaluationYear, "2025");
  }
  // A later transcript spelling is stronger than a title recovered for a code-only row.
  for (const record of [base, passRow]) {
    const state = initialState();
    const input = { ...record, 開講番号: "250K0018" };
    const titleOnly = { ...record, 科目名: "教育実践研究Ⅰ" };
    delete titleOnly.開講番号;
    let importId;
    let prepared = 0;
    for (const source of [input, input, titleOnly, { ...input, 科目名: "教育実践研究Ⅰ" }, input]) {
      const r = make(source, { grades: state.grades, deferMatch: true });
      assert.equal(state.grades.length, importId ? 1 : 0);
      const priorCalls = prepared;
      await confirmPlannerImport({ review: r, selections: confirm(r), mutate: save(state),
        prepareGrades(grades) {
          prepared++;
          return grades.map((grade) => ({ ...grade, matchedCourse: resolveHistoricalGrade(grade, past).match }));
        },
      });
      assert.equal(prepared, priorCalls + 1);
      assert.equal(state.grades.length, 1);
      importId ??= state.grades[0].importId;
      assert.equal(state.grades[0].importId, importId);
      assert.equal(state.grades[0].code, "250K0018");
      assert.equal(state.grades[0].matchedCourse.code, "250K0018");
    }
    assert.equal(state.grades[0].title, "教育実践研究Ⅰ");
    assert.equal(state.grades[0].titleFromOffering, undefined);
  }
});

test("earned zero borrows only a unique same-year offering's corroborated allocated credits", async () => {
  const pack = JSON.parse(await readFile(new URL("../src/archive/packs/2025.json", import.meta.url), "utf8"));
  const past = unpackYear("2025", pack);
  const actual = past.byCode.get("250k0363")[0];
  assert.equal(actual.creditSource, pack.listing + "#page=90");
  const current = catalog.courses.find((c) => c.code === "260K0363");
  const options = { byCode: new Map([[current.code, current]]), evaluationIndices: new Map([["2025", past]]) };
  const header = ["履修年度", "開講番号", "科目名", "開講所属", "修得単位", "評価"];
  const original = ["2025", actual.code, actual.title, "教育学部", "0", "不可"];
  const rowsFor = (row, suffix = [], extra = {}) =>
    review([[...header, ...suffix], row], { ...options, ...extra }).rows[0];
  for (const [year, code] of [["2025", actual.code], ["2026", current.code]]) {
    for (const department of ["03", "教育学部"]) {
      const row = rowsFor([year, code, actual.title, department, "0", "不可", "前期"], ["学期"]);
      assert.equal(row.value, undefined);
      const g = row.finalEvaluationCandidate;
      assert.deepEqual([g.year, g.code, g.offeringDepartment, g.credits, g.counts, g.duplicate],
        [year, code, department, 2, false, false]);
    }
  }
  for (const [suffix, value] of [["学期", "後期"], ["クラス", "A"], ["科目ID", "999"], ["重複", "重複"], ["状態", "保留"]]) {
    assert.equal(rowsFor([...original, value], [suffix]).finalEvaluationCandidate, undefined, suffix);
  }
  for (const [i, value] of [[0, "2026"], [0, ""], [1, current.code], [2, "別の科目"], [3, "工学部"], [4, "1"]]) {
    const changed = [...original];
    changed[i] = value;
    assert.equal(rowsFor(changed).finalEvaluationCandidate, undefined, String(i));
  }
  for (const candidates of [[actual, actual], [{ ...actual, creditSource: undefined }], [{ ...actual, credits: undefined }]]) {
    const index = buildHistoricalIndex("2025", candidates);
    assert.equal(rowsFor(original, [], { evaluationIndices: new Map([["2025", index]]) }).finalEvaluationCandidate, undefined);
  }
  const missing = rowsFor(original, [], { evaluationIndices: new Map() });
  assert.equal(missing.evaluationYear, "2025");
  assert.equal(missing.finalEvaluationCandidate, undefined);
  assert.equal(rowsFor(original, [], { evaluationIndices: new Map([["2025", null]]) }).evaluationYear, undefined);
  const explicit = rowsFor([...original, "3"], ["配当単位"], { evaluationIndices: undefined });
  assert.equal(explicit.evaluationYear, undefined);
  assert.equal(explicit.finalEvaluationCandidate.credits, 3);
  const duplicate = [...original];
  duplicate[3] = "03";
  const repeated = review([header, original, duplicate], options);
  assert.ok(repeated.rows.every((r) => !r.value && !r.finalEvaluationCandidate && !r.evaluationYear));
  const sameSemester = review([[...header, "学期"], [...original, "前期"], [...duplicate, "第1学期"]], options);
  assert.ok(sameSemester.rows.every((r) => !r.finalEvaluationCandidate));
  const previous = rowsFor(original).finalEvaluationCandidate;
  assert.equal(rowsFor(original, [], { grades: [{ ...previous, credits: 3 }] }).finalEvaluationCandidate, undefined);
  const ready = review([header, original], options), state = initialState();
  await assert.rejects(confirmPlannerImport({
    review: ready, selections: confirm(ready), mutate: save(state),
    prepareGrades(incoming) {
      state.grades = [{ ...previous, credits: 3, teacherTrainingOnly: false }];
      return incoming;
    },
  }), /配当単位/);
  assert.equal(state.grades[0].credits, 3);
  assert.equal(state.grades[0].teacherTrainingOnly, false);
});

test("a final failing evaluation requires its own confirmation, preserves allocated credits and uses the archive", async () => {
  const rows = [headers, failed];
  const r = review(rows),
    s = initialState();
  assert.equal(r.rows[0].value, undefined);
  assert.equal(r.rows[0].skipped, true);
  assert.equal(reviewGradeRows(rows, byCode).candidates.length, 0);
  assert.throws(
    () => applyPlannerImport(s, r, [{ id: r.rows[0].id }]),
    /最終評価/,
  );
  const selection = confirm(r);
  selection[0].confirmDistinct = selection[0].excludeDuplicate = true;
  let calls = 0;
  const prepareGrades = (grades) => {
    calls++;
    assert.deepEqual(
      grades.map((g) => [
        g.grade,
        g.finalEvaluation,
        g.credits,
        g.counts,
        g.duplicate,
      ]),
      [["不可", true, 2, false, false]],
    );
    return grades.map((g) => ({
      ...g,
      matchedCourse: { ...course, year: "2026", confirmed: true },
    }));
  };
  for (let n = 0; n < 2; n++) {
    const next = review(rows, { grades: s.grades });
    await confirmPlannerImport({
      review: next,
      selections: selection,
      previousGrades: s.grades,
      prepareGrades,
      mutate: save(s),
    });
    assert.equal(s.grades.length, 1);
    assert.equal(s.grades[0].matchedCourse.code, course.code);
    assert.equal(
      s.grades[0].importId,
      r.rows[0].finalEvaluationCandidate.importId,
    );
    assert.deepEqual(
      [
        s.grades[0].grade,
        s.grades[0].counts,
        s.grades[0].duplicate,
        s.grades[0].credits,
      ],
      ["不可", false, false, 2],
    );
    if (n === 1) assert.equal(s.grades[0].teacherTrainingOnly, false);
    s.grades[0].teacherTrainingOnly = false;
  }
  assert.equal(calls, 2);
});

test("only explicit final results qualify, with consistent course and earned unit columns", () => {
  for (const [col, value] of [
    [3, ""],
    [4, "2"],
    [5, "欠席"],
    [5, "履修中"],
    [5, "辞退"],
    [5, "F"],
    [5, "未修得"],
    [6, "合格"],
    [7, "未確定"],
    [7, "履修取消"],
    [7, "保留"],
  ]) {
    const mixed = [...failed];
    mixed[col] = value;
    const r = review([headers, mixed]);
    assert.equal(r.rows[0].finalEvaluationCandidate, undefined, value);
    assert.throws(() => applyPlannerImport(initialState(), r, confirm(r)));
  }
  const marked = review([
    [...headers, "重複"],
    [...failed, "重複"],
  ]);
  assert.equal(marked.rows[0].finalEvaluationCandidate, undefined);
  const withheld = review([
    [...headers, "評価状況"],
    [...failed, "未確定"],
  ]);
  assert.equal(withheld.rows[0].finalEvaluationCandidate, undefined);
  const withdrawn = [...failed];
  withdrawn.splice(4, 4, "2", "良", "合格", "履修取消");
  assert.equal(review([headers, withdrawn]).rows[0].value, undefined);
  const onlyEarned = [
    ["開講番号", "科目名", "年度", "修得単位", "評価"],
    [course.code, course.title, "2026", "0", "不合格"],
  ];
  assert.equal(review(onlyEarned).rows[0].finalEvaluationCandidate.credits, 2);
  assert.equal(
    review(onlyEarned, { byCode: new Map() }).rows[0].finalEvaluationCandidate,
    undefined,
  );
  const onlyResult = review([
    ["科目名", "単位数", "合否"],
    [course.title, "2", "不合格"],
  ]);
  assert.equal(onlyResult.rows[0].finalEvaluationCandidate.grade, "不合格");
});

test("conflicting original or newly saved outcomes cannot replace a confirmed attempt", async () => {
  const passed = [...failed];
  passed.splice(4, 4, "2", "優", "合格", "");
  const together = review([headers, passed, failed]);
  assert.ok(
    together.rows.every((row) => !row.value && !row.finalEvaluationCandidate),
  );
  const absent = [...failed];
  absent.splice(5, 3, "欠席", "", "");
  assert.ok(
    review([headers, failed, absent]).rows.every(
      (row) => !row.finalEvaluationCandidate,
    ),
  );
  const s = initialState(),
    r = review([headers, failed]);
  await assert.rejects(
    confirmPlannerImport({
      review: r,
      selections: confirm(r),
      mutate: save(s),
      async prepareGrades(gs) {
        const earned = review([headers, passed]);
        applyPlannerImport(s, earned, [{ id: earned.rows[0].id }]);
        return gs;
      },
    }),
    /保存済みの評価/,
  );
  assert.deepEqual(
    s.grades.map((g) => [g.grade, g.counts]),
    [["優", true]],
  );
  const previous = review([headers, failed], { grades: s.grades });
  assert.equal(previous.rows[0].finalEvaluationCandidate, undefined);
  const unevaluated = {
    ...r.rows[0].finalEvaluationCandidate,
    evaluated: false,
  };
  assert.equal(
    review([headers, failed], { grades: [unevaluated] }).rows[0]
      .finalEvaluationCandidate,
    undefined,
  );
  const retry = [...failed];
  retry[2] = "2025";
  const retake = review([headers, retry], { grades: s.grades });
  applyPlannerImport(s, retake, confirm(retake));
  assert.equal(s.grades.length, 2);
  const reverse = review([headers, passed], {
    grades: [r.rows[0].finalEvaluationCandidate],
  });
  assert.equal(reverse.rows[0].value, undefined);
});

test("ambiguous same-name failures stay distinct and cannot provide a confirmed offering", async () => {
  const rows = [
    ["科目名", "単位数", "評価", "年度"],
    [course.title, "2", "不可", "2026"],
    [course.title, "2", "不可", "2026"],
  ];
  const r = review(rows),
    s = initialState();
  await confirmPlannerImport({
    review: r,
    selections: r.rows.map(({ id }) => ({ id, confirmFinalEvaluation: true })),
    prepareGrades: (gs) =>
      gs.map((g) => ({
        ...g,
        matchedCourse: { ...course, year: "2026", confirmed: true },
      })),
    mutate: save(s),
  });
  assert.equal(s.grades.length, 2);
  assert.equal(new Set(s.grades.map((g) => g.importId)).size, 2);
  assert.ok(
    s.grades.every(
      (g) =>
        g.finalEvaluation &&
        g.identityUncertain &&
        !g.counts &&
        !g.duplicate &&
        !g.matchedCourse,
    ),
  );
});
