import test from "node:test";
import assert from "node:assert/strict";
import catalog from "../src/catalog-2026.json" with { type: "json" };
import { initialState, syllabusURL } from "../src/study.mjs";
import {
  departmentLabel,
  departmentOptions,
  filterAndRankCourses,
  formatAcademicFields,
  formatCourseType,
  formatMeetingSlots,
  formatOfferingTerm,
  initialFiltersFromContext,
  matchesDayPeriod,
  parseOfficialSyllabusURL,
} from "../src/components/discovery-search.mjs";
import {
  ENTRY_OPTIONS,
  OWNED_PROFILE_KEYS,
  applyProfilePatch,
  entryOptionList,
  handbooksForFaculty,
  initialProfileDraft,
  programChoicesFor,
  validateProfileDraft,
} from "../src/components/profile-settings.mjs";

const byCode = new Map(catalog.courses.map((c) => [c.code, c]));
const dataCourse = byCode.get("261G3008");
const englishCourse = byCode.get("261G7011");

test("exact official syllabus URL matches only that course and rejects wrong year or non-official URLs", () => {
  const officialUrl = syllabusURL(englishCourse, catalog.year);
  assert.ok(officialUrl);

  const parsed = parseOfficialSyllabusURL(officialUrl);
  assert.equal(parsed.valid, true);
  assert.equal(parsed.code, englishCourse.code);
  assert.equal(parsed.department, englishCourse.department);
  assert.equal(parsed.year, 2026);

  const state = initialState();
  const exact = filterAndRankCourses({
    catalog,
    state,
    byCode,
    filters: { query: officialUrl },
  });
  assert.deepEqual(
    exact.courses.map((c) => c.code),
    [englishCourse.code],
  );
  assert.equal(exact.urlNotice, "");

  const olderYearUrl = officialUrl.replace("/2026/", "/2025/");
  const older = filterAndRankCourses({
    catalog,
    state,
    byCode,
    filters: { query: olderYearUrl },
  });
  assert.equal(older.courses.length, 0);
  assert.match(older.urlNotice, /2025年度/);

  const nonOfficial = filterAndRankCourses({
    catalog,
    state,
    byCode,
    filters: { query: "https://example.test/syllabusHtml/2026/84/84_261G7011_ja_JP.html" },
  });
  assert.equal(nonOfficial.courses.length, 0);
  assert.ok(nonOfficial.urlNotice.length > 0);
});

test("purpose-specific filters handle teacher, department, explicit day/period, and paired slots without false matches", () => {
  const crossDayCourse = {
    code: "261X0001",
    department: "09",
    title: "検証用複数時限科目",
    teacher: "検証 太郎",
    semester: "第1学期",
    period: "第1ターム",
    schedule: "月1,火2",
    credits: 2,
    fields: ["10"],
    category: "自然科学",
    format: "講義",
  };
  assert.equal(matchesDayPeriod(crossDayCourse, "月", "2"), false);
  assert.equal(matchesDayPeriod(crossDayCourse, "月", "1"), true);
  assert.equal(matchesDayPeriod(crossDayCourse, "火", "2"), true);
  assert.equal(matchesDayPeriod(crossDayCourse, "月", "all"), true);
  assert.equal(matchesDayPeriod(crossDayCourse, "all", "2"), true);
  assert.equal(matchesDayPeriod(crossDayCourse, "他", "all"), false);

  assert.equal(formatMeetingSlots(englishCourse), "月曜2限・木曜2限");
  assert.equal(formatMeetingSlots(dataCourse), "月曜1限・月曜2限");
  assert.equal(formatAcademicFields({ fields: [] }, catalog.fields), "分野要確認");
  assert.equal(formatAcademicFields(englishCourse, catalog.fields), "70 英語");
  assert.equal(formatCourseType({ format: "-" }), "要確認");
  assert.equal(formatOfferingTerm({ semester: "第1学期", period: "第1学期" }), "第1学期");
  assert.equal(departmentLabel("84"), "84 教養教育");
  assert.equal(departmentLabel("09"), "09 工学部");
  assert.equal(departmentOptions(catalog.courses)[0][0], "84");

  const state = initialState();
  const byTeacher = filterAndRankCourses({
    catalog,
    state,
    byCode,
    filters: { teacher: englishCourse.teacher, department: "84", day: "木", periodSlot: "2" },
  });
  assert.ok(byTeacher.courses.some((c) => c.code === englishCourse.code));
  assert.ok(byTeacher.courses.every((c) => c.department === "84"));
});

