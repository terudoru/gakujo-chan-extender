import test from "node:test";
import assert from "node:assert/strict";
import {
  createRequirementAPI,
  gradeCourses,
  requirementGroups,
  stageStatus,
} from "../src/requirements.mjs";
import {
  assessmentMonth,
  attendanceMonths,
  matchBalanceRow,
} from "../src/curricula/engine.mjs";

// A self-contained synthetic handbook. The real faculty data packs can be
// imported independently without changing these fixtures or the working tree.
const source = {
  title: "試験用便覧",
  url: "https://example.invalid/handbook#page=3",
};
const book = { faculty: "試験学部", year: "2021", programs: ["甲"], ...source };
const profile = {
  faculty: book.faculty,
  handbook: book.year,
  program: "甲",
  admitted: "2018",
};
const state = (grades = [], balances = []) => ({
  profile: { ...profile },
  grades,
  balances,
  status: {},
});
const course = (code, title, category, credits = 2) => ({
  code,
  title,
  category,
  credits,
  year: "2026",
  department: "09",
  fields: ["70"],
  period: "第1ターム",
  schedule: "火3",
  semester: "第1学期",
});
const flex = course("261T0001", "共通選択", "AB");
const aOnly = course("261T0002", "A専用", "A");
const bOnly = course("261T0003", "B専用", "B");
const other = course("261T0004", "算入外", "X");
const byCode = new Map([flex, aOnly, bOnly, other].map((c) => [c.code, c]));
const grade = (c, extra) => ({ ...c, grade: "優", ...extra });
const inBucket = (k) => (c) => (c.category ? c.category.includes(k) : null);
const leaf = (key, required = 2, extra = {}) => ({
  key,
  label: key + "区分",
  kind: "選択",
  required,
  match: inBucket(key),
  source,
  ...extra,
});
const a = leaf("A", 2, { exclusive: "choice" }),
  b = leaf("B", 2, { exclusive: "choice" });
function apiFor(rows, additions = {}) {
  return createRequirementAPI([
    {
      handbooks: [book],
      default(p) {
        if (p.faculty !== book.faculty || p.handbook !== book.year) return null;
        return {
          title: book.title,
          sources: [source],
          stages: [
            {
              id: "fourth",
              label: "4年次",
              goal: "progress",
              rows: [leaf("A", 1)],
            },
            { id: "degree", label: "卒業", goal: "graduation", rows },
          ],
          ...additions,
        };
      },
    },
  ]);
}
const named = (rows, key) => rows.find((r) => r.key === key);
const balance = (key, current, patch = {}) => ({
  ...profile,
  goal: "graduation",
  stageId: "degree",
  key,
  label: key + "区分",
  current,
  confirmed: true,
  ...patch,
});

test("registry resolves handbook, actual program, and exact stage; unknown dates stay selectable", () => {
  const api = apiFor([a, b]);
  assert.deepEqual(api.availableHandbooks(profile), [book]);
  assert.deepEqual(api.availablePrograms(profile), ["甲"]);
  assert.deepEqual(api.availablePrograms({ ...profile, handbook: "2019" }), []);
  assert.deepEqual(
    api.availableStages(profile, "progress").map((s) => s.id),
    ["fourth"],
  );
  assert.equal(api.facultyInfo(profile).title, book.title);
  assert.deepEqual(api.requirementRows(state(), byCode, [], "wrong-id"), []);
  assert.equal(
    api.requirementRows(state(), byCode, [], "fourth")[0].required,
    1,
  );
  assert.equal(
    api.facultyInfo({ ...profile, handbook: "1991" }).verified,
    false,
  );
});

test("historical confirmation retains original record identity and limits unknown to unsupported evidence", () => {
  const api = apiFor([leaf("A", 9)]);
  const older = grade(aOnly, {
    year: "2021",
    title: "旧表記",
    recordId: "row-1",
  });
  const s = state([older]);
  assert.deepEqual(gradeCourses(s, byCode)[0].fields, []);
  let row = api.requirementRows(s, byCode, [other])[0];
  assert.deepEqual(
    [row.current, row.remaining, row.status, row.evidence.unknown.length],
    [0, null, "unknown", 1],
  );
  s.grades[0] = {
    ...older,
    matchedCourse: {
      ...aOnly,
      code: "211T9999",
      year: "2021",
      sourceUrl: "https://example.invalid/2021/211T9999",
      confirmed: true,
    },
  };
  row = api.requirementRows(s, byCode, [other])[0];
  assert.deepEqual(
    [row.current, row.remaining, row.after, row.planned.length],
    [2, 7, 7, 0],
  );
  const ref = row.evidence.earned[0];
  assert.deepEqual(
    [ref.title, ref.code, ref.year, ref.applied, ref.sourceUrl, ref.source],
    [
      "旧表記",
      aOnly.code,
      "2021",
      2,
      s.grades[0].matchedCourse.sourceUrl,
      source,
    ],
  );
  assert.deepEqual(row.evidence.sources, [source]);
  assert.equal(api.satisfiesFilter(other, "A", profile), false);
});

