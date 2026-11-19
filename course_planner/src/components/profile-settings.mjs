import { FACULTIES } from "../requirements.mjs";

export const ENTRY_OPTIONS = Object.freeze([
  "1年次入学",
  "編入",
  "転部",
  "再入学",
]);

export const OWNED_PROFILE_KEYS = Object.freeze([
  "admitted",
  "handbook",
  "faculty",
  "program",
  "entry",
  "cap",
  "gpa",
  "yearOfStudy",
  "attendanceMonths",
]);

export function toInputText(value) {
  if (value === null || value === undefined) return "";
  return String(value);
}

export function cleanNumericText(value) {
  return toInputText(value).normalize("NFKC").trim();
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
  };
}

export function facultyOptionList(facultyNames = [], handbooks = [], current = "") {
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

export function handbooksForFaculty(handbooks = [], faculty = "", preferredYear = "") {
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

export function validateProfileDraft(draft) {
  const faculty = toInputText(draft.faculty).trim();
  const program = toInputText(draft.program).trim();
  const entry = toInputText(draft.entry).trim() || "1年次入学";
  const admitted = cleanNumericText(draft.admitted);
  const handbook = cleanNumericText(draft.handbook);
  const yearOfStudy = cleanNumericText(draft.yearOfStudy);
  const attendanceMonths = cleanNumericText(draft.attendanceMonths);
  const gpa = cleanNumericText(draft.gpa);
  const cap = cleanNumericText(draft.cap);

  if (!faculty) {
    throw Error("学部・学科を選択してください。");
  }
  if (!/^\d{4}$/.test(handbook)) {
    throw Error("適用便覧の年度は4桁の西暦で入力してください。");
  }
  if (admitted !== "" && !/^\d{4}$/.test(admitted)) {
    throw Error("入学年度は4桁の西暦で入力してください。");
  }
  if (
    yearOfStudy !== "" &&
    (!/^\d+$/.test(yearOfStudy) ||
      Number(yearOfStudy) < 1 ||
      Number(yearOfStudy) > 12)
  ) {
    throw Error("現在の年次は1以上の整数で入力してください。");
  }
  if (
    attendanceMonths !== "" &&
    (!/^\d+$/.test(attendanceMonths) || Number(attendanceMonths) < 0)
  ) {
    throw Error("実在学月数は0以上の整数で入力してください。");
  }
  if (
    gpa !== "" &&
    (!Number.isFinite(Number(gpa)) || Number(gpa) < 0 || Number(gpa) > 4)
  ) {
    throw Error("前学期GPAは0〜4の範囲で入力してください。");
  }
  if (cap !== "" && (!Number.isFinite(Number(cap)) || Number(cap) < 0)) {
    throw Error("個別のCAP上限は0以上の数値で入力してください。");
  }

  return {
    admitted,
    handbook,
    faculty,
    program,
    entry,
    cap,
    gpa,
    yearOfStudy,
    attendanceMonths,
  };
}

export function applyProfilePatch(state, draft) {
  const validated = validateProfileDraft(draft);
  const currentProfile =
    state.profile && typeof state.profile === "object" ? state.profile : {};
  const nextProfile = { ...currentProfile };
  for (const key of OWNED_PROFILE_KEYS) {
    nextProfile[key] = validated[key];
  }
  state.profile = nextProfile;
  return nextProfile;
}
