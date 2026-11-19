import { FACULTIES } from "../requirements.mjs";

export const ENTRY_OPTIONS = Object.freeze([
  "1年次入学",
  "編入",
  "転部",
  "再入学",
]);

export const ACADEMIC_YEARS = Object.freeze(["1", "2", "3", "4", "5", "6"]);

export const SCALAR_OWNED_PROFILE_KEYS = Object.freeze([
  "admitted",
  "handbook",
  "faculty",
  "program",
  "entry",
  "cap",
  "gpa",
  "yearOfStudy",
  "attendanceMonths",
  "assessmentDate",
]);

export const TRI_STATE_PROFILE_KEYS = Object.freeze([
  "earlyGraduation",
  "deanException",
  "lawPaperSubstitutionApproved",
  "iStepApproved",
]);

export const OPTIONAL_NUMERIC_PROFILE_KEYS = Object.freeze([
  "thirdYearCumulativeGpa",
  "entryGrade",
  "graduationYear",
  "graduationMonth",
]);

export const CONDITIONAL_PROFILE_KEYS = Object.freeze([
  ...TRI_STATE_PROFILE_KEYS,
  ...OPTIONAL_NUMERIC_PROFILE_KEYS,
]);

export const OWNED_PROFILE_KEYS = Object.freeze([
  ...SCALAR_OWNED_PROFILE_KEYS,
  "yearAttendanceMonths",
]);

export function toInputText(value) {
  if (value === null || value === undefined) return "";
  return String(value);
}

export function toTriStateText(value) {
  if (value === true) return "true";
  if (value === false) return "false";
  return "";
}

export function cleanNumericText(value) {
  return toInputText(value).normalize("NFKC").trim();
}