test("exclusive assignments reroute flexible courses and are independent of transcript order", () => {
  const api = apiFor([a, b]);
  for (const list of [
    [flex, aOnly],
    [aOnly, flex],
  ]) {
    const rows = api.requirementRows(
      state(list.map((c) => grade(c))),
      byCode,
      [],
    );
    assert.deepEqual(
      rows.map((r) => [r.current, r.earned[0].code]),
      [
        [2, aOnly.code],
        [2, flex.code],
      ],
    );
    assert.deepEqual(
      requirementGroups(rows).map((g) => g.rows.length),
      [2],
    );
  }
  const rows = api.requirementRows(state([grade(flex)]), byCode, [aOnly]);
  assert.deepEqual(
    rows.map((r) => [r.current, r.future]),
    [
      [2, 2],
      [0, 2],
    ],
  );
  assert.equal(rows[1].projectedEarned[0].code, flex.code);
});

test("official balances reserve underlying grades across exclusive rows and future credits only once", () => {
  const api = apiFor([a, b]);
  const s = state([grade(flex)], [balance("B", 2)]);
  const rows = api.requirementRows(s, byCode, [flex, aOnly]);
  assert.deepEqual(
    rows.map((r) => [r.current, r.future]),
    [
      [0, 2],
      [2, 2],
    ],
  );
  assert.equal(rows[1].balance.key, "B");
  assert.deepEqual(rows[1].earned, []);
  assert.equal(rows[1].covered[0].code, flex.code);
  for (const mismatch of [
    { faculty: "別" },
    { handbook: "2022" },
    { program: "乙" },
    { goal: "progress" },
    { stageId: "fourth" },
    { entry: "編入・転部・再入学" },
    { field: "別分野" },
    { curriculum: "別課程" },
    { confirmed: false },
  ]) {
    assert.equal(
      api.requirementRows(state([], [balance("B", 2, mismatch)]), byCode, [])[1]
        .current,
      0,
    );
  }
  const conflict = api.requirementRows(
    state([], [balance("B", 1), balance("B", 2)]),
    byCode,
    [],
  )[1];
  assert.deepEqual(
    [conflict.current, conflict.remaining, conflict.status],
    [null, null, "unknown"],
  );
});

test("an undecidable allocation can release earned credits into a different row", () => {
  const maybe = grade({ ...other, title: "別表照合待ち", code: "261T0020" });
  const uncertain = {
    ...a,
    match: (c) => (c.code === maybe.code ? null : a.match(c)),
  };
  const api = apiFor([uncertain, b]);
  const s = state([
    grade(flex),
    { ...maybe, matchedCourse: { ...maybe, confirmed: true } },
  ]);
  const rows = api.requirementRows(s, byCode, []);
  assert.deepEqual(
    [rows[1].current, rows[1].remaining, rows[1].unresolved[0].code],
    [0, null, maybe.code],
  );
  s.balances = [balance("B", 1), balance("B", 2)];
  assert.equal(api.requirementRows(s, byCode, [])[0].status, "unknown");
});

test("balances match exact unambiguous statement labels and resist stage and field leakage", () => {
  const stages = [
    { id: "second", goal: "progress", rows: [a] },
    { id: "third", goal: "progress", rows: [a] },
  ];
  const api = apiFor([], { stages });
  const s = state(
    [],
    [balance("A", 2, { stageId: undefined, goal: "progress" })],
  );
  assert.equal(api.requirementRows(s, byCode, [], "second")[0].current, 0);
  s.balances[0] = balance(undefined, 2, {
    stageId: "third",
    goal: "progress",
    label: a.label,
  });
  assert.equal(api.requirementRows(s, byCode, [], "third")[0].current, 2);
  assert.equal(api.requirementRows(s, byCode, [], "second")[0].current, 0);
  const collision = matchBalanceRow(
    { label: a.label },
    { rows: [a, { ...b, label: a.label }] },
  );
  assert.equal(collision.status, "review");
  assert.deepEqual(collision.candidates, ["A", "B"]);
});

test("fractional credits, course counts, repeats, recognition and equivalent titles", () => {
  const api = apiFor(
    [leaf("A", 8), leaf("count", 3, { unit: "courses", match: inBucket("A") })],
    {
      equivalences: [
        ["旧科目", "読替科目"],
        ["読替科目", "現科目"],
      ],
    },
  );
  const old = course("261T0007", "旧科目", "A", 0.5);
  const next = course("261T0008", "現科目", "A", 0.5);
  const s = state([
    grade(old, { matchedCourse: { ...old, confirmed: true } }),
    grade(aOnly, { counts: false, duplicate: true }),
    grade(bOnly, { grade: "不可" }),
    {
      title: "他大学の認定科目",
      grade: "認定",
      year: "2024",
      credits: 1.5,
      allocationKey: "A",
    },
  ]);
  let row = api.requirementRows(s, byCode, [next, aOnly])[0];
  assert.deepEqual([row.current, row.future, row.planned.length], [2, 4, 1]);
  s.grades.push({
    title: "未配分の認定",
    year: "2024",
    grade: "認定",
    credits: 5,
  });
  row = api.requirementRows(s, byCode, [next, aOnly])[0];
  assert.deepEqual(
    [row.current, row.future, row.remaining, row.after, row.unresolved.length],
    [2, 4, null, null, 1],
  );
  const count = api.requirementRows(state([grade(flex)]), byCode, [aOnly])[1];
  assert.deepEqual(
    [count.unit, count.current, count.future],
    ["courses", 1, 2],
  );
});

