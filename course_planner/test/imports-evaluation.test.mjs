import assert from "node:assert/strict";
import test from "node:test";
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
