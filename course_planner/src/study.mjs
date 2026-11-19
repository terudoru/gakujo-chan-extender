export const DAYS = [..."月火水木金土日"];
export const GAKUJO =
  "https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=rs";
export const STATUS = ["履修予定", "申請中", "許可", "不許可", "要確認"];
export { courseFields, hasUnscheduled, normalize, slotsFor, syllabusURL, termsFor } from "./course-facts.mjs";
import { hasUnscheduled, normalize, slotsFor, termsFor } from "./course-facts.mjs";
import { resolveCAP } from "./requirements.mjs";
export function activeCourses(state, byCode) {
  const codes = new Set([
    ...state.plan,
    ...Object.keys(state.status).filter((code) =>
      ["申請中", "許可"].includes(state.status[code]),
    ),
  ]);
  return [...codes]
    .filter((code) => state.status[code] !== "不許可")
    .map((code) => byCode.get(code))
    .filter(Boolean);
}
export function overlaps(a, b) {
  if (
    a.code === b.code ||
    !termsFor(a).some((term) => termsFor(b).includes(term))
  )
    return [];
  return slotsFor(a).filter((slot) => slotsFor(b).includes(slot));
}
export function conflicts(course, state, byCode) {
  return activeCourses(state, byCode).flatMap((other) => {
    const slots = overlaps(course, other);
    return slots.length ? [{ course: other, slots }] : [];
  });
}

export function chooseCourse(state, course, byCode, replace = false) {
  if (state.status[course.code] === "不許可")
    throw Error("学務で不許可となった授業です。別の候補を選んでください。");
  const collisions = conflicts(course, state, byCode);
  if (
    collisions.some(({ course: c }) =>
      ["許可", "申請中"].includes(state.status[c.code]),
    )
  ) {
    throw Error(
      "学務で申請済みの授業と重なります。学務の登録状況を確認してください。",
    );
  }
  if (collisions.length && !replace)
    throw Error("入れ替える授業を確認してください。");
  const remove = new Set(collisions.map((c) => c.course.code));
  state.plan = [
    ...new Set([
      ...state.plan.filter((code) => !remove.has(code)),
      course.code,
    ]),
  ];
}

export function spansSemesters(terms) {
  return terms.some((t) => t <= 2) && terms.some((t) => t > 2);
}
export function semesterCredits(courses, term, profile, overrides = {}, splits = {}) {
  const firstSemester = term <= 2;
  const policy = resolveCAP(profile, overrides);
  const unconfirmed = [];
  let included = 0, excluded = 0, scheduled = 0;
  for (const course of courses) {
    const terms = termsFor(course);
    if (!terms.length) {
      unconfirmed.push(course);
      continue;
    }
    if (!terms.some((t) => (t <= 2) === firstSemester)) continue;
    const crossesSemesters = spansSemesters(terms);
    let credits = course.credits;
    if (crossesSemesters) {
      const split = splits?.[course.code];
      credits = Number.isFinite(split?.first) && split.first >= 0 &&
        Number.isFinite(split.second) && split.second >= 0 &&
        Number.isFinite(course.credits) && Math.abs(split.first + split.second - course.credits) < 1e-8
        ? (firstSemester ? split.first : split.second)
        : null;
    }
    const classification = policy.classify(course);
    if (!Number.isFinite(credits) || credits < 0) {
      if (classification !== "exclude") unconfirmed.push(course);
      continue;
    }
    scheduled += credits;
    if (classification === "include") included += credits;
    else if (classification === "exclude") excluded += credits;
    else unconfirmed.push(course);
  }
  return { ...policy, included, excluded, scheduled, unconfirmed };
}



export function initialState() {
  return {
    v: 1,
    lists: [{ id: "mine", name: "履修候補", codes: [] }],
    plan: [],
    status: {},
    capOverrides: {},
    profile: {
      faculty: "",
      program: "",
      admitted: "",
      handbook: "",
      gpa: "",
      cap: "",
    },
    grades: [],
    balances: [],
    semesters: {},
  };
}
export function validCode(code) {
  return typeof code === "string" && /^\d{3}[A-Z][A-Z0-9]{4,5}$/.test(code);
}
export function validName(value) {
  const name = String(value ?? "").trim();
  if (!name || [...name].length > 80)
    throw Error("リスト名は1〜80文字で入力してください。");
  return name;
}
export function listCandidates(state, byCode, term, slot) {
  const found = new Map();
  for (const list of state.lists)
    for (const code of list.codes) {
      const course = byCode.get(code);
      if (
        !course ||
        !termsFor(course).includes(term) ||
        (slot === "他"
          ? !hasUnscheduled(course)
          : !slotsFor(course).includes(slot))
      )
        continue;
      if (!found.has(code)) found.set(code, { course, lists: [] });
      found.get(code).lists.push(list.name);
    }
  return [...found.values()];
}
export function snapshot(list, year) {
  return {
    v: 1,
    year,
    name: validName(list.name),
    codes: [...new Set(list.codes.filter(validCode))],
  };
}
export function shareLink(list, year, base) {
  const url = new URL(base);
  url.search = "";
  const bytes = new TextEncoder().encode(JSON.stringify(snapshot(list, year)));
  const encoded = Array.from(bytes, (n) => String.fromCharCode(n)).join("");
  url.hash =
    "list=" +
    btoa(encoded).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
  return url.href;
}
export function readShare(hash, year) {
  if (!hash.startsWith("#list=")) return null;
  const encoded = hash.slice(6);
  if (!/^[A-Za-z0-9_-]{1,180000}$/.test(encoded))
    throw Error("共有リンクを読み取れません。");
  let data;
  try {
    const raw = atob(encoded.replaceAll("-", "+").replaceAll("_", "/"));
    data = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(
        Uint8Array.from(raw, (c) => c.charCodeAt(0)),
      ),
    );
  } catch {
    throw Error("共有リンクを読み取れません。");
  }
  if (
    data?.v !== 1 ||
    data.year !== year ||
    !Array.isArray(data.codes) ||
    data.codes.length > 6000 ||
    !data.codes.every(validCode) ||
    typeof data.name !== "string"
  )
    throw Error("共有リンクの年度または形式に対応していません。");
  return { name: validName(data.name), codes: [...new Set(data.codes)] };
}