test("ambiguous same-title offerings remain visible and known repeatable offerings count separately", () => {
  const api = apiFor([leaf("A", 8)]);
  const duplicateTitle = { ...aOnly, code: "261T0009" };
  const s = state([grade(aOnly)]);
  const row = api.requirementRows(s, byCode, [duplicateTitle])[0];
  assert.deepEqual(
    [row.future, row.after, row.unresolved[0].code],
    [2, null, duplicateTitle.code],
  );
  assert.equal(
    api.requirementRows(s, byCode, [{ ...duplicateTitle, repeatable: true }])[0]
      .future,
    4,
  );
});

test("capped child pools allocate shared courses once and leave unrelated minima outstanding", () => {
  const api = apiFor([
    leaf("A", 4),
    leaf("B", 4),
    {
      key: "pool",
      label: "共通枠",
      required: 5,
      pool: [
        { key: "A", cap: 2 },
        { key: "B", cap: 2 },
      ],
    },
  ]);
  const s = state([grade(flex), grade(aOnly)]);
  const rows = api.requirementRows(s, byCode, [bOnly]);
  const pool = named(rows, "pool");
  assert.deepEqual(
    [pool.current, pool.future, pool.remaining, pool.after],
    [4, 4, 1, 1],
  );
  assert.equal(
    pool.earned.reduce((sum, c) => sum + c.applied, 0),
    4,
  );
  assert.equal(
    named(api.requirementRows(state([grade(flex)]), byCode, []), "pool")
      .current,
    2,
  );
});

test("assessment date, credited attendance, individual decision and custom pair evaluator", () => {
  const api = apiFor([
    {
      key: "months",
      label: "在学",
      unit: "months",
      required: 24,
      profileValue: (p) => attendanceMonths(p),
    },
    {
      key: "year",
      label: "学年別",
      unit: "months",
      required: 12,
      profileValue: (p) => attendanceMonths(p, 3),
    },
    {
      key: "month",
      label: "判定月",
      unit: "condition",
      required: 1,
      profileValue: (p) => assessmentMonth(p, [4, 10]),
    },
    {
      key: "approval",
      label: "個別認定",
      unit: "condition",
      required: 1,
      profileValue: (p) => p.approved,
    },
    {
      key: "pair",
      label: "AとB",
      required: 2,
      unit: "courses",
      evaluate({ courses }) {
        const one = courses.find((c) => c.category === "A"),
          two = courses.find((c) => c.category === "B");
        const chosen = [one, two].filter(Boolean);
        return {
          value: chosen.length,
          contributions: chosen.map((course) => ({ course, applied: 1 })),
        };
      },
    },
  ]);
  const s = state([grade(aOnly)]);
  let rows = api.requirementRows(s, byCode, [bOnly]);
  assert.deepEqual(
    rows.slice(0, 4).map((r) => r.status),
    Array(4).fill("unknown"),
  );
  Object.assign(s.profile, {
    attendanceMonths: 26,
    yearAttendanceMonths: { 3: 9 },
    assessmentDate: "2026-02-30",
    approved: false,
  });
  rows = api.requirementRows(s, byCode, [bOnly]);
  assert.deepEqual(
    rows.map((r) => r.remaining),
    [0, 3, null, 1, 1],
  );
  assert.equal(stageStatus(rows), "short");
  Object.assign(s.profile, {
    yearAttendanceMonths: { 3: 12 },
    assessmentDate: "2026-04-01",
    approved: true,
  });
  rows = api.requirementRows(s, byCode, [bOnly]);
  assert.equal(stageStatus(rows, true), "met");
  assert.equal(rows[4].planned[0].code, bOnly.code);
});

test("shortage discovery and slot links share stage, known eligibility, duplicate and denial checks", () => {
  const api = apiFor([a, b]);
  const s = state([grade(aOnly)]);
  s.status[bOnly.code] = "不許可";
  const find = api.shortageFilter(s, byCode, [], {
    key: "B",
    stageId: "degree",
    slot: "火3",
    term: 1,
  });
  assert.deepEqual(
    [flex, aOnly, bOnly, other].filter(find).map((c) => c.code),
    [flex.code],
  );
  assert.equal(
    api.shortageFilter(s, byCode, [], { key: "B", stageId: "fourth" })(flex),
    false,
  );
  assert.deepEqual(
    api
      .slotRequirements(s, byCode, [flex], [flex])
      .map((r) => [r.stageId, r.key]),
    [["degree", "B"]],
  );
  const field = api.academicFieldRows(s, byCode, [aOnly, flex, bOnly])[0];
  assert.deepEqual([field.field, field.earned, field.planned], ["70", 2, 2]);
});

