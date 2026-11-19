import test from "node:test";
import assert from "node:assert/strict";
import {
  applyPlannerImport,
  confirmPlannerImport,
  reviewPlannerImport,
} from "../src/imports/review.mjs";
import { initialState } from "../src/study.mjs";

const table = (rows, heading = "成績確認表") => ({
  v: 1,
  kind: "grades",
  tables: [{ heading, rows }],
});
const head = [
  "年度",
  "科目名",
  "単位数",
  "評価",
  "開講番号",
  "クラス",
  "開講所属",
  "認定区分",
];
const a = ["2020", "同名講義", "＊1", "優", "200G0105", "A", "84", ""];
const b = ["2020", "同名講義", "2", "認定", "200H0106", "B", "01", "専門"];
const c = ["2019", "選択しない科目", "3", "良", "190H0106", "C", "01", ""];
const profile = { faculty: "例学部", handbook: "2020" };
const opts = {
  profile,
  deferMatch: true,
  requirementRows: [{ key: "major", label: "専門", required: 20 }],
};
const makeReview = (rows = [a, b, c]) =>
  reviewPlannerImport(table([head, ...rows]), opts);
const choose = (r) => r.rows.map(({ id }) => ({ id }));
const newState = () => ({ ...initialState(), profile });
const commit = (state) => (update) => {
  update(state);
  return true;
};
function match(g, fields = ["70"]) {
  return {
    year: g.year,
    title: g.title,
    code: g.code,
    department: g.offeringDepartment || "84",
    fields,
    category: "専門",
    confirmed: true,
    sourceUrl: "https://syllabus.niigata-u.ac.jp/",
    sourceKind: "syllabus",
    fieldSource: "https://syllabus.niigata-u.ac.jp/campus-sy/",
    categorySource: "https://www.niigata-u.ac.jp/example.pdf#page=2",
  };
}
function deferred() {
  let resolve;
  const promise = new Promise((r) => {
    resolve = r;
  });
  return { resolve, promise };
}

test("only selected grades are prepared and source values survive a reordered result", async () => {
  const review = makeReview(),
    state = newState();
  const original = structuredClone(review);
  const selections = choose(review).slice(0, 2);
  const ok = await confirmPlannerImport({
    review,
    selections,
    mutate: commit(state),
    prepareGrades(grades, previous) {
      assert.equal(previous.length, 0);
      assert.deepEqual(
        grades.map((g) => [g.code, g.reviewRowId]),
        [
          [a[4], selections[0].id],
          [b[4], selections[1].id],
        ],
      );
      return grades.reverse().map((g) => ({
        ...g,
        title: "別表での名称",
        credits: 99,
        duplicate: false,
        counts: true,
        recognized: false,
        allocationKey: "override",
        matchedCourse: g.recognized ? null : match(g),
      }));
    },
  });
  assert.equal(ok, true);
  assert.deepEqual(review, original);
  assert.deepEqual(
    state.grades.map((g) => [
      g.title,
      g.credits,
      g.code,
      g.offeringDepartment,
      g.recognized,
      g.duplicate,
      g.counts,
    ]),
    [
      ["同名講義", 1, a[4], "84", false, true, false],
      ["同名講義", 2, b[4], "01", true, false, true],
    ],
  );
  assert.equal(state.grades[1].allocationKey, "major");
  assert.equal(state.grades[1].matchedCourse, null);
  assert.deepEqual(state.grades[0].matchedCourse, match(state.grades[0]));
  assert.equal(state.grades[0].fields[0], "70");
  assert.equal(state.grades[0].source, "成績確認表");
  assert.equal(
    state.grades.some((g) => "reviewRowId" in g),
    false,
  );
});

test("original transcript spelling stays separate from its normalized syllabus title on reimport", async () => {
  const review = makeReview([
    ["2020", "講義Ⅰ", "2", "優", "200G0105", "A", "84", ""],
  ]);
  const state = newState();
  const selections = [{ id: review.rows[0].id, excludeDuplicate: true }];
  const prepareGrades = (grades) => {
    assert.equal(grades[0].title, "講義Ⅰ");
    assert.equal(grades[0].counts, false);
    assert.equal(grades[0].duplicateReviewed, true);
    return grades.map((grade) => ({
      ...grade,
      matchedCourse: { ...match(grade), title: "講義I" },
    }));
  };
  for (let i = 0; i < 2; i++)
    await confirmPlannerImport({
      review,
      selections,
      previousGrades: structuredClone(state.grades),
      prepareGrades,
      mutate: commit(state),
    });
  assert.equal(state.grades.length, 1);
  assert.equal(state.grades[0].title, "講義Ⅰ");
  assert.equal(state.grades[0].matchedCourse.title, "講義I");
});

