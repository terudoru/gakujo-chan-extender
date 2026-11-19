import { createRegistry, installedPacks } from "./curricula/registry.mjs";
import {
  curriculumKey,
  evaluateStage,
  recognitionRule,
  selectStage,
} from "./curricula/engine.mjs";
import {
  allocationAppliesToStage,
  courseMatch,
  isAcademicFieldKey,
  prepareCourses,
  quantity,
  sameProfile,
} from "./curricula/engine-evidence.mjs";
export { gradeCourses } from "./curricula/engine-evidence.mjs";
export {
  assessmentMonth,
  attendanceMonths,
  matchBalanceRow,
  requirementGroups,
  stageStatus,
} from "./curricula/engine.mjs";

import {
  FACULTIES,
  priorDescriptor,
  priorFacultyInfo,
} from "./curricula/engine-legacy.mjs";
export { FACULTIES, sourceLinks } from "./curricula/engine-legacy.mjs";
import { courseFields, hasUnscheduled, slotsFor, termsFor } from "./course-facts.mjs";

// A confirmed field subtotal may be the only known requirement for an older
// handbook. Use its own goal/stage only when the search identifies one scope.
function statementFieldStage(state, key, context) {
  if (!isAcademicFieldKey(key)) return null;
  const balances = [],
    scopes = new Map();
  for (const b of state.balances ?? []) {
    const scope = b.scope ?? b;
    if (
      b.key !== key ||
      b.confirmed === false ||
      !sameProfile(scope, state.profile)
    )
      continue;
    const id = scope.stageId || scope.stage || scope.goal;
    if (
      !id ||
      (context.stageId && context.stageId !== id) ||
      (context.goal && context.goal !== scope.goal)
    )
      continue;
    const goal = scope.goal || context.goal;
    if (!goal) continue;
    scopes.set(JSON.stringify([goal, id]), { id, goal, rows: [] });
    balances.push(b);
  }
  if (scopes.size !== 1) return null;
  return { stage: scopes.values().next().value, state: { ...state, balances } };
}