test("CAP combines cohort classification with confirmed individual exceptions", () => {
  const api = apiFor([a], {
    cap: {
      limit: 24,
      source,
      classify: (c, p) =>
        p.program === "甲" && c.category === "A" ? "include" : "unknown",
    },
  });
  assert.equal(api.resolveCAP(profile).limit, 24);
  assert.equal(api.resolveCAP({ ...profile, handbook: "1990" }).limit, null);
  const cap = api.resolveCAP(
    { ...profile, cap: "27.5" },
    { [aOnly.code]: "除外", [other.code]: "算入" },
  );
  assert.deepEqual(
    [
      cap.limit,
      cap.individual,
      cap.source,
      cap.classify(aOnly),
      cap.classify(other),
      cap.classify(bOnly),
    ],
    [27.5, true, source, "exclude", "include", "unknown"],
  );
});

test("a scalar statement alone cannot identify the counterpart for a projected pair", () => {
  const api = apiFor([
    {
      key: "pair",
      label: "組合せ",
      required: 4,
      evaluate({ courses }) {
        return {
          value:
            courses.some((c) => c.category === "A") &&
            courses.some((c) => c.category === "B")
              ? 4
              : 0,
        };
      },
    },
  ]);
  const s = state([], [balance("pair", 2)]);
  const row = api.requirementRows(s, byCode, [bOnly])[0];
  assert.deepEqual(
    [row.current, row.remaining, row.future, row.after],
    [2, 2, 2, null],
  );
  assert.match(row.reason, /内訳/);
});

test("a documented recognition label maps once within its applicable stage", () => {
  const api = apiFor([a, b]);
  const s = state([
    {
      title: "認定科目",
      year: "2020",
      credits: 2,
      recognized: true,
      allocationLabel: b.label,
      allocationScope: { ...profile, goal: "graduation", stageId: "degree" },
    },
  ]);
  let rows = api.requirementRows(s, byCode, []);
  assert.deepEqual(
    rows.map((r) => r.current),
    [0, 2],
  );
  assert.equal(api.requirementRows(s, byCode, [], "fourth")[0].remaining, null);
  s.balances = [balance("B", 2)];
  rows = api.requirementRows(s, byCode, []);
  assert.deepEqual(
    rows.map((r) => r.current),
    [0, 2],
  );
  assert.deepEqual(rows[1].evidence.earned, []);
});

test("statement reservations leave separately eligible earned courses available and respect the unit", () => {
  const api = apiFor([
    a,
    b,
    {
      key: "months",
      label: "在学",
      unit: "months",
      required: 24,
      profileValue: () => null,
    },
  ]);
  const s = state(
    [grade(flex), grade(bOnly)],
    [balance("B", 2), balance("months", 24)],
  );
  const rows = api.requirementRows(s, byCode, []);
  assert.deepEqual(
    rows.map((r) => r.current),
    [2, 2, null],
  );
  assert.equal(rows[0].earned[0].code, flex.code);
  assert.equal(rows[1].covered[0].code, bOnly.code);
});

test("custom exclusive requirements consume only the evaluator's per-course witnesses", () => {
  const custom = {
    ...a,
    evaluate({ courses }) {
      const chosen = courses.filter((c) => c.category === "A");
      return {
        value: chosen.length,
        contributions: chosen.map((course) => ({ course, applied: 1 })),
      };
    },
  };
  const api = apiFor([custom, { ...b, match: () => true }]);
  const rows = api.requirementRows(
    state([grade(aOnly), grade(bOnly)]),
    byCode,
    [],
  );
  assert.deepEqual(
    rows.map((r) => r.current),
    [1, 2],
  );
  assert.equal(rows[0].earned[0].applied, 1);
  const opaque = apiFor([{ ...custom, evaluate: () => ({ value: 2 }) }, b]);
  assert.equal(
    opaque.requirementRows(state([grade(flex)]), byCode, [])[0].remaining,
    null,
  );
});

test("a statement is confined to the exact admission type, department, curriculum and individual scope", () => {
  const s = state();
  Object.assign(s.profile, {
    entry: "編入",
    department: "甲学科",
    curriculum: "特別",
    individual: "認定A",
  });
  s.balances = [
    {
      key: "B",
      current: 2,
      scope: { ...s.profile, goal: "graduation", stage: "degree" },
    },
  ];
  const api = apiFor([a, b]);
  const current = () => api.requirementRows(s, byCode, [])[1].current;
  assert.equal(current(), 2);
  for (const [key, value] of [
    ["entry", "転部"],
    ["entry", "再入学"],
    ["entry", "編入・転部・再入学"],
    ["admitted", "2017"],
    ["individual", "認定B"],
    ["department", "乙学科"],
  ]) {
    const old = s.profile[key];
    s.profile[key] = value;
    assert.equal(current(), 0);
    s.profile[key] = old;
  }
});

