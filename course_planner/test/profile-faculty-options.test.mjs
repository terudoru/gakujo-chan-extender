import test from "node:test";
import assert from "node:assert/strict";
import { initialState } from "../src/study.mjs";
import {
  applyProfilePatch,
  initialProfileDraft,
  validateProfileDraft,
} from "../src/components/profile-settings.mjs";

const BASE = {
  faculty: "法学部",
  handbook: "2026",
  admitted: "2026",
  entry: "1年次入学",
  program: "",
  yearOfStudy: "",
  attendanceMonths: "",
  cap: "",
  gpa: "",
  assessmentDate: "",
};

test("GPA and thirdYearCumulativeGpa accept 0, 4.5, and 5 and reject > 5 or < 0", () => {
  for (const valid of ["0", "2.8", "4.5", "5", "５"]) {
    const res = validateProfileDraft({
      ...BASE,
      gpa: valid,
      thirdYearCumulativeGpa: valid,
    });
    assert.equal(Number(res.gpa), Number(valid.normalize("NFKC")));
    assert.strictEqual(
      res.thirdYearCumulativeGpa,
      Number(valid.normalize("NFKC")),
    );
  }
  const empty = validateProfileDraft({
    ...BASE,
    gpa: "",
    thirdYearCumulativeGpa: "",
  });
  assert.equal(empty.gpa, "");
  assert.equal(Object.hasOwn(empty, "thirdYearCumulativeGpa"), false);

  for (const invalid of ["5.01", "5.1", "6", "-0.1", "abc"]) {
    assert.throws(() => validateProfileDraft({ ...BASE, gpa: invalid }));
    assert.throws(() =>
      validateProfileDraft({ ...BASE, thirdYearCumulativeGpa: invalid }),
    );
  }
});

test("tri-state conditional booleans keep true, false, and absent distinct with no inferred approvals", () => {
  const unset = validateProfileDraft({ ...BASE });
  for (const key of [
    "earlyGraduation",
    "deanException",
    "lawPaperSubstitutionApproved",
    "iStepApproved",
  ]) {
    assert.equal(Object.hasOwn(unset, key), false);
  }

  const mixed = validateProfileDraft({
    ...BASE,
    earlyGraduation: "true",
    deanException: "false",
    lawPaperSubstitutionApproved: "",
    iStepApproved: "true",
  });
  assert.strictEqual(mixed.earlyGraduation, true);
  assert.strictEqual(mixed.deanException, false);
  assert.equal(Object.hasOwn(mixed, "lawPaperSubstitutionApproved"), false);
  assert.strictEqual(mixed.iStepApproved, true);

  // Initializing draft from booleans & absent
  const draft = initialProfileDraft(mixed);
  assert.equal(draft.earlyGraduation, "true");
  assert.equal(draft.deanException, "false");
  assert.equal(draft.lawPaperSubstitutionApproved, "");
  assert.equal(draft.iStepApproved, "true");
});

test("entryGrade, graduationYear, and graduationMonth validate bounds and omit empty values", () => {
  const valid = validateProfileDraft({
    ...BASE,
    faculty: "創生学部",
    entry: "編入",
    entryGrade: "3",
    graduationYear: "2027",
    graduationMonth: "3",
  });
  assert.strictEqual(valid.entryGrade, 3);
  assert.strictEqual(valid.graduationYear, 2027);
  assert.strictEqual(valid.graduationMonth, 3);

  // Other valid calendar months 1..12 allowed when source month is unknown
  assert.strictEqual(
    validateProfileDraft({ ...BASE, graduationMonth: "9" }).graduationMonth,
    9,
  );
  assert.strictEqual(
    validateProfileDraft({ ...BASE, graduationMonth: "6" }).graduationMonth,
    6,
  );
  assert.strictEqual(
    validateProfileDraft({ ...BASE, graduationMonth: "12" }).graduationMonth,
    12,
  );

  // Invalid values rejected
  for (const badGrade of ["0", "-1", "2.5", "abc"]) {
    assert.throws(() => validateProfileDraft({ ...BASE, entryGrade: badGrade }));
  }
  for (const badYear of ["27", "20265", "abcd"]) {
    assert.throws(() =>
      validateProfileDraft({ ...BASE, graduationYear: badYear }),
    );
  }
  for (const badMonth of ["0", "13", "-3", "3.5", "abc"]) {
    assert.throws(() =>
      validateProfileDraft({ ...BASE, graduationMonth: badMonth }),
    );
  }
});

test("diff-based patch clears edited tri-state to absent while preserving hidden and concurrently synced fields", () => {
  const initialProfile = {
    ...BASE,
    earlyGraduation: true,
    deanException: false,
    iStepApproved: true, // hidden while faculty === 法学部
    entryGrade: 3, // hidden while faculty === 法学部
    graduationYear: 2027, // hidden while faculty === 法学部
    graduationMonth: 3, // hidden while faculty === 法学部
  };
  const initialDraft = initialProfileDraft(initialProfile);

  // User clears earlyGraduation to "" and sets thirdYearCumulativeGpa to "0" (true zero)
  const submittedDraft = {
    ...initialDraft,
    earlyGraduation: "",
    thirdYearCumulativeGpa: "0",
  };

  // Competing sync updated deanException (same faculty), iStepApproved (hidden), and gpa
  const latestState = initialState();
  latestState.profile = {
    ...initialProfile,
    deanException: true,
    iStepApproved: false,
    gpa: "4.5",
    unknownCustom: "keep",
  };

  applyProfilePatch(latestState, submittedDraft, initialDraft);

  assert.equal(Object.hasOwn(latestState.profile, "earlyGraduation"), false);
  assert.strictEqual(latestState.profile.thirdYearCumulativeGpa, 0);
  assert.strictEqual(latestState.profile.deanException, true);
  assert.strictEqual(latestState.profile.iStepApproved, false);
  assert.strictEqual(latestState.profile.entryGrade, 3);
  assert.strictEqual(latestState.profile.graduationYear, 2027);
  assert.strictEqual(latestState.profile.graduationMonth, 3);
  assert.equal(latestState.profile.gpa, "4.5");
  assert.equal(latestState.profile.unknownCustom, "keep");
});