test("requirement context supports matchesRequirement predicate, eligibleCodes collection, default satisfiesFilter, and available-first ranking", () => {
  const state = initialState();
  state.profile.faculty = "工学部";
  state.profile.program = "融合領域分野";
  state.plan = [dataCourse.code]; // occupies 月1, 月2 in term 1 -> conflicts with englishCourse (月2, 木2)

  const nonConflictingGeneral = catalog.courses.find(
    (c) =>
      c.department === "84" &&
      c.code !== dataCourse.code &&
      c.code !== englishCourse.code &&
      !c.schedule.includes("月1") &&
      !c.schedule.includes("月2") &&
      c.period === "第1ターム",
  );
  assert.ok(nonConflictingGeneral);

  // eligibleCodes array (order starts with conflicting englishCourse, must rank available first)
  const fromCodes = filterAndRankCourses({
    catalog,
    state,
    byCode,
    context: {
      label: "対象科目",
      eligibleCodes: [englishCourse.code, nonConflictingGeneral.code],
    },
    filters: { term: "1" },
  });
  assert.equal(fromCodes.hasRequirementContext, true);
  assert.deepEqual(
    fromCodes.courses.map((c) => c.code),
    [nonConflictingGeneral.code, englishCourse.code],
  );

  // Empty eligibleCodes must never guess eligibility
  const emptyCodes = filterAndRankCourses({
    catalog,
    state,
    byCode,
    context: { requirement: "general", eligibleCodes: [] },
    filters: {},
  });
  assert.equal(emptyCodes.courses.length, 0);

  // Custom predicate prop overrides satisfiesFilter
  const fromPredicate = filterAndRankCourses({
    catalog,
    state,
    byCode,
    context: { requirement: "unknown-key" },
    matchesRequirement: (c) => c.code === dataCourse.code,
    filters: {},
  });
  assert.deepEqual(
    fromPredicate.courses.map((c) => c.code),
    [dataCourse.code],
  );

  // Inherited slot initializes explicit day/period
  assert.deepEqual(initialFiltersFromContext({ slot: "月2", term: 1 }), {
    query: "",
    teacher: "",
    term: "1",
    department: "all",
    day: "月",
    periodSlot: "2",
    field: "all",
    free: false,
  });
  assert.equal(initialFiltersFromContext({ slot: "他" }).day, "他");
  assert.equal(initialFiltersFromContext({ requirement: "field-70" }).field, "70");
});