test("slot comparison exposes both projections per stage and omits unknown deficit changes", () => {
  const conditional = leaf("conditional", 8, {
    match: (c) => (c.category === "A" ? true : null),
  });
  const api = apiFor([leaf("A", 3), conditional]);
  const s = state();
  const impacts = api.slotRequirements(s, byCode, [aOnly, bOnly], [aOnly]);
  assert.deepEqual(
    impacts.map((r) => [
      r.stageId,
      r.key,
      r.previousAfter,
      r.after,
      r.previousFuture,
      r.future,
    ]),
    [
      ["fourth", "A", 1, 0, 0, 2],
      ["degree", "A", 3, 1, 0, 2],
    ],
  );
  assert.deepEqual(
    api
      .slotRequirements(s, byCode, [aOnly, bOnly], [aOnly], "graduation")
      .map((r) => r.stageId),
    ["degree"],
  );
  const unknownBefore = apiFor([
    leaf("A", 2, { match: (c) => (c.category === "A" ? true : null) }),
  ]);
  assert.deepEqual(
    unknownBefore.slotRequirements(
      s,
      byCode,
      [aOnly, bOnly],
      [aOnly],
      "graduation",
    ),
    [],
  );
});

test("an explicit zero CAP differs from a blank under known and unpublished rules", () => {
  const api = apiFor([], { cap: { limit: 24 } });
  for (const cap of [0, "0"]) {
    for (const handbook of [book.year, "1950"]) {
      const r = api.resolveCAP({ ...profile, cap, handbook });
      assert.deepEqual([r.limit, r.individual, r.status], [0, true, "known"]);
    }
  }
  for (const cap of ["", " ", undefined]) {
    assert.deepEqual(
      [
        api.resolveCAP({ ...profile, cap }).limit,
        api.resolveCAP({ ...profile, cap }).individual,
      ],
      [24, false],
    );
    assert.equal(
      api.resolveCAP({ ...profile, cap, handbook: "1950" }).status,
      "unknown",
    );
  }
});

test("field review preserves positive pending syllabuses and each uncertain identity with zero duplicate credit", () => {
  const api = apiFor([]);
  const pending = grade(aOnly, { year: "2020", importId: "pending" });
  const s = state([
    pending,
    grade(bOnly, { importId: "documented", duplicate: true, counts: false }),
    ...["first", "second"].map((id) =>
      grade(bOnly, { importId: id, identityUncertain: true, counts: false }),
    ),
    grade(flex, {
      importId: "alternative",
      possibleDuplicate: true,
      counts: false,
    }),
  ]);
  const rows = api.academicFieldRows(s, byCode, []);
  assert.deepEqual(
    rows.map((r) => [r.field, r.earned, r.planned]),
    [["?", 2, 0]],
  );
  assert.deepEqual(
    rows[0].courses.map(({ course }) => course.importId).sort(),
    ["alternative", "first", "pending", "second"],
  );
  assert.equal(
    rows[0].courses.find(({ course }) => course.importId === "pending").course
      .unresolvedOffering,
    true,
  );
  const held = rows[0].courses.filter((r) => r.reviewOnly);
  assert.equal(held.length, 3);
  assert.ok(
    held.every((r) => r.applied === 0 && r.course.credits === 2 && r.reason),
  );
  const reconsidered = api.academicFieldRows(s, byCode, [bOnly]);
  assert.deepEqual(
    reconsidered.map((r) => [r.field, r.earned, r.planned]),
    [["?", 2, 0]],
  );
});

test("current catalog fallback requires an unreviewed compatible legacy grade", () => {
  const offering = { ...aOnly, section: "A", courseId: "101" };
  const map = new Map([[offering.code, offering]]);
  const record = grade(offering, { term: "第1学期" });
  assert.equal(
    gradeCourses(state([record]), map)[0].matchedCourse?.confirmed,
    true,
  );
  for (const patch of [
    { importId: "reviewed" },
    { importId: "reviewed", title: "別名" },
    { grade: "認定", importId: "no-syllabus" },
    { title: "別名" },
    { credits: 1 },
    { section: "B" },
    { courseId: "999" },
    { term: "第2学期" },
    { year: "2023" },
    { matchedCourse: null },
  ]) {
    const s = state([{ ...record, ...patch }]);
    assert.equal(gradeCourses(s, map)[0].matchedCourse, null);
    assert.equal(apiFor([]).academicFieldRows(s, map, [])[0].field, "?");
  }
  const explicit = grade(
    { ...record, title: "原表の略称" },
    { importId: "accepted", matchedCourse: { ...offering, confirmed: true } },
  );
  assert.equal(
    gradeCourses(state([explicit]), map)[0].matchedCourse.title,
    offering.title,
  );
});

