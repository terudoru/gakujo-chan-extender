import {
  DAYS,
  conflicts,
  hasUnscheduled,
  normalize,
  slotsFor,
  syllabusURL,
  termsFor,
} from "../study.mjs";
import { FACULTIES, satisfiesFilter } from "../requirements.mjs";

export const PERIOD_NUMBERS = ["1", "2", "3", "4", "5", "6", "7"];
export const SYLLABUS_HOST = "syllabus.niigata-u.ac.jp";

const OFFICIAL_SYLLABUS_PATH =
  /^\/syllabusHtml\/(\d{4})\/([A-Z0-9]{2})\/\2_(\d{3}[A-Z][A-Z0-9]{4,5})_(?:ja_JP|en_US)\.html$/;

function buildFallbackDepartments() {
  const grouped = new Map();
  for (const [name, info] of Object.entries(FACULTIES)) {
    if (!info?.unit) continue;
    if (!grouped.has(info.unit)) grouped.set(info.unit, []);
    grouped.get(info.unit).push(name);
  }
  const map = { "84": "教養教育" };
  for (const [unit, names] of grouped.entries()) {
    if (names.length === 1) {
      map[unit] = names[0];
    } else if (names.every((n) => n.startsWith("医学部"))) {
      map[unit] = "医学部";
    } else if (names.every((n) => n.startsWith("歯学部"))) {
      map[unit] = "歯学部";
    } else {
      map[unit] = names.join("・");
    }
  }
  return map;
}

export const DEFAULT_DEPARTMENT_NAMES = Object.freeze(
  buildFallbackDepartments(),
);

export function departmentName(code, departmentNames) {
  if (!code) return "";
  return departmentNames?.[code] ?? DEFAULT_DEPARTMENT_NAMES[code] ?? "";
}

export function departmentLabel(code, departmentNames) {
  if (!code) return "要確認";
  const name = departmentName(code, departmentNames);
  return name ? `${code} ${name}` : code;
}

export function departmentOptions(courses = [], departmentNames) {
  const seen = new Set();
  for (const c of courses) {
    if (c?.department) seen.add(c.department);
  }
  const sorted = [...seen].sort((a, b) => {
    if (a === "84" && b !== "84") return -1;
    if (b === "84" && a !== "84") return 1;
    return a.localeCompare(b);
  });
  return sorted.map((code) => [code, departmentLabel(code, departmentNames)]);
}

export function formatSlotLabel(slot) {
  return slot === "他" ? "集中・時限未定" : `${slot[0]}曜${slot.slice(1)}限`;
}

export function formatMeetingSlots(course) {
  if (!course) return "要確認";
  const regular = slotsFor(course).map(formatSlotLabel);
  const parts = [...regular];
  if (hasUnscheduled(course)) {
    const rawTokens = String(course.schedule ?? "")
      .normalize("NFKC")
      .split(/[,、]/)
      .map((s) => s.trim())
      .filter((s) => s && !/^[月火水木金土日][1-7]$/.test(s));
    if (rawTokens.length) {
      for (const token of rawTokens) {
        const label = token === "他" ? "集中・時限未定" : token;
        if (!parts.includes(label)) parts.push(label);
      }
    } else if (!parts.length) {
      parts.push("集中・時限未定");
    }
  }
  return parts.length ? parts.join("・") : course.schedule || "要確認";
}

export function formatOfferingTerm(course) {
  if (!course) return "要確認";
  const parts = [];
  for (const item of [course.semester, course.period]) {
    if (item && !parts.includes(item)) parts.push(item);
  }
  return parts.length ? parts.join(" · ") : "要確認";
}

export function formatAcademicFields(course, fields = {}) {
  if (!course?.fields?.length) return "分野要確認";
  return course.fields
    .map((id) => (fields[id] ? `${id} ${fields[id]}` : String(id)))
    .join("、");
}

export function formatCourseType(course) {
  const value = String(course?.format ?? "").trim();
  return value && value !== "-" ? value : "要確認";
}

export function parseOfficialSyllabusURL(raw) {
  const trimmed = String(raw ?? "").trim();
  if (!trimmed) return null;
  const looksLikeURL =
    /^https?:\/\//i.test(trimmed) ||
    trimmed.toLowerCase().includes(SYLLABUS_HOST);
  if (!looksLikeURL) return null;
  let parsed;
  try {
    parsed = new URL(trimmed);
  } catch {
    return { valid: false, reason: "invalid-url" };
  }
  if (parsed.protocol !== "https:" || parsed.host !== SYLLABUS_HOST || parsed.username || parsed.password) {
    return { valid: false, reason: "non-official-host" };
  }
  const match = OFFICIAL_SYLLABUS_PATH.exec(parsed.pathname);
  if (!match) {
    return { valid: false, reason: "unsupported-path" };
  }
  const year = Number(match[1]);
  const department = match[2];
  const code = match[3];
  const sourceUrl = `${parsed.origin}${parsed.pathname}`;
  const canonical = syllabusURL({ department, code, sourceUrl }, year);
  if (!canonical || `${parsed.origin}${parsed.pathname}` !== canonical) {
    return { valid: false, reason: "non-canonical" };
  }
  return { valid: true, year, department, code, canonical };
}

export function matchesDayPeriod(course, day = "all", periodSlot = "all") {
  if (day === "他") return hasUnscheduled(course);
  if (day !== "all" && periodSlot !== "all") {
    return slotsFor(course).includes(`${day}${periodSlot}`);
  }
  if (day !== "all") {
    return slotsFor(course).some((slot) => slot[0] === day);
  }
  if (periodSlot !== "all") {
    return slotsFor(course).some((slot) => slot.slice(1) === periodSlot);
  }
  return true;
}