test("freshly confirmed manual correspondence takes priority over the in-flight archive and stale history", async () => {
  const review = makeReview([b]),
    selections = choose(review),
    state = newState();
  applyPlannerImport(state, review, selections);
  const first = match(state.grades[0], ["20"]),
    manual = {
      ...match(state.grades[0], ["31"]),
      sourceKind: "manual-record",
      sourceUrl: "https://www.niigata-u.ac.jp/example.pdf#page=3",
    };
  state.grades[0].matchedCourse = first;
  const result = deferred();
  const previousGrades = structuredClone(state.grades);
  const pending = confirmPlannerImport({
    review,
    selections,
    previousGrades,
    mutate: commit(state),
    async prepareGrades(grades, previous) {
      assert.deepEqual(previous[0].matchedCourse, first);
      await result.promise;
      return grades.map((g) => ({ ...g, matchedCourse: first }));
    },
  });
  state.grades[0].matchedCourse = manual;
  result.resolve();
  await pending;
  assert.equal(state.grades.length, 1);
  assert.deepEqual(state.grades[0].matchedCourse, manual);
  assert.deepEqual(state.grades[0].fields, ["31"]);
  assert.equal(state.grades[0].importId, review.rows[0].value.importId);
});

test("an offline or ambiguous archive leaves original evidence importable and duplicate decisions intact", async () => {
  const review = makeReview([b, c]),
    selections = choose(review);
  selections[1].excludeDuplicate = true;
  for (const prepareGrades of [
    () => {
      throw Error("offline");
    },
    (grades) => grades.map((g) => ({ ...g, matchedCourse: null })),
    (grades) =>
      [...grades, ...grades].map((g) => ({ ...g, matchedCourse: match(g) })),
    (grades) =>
      grades.map((g) => ({
        ...g,
        reviewRowId: "foreign",
        matchedCourse: match(g),
      })),
    (grades) =>
      grades.map((g) => ({
        ...g,
        matchedCourse: { ...match(g), year: "1900" },
      })),
  ]) {
    const state = newState();
    await confirmPlannerImport({
      review,
      selections,
      prepareGrades,
      mutate: commit(state),
    });
    assert.deepEqual(
      state.grades.map((g) => [g.year, g.credits, g.matchedCourse, g.counts]),
      [
        ["2020", 2, null, true],
        ["2019", 3, null, false],
      ],
    );
    assert.equal(state.grades[0].allocationLabel, "専門");
  }
  const weak = makeReview([
    ["2019", "同名", "2", "優", "", "", "", ""],
    ["2019", "同名", "2", "優", "", "", "", ""],
  ]);
  const state = newState();
  await confirmPlannerImport({
    review: weak,
    selections: choose(weak),
    mutate: commit(state),
    prepareGrades: (grades) =>
      grades.map((g) => ({ ...g, matchedCourse: match(g) })),
  });
  assert.ok(
    state.grades.every(
      (g) => g.identityUncertain && !g.counts && !g.matchedCourse,
    ),
  );
});

test("a canceled lookup and a canceled queued transaction cannot write, and a retry has its own results", async () => {
  const review = makeReview([a]),
    selections = choose(review),
    state = newState();
  const first = deferred(),
    controller = new AbortController();
  const canceled = confirmPlannerImport({
    review,
    selections,
    signal: controller.signal,
    async prepareGrades(grades) {
      await first.promise;
      return grades.map((g) => ({ ...g, matchedCourse: match(g, ["12"]) }));
    },
    mutate() {
      assert.fail("canceled lookup reached storage");
    },
  });
  controller.abort();
  const save = async (fields, mutate) =>
    confirmPlannerImport({
      review,
      selections,
      mutate,
      prepareGrades: (grades) =>
        grades.map((g) => ({ ...g, matchedCourse: match(g, fields) })),
    });
  assert.equal(await save(["11"], () => false), false);
  assert.equal(await save(["21"], commit(state)), true);
  first.resolve();
  assert.equal(await canceled, false);
  assert.deepEqual(state.grades[0].fields, ["21"]);

  const lock = deferred(),
    entered = deferred(),
    second = new AbortController();
  const queued = confirmPlannerImport({
    review,
    selections,
    signal: second.signal,
    prepareGrades: (grades) => grades,
    async mutate(update) {
      entered.resolve();
      await lock.promise;
      update(state);
      return true;
    },
  });
  await entered.promise;
  second.abort();
  const before = structuredClone(state);
  lock.resolve();
  assert.equal(await queued, false);
  assert.deepEqual(state, before);
});

test("registration and balances never invoke grade preparation", async () => {
  for (const [kind, rows] of [
    [
      "registration",
      [
        ["開講番号", "登録状況"],
        ["201G0105", "許可"],
      ],
    ],
    [
      "balances",
      [
        ["区分", "既修得単位"],
        ["専門", "3"],
      ],
    ],
  ]) {
    const review = reviewPlannerImport(
      { v: 1, kind, tables: [{ heading: "", rows }] },
      { ...opts, byCode: new Map([["201G0105", { title: "講義" }]]) },
    );
    await confirmPlannerImport({
      review,
      selections: choose(review),
      prepareGrades() {
        assert.fail("non-grade data sent to archive");
      },
      mutate: commit(newState()),
    });
  }
});