test("field balance discovery uses positive marginal field credit with or without a handbook stage", () => {
  const archived = course("211T0005", "旧年度科目", "A");
  archived.year = "2021";
  const old = grade(archived, {
    matchedCourse: { ...archived, confirmed: true },
  });
  const row = balance("field-70", 1, { label: "A区分", required: 7 });
  const s = state([old], [row]);
  s.status[bOnly.code] = "不許可";
  for (const api of [apiFor([a]), createRequirementAPI([])]) {
    for (const stageId of [undefined, "", "degree"]) {
      const eligible = api.shortageFilter(s, byCode, [aOnly], {
        key: "field-70",
        goal: "graduation",
        stageId,
        slot: "火3",
        term: 1,
      });
      assert.equal(eligible(flex), true);
      for (const c of [
        aOnly,
        bOnly,
        archived,
        { ...other, title: archived.title },
        { ...other, fields: ["10"] },
        { ...other, credits: 0 },
        { ...other, period: "第3ターム" },
        { ...other, schedule: "木2" },
      ])
        assert.equal(eligible(c), false);
    }
    assert.equal(
      api.shortageFilter(s, byCode, [], {
        key: "field-70",
        stageId: "unrelated",
      })(flex),
      false,
    );
    assert.equal(
      api.shortageFilter(s, byCode, [], { key: "field-10" })(other),
      false,
    );
  }
  const noPack = createRequirementAPI([]);
  const academic = noPack.academicFieldRows(s, byCode, [aOnly], null);
  assert.equal(
    academic.find((row) => row.field === "70").requirement?.after,
    4,
  );
  s.balances.push({ ...row, stageId: "different" });
  assert.equal(
    noPack.shortageFilter(s, byCode, [], { key: "field-70" })(flex),
    false,
  );
  s.balances = [{ ...row, current: 7 }];
  assert.equal(
    noPack.shortageFilter(s, byCode, [], { key: "field-70" })(flex),
    false,
  );
  s.balances = [{ ...row, unit: "courses" }];
  assert.equal(
    noPack.shortageFilter(s, byCode, [], { key: "field-70" })(flex),
    false,
  );
});

test("a recognized allocation imported with scope.stage stays in its program and exact stage within a goal", () => {
  const api = apiFor([], {
    stages: ["second", "fourth"].map((id) => ({
      id,
      goal: "progress",
      rows: [a],
    })),
  });
  const recognized = {
    recognized: true,
    grade: "認定",
    title: "認定済",
    credits: 2,
    allocationKey: "A",
    allocationScope: {
      ...profile,
      entry: "",
      goal: "progress",
      stage: "fourth",
    },
  };
  const s = state([recognized]);
  assert.equal(api.requirementRows(s, byCode, [], "fourth")[0].current, 2);
  assert.equal(api.requirementRows(s, byCode, [], "second")[0].remaining, null);
  assert.equal(api.satisfiesFilter(recognized, "A", profile, "second"), false);
  for (const patch of [
    { faculty: "別学部" },
    { program: "乙" },
    { handbook: "2022" },
  ]) {
    s.grades = [
      {
        ...recognized,
        allocationScope: { ...recognized.allocationScope, ...patch },
      },
    ];
    assert.equal(
      api.requirementRows(s, byCode, [], "fourth")[0].remaining,
      null,
    );
  }
});

const recognitionScope = { ...profile, stage: "degree", goal: "graduation" };
const assigned = (key, patch = {}) => ({
  title: "学外で修得した科目",
  code: "R1",
  year: "2020",
  grade: "認定",
  credits: 0.5,
  recognized: true,
  allocationKey: key,
  allocationScope: recognitionScope,
  sourceId: "statement",
  importId: "record1",
  sourceUrl: "https://example.invalid/decision",
  ...patch,
});

