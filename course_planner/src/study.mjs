export const DAYS = [..."月火水木金土日"];
export const GAKUJO =
  "https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=rs";
export const STATUS = ["履修予定", "申請中", "許可", "不許可", "要確認"];
export const normalize = (text) =>
  String(text ?? "")
    .normalize("NFKC")
    .replace(/\s+/gu, "")
    .toLowerCase();

export function termsFor(course) {
  const period = course.period.normalize("NFKC");
  if (period === "通年") return [1, 2, 3, 4];
  if (period.includes("ターム")) {
    const ns = [...period.matchAll(/[1-4]/g)].map((m) => Number(m[0]));
    if (/[~〜～]/.test(period) && ns.length === 2) {
      return [1, 2, 3, 4].filter((n) => n >= ns[0] && n <= ns[1]);
    }
    return ns;
  }
  if (course.semester.includes("1")) return [1, 2];
  if (course.semester.includes("2")) return [3, 4];
  return [];
}

export function slotsFor(course) {
  return course.schedule
    .normalize("NFKC")
    .split(/[,、]/)
    .map((s) => s.trim())
    .filter((s) => /^[月火水木金土日][1-7]$/.test(s));
}
export function hasUnscheduled(course) {
  return course.schedule
    .normalize("NFKC")
    .split(/[,、]/)
    .some((s) => !/^[月火水木金土日][1-7]$/.test(s.trim()));
}
export function syllabusURL(course, year = 2026) {
  if (
    !/^[A-Z0-9]{2}$/.test(course.department) ||
    !/^\d{3}[A-Z][A-Z0-9]{4,5}$/.test(course.code)
  )
    return null;
  return (
    "https://syllabus.niigata-u.ac.jp/syllabusHtml/" +
    year +
    "/" +
    course.department +
    "/" +
    course.department +
    "_" +
    course.code +
    "_ja_JP.html"
  );
}
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

export function semesterCredits(courses, term, profile, overrides = {}) {
  const semester = term <= 2 ? 1 : 2;
  let included = 0,
    excluded = 0;
  const unconfirmed = [];
  const currentRules = Number(profile.handbook) === 2026;
  for (const c of courses) {
    const terms = termsFor(c);
    if (!terms.some((t) => (t <= 2 ? 1 : 2) === semester)) continue;
    const override = overrides[c.code];
    const cross = terms.some((t) => t <= 2) && terms.some((t) => t >= 3);
    const engineering = currentRules && profile.faculty === "工学部";
    const agriculture = currentRules && profile.faculty === "農学部";
    const formats = (c.format ?? "").split("・");
    const exempt =
      ((engineering || agriculture) && c.period === "集中") ||
      (engineering && c.title.includes("リメディアル演習")) ||
      (agriculture &&
        (formats.every((f) => ["演習", "実習", "実技", "実験"].includes(f)) ||
          c.category === "留学生基本科目"));
    if (override === "除外" || (override !== "算入" && exempt)) {
      excluded += c.credits ?? 0;
    } else if (
      c.credits == null ||
      cross ||
      !terms.length ||
      (agriculture &&
        formats.includes("講義") &&
        formats.length > 1 &&
        override !== "算入")
    ) {
      unconfirmed.push(c);
    } else {
      included += c.credits;
    }
  }
  const limit =
    profile.cap != null && profile.cap !== ""
      ? Number(profile.cap)
      : currentRules && profile.faculty === "工学部"
        ? 28
        : currentRules && profile.faculty === "農学部"
          ? Number(profile.gpa) >= 3.5
            ? 28
            : 24
          : null;
  return { included, excluded, limit, unconfirmed };
}

export function courseFields(earned, planned) {
  const rows = new Map();
  for (const [records, column] of [
    [earned, "earned"],
    [planned, "planned"],
  ]) {
    for (const course of records) {
      for (const field of new Set(
        course.fields?.length ? course.fields : ["?"],
      )) {
        if (!rows.has(field))
          rows.set(field, { field, earned: 0, planned: 0, courses: [] });
        const row = rows.get(field);
        row[column] += course.credits ?? 0;
        row.courses.push({ course, column });
      }
    }
  }
  return [...rows.values()].sort((a, b) => a.field.localeCompare(b.field));
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
      admitted: "2026",
      handbook: "2026",
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