export function isValidISODate(value) {
  const cleaned = cleanNumericText(value);
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(cleaned);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

export function safeExternalURL(url) {
  if (typeof url !== "string" || !url.trim()) return null;
  try {
    const parsed = new URL(url.trim());
    if (parsed.protocol === "https:" || parsed.protocol === "http:") {
      return parsed.href;
    }
    return null;
  } catch {
    return null;
  }
}

export function initialYearAttendanceDraft(source) {
  const map =
    source && typeof source === "object" && !Array.isArray(source)
      ? source
      : {};
  const draft = {};
  for (const year of ACADEMIC_YEARS) {
    draft[year] = toInputText(map[year]);
  }
  return draft;
}

export function initialProfileDraft(profile = {}) {
  return {
    faculty: toInputText(profile.faculty),
    program: toInputText(profile.program),
    entry: toInputText(profile.entry) || "1年次入学",
    admitted: toInputText(profile.admitted),
    handbook: toInputText(profile.handbook),
    yearOfStudy: toInputText(profile.yearOfStudy),
    attendanceMonths: toInputText(profile.attendanceMonths),
    gpa: toInputText(profile.gpa),
    cap: toInputText(profile.cap),
    assessmentDate: toInputText(profile.assessmentDate),
    yearAttendanceMonths: initialYearAttendanceDraft(
      profile.yearAttendanceMonths,
    ),
    earlyGraduation: toTriStateText(profile.earlyGraduation),
    deanException: toTriStateText(profile.deanException),
    lawPaperSubstitutionApproved: toTriStateText(
      profile.lawPaperSubstitutionApproved,
    ),
    thirdYearCumulativeGpa: toInputText(profile.thirdYearCumulativeGpa),
    iStepApproved: toTriStateText(profile.iStepApproved),
    entryGrade: toInputText(profile.entryGrade),
    graduationYear: toInputText(profile.graduationYear),
    graduationMonth: toInputText(profile.graduationMonth),
  };
}

export function facultyOptionList(
  facultyNames = [],
  handbooks = [],
  current = "",
) {
  const base = facultyNames.length ? [...facultyNames] : Object.keys(FACULTIES);
  const seen = new Set(base);
  for (const item of handbooks) {
    if (item?.faculty && !seen.has(item.faculty)) {
      seen.add(item.faculty);
      base.push(item.faculty);
    }
  }
  if (current && !seen.has(current)) {
    base.push(current);
  }
  return base;
}

export function entryOptionList(current = "") {
  const list = [...ENTRY_OPTIONS];
  if (current && !list.includes(current)) {
    list.push(current);
  }
  return list;
}

export function handbooksForFaculty(
  handbooks = [],
  faculty = "",
  preferredYear = "",
) {
  if (!faculty) return [];
  const preferred = cleanNumericText(preferredYear);
  return handbooks
    .filter((item) => item && item.faculty === faculty)
    .map((item) => ({
      faculty: String(item.faculty),
      year: cleanNumericText(item.year),
      title: String(item.title ?? ""),
      url: safeExternalURL(item.url),
      programs: normalizeProgramList(item.programs),
    }))
    .sort((a, b) => {
      const aMatch = preferred && a.year === preferred ? 1 : 0;
      const bMatch = preferred && b.year === preferred ? 1 : 0;
      if (aMatch !== bMatch) return bMatch - aMatch;
      return Number(b.year || 0) - Number(a.year || 0);
    });
}

function normalizeProgramList(programs) {
  if (!Array.isArray(programs)) return [];
  const out = [];
  const seen = new Set();
  for (const item of programs) {
    const label =
      typeof item === "string"
        ? item.trim()
        : String(item?.name ?? item?.label ?? "").trim();
    if (label && !seen.has(label)) {
      seen.add(label);
      out.push(label);
    }
  }
  return out;
}

export function programChoicesFor(
  handbooks = [],
  faculty = "",
  handbookYear = "",
  admittedYear = "",
) {
  if (!faculty) return [];
  const records = handbooksForFaculty(handbooks, faculty, handbookYear);
  const targetHandbook = cleanNumericText(handbookYear);
  const targetAdmitted = cleanNumericText(admittedYear);

  const exactHandbook = records.find(
    (r) => targetHandbook && r.year === targetHandbook && r.programs.length > 0,
  );
  if (exactHandbook) return exactHandbook.programs;

  const exactAdmitted = records.find(
    (r) => targetAdmitted && r.year === targetAdmitted && r.programs.length > 0,
  );
  if (exactAdmitted) return exactAdmitted.programs;

  return [];
}

function validateGpaText(raw, label) {
  const cleaned = cleanNumericText(raw);
  if (cleaned === "") return "";
  if (
    !Number.isFinite(Number(cleaned)) ||
    Number(cleaned) < 0 ||
    Number(cleaned) > 5
  ) {
    throw Error(`${label}は0〜5の範囲で入力してください。`);
  }
  return cleaned;
}

function validateScalarField(key, raw) {
  switch (key) {
    case "faculty": {
      const faculty = toInputText(raw).trim();
      if (!faculty) throw Error("学部・学科を選択してください。");
      return faculty;
    }
    case "program":
      return toInputText(raw).trim();
    case "entry":
      return toInputText(raw).trim() || "1年次入学";
    case "handbook": {
      const handbook = cleanNumericText(raw);
      if (!/^\d{4}$/.test(handbook)) {
        throw Error("適用便覧の年度は4桁の西暦で入力してください。");
      }
      return handbook;
    }
    case "admitted": {
      const admitted = cleanNumericText(raw);
      if (admitted !== "" && !/^\d{4}$/.test(admitted)) {
        throw Error("入学年度は4桁の西暦で入力してください。");
      }
      return admitted;
    }
    case "yearOfStudy": {
      const yearOfStudy = cleanNumericText(raw);
      if (
        yearOfStudy !== "" &&
        (!/^\d+$/.test(yearOfStudy) ||
          Number(yearOfStudy) < 1 ||
          !Number.isSafeInteger(Number(yearOfStudy)))
      ) {
        throw Error("現在の年次は1以上の整数で入力してください。");
      }
      return yearOfStudy;
    }
    case "attendanceMonths": {
      const attendanceMonths = cleanNumericText(raw);
      if (
        attendanceMonths !== "" &&
        (!/^\d+$/.test(attendanceMonths) ||
          Number(attendanceMonths) < 0 ||
          !Number.isSafeInteger(Number(attendanceMonths)))
      ) {
        throw Error("実在学月数は0以上の整数で入力してください。");
      }
      return attendanceMonths;
    }
    case "gpa":
      return validateGpaText(raw, "前学期GPA");
    case "cap": {
      const cap = cleanNumericText(raw);
      if (cap !== "" && (!Number.isFinite(Number(cap)) || Number(cap) < 0)) {
        throw Error("個別のCAP上限は0以上の数値で入力してください。");
      }
      return cap;
    }
    case "assessmentDate": {
      const assessmentDate = cleanNumericText(raw);
      if (assessmentDate !== "" && !isValidISODate(assessmentDate)) {
        throw Error(
          "判定基準日は実在する日付をYYYY-MM-DD形式で入力してください。",
        );
      }
      return assessmentDate;
    }
    default:
      return raw;
  }
}

function validateConditionalField(key, raw) {
  if (TRI_STATE_PROFILE_KEYS.includes(key)) {
    if (raw === true || raw === "true") return true;
    if (raw === false || raw === "false") return false;
    const text = toInputText(raw).trim();
    if (text === "") return undefined;
    throw Error("該当・非該当または未設定を選択してください。");
  }
  switch (key) {
    case "thirdYearCumulativeGpa": {
      const cleaned = validateGpaText(raw, "3年次末累積GPA");
      if (cleaned === "") return undefined;
      const n = Number(cleaned);
      return Object.is(n, -0) ? 0 : n;
    }
    case "entryGrade": {
      const cleaned = cleanNumericText(raw);
      if (cleaned === "") return undefined;
      if (
        !/^\d+$/.test(cleaned) ||
        Number(cleaned) < 1 ||
        Number(cleaned) > 4
      ) {
        throw Error("編入した年次は1〜4の整数で入力してください。");
      }
      return Number(cleaned);
    }
    case "graduationYear": {
      const cleaned = cleanNumericText(raw);
      if (cleaned === "") return undefined;
      if (!/^\d{4}$/.test(cleaned)) {
        throw Error("卒業予定（暦年）は4桁の西暦で入力してください。");
      }
      return Number(cleaned);
    }
    case "graduationMonth": {
      const cleaned = cleanNumericText(raw);
      if (cleaned === "") return undefined;
      if (cleaned !== "3" && cleaned !== "9") {
        throw Error("卒業予定月は3月または9月を選択してください（未設定も可）。");
      }
      return Number(cleaned);
    }
    default:
      return undefined;
  }
}

function validateYearMonthValue(raw) {
  const cleaned = cleanNumericText(raw);
  if (cleaned === "") return null;
  if (
    !/^\d+$/.test(cleaned) ||
    Number(cleaned) < 0 ||
    !Number.isSafeInteger(Number(cleaned))
  ) {
    throw Error("年次別の在学月数は0以上の整数で入力してください。");
  }
  return Number(cleaned);
}

function normalizeForDiff(key, raw) {
  if (key === "faculty" || key === "program" || key === "entry") {
    return toInputText(raw).trim();
  }
  if (TRI_STATE_PROFILE_KEYS.includes(key)) {
    if (raw === true || raw === "true") return "true";
    if (raw === false || raw === "false") return "false";
    return toInputText(raw).trim();
  }
  return cleanNumericText(raw);
}

export function validateProfileDraft(draft) {
  const result = {};
  for (const key of SCALAR_OWNED_PROFILE_KEYS) {
    result[key] = validateScalarField(key, draft?.[key]);
  }
  const yearMonths = {};
  const rawYears = draft?.yearAttendanceMonths ?? {};
  for (const year of ACADEMIC_YEARS) {
    const parsed = validateYearMonthValue(rawYears[year]);
    if (parsed !== null) {
      yearMonths[year] = parsed;
    }
  }
  result.yearAttendanceMonths = yearMonths;
  for (const key of CONDITIONAL_PROFILE_KEYS) {
    const parsed = validateConditionalField(key, draft?.[key]);
    if (parsed !== undefined) {
      result[key] = parsed;
    }
  }
  return result;
}

export function diffProfileDraft(initialDraft, submittedDraft) {
  const scalarChanges = {};
  for (const key of SCALAR_OWNED_PROFILE_KEYS) {
    const before = normalizeForDiff(key, initialDraft?.[key]);
    const after = normalizeForDiff(key, submittedDraft?.[key]);
    if (before !== after) {
      scalarChanges[key] = validateScalarField(key, submittedDraft?.[key]);
    }
  }

  const conditionalChanges = {};
  for (const key of CONDITIONAL_PROFILE_KEYS) {
    const before = normalizeForDiff(key, initialDraft?.[key]);
    const after = normalizeForDiff(key, submittedDraft?.[key]);
    if (before !== after) {
      conditionalChanges[key] = validateConditionalField(
        key,
        submittedDraft?.[key],
      );
    }
  }

  const yearMonthChanges = {};
  const beforeYears = initialDraft?.yearAttendanceMonths ?? {};
  const afterYears = submittedDraft?.yearAttendanceMonths ?? {};
  for (const year of ACADEMIC_YEARS) {
    const before = cleanNumericText(beforeYears[year]);
    const after = cleanNumericText(afterYears[year]);
    if (before !== after) {
      yearMonthChanges[year] = validateYearMonthValue(afterYears[year]);
    }
  }

  return { scalarChanges, conditionalChanges, yearMonthChanges };
}

export function applyProfilePatch(state, draft, initialDraft) {
  const currentProfile =
    state.profile && typeof state.profile === "object" ? state.profile : {};

  if (!initialDraft) {
    const validated = validateProfileDraft(draft);
    const nextProfile = { ...currentProfile };
    for (const key of SCALAR_OWNED_PROFILE_KEYS) {
      nextProfile[key] = validated[key];
    }
    for (const key of CONDITIONAL_PROFILE_KEYS) {
      if (Object.hasOwn(validated, key)) {
        nextProfile[key] = validated[key];
      } else {
        delete nextProfile[key];
      }
    }
    const existingYearMonths =
      currentProfile.yearAttendanceMonths &&
      typeof currentProfile.yearAttendanceMonths === "object" &&
      !Array.isArray(currentProfile.yearAttendanceMonths)
        ? { ...currentProfile.yearAttendanceMonths }
        : {};
    for (const year of ACADEMIC_YEARS) {
      if (Object.hasOwn(validated.yearAttendanceMonths, year)) {
        existingYearMonths[year] = validated.yearAttendanceMonths[year];
      } else {
        delete existingYearMonths[year];
      }
    }
    nextProfile.yearAttendanceMonths = existingYearMonths;
    state.profile = nextProfile;
    return nextProfile;
  }

  const { scalarChanges, conditionalChanges, yearMonthChanges } =
    diffProfileDraft(initialDraft, draft);
  const nextProfile = { ...currentProfile, ...scalarChanges };

  for (const [key, value] of Object.entries(conditionalChanges)) {
    if (value === undefined) {
      delete nextProfile[key];
    } else {
      nextProfile[key] = value;
    }
  }

  // Validate required profile invariants against the merged latest state.
  validateScalarField("faculty", nextProfile.faculty);
  validateScalarField("handbook", nextProfile.handbook);

  const changedYears = Object.keys(yearMonthChanges);
  if (changedYears.length > 0) {
    const existingYearMonths =
      currentProfile.yearAttendanceMonths &&
      typeof currentProfile.yearAttendanceMonths === "object" &&
      !Array.isArray(currentProfile.yearAttendanceMonths)
        ? { ...currentProfile.yearAttendanceMonths }
        : {};
    for (const year of changedYears) {
      const value = yearMonthChanges[year];
      if (value === null) {
        delete existingYearMonths[year];
      } else {
        existingYearMonths[year] = value;
      }
    }
    nextProfile.yearAttendanceMonths = existingYearMonths;
  }

  state.profile = nextProfile;
  return nextProfile;
}