test("direct pool recognition retains its course at each ancestor without earning a named child", () => {
  const rows = [
    { ...a, match: () => true },
    b,
    { key: "major", required: 5, pool: ["A", "B"], disjoint: true },
    { key: "degree-pool", required: 5, pool: [{ key: "major", cap: 1 }] },
    { key: "total", required: 5, pool: ["degree-pool"] },
  ];
  const api = apiFor(rows);
  const recognized = assigned("major");
  const planned = assigned("major", {
    title: "別の科目",
    code: "R2",
    importId: "record2",
    credits: 1,
  });
  const evaluate = (grades, balances = [], plan = []) =>
    api.requirementRows(state(grades, balances), byCode, plan);
  const result = evaluate([recognized, { ...recognized }], [], [planned]);
  assert.deepEqual(
    result.map((r) => [r.current, r.future]),
    [
      [0, 0],
      [0, 0],
      [0.5, 1.5],
      [0.5, 1],
      [0.5, 1],
    ],
  );
  for (const key of ["major", "degree-pool", "total"]) {
    const [entry] = named(result, key).earned;
    assert.deepEqual(
      [
        entry.title,
        entry.year,
        entry.code,
        entry.recordId,
        entry.sourceUrl,
        entry.applied,
      ],
      [recognized.title, "2020", "R1", "record1", recognized.sourceUrl, 0.5],
    );
  }
  assert.deepEqual(
    named(result, "total").planned.map((c) => [c.recordId, c.applied]),
    [["record2", 0.5]],
  );
  const covered = evaluate([recognized], [balance("major", 0.5)], [planned]);
  assert.deepEqual(
    [
      named(covered, "major").current,
      named(covered, "major").covered[0].recordId,
      named(covered, "total").current,
      named(covered, "total").future,
    ],
    [0.5, "record1", 0.5, 1],
  );
  assert.deepEqual(named(covered, "major").earned, []);
  const priorStatement = named(
    evaluate([], [balance("major", 2)], [planned]),
    "major",
  );
  assert.deepEqual(
    [
      priorStatement.current,
      priorStatement.future,
      priorStatement.planned[0].applied,
    ],
    [2, 3, 1],
  );
  const overlap = named(evaluate([recognized], [balance("A", 0.5)]), "major");
  assert.deepEqual(
    [overlap.current, overlap.remaining, overlap.earned[0].applied],
    [0.5, null, 0.5],
  );
  const fromLeaf = evaluate([assigned("A")]);
  assert.deepEqual(
    fromLeaf.map((r) => r.current),
    [0.5, 0, 0.5, 0.5, 0.5],
  );
  const fromTotal = evaluate([assigned("total")]);
  assert.deepEqual(
    fromTotal.map((r) => r.current),
    [0, 0, 0, 0, 0.5],
  );
  for (const wrong of [
    assigned("unrelated"),
    assigned("major", {
      allocationScope: { ...recognitionScope, stage: "fourth" },
    }),
    assigned("major", {
      allocationScope: { ...recognitionScope, program: "乙" },
    }),
  ]) {
    assert.deepEqual(
      evaluate([wrong]).map((r) => r.current),
      [0, 0, 0, 0, 0],
    );
  }
});

test("a directly recognized evaluated amount counts once independently of syllabus predicates", () => {
  const sum = ({ courses }) => ({
    value: courses.reduce((n, c) => n + c.credits, 0),
    contributions: courses.map((course) => ({
      course,
      applied: course.credits,
    })),
  });
  const api = apiFor([
    { ...a, match: () => true },
    { ...b, evaluate: sum, match: () => true },
    {
      key: "major",
      required: 4,
      evaluate: sum,
      match: () => false,
      allocationKeys: ["A", "B"],
    },
    { key: "total", required: 8, evaluate: sum, match: () => false },
    {
      key: "decision",
      unit: "condition",
      required: 1,
      evaluate: () => ({ value: 0 }),
    },
  ]);
  const result = api.requirementRows(
    state([assigned("major"), grade(aOnly)]),
    byCode,
    [],
  );
  assert.deepEqual(
    result.map((r) => r.current),
    [2, 0, 2.5, 2.5, 0],
  );
  assert.equal(
    named(result, "total").earned.find((c) => c.recordId === "record1").applied,
    0.5,
  );
  const fromLeaf = api.requirementRows(state([assigned("B")]), byCode, []);
  assert.deepEqual(
    fromLeaf.map((r) => r.current),
    [0, 0.5, 0.5, 0.5, 0],
  );
  const superseded = api.requirementRows(
    state([assigned("B")], [balance("B", 0)]),
    byCode,
    [],
  );
  assert.deepEqual(
    superseded.map((r) => r.current),
    [0, 0, 0, 0, 0],
  );
  const directTotal = api.requirementRows(
    state([assigned("total")]),
    byCode,
    [],
  );
  assert.deepEqual(
    directTotal.map((r) => r.current),
    [0, 0, 0, 0.5, 0],
  );
  const unrelated = api.requirementRows(state([assigned("other")]), byCode, []);
  assert.deepEqual(
    unrelated.map((r) => r.current),
    [0, 0, 0, 0, 0],
  );
});

test("scalar course totals stay independent of unrelated statements and report possible overlap with an anonymous baseline", () => {
  const api = apiFor([
    {
      key: "major",
      required: 5,
      evaluate: ({ courses, baseline }) => ({
        value:
          courses.reduce((n, c) => n + c.credits, 0) + (baseline["part"] ?? 0),
      }),
    },
  ]);
  const run = (balances) =>
    named(
      api.requirementRows(
        state([grade(aOnly), assigned("major")], balances),
        byCode,
        [],
      ),
      "major",
    );
  const ordinary = run([balance("other", 1)]);
  assert.deepEqual(
    [ordinary.current, ordinary.remaining, ordinary.earned[0].applied],
    [2.5, 2.5, 0.5],
  );
  const overlapping = run([balance("part", 1)]);
  assert.deepEqual(
    [overlapping.current, overlapping.remaining, overlapping.earned[0].applied],
    [3, null, 0.5],
  );
});

