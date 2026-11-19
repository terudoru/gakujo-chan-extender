import test from "node:test";
import assert from "node:assert/strict";
import catalog from "../src/catalog-2026.json" with { type: "json" };
import {
  activeCourses,
  chooseCourse,
  conflicts,
  courseFields,
  initialState,
  listCandidates,
  readShare,
  semesterCredits,
  shareLink,
  slotsFor,
  syllabusURL,
  termsFor,
  validCode,
} from "../src/study.mjs";
import { facultyInfo, requirementRows } from "../src/requirements.mjs";
import {
  delimitedRows,
  mergeGrades,
  reviewGradeRows,
} from "../src/transcript.mjs";

const byCode = new Map(catalog.courses.map((c) => [c.code, c]));
const data = byCode.get("261G3008"),
  english = byCode.get("261G7011");
function engineering() {
  const s = initialState();
  Object.assign(s.profile, {
    faculty: "工学部", program: "融合領域分野", handbook: "2026", admitted: "2026",
  });
  return s;
}
test("catalog links and paired slots refer to unique undergraduate offerings", () => {
  assert.equal(byCode.size, catalog.courses.length);
  assert.ok(byCode.size > 4000);
  for (const course of catalog.courses) {
    assert.ok(validCode(course.code));
    assert.ok(syllabusURL(course));
    assert.ok(termsFor(course).length);
    assert.ok(course.fields.every((k) => Object.hasOwn(catalog.fields, k)));
  }
  assert.deepEqual(slotsFor(data), ["月1", "月2"]);
  assert.deepEqual(termsFor({ ...data, period: "第1~3ターム" }), [1, 2, 3]);
  assert.deepEqual(slotsFor(english), ["月2", "木2"]);
});
test("sharing is a point-in-time copy containing only list metadata", () => {
  const s = engineering();
  s.grades.push({ title: "個人の成績", credits: 2 });
  const list = s.lists[0];
  list.codes.push(data.code, english.code);
  const link = new URL(
    shareLink(list, 2026, "https://example.test/planner/?student=private"),
  );
  list.codes.pop();
  assert.equal(link.search, "");
  const copy = readShare(link.hash, 2026);
  assert.deepEqual(copy, { name: list.name, codes: [data.code, english.code] });
  assert.throws(() => readShare(link.hash, 2025));
  assert.throws(() => readShare("#list=broken", 2026));
  copy.codes.pop();
  assert.equal(readShare(link.hash, 2026).codes.length, 2);
});
test("shared slot replaces all meetings, retains candidates, and respects official results", () => {
  const s = engineering();
  s.lists[0].codes.push(data.code, english.code);
  chooseCourse(s, data, byCode);
  assert.deepEqual(
    conflicts(english, s, byCode).map((c) => c.slots),
    [["月2"]],
  );
  assert.throws(() => chooseCourse(s, english, byCode));
  chooseCourse(s, english, byCode, true);
  assert.deepEqual(s.plan, [english.code]);
  assert.equal(listCandidates(s, byCode, 1, "月2").length, 2);
  assert.equal(listCandidates(s, byCode, 2, "月2").length, 0);
  s.status[english.code] = "許可";
  assert.throws(() => chooseCourse(s, data, byCode, true));
  s.status[english.code] = "不許可";
  assert.deepEqual(activeCourses(s, byCode), []);
  chooseCourse(s, data, byCode);
  assert.deepEqual(
    activeCourses(s, byCode).map((c) => c.code),
    [data.code],
  );
});
test("one semester counts all its terms once and flags annual or mixed credits", () => {
  const s = engineering(),
    later = { ...english, code: "262G7011", period: "第2ターム" };
  const map = new Map([
    [data.code, data],
    [later.code, later],
  ]);
  chooseCourse(s, data, map);
  chooseCourse(s, later, map);
  s.status[data.code] = "申請中";
  for (const t of [1, 2])
    assert.equal(
      semesterCredits(activeCourses(s, map), t, s.profile).included,
      3,
    );
  assert.equal(semesterCredits([data], 1, s.profile).limit, 28);
  const intensive = { ...data, period: "集中" };
  assert.equal(semesterCredits([intensive], 1, s.profile).excluded, 2);
  assert.equal(
    semesterCredits([intensive], 1, s.profile, { [data.code]: "算入" })
      .included,
    2,
  );
  assert.equal(
    semesterCredits([{ ...data, period: "通年" }], 3, s.profile).unconfirmed
      .length,
    1,
  );
  assert.equal(
    semesterCredits([data], 1, { ...s.profile, handbook: "2017" }).limit,
    null,
  );
});
test("annual CAP uses the recorded shares, validates both halves and preserves zero", () => {
  const profile = engineering().profile;
  const course = { ...data, period: "通年" };
  const split = { [course.code]: { first: 0, second: 2 } };
  const first = semesterCredits([course], 1, profile, {}, split);
  assert.equal(first.included, 0);
  assert.deepEqual(first.unconfirmed, []);
  assert.equal(semesterCredits([course], 4, profile, {}, split).included, 2);
  for (const bad of [{ first: 1 }, { first: 1, second: 2 }, { first: -1, second: 3 }]) {
    const result = semesterCredits([course], 1, profile, {}, { [course.code]: bad });
    assert.deepEqual(result.unconfirmed, [course]);
    assert.equal(result.included, 0);
  }
  const unknown = semesterCredits([data], 1, initialState().profile);
  assert.equal(unknown.scheduled, 2);
  assert.equal(unknown.included, 0);
  assert.equal(unknown.limit, null);
});
test("academic field and curriculum allocation remain distinct across cutoff and personal balances", () => {
  const s = engineering(),
    total = (rows, key) => rows.find((r) => r.key === key);
  assert.equal(courseFields([], [english])[0].field, "70");
  assert.equal(total(requirementRows(s, byCode, [english]), "human").after, 3);
  assert.equal(
    total(requirementRows(s, byCode, [english]), "english").after,
    2,
  );
  assert.equal(total(requirementRows(s, byCode, [data]), "data").after, 0);
  s.balances.push({
    faculty: "工学部",
    program: "融合領域分野",
    handbook: "2026",
    goal: "graduation",
    key: "human",
    label: "人文社会・教育科学",
    kind: "必修",
    required: 4,
    current: 4,
  });
  assert.equal(
    total(requirementRows(s, byCode, [english]), "socialPool").after,
    1,
  );
  s.grades = [{ ...english, year: "2026" }];
  assert.equal(total(requirementRows(s, byCode, [english]), "total").future, 1);
  s.profile.handbook = "2016";
  assert.deepEqual(requirementRows(s, byCode, [data]), []);
  s.profile.handbook = "2026";
  s.profile.entry = "編入・転部・再入学";
  assert.equal(facultyInfo(s.profile).verified, false);
});
test("field forecasts keep distinct years and exclude duplicated or already earned offerings", () => {
  const confirmed = {
    code: "", title: english.title, credits: 1, fields: [],
    matchedCourse: { ...english, year: "2026", confirmed: true },
  };
  const rows = courseFields(
    [
      confirmed,
      { ...english, year: "2025", credits: 2 },
      { ...data, year: "2026", counts: false, duplicate: true },
      { title: "歴史分野の認定科目", credits: 0.5, fields: [] },
    ],
    [english, data, data],
    2026,
  );
  const totals = Object.fromEntries(rows.map((r) => [r.field, [r.earned, r.planned]]));
  assert.deepEqual(totals, { "70": [3, 0], "10": [0, 2], "?": [0.5, 0] });
  assert.equal(rows.find((r) => r.field === "70").courses.length, 2);
  const olderOnly = courseFields([{ ...english, year: "2024" }], [english], 2026);
  assert.equal(olderOnly[0].planned, 1);
  assert.equal(courseFields([], [{ ...data, credits: null }], 2026)[0].needsReview, true);
});
test("transcript preview never converts scores or failing rows into earned units", () => {
  const header = "科目コード,科目名,単位数,評価,年度";
  const parsed = reviewGradeRows(
    delimitedRows(
      [
        header,
        "261G7011,英語基礎 L,1,良,2026",
        "261G3008,情報,2,不可,2026",
        ",認定科目,2,認定,2023",
        "261G3008,情報,,優,2026",
      ].join("\n"),
    ),
    byCode,
  );
  assert.equal(parsed.candidates.length, 2);
  assert.equal(parsed.missing.length, 1);
  const s = engineering();
  mergeGrades(s, parsed.candidates);
  mergeGrades(s, parsed.candidates);
  assert.equal(s.grades.length, 2);
  assert.equal(s.grades[1].title, "認定科目");
  assert.equal(s.grades[1].fields.length, 0);
});
