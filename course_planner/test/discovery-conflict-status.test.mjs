import test from "node:test";
import assert from "node:assert/strict";
import catalog from "../src/catalog-2026.json" with { type: "json" };
import { initialState } from "../src/study.mjs";
import {
  assessCourseConflicts,
  filterAndRankCourses,
} from "../src/components/discovery-search.mjs";

const byCode = new Map(catalog.courses.map((c) => [c.code, c]));
const english = byCode.get("261G7011"); // 第1ターム 月2, 木2
const business = byCode.get("261E6002"); // 第1ターム 他
const data = byCode.get("261G3008"); // 第1ターム 月1, 月2 (collides with english on 月2)
const wed2 = byCode.get("260G0017"); // 第1,2ターム 水2 (proven clear against english)
const term3Course = catalog.courses.find(
  (c) => c.period === "第3ターム" && c.schedule !== "他",
);

assert.ok(english && business && data && wed2 && term3Course);

test("repro: active 月2・木2 第1ターム treats same-term 261E6002 (他) as uncertain and excludes it from free filter", () => {
  const state = initialState();
  state.plan = [english.code];

  const businessStatus = assessCourseConflicts(business, state, byCode);
  assert.equal(businessStatus.status, "uncertain");
  assert.equal(businessStatus.candidateUndetermined, true);
  assert.equal(businessStatus.definite.length, 0);

  const freeSearch = filterAndRankCourses({
    catalog,
    state,
    byCode,
    filters: { query: business.code, free: true },
  });
  assert.equal(freeSearch.courses.length, 0);

  const clearStatus = assessCourseConflicts(wed2, state, byCode);
  assert.equal(clearStatus.status, "clear");

  const clearFreeSearch = filterAndRankCourses({
    catalog,
    state,
    byCode,
    filters: { query: wed2.code, free: true },
  });
  assert.deepEqual(
    clearFreeSearch.courses.map((c) => c.code),
    [wed2.code],
  );
});

test("mixed known/他 and empty schedule handle explicit collisions first and never claim proven non-overlap", () => {
  const state = initialState();
  state.plan = [english.code]; // 月2, 木2 第1ターム

  const mixedClearSlot = {
    code: "261X0010",
    department: "84",
    title: "検証混在未重複",
    teacher: "検証 教員",
    semester: "第1学期",
    period: "第1ターム",
    schedule: "火3, 他",
    credits: 2,
    fields: ["10"],
    category: "自然科学",
    format: "講義",
  };
  const mixedCollidingSlot = {
    ...mixedClearSlot,
    code: "261X0011",
    title: "検証混在重複",
    schedule: "月2, 他",
  };
  const emptySchedule = {
    ...mixedClearSlot,
    code: "261X0012",
    title: "検証空欄時限",
    schedule: "",
  };

  const mixedUncertain = assessCourseConflicts(mixedClearSlot, state, byCode);
  assert.equal(mixedUncertain.status, "uncertain");
  assert.equal(mixedUncertain.candidateUndetermined, true);

  const mixedConflict = assessCourseConflicts(mixedCollidingSlot, state, byCode);
  assert.equal(mixedConflict.status, "conflict");
  assert.equal(mixedConflict.definite.length, 1);
  assert.equal(mixedConflict.definite[0].course.code, english.code);
  assert.deepEqual(mixedConflict.definite[0].slots, ["月2"]);
  assert.equal(mixedConflict.hasUndetermined, true);

  const emptyUncertain = assessCourseConflicts(emptySchedule, state, byCode);
  assert.equal(emptyUncertain.status, "uncertain");
});

test("undetermined active same-term course marks other same-term candidates uncertain while ignoring self and unrelated terms", () => {
  const state = initialState();
  state.plan = [business.code]; // 261E6002 第1ターム 他

  // Same-term known-slot candidate cannot be proven non-overlapping with 261E6002
  const sameTerm = assessCourseConflicts(wed2, state, byCode);
  assert.equal(sameTerm.status, "uncertain");
  assert.equal(sameTerm.candidateUndetermined, false);
  assert.deepEqual(
    sameTerm.undeterminedOthers.map((c) => c.code),
    [business.code],
  );

  // Course itself is ignored
  const selfStatus = assessCourseConflicts(business, state, byCode);
  assert.equal(selfStatus.status, "clear");

  // Unrelated term course (第3ターム) is unaffected by 第1ターム active course
  const unrelatedTerm = assessCourseConflicts(term3Course, state, byCode);
  assert.equal(unrelatedTerm.status, "clear");

  // Conversely, active 第3ターム course does not make 第1ターム 261E6002 uncertain
  const otherTermState = initialState();
  otherTermState.plan = [term3Course.code];
  assert.equal(
    assessCourseConflicts(business, otherTermState, byCode).status,
    "clear",
  );
});

test("requirement ranking orders proven clear -> uncertain -> definite conflict and free filter keeps only proven clear", () => {
  const state = initialState();
  state.plan = [english.code]; // 第1ターム 月2, 木2

  const ranked = filterAndRankCourses({
    catalog,
    state,
    byCode,
    context: {
      label: "第1ターム候補",
      eligibleCodes: [data.code, business.code, wed2.code],
    },
    filters: { term: "1", free: false },
  });
  assert.deepEqual(
    ranked.courses.map((c) => c.code),
    [wed2.code, business.code, data.code],
  );

  const freeOnly = filterAndRankCourses({
    catalog,
    state,
    byCode,
    context: {
      label: "第1ターム候補",
      eligibleCodes: [data.code, business.code, wed2.code],
    },
    filters: { term: "1", free: true },
  });
  assert.deepEqual(
    freeOnly.courses.map((c) => c.code),
    [wed2.code],
  );
});