test("official decision balances require an enabled boolean rule, an explicit outcome and the captured assessment scope", () => {
  const gate = {
    key: "exam",
    label: "合否",
    required: 1,
    unit: "condition",
    officialDecision: true,
    unknown: "結果を確認",
  };
  const api = apiFor([
    gate,
    { ...gate, key: "unmarked", officialDecision: false },
    {
      ...gate,
      key: "gpa",
      unit: "points",
      required: 4,
      profileValue: () => 2.5,
    },
    {
      ...gate,
      key: "attendance",
      unit: "months",
      required: 1,
      profileValue: () => 0,
    },
    { ...gate, key: "multiple", required: 2 },
    { ...gate, key: "age", officialDecision: false, profileValue: () => 0 },
  ]);
  const statement = (current, patch = {}) => ({
    scope: {
      ...recognitionScope,
      entryGrade: "",
      assessmentDate: "2026-04-01",
      graduationYear: "2028",
      graduationMonth: 3,
      package: "甲",
    },
    key: "exam",
    unit: "condition",
    required: 1,
    confirmed: true,
    current,
    ...patch,
  });
  const s = state();
  Object.assign(s.profile, statement().scope);
  const rows = (b) =>
    api.requirementRows({ ...s, balances: [b] }, byCode, [other]);
  assert.deepEqual(
    rows(statement(undefined)).map((r) => r.officialDecision),
    [true, false, false, false, false, false],
  );
  for (const current of [0, 1]) {
    const r = rows(statement(current))[0];
    assert.deepEqual(
      [r.current, r.future, r.remaining, r.after],
      [current, current, 1 - current, 1 - current],
    );
  }
  for (const patch of [
    { current: null },
    { current: 2 },
    { current: true },
    { confirmed: false },
    { required: 2 },
  ]) {
    assert.equal(rows(statement(1, patch))[0].current, null);
  }
  for (const [key, value] of Object.entries({
    entryGrade: "3",
    assessmentDate: "",
    graduationYear: 2027,
    graduationMonth: 9,
    package: "乙",
    stage: "fourth",
  })) {
    assert.equal(
      rows(statement(1, { scope: { ...statement().scope, [key]: value } }))[0]
        .current,
      null,
    );
  }
  assert.equal(rows(statement(1, { scope: recognitionScope }))[0].current, 1);
  for (const [key, expected] of [
    ["unmarked", null],
    ["gpa", 2.5],
    ["attendance", 0],
    ["multiple", null],
    ["age", 0],
  ])
    assert.equal(named(rows(statement(1, { key })), key).current, expected);
});

test("creation domain deficits participate in stage status and legacy decisions follow only the renamed stage rows", () => {
  const p = { ...profile, faculty: "創生学部" };
  const scope = { ...p, goal: "graduation", stage: "degree" };
  const oldKeys = ["field-foundation", "field-advanced", "field-pool"];
  const newKeys = ["domain-foundation", "domain-advanced", "domain-pool"];
  const rule = (key) => leaf(key, 2, { match: (c) => c.category === "A" });
  const pack = (keys) =>
    createRequirementAPI([
      {
        handbooks: [{ ...book, faculty: p.faculty }],
        default: () => ({
          sources: [source],
          stages: [{ id: "degree", goal: "graduation", rows: keys.map(rule) }],
        }),
      },
    ]);
  for (const keys of [newKeys, oldKeys]) {
    const api = pack(keys);
    const s = {
      ...state(),
      profile: p,
      grades: [],
      balances: oldKeys.map((key, i) => ({
        scope,
        key,
        current: i === 2 ? 0 : 2,
        confirmed: true,
      })),
    };
    s.balances.push({
      scope,
      key: "field-70",
      label: "学問分野",
      current: 0,
      required: 2,
      confirmed: true,
    });
    let result = api.requirementRows(s, byCode, []);
    assert.deepEqual(
      result.map((r) => r.current),
      [2, 2, 0, 0],
    );
    assert.equal(stageStatus(result), "short");
    assert.equal(api.satisfiesFilter(aOnly, "field-pool", p), true);
    assert.equal(
      api.shortageFilter(s, byCode, [], { key: "field-pool" })(aOnly),
      true,
    );
    assert.deepEqual(
      api.academicFieldRows(s, byCode, []).map((r) => r.field),
      ["70"],
    );
    s.balances[2].current = 2;
    assert.equal(stageStatus(api.requirementRows(s, byCode, [])), "met");
    s.balances = [];
    s.grades = [assigned("field-pool", { allocationScope: scope })];
    result = api.requirementRows(s, byCode, []);
    assert.deepEqual(
      result.map((r) => r.current),
      [0, 0, 0.5],
    );
    assert.equal(result[2].earned[0].recordId, "record1");
    assert.equal(s.grades[0].allocationKey, "field-pool");
  }
  const otherFaculty = apiFor(newKeys.map(rule));
  assert.deepEqual(
    otherFaculty
      .requirementRows(state([assigned("field-pool")]), byCode, [])
      .map((r) => r.current),
    [0, 0, 0],
  );
});
