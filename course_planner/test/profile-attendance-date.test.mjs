import test from "node:test";
import assert from "node:assert/strict";
import { initialState } from "../src/study.mjs";
import {
  applyProfilePatch,
  diffProfileDraft,
  initialProfileDraft,
  isValidISODate,
  validateProfileDraft,
} from "../src/components/profile-settings.mjs";

test("isValidISODate validates real calendar dates including leap days and rejects invalid dates", () => {
  assert.equal(isValidISODate("2024-02-29"), true);
  assert.equal(isValidISODate("2000-02-29"), true);
  assert.equal(isValidISODate("2026-04-01"), true);
  assert.equal(isValidISODate("２０２４-０２-２９"), true);

  assert.equal(isValidISODate("2026-02-29"), false);
  assert.equal(isValidISODate("2100-02-29"), false);
  assert.equal(isValidISODate("2026-04-31"), false);
  assert.equal(isValidISODate("2026-13-01"), false);
  assert.equal(isValidISODate("2026-00-10"), false);
  assert.equal(isValidISODate("2026-4-1"), false);
  assert.equal(isValidISODate("2026/04/01"), false);
  assert.equal(isValidISODate(""), false);
});

test("yearOfStudy allows values above 12, yearAttendanceMonths keeps empty distinct from true zero, and dates are never inferred", () => {
  const draft = initialProfileDraft({
    faculty: "工学部",
    handbook: "2026",
    admitted: "",
    yearOfStudy: "14",
    attendanceMonths: "0",
    assessmentDate: "",
    yearAttendanceMonths: { "1": 12, "3": 0 },
  });
  assert.equal(draft.admitted, "");
  assert.equal(draft.assessmentDate, "");
  assert.equal(draft.yearAttendanceMonths["1"], "12");
  assert.equal(draft.yearAttendanceMonths["2"], "");
  assert.equal(draft.yearAttendanceMonths["3"], "0");

  const validated = validateProfileDraft(draft);
  assert.equal(validated.yearOfStudy, "14");
  assert.equal(validated.attendanceMonths, "0");
  assert.equal(validated.assessmentDate, "");
  assert.deepEqual(validated.yearAttendanceMonths, { "1": 12, "3": 0 });
  assert.strictEqual(validated.yearAttendanceMonths["3"], 0);
  assert.equal(Object.hasOwn(validated.yearAttendanceMonths, "2"), false);

  assert.throws(() =>
    validateProfileDraft({ ...draft, assessmentDate: "2026-02-29" }),
  );
  assert.throws(() =>
    validateProfileDraft({
      ...draft,
      yearAttendanceMonths: { ...draft.yearAttendanceMonths, "2": "-1" },
    }),
  );
  assert.throws(() =>
    validateProfileDraft({
      ...draft,
      yearAttendanceMonths: { ...draft.yearAttendanceMonths, "2": "1.5" },
    }),
  );
  assert.throws(() => validateProfileDraft({ ...draft, yearOfStudy: "0" }));
});

test("diff-based patch updates only edited fields and preserves competing sync updates across years, owned fields, and legacy keys", () => {
  const initialProfile = {
    faculty: "工学部",
    program: "融合領域分野",
    entry: "1年次入学",
    admitted: "2024",
    handbook: "2024",
    yearOfStudy: "3",
    attendanceMonths: "24",
    gpa: "3.2",
    cap: "",
    assessmentDate: "",
    yearAttendanceMonths: { "1": 12 },
  };
  const initialDraft = initialProfileDraft(initialProfile);

  // User edits ONLY year 3 to true zero "0" and assessmentDate to leap day "2024-02-29"
  const submittedDraft = {
    ...initialDraft,
    assessmentDate: "2024-02-29",
    yearAttendanceMonths: {
      ...initialDraft.yearAttendanceMonths,
      "3": "0",
    },
  };

  const diff = diffProfileDraft(initialDraft, submittedDraft);
  assert.deepEqual(diff.scalarChanges, { assessmentDate: "2024-02-29" });
  assert.deepEqual(diff.yearMonthChanges, { "3": 0 });

  // Competing sync updated owned fields AND a different academic year AND unknown/legacy fields while dialog was open
  const latestState = initialState();
  latestState.profile = {
    ...initialProfile,
    gpa: "3.9",
    attendanceMonths: "30",
    handbook: "2025",
    legacyCustom: "keep-top",
    yearAttendanceMonths: {
      "1": 12,
      "2": 12,
      legacyYear: 6,
    },
  };

  applyProfilePatch(latestState, submittedDraft, initialDraft);

  assert.equal(latestState.profile.assessmentDate, "2024-02-29");
  assert.equal(latestState.profile.gpa, "3.9");
  assert.equal(latestState.profile.attendanceMonths, "30");
  assert.equal(latestState.profile.handbook, "2025");
  assert.equal(latestState.profile.legacyCustom, "keep-top");
  assert.deepEqual(latestState.profile.yearAttendanceMonths, {
    "1": 12,
    "2": 12,
    "3": 0,
    legacyYear: 6,
  });
  assert.strictEqual(latestState.profile.yearAttendanceMonths["3"], 0);
});

test("clearing a previously set year deletes only that year key without zeroing or clobbering sibling years", () => {
  const initialProfile = {
    faculty: "工学部",
    handbook: "2026",
    yearAttendanceMonths: { "2": 12, "3": 6 },
  };
  const initialDraft = initialProfileDraft(initialProfile);
  const submittedDraft = {
    ...initialDraft,
    yearAttendanceMonths: {
      ...initialDraft.yearAttendanceMonths,
      "3": "",
    },
  };

  const latestState = initialState();
  latestState.profile = {
    ...initialProfile,
    yearAttendanceMonths: { "2": 12, "3": 6, "4": 0 },
  };

  applyProfilePatch(latestState, submittedDraft, initialDraft);
  assert.deepEqual(latestState.profile.yearAttendanceMonths, {
    "2": 12,
    "4": 0,
  });
  assert.equal(Object.hasOwn(latestState.profile.yearAttendanceMonths, "3"), false);
});
