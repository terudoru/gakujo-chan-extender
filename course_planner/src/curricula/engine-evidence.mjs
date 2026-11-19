import { normalize, syllabusURL } from "../course-facts.mjs";

export function quantity(value) {
  if (typeof value !== "number" && typeof value !== "string") return null;
  if (typeof value === "string" && !/^\d+(\.\d+)?$/.test(value.trim()))
    return null;
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

// The original transcript title, year, code and record ID survive confirmation.
// The legacy Map supplied by App contains the 2026 catalog. Other catalogs must
// supply their offering year. A newer syllabus must never fill a historical row.
export function gradeCourses(state, byCode = new Map()) {
  return (state.grades ?? []).map((grade) => {
    const saved = grade.matchedCourse;
    const candidate = byCode.get(grade.code);
    let match = null;
    if (
      saved?.confirmed === true &&
      saved.year &&
      (!grade.year || String(saved.year) === String(grade.year))
    ) {
      match = saved;
    } else if (
      !saved &&
      !grade.importId &&
      !Object.hasOwn(grade, "matchedCourse") &&
      !/unknown|ambiguous|unresolved|pending|要確認/i.test(
        grade.matchStatus ?? "",
      ) &&
      candidate &&
      String(grade.year) === String(candidate.year ?? 2026) &&
      !!normalize(grade.title) &&
      normalize(grade.title) === normalize(candidate.title) &&
      (candidate.credits == null ||
        (quantity(grade.credits) !== null &&
          quantity(grade.credits) === quantity(candidate.credits))) &&
      ["section", "courseId"].every(
        (key) =>
          !grade[key] || normalize(grade[key]) === normalize(candidate[key]),
      ) &&
      (!grade.term ||
        [candidate.term, candidate.period, candidate.semester].some(
          (term) => term && normalize(term) === normalize(grade.term),
        ))
    ) {
      match = { ...candidate, year: grade.year, confirmed: true };
    }
    return {
      ...grade,
      code: grade.code ?? "",
      matchedCourse: match,
      fields: match?.fields ?? [],
      category: match?.category ?? "",
      department: match?.department ?? "",
    };
  });
}

const passed = /^(?:秀|優|良|可|合格|認定|修得(?:済み?)?|S|[ABC][+-]?|P)$/i;
const inProgress = /^(?:履修中|受講中|履修予定|申請中|許可)$/;
export const hasFailedGrade = (value) => /^(?:不可|不合格|F|D)$/i.test(value);
const notEvaluated =
  /^(?:欠席|欠試|未受験|放棄|未確定|未評価|評価なし|未修得|登録取消|履修取消|辞退|不許可|要確認|申請中|履修予定|履修中|受講中|[-－ー]+)$/;
const unregistered =
  /^(?:申請中|履修予定|不許可|登録取消|履修取消|辞退|放棄|要確認)$/;

function registration(course, status) {
  if (!status) return course;
  const registered =
    ["許可", "履修中", "受講中"].includes(status) ||
    (course.registered === true && !unregistered.test(status));
  return { ...course, status, registered };
}

function ledgerCourse(course, column, fromGrade = false) {
  const match = course.matchedCourse;
  const code = match?.code ?? course.code;
  return {
    ...match,
    ...course,
    originalTitle: course.title,
    originalCode: course.code,
    title: match?.title ?? course.title,
    code,
    year:
      course.year ||
      match?.year ||
      (!fromGrade && /^\d\d\d[A-Z]/.test(code) ? "20" + code.slice(0, 2) : ""),
    recognized: course.recognized === true || course.grade === "認定",
    unresolvedOffering: fromGrade && !match,
    column,
  };
}

// Explicit equivalences link different titles/codes. A merely identical title
// on two different records is ambiguous unless a repeat policy/identity is known.
export function prepareCourses(state, byCode, planned = [], descriptor = {}) {
  const earned = [],
    upcoming = [],
    ignored = [],
    identityReview = [];
  const history = gradeCourses(state, byCode);
  // A current registration decision supersedes stale flags on a saved plan.
  // Apply it to discovery simulations through the same entry point.
  function plannedCourse(course) {
    const status =
      state.status?.[course.code] ||
      course.status ||
      (inProgress.test(course.grade) && course.grade);
    return ledgerCourse(registration(course, status), "planned");
  }
  const records = history
    .filter((g) => !inProgress.test(g.grade))
    .map((g) => ledgerCourse(g, "earned", true));
  records.push(
    ...history
      .filter((g) => inProgress.test(g.grade))
      .map((g) =>
        ledgerCourse(
          registration(
            g,
            unregistered.test(g.grade) ? g.grade : g.status || g.grade,
          ),
          "planned",
          true,
        ),
      ),
  );
  records.push(...planned.map(plannedCourse));
  const identities = new Set(),
    titles = new Map(),
    heldKeys = new Set(),
    heldTitles = new Set();
  // Union before consuming entries so equivalence chains work in either order.
  const parents = new Map();
  function root(key) {
    const parent = parents.get(key);
    if (!parent || parent === key) return key;
    const representative = root(parent);
    parents.set(key, representative);
    return representative;
  }
  function join(a, b) {
    if (a && b) parents.set(root(a), root(b));
  }
  for (const [a, b] of descriptor?.equivalences ?? [])
    join(normalize(a), normalize(b));
  for (const c of records) {
    const title = normalize(c.title);
    if (c.equivalentTitle) join(title, normalize(c.equivalentTitle));
    if (c.equivalentTo) join(title, normalize(c.equivalentTo));
  }
  const aliasRoots = new Set([...parents.values()].map(root));
  function identity(c) {
    const title = normalize(c.title);
    const commonId =
      descriptor?.courseIdentity?.(c, state.profile) ??
      c.equivalenceKey ??
      c.repeatGroup;
    const code = normalize(c.code);
    const keys = [];
    if (c.recordId || c.importId)
      keys.push(
        "record:" + (c.sourceId ?? "") + "/" + (c.recordId || c.importId),
      );
    const year =
      c.year ||
      c.matchedCourse?.year ||
      (/^\d\d\d[a-z]/.test(code) ? "20" + code.slice(0, 2) : "");
    if (code) keys.push("offering:" + year + "/" + code);
    if (commonId) keys.push("curriculum:" + commonId);
    for (const name of [title, code]) {
      if (name && aliasRoots.has(root(name))) keys.push("alias:" + root(name));
    }
    return { title, keys, commonId };
  }
  function ineligible(c) {
    return (
      c.duplicate ||
      c.duplicateOf ||
      (c.column === "earned" && c.grade && !passed.test(c.grade)) ||
      (c.column === "planned" &&
        (state.status?.[c.code] === "不許可" || c.status === "不許可"))
    );
  }
  function awaitingIdentity(c) {
    return (
      c.identityUnresolved ||
      c.identityUncertain ||
      (c.possibleDuplicate && !c.duplicateReviewed)
    );
  }
  function overlapsHeld(c, { keys, title, commonId }) {
    return (
      keys.some((k) => heldKeys.has(k)) ||
      (title && !commonId && !c.repeatable && heldTitles.has(title))
    );
  }
  // Within each column use the confirmed offering first, then a stable order
  // for evidence when several equally good allocations exist.
  const compare = (a, b) =>
    Number(a.column === "planned") - Number(b.column === "planned") ||
    Number(a.unresolvedOffering) - Number(b.unresolvedOffering) ||
    String(a.year ?? "").localeCompare(String(b.year ?? "")) ||
    String(a.code ?? "").localeCompare(String(b.code ?? "")) ||
    String(a.recordId ?? "").localeCompare(String(b.recordId ?? ""));
  records.sort(compare);
  for (const c of records) {
    if (ineligible(c)) {
      ignored.push(c);
      continue;
    }
    const id = identity(c);
    const uncertain =
      awaitingIdentity(c) || (c.column === "planned" && overlapsHeld(c, id));
    if (uncertain) {
      c.identityUnresolved = true;
      identityReview.push(c);
      if (c.column === "earned") {
        for (const k of id.keys) heldKeys.add(k);
        for (const t of [id.title, normalize(c.alternativeTitle)])
          if (t) heldTitles.add(t);
      }
    }
    if (c.counts === false) {
      ignored.push(c);
      continue;
    }
    const { title, keys, commonId } = id;
    const duplicate = keys.some((k) => identities.has(k));
    for (const key of keys) identities.add(key);
    if (duplicate) {
      ignored.push(c);
      continue;
    }
    if (title && !c.repeatable && !commonId && titles.has(title)) {
      c.ambiguousRepeat = true;
      if (!uncertain) identityReview.push(c);
    }
    if (title) titles.set(title, c);
    (c.column === "earned" ? earned : upcoming).push(c);
  }
  // A failed evaluation is evidence of an assessed attempt only. It must not
  // reserve an offering, suppress a later retake or enter an earned ledger.
  const failedEvaluations = [];
  let seenEvaluations;
  for (const [i, g] of history.entries()) {
    if (
      !hasFailedGrade(g.grade) ||
      g.finalEvaluation === false ||
      g.evaluated === false ||
      g.passed === true ||
      g.earned === true ||
      notEvaluated.test(g.status) ||
      passed.test(g.status) ||
      notEvaluated.test(g.result) ||
      passed.test(g.result) ||
      g.duplicate ||
      g.duplicateOf ||
      g.ambiguousRepeat ||
      awaitingIdentity(g) ||
      !g.year ||
      !(g.title || g.code) ||
      state.grades[i].matchedCourse?.confirmed !== true ||
      /unknown|ambiguous|unresolved|pending|要確認/i.test(
        g.matchStatus ?? "",
      ) ||
      !g.matchedCourse?.code ||
      !g.matchedCourse.title
    )
      continue;
    const c = {
      ...ledgerCourse(g, "evaluation", true),
      evaluated: true,
      earnedCredits: 0,
    };
    const { keys } = identity(c);
    // Two contradictory results for the same recorded attempt need review.
    // A pass in a later year is a distinct attempt and keeps its own evidence.
    seenEvaluations ??= new Set(
      earned.flatMap((c) =>
        identity(c).keys.filter(
          (k) => k.startsWith("record:") || k.startsWith("offering:"),
        ),
      ),
    );
    if (keys.some((k) => seenEvaluations.has(k) || heldKeys.has(k))) continue;
    for (const k of keys) seenEvaluations.add(k);
    failedEvaluations.push(c);
  }
  function additionalCourse(input) {
    const c = plannedCourse(input);
    const id = identity(c);
    const { title, keys, commonId } = id;
    if (
      c.counts === false ||
      ineligible(c) ||
      keys.some((k) => identities.has(k)) ||
      awaitingIdentity(c) ||
      overlapsHeld(c, id) ||
      (title && titles.has(title) && !c.repeatable && !commonId)
    )
      return null;
    return c;
  }
  return {
    earned,
    failedEvaluations,
    planned: upcoming,
    ignored,
    identityReview,
    additionalCourse,
  };
}

export function evidence(course, applied, reason, source) {
  const syllabus = course.matchedCourse ?? course;
  const year =
    course.year ||
    syllabus.year ||
    (/^\d\d\d[A-Z]/.test(course.code) ? "20" + course.code.slice(0, 2) : "");
  const sourceUrl =
    course.matchedCourse?.sourceUrl ??
    course.sourceUrl ??
    (year && !course.unresolvedOffering ? syllabusURL(syllabus, year) : null);
  return {
    title: course.originalTitle || course.title,
    code: course.originalCode ?? course.code ?? "",
    matchedCode: syllabus.code ?? "",
    year,
    credits: quantity(course.credits),
    applied,
    column: course.column,
    ...(course.column === "evaluation" && {
      grade: course.grade,
      earnedCredits: 0,
      reason: "最終評価 " + course.grade + "（修得単位なし）",
    }),
    recordId: course.recordId ?? course.importId,
    sourceId: course.sourceId,
    sourceUrl: /^https?:\/\//i.test(sourceUrl ?? "") ? sourceUrl : null,
    source,
    ...(reason && { reason }),
  };
}

export function sameProfile(scope, profile) {
  return (
    scope.faculty === profile.faculty &&
    (scope.department ?? "") === (profile.department ?? "") &&
    (scope.individual ?? "") === (profile.individual ?? "") &&
    String(scope.handbook ?? "") === String(profile.handbook ?? "") &&
    (!scope.admitted ||
      String(scope.admitted) === String(profile.admitted ?? "")) &&
    (scope.program ?? "") === (profile.program ?? "") &&
    (scope.field ?? "") === (profile.field ?? "") &&
    (scope.entry || "1年次入学") === (profile.entry || "1年次入学") &&
    (scope.curriculum ?? "") === (profile.curriculum ?? "")
  );
}

export const isAcademicFieldKey = (key) => /^field-\d+$/.test(key);

export function courseMatch(row, course, profile) {
  let result;
  if (course.recognized && !isAcademicFieldKey(row.key)) {
    if (
      !course.allocationKey ||
      (course.allocationScope && !sameProfile(course.allocationScope, profile))
    )
      return null;
    // Recognition proves the assigned bucket. An offering's title or category
    // cannot move that decision to another bucket or a named child.
    result = (row.unit ?? "credits") === "credits" || row.unit === "courses";
    result =
      result &&
      (row.key === course.allocationKey ||
        !!row.allocationKeys?.includes(course.allocationKey));
  } else {
    result = row.match?.(course, profile);
    if (course.unresolvedOffering && !row.matchTranscript) return null;
  }
  if (result !== true && result !== false) return null;
  return result && (course.ambiguousRepeat || course.identityUnresolved)
    ? null
    : result;
}

export function allocationAppliesToStage(course, stage) {
  const scope = course.allocationScope;
  const id = scope?.stageId || scope?.stage;
  return (
    (!id || id === stage?.id) && (!scope?.goal || scope.goal === stage?.goal)
  );
}