test("ProfileSettings keeps empty and 0 distinct, never infers dates, preserves custom values and concurrent unrelated keys", () => {
  // Never infers enrollment date when empty
  const emptyDraft = initialProfileDraft({
    faculty: "",
    program: "",
    admitted: "",
    handbook: "",
    gpa: "",
    cap: "",
    yearOfStudy: "",
    attendanceMonths: "",
  });
  assert.equal(emptyDraft.admitted, "");
  assert.equal(emptyDraft.handbook, "");

  // Numeric 0 initializes to "0", never ""
  const zeroDraft = initialProfileDraft({
    faculty: "工学部",
    admitted: "",
    handbook: "2021",
    entry: "編入",
    program: "旧課程カスタム分野",
    yearOfStudy: 3,
    attendanceMonths: 0,
    gpa: 0,
    cap: 0,
  });
  assert.equal(zeroDraft.attendanceMonths, "0");
  assert.equal(zeroDraft.gpa, "0");
  assert.equal(zeroDraft.cap, "0");
  assert.equal(zeroDraft.admitted, "");

  const validatedZero = validateProfileDraft(zeroDraft);
  assert.equal(validatedZero.attendanceMonths, "0");
  assert.equal(validatedZero.gpa, "0");
  assert.equal(validatedZero.cap, "0");
  assert.equal(validatedZero.admitted, "");
  assert.equal(validatedZero.handbook, "2021");
  assert.equal(validatedZero.entry, "編入");
  assert.equal(validatedZero.program, "旧課程カスタム分野");

  // Empty stays ""
  const validatedEmpty = validateProfileDraft({
    faculty: "農学部",
    program: "",
    entry: "再入学",
    admitted: "",
    handbook: "2019",
    yearOfStudy: "",
    attendanceMonths: "",
    gpa: "",
    cap: "",
  });
  assert.equal(validatedEmpty.attendanceMonths, "");
  assert.equal(validatedEmpty.gpa, "");
  assert.equal(validatedEmpty.cap, "");
  assert.equal(validatedEmpty.yearOfStudy, "");

  // Invalid inputs throw
  assert.throws(() => validateProfileDraft({ ...validatedEmpty, faculty: "" }));
  assert.throws(() => validateProfileDraft({ ...validatedEmpty, handbook: "26" }));
  assert.throws(() => validateProfileDraft({ ...validatedEmpty, admitted: "abc" }));
  assert.throws(() => validateProfileDraft({ ...validatedEmpty, gpa: "4.5" }));
  assert.throws(() => validateProfileDraft({ ...validatedEmpty, attendanceMonths: "-1" }));
  assert.throws(() => validateProfileDraft({ ...validatedEmpty, yearOfStudy: "0" }));

  // Entry options include all 4 alternatives and preserve legacy value if stored
  assert.deepEqual(ENTRY_OPTIONS, ["1年次入学", "編入", "転部", "再入学"]);
  assert.ok(entryOptionList("編入・転部・再入学").includes("編入・転部・再入学"));

  // Concurrently updated unrelated state/profile values are retained on patch
  const liveState = initialState();
  liveState.plan = [englishCourse.code];
  liveState.profile.concurrentFlag = "keep-me";
  liveState.profile.otherMeta = { synced: true };

  applyProfilePatch(liveState, validatedZero);
  assert.equal(liveState.profile.concurrentFlag, "keep-me");
  assert.deepEqual(liveState.profile.otherMeta, { synced: true });
  assert.deepEqual(liveState.plan, [englishCourse.code]);
  for (const key of OWNED_PROFILE_KEYS) {
    assert.ok(Object.hasOwn(liveState.profile, key));
  }
});

test("ProfileSettings handbook and program suggestions use only supplied records and reject unsafe URLs", () => {
  const sampleHandbooks = [
    {
      faculty: "サンプル工学部",
      year: 2026,
      title: "2026年度 サンプル学生必携",
      url: "https://example.test/handbook-2026.pdf",
      programs: ["サンプルAプログラム", "サンプルBプログラム"],
    },
    {
      faculty: "サンプル工学部",
      year: 2022,
      title: "2022年度 サンプル学生必携",
      url: "javascript:alert(1)",
      programs: ["サンプル旧プログラム"],
    },
  ];
  const matched = handbooksForFaculty(sampleHandbooks, "サンプル工学部", "2022");
  assert.equal(matched.length, 2);
  assert.equal(matched[0].year, "2022");
  assert.equal(matched[0].url, null); // unsafe URL rejected
  assert.equal(matched[1].url, "https://example.test/handbook-2026.pdf");

  assert.deepEqual(
    programChoicesFor(sampleHandbooks, "サンプル工学部", "2026", "2026"),
    ["サンプルAプログラム", "サンプルBプログラム"],
  );
  assert.deepEqual(
    programChoicesFor(sampleHandbooks, "サンプル工学部", "2019", "2019"),
    [], // never invents or silently substitutes mismatched cohort programs
  );
});