// UI integration: pass the selected stage ID to requirementRows. Use its
// nullable remaining/after values, status/futureStatus, evidence and balance.
// Compile shortageFilter once per search with { key, stageId, term?, slot? }.
// slotRequirements returns those same stage/row keys for the selected courses.
// semesterCredits uses the same faculty policy and any individually recorded course overrides.
export function createRequirementAPI(packs = installedPacks) {
  const registry = createRegistry(packs);
  function descriptor(profile) {
    const p = {
      ...profile,
      entry: profile.entry ?? "1年次入学",
      handbook: String(profile.handbook ?? ""),
    };
    const result = registry.resolve(p);
    if (!result)
      return registry.availableHandbooks(p).length ? null : priorDescriptor(p);
    const previous = priorFacultyInfo(p)?.stage;
    if (
      !previous ||
      !result.stages.some((s) => s.goal === "progress" && s.label === previous)
    )
      return result;
    // A legacy statement with goal:"progress" belonged to this specific
    // gate before multiple stages were selectable.
    return {
      ...result,
      stages: result.stages.map((s) =>
        s.goal === "progress" && s.label === previous
          ? { ...s, legacyBalanceScope: true, default: s.default ?? true }
          : s,
      ),
    };
  }
  function availableStages(profile, goal) {
    return (descriptor(profile)?.stages ?? []).filter(
      (s) => !goal || s.goal === goal,
    );
  }
  function facultyInfo(profile) {
    if (
      !FACULTIES[profile.faculty] &&
      !registry.availableHandbooks(profile).length
    )
      return null;
    const d = descriptor(profile);
    if (!d)
      return {
        unit: FACULTIES[profile.faculty]?.unit,
        verified: false,
        stages: [],
        sources: registry
          .availableHandbooks(profile)
          .map(({ title, url }) => ({ title, url })),
        note:
          profile.faculty +
          "の学務担当に、適用便覧と個別の認定結果を確認してください。",
      };
    const progress = selectStage(d, "progress"),
      graduation = selectStage(d, "graduation");
    const minimum = (stage, key) =>
      stage?.rows.find((r) => r.key === key)?.required;
    return {
      ...d,
      unit: FACULTIES[profile.faculty]?.unit,
      verified:
        d.verified !== false &&
        (profile.entry !== "編入・転部・再入学" || d.verified === true) &&
        !!d.stages?.some((s) => s.rows.some((r) => r.required != null)),
      stage: progress?.label,
      progress: minimum(progress, "total"),
      graduation: minimum(graduation, "total"),
      general: minimum(graduation, "general"),
      major: minimum(graduation, "major"),
    };
  }
  function requirementRows(state, byCode, planned, selector = "graduation") {
    return evaluateStage(
      state,
      byCode,
      planned,
      descriptor(state.profile),
      selector,
    );
  }
  function satisfiesFilter(course, key, profile, selector = "graduation") {
    const rowKey = typeof key === "string" ? key : (key.key ?? key.requirement);
    if (!rowKey) return false;
    if (isAcademicFieldKey(rowKey))
      return !!course.fields?.includes(rowKey.slice(6));
    const stage = selectStage(
      descriptor(profile),
      typeof key === "string"
        ? selector
        : (key.stageId ?? key.goal ?? selector),
    );
    if (course.recognized) {
      if (!allocationAppliesToStage(course, stage)) return false;
      course = {
        ...course,
        allocationKey: curriculumKey(
          course.allocationKey,
          stage,
          profile.faculty,
        ),
      };
    }
    const visited = new Set();
    function matches(k) {
      if (visited.has(k)) return false;
      visited.add(k);
      const row = recognitionRule(
        stage?.rows.find((r) => r.key === k),
        stage,
      );
      if (!row) return false;
      if (course.recognized) {
        if (courseMatch(row, course, profile) === true) return true;
        if (row.evaluate && row.allocationKeys?.some(matches)) return true;
      } else if (row.match) return courseMatch(row, course, profile) === true;
      return (
        row.pool?.some((p) => matches(typeof p === "string" ? p : p.key)) ??
        false
      );
    }
    return matches(curriculumKey(rowKey, stage, profile.faculty));
  }
  // Compile once per discovery view. Re-audit only plausible candidates.
  // Requiring a positive marginal contribution accounts for exclusive pools,
  // recognized/repeated credits, same-language minima and alternate pairs.
  function shortageFilter(state, byCode, planned, context) {
    const requested = context.key ?? context.requirement;
    let d = descriptor(state.profile);
    let stage = selectStage(d, context.stageId || context.goal || "graduation");
    let auditState = state;
    if (!stage) {
      const scoped = statementFieldStage(state, requested, context);
      if (!scoped) return () => false;
      stage = scoped.stage;
      auditState = scoped.state;
      d = { ...d, stages: [stage] };
    }
    const key = curriculumKey(requested, stage, state.profile.faculty);
    const rule = stage.rows.find((r) => r.key === key);
    const keys = new Set([key]);
    for (const k of keys) {
      const row = recognitionRule(
        stage.rows.find((r) => r.key === k),
        stage,
      );
      if (!row) continue;
      for (const child of row.pool ?? [])
        keys.add(typeof child === "string" ? child : child.key);
      if (row.evaluate)
        for (const child of row.allocationKeys ?? []) keys.add(child);
      if (row.exclusive)
        for (const peer of stage.rows)
          if (peer.exclusive === row.exclusive) keys.add(peer.key);
    }
    const ledger = prepareCourses(state, byCode, planned, d);
    const audit = (prepared) =>
      evaluateStage(
        auditState,
        byCode,
        planned,
        d,
        stage.id,
        prepared,
        keys,
      ).find((r) => r.key === key);
    const base = audit(ledger);
    if (
      !base?.searchable ||
      base.after === 0 ||
      (!rule && base.required === null)
    )
      return () => false;
    const primitive = stage.rows.filter((r) => keys.has(r.key));
    const cacheable = primitive.length && primitive.every((r) => !r.evaluate);
    const cache = new Map();
    return (course) => {
      if (state.status?.[course.code] === "不許可") return false;
      if (
        context.term &&
        context.term !== "all" &&
        !termsFor(course).includes(Number(context.term))
      )
        return false;
      if (
        context.slot &&
        (context.slot === "他"
          ? !hasUnscheduled(course)
          : !slotsFor(course).includes(context.slot))
      )
        return false;
      if (
        !course.recognized &&
        rule?.match &&
        courseMatch(rule, course, state.profile) !== true
      )
        return false;
      if (!rule && !course.fields?.includes(key.slice(6))) return false;
      const candidate = ledger.additionalCourse(course);
      if (!candidate) return false;
      let candidateLedger;
      if (course.equivalentTo || course.equivalentTitle) {
        // A new equivalence can also join two existing identity groups.
        candidateLedger = prepareCourses(
          state,
          byCode,
          [...planned, course],
          d,
        );
      } else
        candidateLedger = {
          ...ledger,
          planned: [...ledger.planned, candidate],
        };
      const memoKey =
        cacheable &&
        !course.recognized &&
        !course.equivalentTo &&
        !course.equivalentTitle
          ? JSON.stringify([
              candidate.credits,
              ...primitive.map((r) => courseMatch(r, candidate, state.profile)),
            ])
          : null;
      if (memoKey && cache.has(memoKey)) return cache.get(memoKey);
      const next = audit(candidateLedger);
      const eligible =
        base.future !== null &&
        next.future !== null &&
        next.future > base.future;
      if (memoKey) cache.set(memoKey, eligible);
      return eligible;
    };
  }
  function resolveCAP(profile, overrides = {}) {
    const cap = descriptor(profile)?.cap;
    const individual = quantity(profile.cap);
    const limit = individual ?? quantity(cap?.limit);
    return {
      ...cap,
      limit,
      individual: individual !== null,
      status: limit === null ? "unknown" : "known",
      source: cap?.source,
      note:
        cap?.note ??
        (limit === null
          ? "適用便覧のCAP規定を所属学部で確認してください。"
          : undefined),
      classify(course) {
        const override = overrides[course.code];
        if (override === "算入" || override === "include") return "include";
        if (override === "除外" || override === "exclude") return "exclude";
        const result = cap?.classify?.(course, profile);
        return result === "include" || result === "exclude"
          ? result
          : "unknown";
      },
    };
  }
  function courseLedger(state, byCode, planned) {
    return prepareCourses(
      state,
      byCode,
      planned,
      descriptor(state.profile) ?? {},
    );
  }
  function academicFieldRows(state, byCode, planned, selector = "graduation") {
    selector ||= "graduation";
    const d = descriptor(state.profile);
    const ledger = prepareCourses(state, byCode, planned, d);
    const usable = (courses) =>
      courses.filter((c) => !c.ambiguousRepeat && !c.identityUnresolved);
    const fields = courseFields(usable(ledger.earned), usable(ledger.planned));
    const byField = new Map(fields.map((r) => [r.field, r]));
    if (ledger.identityReview.length) {
      const pending = byField.get("?") ?? {
        field: "?",
        earned: 0,
        planned: 0,
        courses: [],
      };
      for (const course of ledger.identityReview) {
        pending.courses.push({
          course,
          column: course.column,
          applied: 0,
          reviewOnly: true,
          reason: "同じ授業の単位か確認してください。",
        });
      }
      byField.set("?", pending);
    }
    let fieldRules = [];
    if (selectStage(d, selector)) {
      fieldRules = evaluateStage(
        state,
        byCode,
        planned,
        d,
        selector,
        ledger,
      ).filter((r) => isAcademicFieldKey(r.key));
    } else {
      const context =
        typeof selector === "object"
          ? selector
          : ["graduation", "progress"].includes(selector)
            ? { goal: selector }
            : { stageId: selector };
      for (const key of new Set((state.balances ?? []).map((b) => b.key))) {
        const scoped = statementFieldStage(state, key, context);
        if (scoped)
          fieldRules.push(
            ...evaluateStage(
              scoped.state,
              byCode,
              planned,
              { ...d, stages: [scoped.stage] },
              scoped.stage.id,
              ledger,
              new Set([key]),
            ),
          );
      }
    }
    for (const row of fieldRules) {
      const field = row.key.slice(6);
      if (!byField.has(field))
        byField.set(field, { field, earned: 0, planned: 0, courses: [] });
      byField.get(field).requirement = row;
    }
    return [...byField.values()].sort((a, b) => a.field.localeCompare(b.field));
  }
  function slotRequirements(state, byCode, planned, selected, goal) {
    const codes = new Set(selected.map((c) => c.code));
    const d = descriptor(state.profile);
    const ledger = prepareCourses(state, byCode, planned, d);
    const without = {
      ...ledger,
      planned: ledger.planned.filter((c) => !codes.has(c.code)),
    };
    if (without.planned.length === ledger.planned.length) return [];
    return (d?.stages ?? [])
      .filter((s) => !goal || s.goal === goal)
      .flatMap((s) => {
        const previous = new Map(
          evaluateStage(state, byCode, planned, d, s.id, without).map((r) => [
            r.key,
            r,
          ]),
        );
        return evaluateStage(state, byCode, planned, d, s.id, ledger).flatMap(
          (r) => {
            const prior = previous.get(r.key);
            if (
              prior.after === null ||
              r.after === null ||
              r.after >= prior.after ||
              prior.future === null ||
              r.future === null ||
              r.future <= prior.future
            )
              return [];
            return [
              {
                ...r,
                previousAfter: prior.after,
                previousFuture: prior.future,
              },
            ];
          },
        );
      });
  }
  return {
    ...registry,
    facultyInfo,
    requirementRows,
    availableStages,
    satisfiesFilter,
    shortageFilter,
    resolveCAP,
    courseLedger,
    academicFieldRows,
    slotRequirements,
  };
}

export const {
  facultyInfo,
  requirementRows,
  availableHandbooks,
  availablePrograms,
  availableStages,
  satisfiesFilter,
  shortageFilter,
  resolveCAP,
  courseLedger,
  academicFieldRows,
  slotRequirements,
} = createRequirementAPI();
export const handbooks = availableHandbooks();