export function resolveRequirementMatcher(
  context = {},
  profile = {},
  matchesRequirement,
) {
  if (typeof matchesRequirement === "function") {
    return {
      active: true,
      test: (course) => Boolean(matchesRequirement(course, context, profile)),
    };
  }
  if (typeof context?.matchesRequirement === "function") {
    return {
      active: true,
      test: (course) =>
        Boolean(context.matchesRequirement(course, context, profile)),
    };
  }
  const rawCodes =
    context?.eligibleCodes !== undefined
      ? context.eligibleCodes
      : context?.codes !== undefined
        ? context.codes
        : null;
  if (rawCodes !== null) {
    const allowed = rawCodes instanceof Set ? rawCodes : new Set(rawCodes);
    return {
      active: true,
      test: (course) => allowed.has(course.code),
    };
  }
  if (context?.requirement) {
    return {
      active: true,
      test: (course) => satisfiesFilter(course, context.requirement, profile),
    };
  }
  return { active: false, test: () => true };
}

export function initialFiltersFromContext(context = {}) {
  let day = "all";
  let periodSlot = "all";
  if (context.slot === "他") {
    day = "他";
  } else if (
    typeof context.slot === "string" &&
    /^[月火水木金土日][1-7]$/.test(context.slot)
  ) {
    day = context.slot[0];
    periodSlot = context.slot.slice(1);
  } else {
    if (context.day && (context.day === "他" || DAYS.includes(context.day))) {
      day = context.day;
    }
    if (
      context.period &&
      PERIOD_NUMBERS.includes(String(context.period)) &&
      day !== "他"
    ) {
      periodSlot = String(context.period);
    }
  }
  const field =
    context.field != null && context.field !== ""
      ? String(context.field)
      : typeof context.requirement === "string" &&
          context.requirement.startsWith("field-")
        ? context.requirement.slice(6)
        : "all";
  return {
    query: String(context.query ?? ""),
    teacher: String(context.teacher ?? ""),
    term: context.term ? String(context.term) : "all",
    department: context.department ? String(context.department) : "all",
    day,
    periodSlot,
    field,
    free: Boolean(context.free),
  };
}

export function filterAndRankCourses({
  catalog,
  state,
  byCode,
  context = {},
  filters = {},
  matchesRequirement,
  departmentNames,
}) {
  const {
    query = "",
    teacher = "",
    term = "all",
    department = "all",
    day = "all",
    periodSlot = "all",
    field = "all",
    free = false,
  } = filters;
  const req = resolveRequirementMatcher(
    context,
    state?.profile ?? {},
    matchesRequirement,
  );
  const urlQuery = parseOfficialSyllabusURL(query);
  if (urlQuery && !urlQuery.valid) {
    return {
      courses: [],
      hasRequirementContext: req.active,
      urlNotice:
        "公式シラバス（https://syllabus.niigata-u.ac.jp/syllabusHtml/…）のURLで検索してください。",
    };
  }
  if (
    urlQuery?.valid &&
    catalog?.year != null &&
    urlQuery.year !== Number(catalog.year)
  ) {
    return {
      courses: [],
      hasRequirementContext: req.active,
      urlNotice: `${urlQuery.year}年度のシラバスURLです。現在の検索対象は${catalog.year}年度です。`,
    };
  }

  const words = urlQuery
    ? []
    : String(query).trim().split(/\s+/).map(normalize).filter(Boolean);
  const teacherWords = String(teacher)
    .trim()
    .split(/\s+/)
    .map(normalize)
    .filter(Boolean);
  const deptMap = departmentNames ?? catalog?.departments;
  const catalogFields = catalog?.fields ?? {};
  const catalogYear = catalog?.year ?? 2026;

  const filtered = (catalog?.courses ?? []).filter((course) => {
    if (urlQuery?.valid) {
      if (syllabusURL(course, catalogYear) !== urlQuery.canonical) return false;
    }
    if (term !== "all" && !termsFor(course).includes(Number(term))) {
      return false;
    }
    if (department !== "all" && course.department !== department) {
      return false;
    }
    if (!matchesDayPeriod(course, day, periodSlot)) {
      return false;
    }
    if (!req.test(course)) {
      return false;
    }
    if (field !== "all" && !(course.fields ?? []).includes(field)) {
      return false;
    }
    if (free && conflicts(course, state, byCode).length > 0) {
      return false;
    }
    if (teacherWords.length) {
      const normalizedTeacher = normalize(course.teacher);
      if (!teacherWords.every((w) => normalizedTeacher.includes(w))) {
        return false;
      }
    }
    if (words.length) {
      const haystack = normalize(
        [
          course.title,
          course.teacher,
          course.code,
          course.department,
          departmentName(course.department, deptMap),
          course.category,
          course.format,
          course.period,
          course.schedule,
          ...(course.fields ?? []).map(
            (f) => `${f} ${catalogFields[f] ?? ""}`,
          ),
        ].join(" "),
      );
      if (!words.every((w) => haystack.includes(w))) {
        return false;
      }
    }
    return true;
  });

  if (!req.active || free) {
    return {
      courses: filtered,
      hasRequirementContext: req.active,
      urlNotice: "",
    };
  }
  const available = [];
  const overlapping = [];
  for (const course of filtered) {
    (conflicts(course, state, byCode).length ? overlapping : available).push(
      course,
    );
  }
  return {
    courses: [...available, ...overlapping],
    hasRequirementContext: req.active,
    urlNotice: "",
  };
}
