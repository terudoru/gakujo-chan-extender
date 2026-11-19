import {
  amount,
  distribute,
  exclusiveGroup,
  sumApplied,
} from "./engine-allocation.mjs";
import {
  allocationAppliesToStage,
  courseMatch,
  evidence,
  isAcademicFieldKey,
  prepareCourses,
  quantity,
  sameProfile,
} from "./engine-evidence.mjs";
import { normalize } from "../course-facts.mjs";

const empty = () => ({ value: 0, applied: new Map(), pending: [] });
const checkCourse =
  "適用便覧の算入区分と、成績確認表の授業・修得年度を照合してください。";
const checkBalance =
  "同じ区分の確認表に異なる数値があります。適用される確認表を確認してください。";
function uncertaintyReason(course, faculty) {
  if (course.ambiguousRepeat || course.identityUnresolved)
    return (
      "同名・読替科目の重複の扱いを" +
      faculty +
      "の学務担当に確認してください。"
    );
  if (course.recognized && !course.allocationKey)
    return faculty + "の認定結果で、この科目の算入区分を確認してください。";
  if (course.unresolvedOffering)
    return "履修年度のシラバスと成績確認表の開講番号を照合してください。";
  if (quantity(course.credits) === null)
    return "シラバスまたは成績確認表で単位数を確認してください。";
  return checkCourse;
}
function groupBy(items, key) {
  const groups = new Map();
  for (const item of items) {
    const name = key(item);
    if (!groups.has(name)) groups.set(name, []);
    groups.get(name).push(item);
  }
  return groups;
}

// Date/attendance values refer to the actual assessment and credited months.
// No elapsed-time calculation from the admission year is valid after leave.
export function assessmentMonth(profile, allowed) {
  const date = profile.assessmentDate;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date ?? "")) return null;
  const parsed = new Date(date + "T00:00:00Z");
  if (!Number.isFinite(+parsed) || parsed.toISOString().slice(0, 10) !== date)
    return null;
  return Number(allowed.includes(parsed.getUTCMonth() + 1));
}

export function attendanceMonths(profile, year) {
  const n = quantity(
    year == null
      ? profile.attendanceMonths
      : profile.yearAttendanceMonths?.[year],
  );
  return Number.isInteger(n) ? n : null;
}

export function selectStage(descriptor, selector = "graduation") {
  const stages = descriptor?.stages ?? [];
  const id =
    typeof selector === "string"
      ? selector
      : (selector.stageId ?? selector.stage ?? selector.goal);
  return (
    stages.find((s) => s.id === id) ??
    stages.find((s) => s.goal === id && s.id === descriptor?.defaultStage) ??
    stages.find((s) => s.goal === id && s.default) ??
    stages.find((s) => s.goal === id)
  );
}

// Older handbooks evaluate graduation totals without an explicit pool. The
// shared general and major buckets are graduation credit subtotals. A pack's
// explicit membership (including an empty list) always takes precedence.
export function recognitionRule(row, stage) {
  if (
    row?.key !== "total" ||
    stage.goal !== "graduation" ||
    row.pool ||
    row.allocationKeys
  )
    return row;
  const allocationKeys = stage.rows
    .filter(
      (r) =>
        ["general", "major"].includes(r.key) &&
        (r.unit ?? "credits") === "credits",
    )
    .map((r) => r.key);
  return { ...row, allocationKeys };
}

const isOfficialDecision = (row) =>
  row?.officialDecision === true &&
  row.unit === "condition" &&
  quantity(row.required) === 1;

// Earlier creation handbooks used field-* for three curricular domain rows.
// Stored decisions retain their original keys; remap only in a stage which
// actually declares the replacement for the same faculty.
export function curriculumKey(key, stage, faculty) {
  if (
    faculty === "創生学部" &&
    /^field-(foundation|advanced|pool)$/.test(key)
  ) {
    const next = "domain-" + key.slice(6);
    if (
      stage?.rows.some((r) => r.key === next) &&
      !stage.rows.some((r) => r.key === key)
    )
      return next;
  }
  return key;
}

export function matchBalanceRow(
  statement,
  stage,
  faculty = statement.scope?.faculty ?? statement.faculty,
) {
  const rows = stage?.rows ?? [];
  const key = curriculumKey(statement.key, stage, faculty);
  const keyed = rows.find((r) => r.key === key);
  const name = normalize(statement.label || statement.allocationLabel);
  const named = name
    ? rows.filter((r) =>
        [r.label, ...(r.balanceLabels ?? [])].some(
          (s) => normalize(s) === name,
        ),
      )
    : [];
  if (keyed && (!named.length || named.includes(keyed)))
    return { key: keyed.key, status: "matched" };
  if (!keyed && named.length === 1)
    return { key: named[0].key, status: "matched" };
  return {
    key: null,
    status: "review",
    candidates: [
      ...new Set([keyed, ...named].filter(Boolean).map((r) => r.key)),
    ],
  };
}

// Unscoped legacy progression statements may refer to a different year gate.
// Use one only when the goal is unique or its old stage is explicitly named.
function balancesFor(state, descriptor, stage) {
  const balances = new Map();
  for (const b of state.balances ?? []) {
    const scope = b.scope ?? b;
    if (
      b.confirmed === false ||
      !sameProfile(scope, state.profile) ||
      (scope.goal && scope.goal !== stage.goal)
    )
      continue;
    const stageId = scope.stageId || scope.stage;
    if (
      stageId
        ? stageId !== stage.id
        : !scope.goal ||
          ((descriptor?.stages ?? []).filter((s) => s.goal === scope.goal)
            .length > 1 &&
            !stage.legacyBalanceScope)
    )
      continue;
    // Field balances retain their syllabus-field key even when a curricular
    // bucket happens to have the same display label.
    const mapped = isAcademicFieldKey(b.key)
      ? { key: b.key }
      : matchBalanceRow(b, stage);
    const key = mapped.key ?? (!mapped.candidates?.length ? b.key : null);
    const rule = stage.rows.find((r) => r.key === key);
    if (
      !key ||
      (isAcademicFieldKey(key) && b.unit && b.unit !== "credits") ||
      (rule && (rule.unit ?? "credits") !== (b.unit ?? "credits"))
    )
      continue;
    const current = quantity(b.current),
      required = quantity(b.required);
    if (current === null) continue;
    if (
      b.unit === "condition" &&
      (!isOfficialDecision(rule) ||
        b.confirmed !== true ||
        stageId !== stage.id ||
        (current !== 0 && current !== 1) ||
        (Object.hasOwn(b, "required") && required !== 1) ||
        [
          "entryGrade",
          "assessmentDate",
          "graduationYear",
          "graduationMonth",
          "package",
        ].some(
          (k) =>
            Object.hasOwn(scope, k) &&
            String(scope[k] ?? "") !== String(state.profile[k] ?? ""),
        ))
    )
      continue;
    const previous = balances.get(key);
    const conflict =
      previous &&
      (previous.conflict ||
        previous.current !== current ||
        (previous.required !== null &&
          required !== null &&
          previous.required !== required));
    balances.set(key, {
      ...b,
      key,
      current,
      required: required ?? previous?.required ?? null,
      conflict: !!conflict,
    });
  }
  return balances;
}

function independent(row, courses, profile) {
  const result = empty();
  for (const c of courses) {
    const match = courseMatch(row, c, profile),
      n = amount(row, c);
    if (match === false) continue;
    if (match === null || n === null) result.pending.push(c);
    else {
      const applied = Math.min(n, row.maxPerCourse ?? Infinity);
      result.applied.set(c, applied);
      result.value += applied;
    }
  }
  return result;
}

// A decision addressed to this credit bucket does not need a syllabus match.
// Keep the actual record as its witness, including fractional credits. An
// unidentified earned statement may already include it; planned credits cannot.
function addRecognitions(result, row, credits, unidentified = 0) {
  let earned = 0;
  for (const [c, n] of credits) {
    if (n === null) {
      result.pending.push(c);
      continue;
    }
    const previous = result.applied.get(c) ?? 0;
    const applied = Math.min(n, row.maxPerCourse ?? Infinity) - previous;
    if (applied <= 0) continue;
    if (result.value === null) {
      result.value = 0;
      result.reason ||= checkCourse;
    }
    result.applied.set(c, previous + applied);
    result.value += applied;
    if (c.column === "earned") earned += applied;
  }
  if (earned && unidentified > 0) {
    result.value -= Math.min(unidentified, earned);
    result.reason ||=
      "認定科目が下位区分の確認表に含まれるか、所属学部で確認してください。";
  }
  result.unidentifiedStatement = Math.max(0, unidentified - earned);
}

// evaluate({courses, profile, baseline}) is called for earned courses and then
// for earned + planned. Return the full audited value and optional contributions
// [{course, applied}] or [{code, year, title, credits, applied}]. baseline is a
// key -> official earned subtotal map. A null value/unknown reason is retained.
function evaluated(
  row,
  courses,
  profile,
  baseline,
  children = new Map(),
  definitions,
) {
  const result = empty(),
    audited = [],
    recognized = new Map();
  const inherited = new Map();
  for (const [key, child] of children) {
    for (const [c, n] of child.applied) {
      if (c.recognized) inherited.set(c, Math.max(n, inherited.get(c) ?? 0));
    }
    // A child's official figure supersedes its course-derived credits. Only
    // identify underlying records when their combined amount fits the figure.
    if (child.covered && sumApplied(child.covered) <= baseline[key]) {
      for (const [c, n] of child.covered)
        if (c.recognized) inherited.set(c, Math.max(n, inherited.get(c) ?? 0));
    }
  }
  for (const c of courses) {
    if (inherited.has(c)) {
      recognized.set(c, inherited.get(c));
      continue;
    }
    const match = c.recognized ? courseMatch(row, c, profile) : true;
    if (match === false) {
      // Some older subtotal callbacks privately enumerate their named leaves.
      // They may still audit a confirmed offering when the actual syllabus
      // independently proves both the assigned leaf and the enclosing bucket.
      const leaf = definitions?.get(c.allocationKey);
      if (
        !row.allocationKeys &&
        ["区分計", "合計"].includes(row.kind) &&
        c.matchedCourse?.confirmed &&
        !c.identityUnresolved &&
        !c.ambiguousRepeat &&
        leaf &&
        !leaf.evaluate &&
        !leaf.pool &&
        courseMatch(leaf, c, profile) === true &&
        leaf.match?.(c, profile) === true &&
        row.match?.(c, profile) === true
      )
        audited.push(c);
      continue;
    }
    if (
      c.ambiguousRepeat ||
      c.identityUnresolved ||
      match === null ||
      (c.unresolvedOffering && !row.matchTranscript && !c.allocationKey)
    ) {
      result.pending.push(c);
    } else if (
      c.recognized &&
      (row.unit ?? "credits") === "credits" &&
      !isAcademicFieldKey(row.key)
    ) {
      if (!children.has(c.allocationKey) || c.allocationKey === row.key)
        recognized.set(c, quantity(c.credits));
    } else audited.push(c);
  }
  const calculated = row.evaluate({ courses: audited, profile, baseline });
  result.value = quantity(calculated?.value);
  result.reason = calculated?.unknown;
  for (const ref of calculated?.contributions ?? []) {
    const direct = ref.course ?? ref;
    const candidates = audited.includes(direct)
      ? [direct]
      : audited.filter(
          (c) =>
            (ref.recordId
              ? ref.recordId === c.recordId
              : ref.code
                ? c.code === ref.code
                : !!ref.title && c.title === ref.title) &&
            (!ref.year || String(ref.year) === String(c.year)),
        );
    const n = quantity(ref.applied ?? direct.credits);
    if (candidates.length === 1 && n !== null)
      result.applied.set(candidates[0], n);
  }
  // A scalar evaluator may legitimately omit witnesses for ordinary courses.
  // Only the part added by a statement can overlap the recognition records.
  const anonymous = Math.max(
    0,
    (result.value ?? 0) - sumApplied(result.applied),
  );
  let unidentified = 0;
  if (
    anonymous &&
    Object.keys(baseline).length &&
    courses.some((c) => c.recognized)
  ) {
    const without = row.evaluate({ courses: audited, profile, baseline: {} });
    unidentified = Math.min(
      anonymous,
      Math.max(0, result.value - (quantity(without?.value) ?? 0)),
    );
  }
  addRecognitions(result, row, recognized, unidentified);
  return result;
}

// pool: [{key,cap?}, ...] sums child rows with optional per-child ceilings.
// Offerings shared by several children contribute only once. Statement-only
// amounts may be summed across disjoint children (exclusive or disjoint:true).
function pooled(row, get, definitions, courses, balances, profile) {
  const result = empty();
  const parts = row.pool.map((part) =>
    typeof part === "string" ? { key: part } : part,
  );
  const known = new Map(parts.map((p) => [p, get(p.key)]));
  const capacity = new Map(courses.map((c) => [c, amount(row, c) ?? 0]));
  const exclusive = new Set(
    parts.map((p) => definitions.get(p.key)?.exclusive),
  );
  const disjoint =
    parts.length === 1 ||
    row.disjoint ||
    (exclusive.size === 1 && !exclusive.has(undefined));
  const target = new Map();
  let unidentified = 0;
  for (const [part, child] of known) {
    if (!child) throw new Error("Unknown curriculum pool member: " + part.key);
    const cap = part.cap ?? Infinity;
    let anonymous = Math.max(0, (child.value ?? 0) - sumApplied(child.applied));
    if (
      child.value === null ||
      child.reason ||
      balances.get(part.key)?.conflict
    )
      result.reason = child.reason || checkCourse;
    if (anonymous && !disjoint) {
      result.reason =
        "確認表の区分間で重複する単位の内訳を所属学部で確認してください。";
      anonymous = 0;
    }
    result.value += Math.min(anonymous, cap);
    const untraced = balances.has(part.key)
      ? Math.max(0, anonymous - (child.covered ? sumApplied(child.covered) : 0))
      : (child.unidentifiedStatement ?? 0);
    unidentified += Math.min(cap, anonymous, untraced);
    target.set(part, Math.max(0, cap - anonymous));
    if (child.value === null || child.value < cap)
      result.pending.push(...child.pending);
  }
  const assigned = distribute(
    parts,
    courses,
    capacity,
    (p) => target.get(p),
    (p, c) => known.get(p).applied.has(c),
    (p, c) => known.get(p).applied.get(c) ?? 0,
  );
  for (const entries of assigned.applied.values()) {
    result.value += sumApplied(entries);
    for (const [c, n] of entries)
      result.applied.set(c, (result.applied.get(c) ?? 0) + n);
  }
  if ((row.unit ?? "credits") === "credits") {
    // Children have already applied their own caps and exclusive allocations.
    // Only credits addressed directly to this pool bypass its child branches.
    const direct = new Map();
    for (const c of courses)
      if (c.recognized && c.allocationKey === row.key)
        direct.set(
          c,
          courseMatch(row, c, profile) === true ? quantity(c.credits) : null,
        );
    addRecognitions(result, row, direct, unidentified);
  }
  return result;
}

function assess(rows, courses, profile, balances, before) {
  const values = new Map(),
    visiting = new Set();
  const definitions = new Map(rows.map((r) => [r.key, r]));
  const baseline = Object.fromEntries(
    [...balances]
      .filter(([, b]) => !b.conflict)
      .map(([k, b]) => [k, b.current]),
  );
  const groups = groupBy(
    rows.filter((r) => r.exclusive && r.required !== null),
    (r) => r.exclusive,
  );
  for (const group of groups.values()) {
    if (new Set(group.map((r) => r.unit ?? "credits")).size !== 1)
      throw new Error("Incompatible units in exclusive group");
    const customRows = new Map();
    for (const row of group.filter((r) => r.evaluate)) {
      const result = evaluated(row, courses, profile, baseline);
      if (result.value === null || result.value > sumApplied(result.applied))
        result.reason ||= checkCourse;
      customRows.set(row, result);
    }
    for (const [key, result] of exclusiveGroup(
      group,
      courses,
      profile,
      balances,
      customRows,
    ))
      values.set(key, result);
  }
  function get(key) {
    if (balances.get(key)?.conflict) {
      const result = { ...empty(), value: null, reason: checkBalance };
      values.set(key, result);
      return result;
    }
    if (values.has(key)) return values.get(key);
    const row = definitions.get(key);
    if (!row) return null;
    if (visiting.has(key)) throw new Error("Cyclic curriculum pool: " + key);
    visiting.add(key);
    const balance = balances.get(key);
    let result;
    if (row.profileValue) {
      const v = row.profileValue(profile);
      result = {
        ...empty(),
        value: typeof v === "boolean" ? Number(v) : quantity(v),
      };
    } else if (row.evaluate) {
      const children = new Map();
      if (
        (row.unit ?? "credits") === "credits" &&
        courses.some((c) => c.recognized)
      ) {
        for (const k of row.allocationKeys ?? []) {
          if (k !== key && definitions.has(k)) children.set(k, get(k));
        }
      }
      result = evaluated(
        row,
        courses,
        profile,
        baseline,
        children,
        definitions,
      );
    } else if (row.pool)
      result = pooled(row, get, definitions, courses, balances, profile);
    else if (row.match) result = independent(row, courses, profile);
    else {
      result = independent(row, courses, profile);
      if (!result.applied.size) result.value = null;
      result.reason =
        row.unknown || "対象科目の算入先を所属学部の確認表で確認してください。";
    }
    const rawValue = result.value;
    if (balance) {
      const planned = courses.filter((c) => c.column === "planned");
      let increment = 0,
        pending = [],
        reason,
        confirmedPlanned;
      if (before && planned.length && !row.officialDecision) {
        if (row.evaluate || row.pool) {
          const prior = before.get(key);
          if (
            rawValue !== null &&
            prior.rawValue === balance.current &&
            !prior.rawIncomplete
          ) {
            increment = rawValue - prior.rawValue;
            pending = result.pending;
            reason = result.reason;
          } else {
            // A new, explicit award to the bucket itself is independent of
            // the unidentified courses behind its earlier statement.
            const direct = planned.filter(
              (c) =>
                c.recognized &&
                c.allocationKey === key &&
                (row.unit ?? "credits") === "credits",
            );
            const addition = independent(row, direct, profile);
            confirmedPlanned = addition.applied;
            increment = addition.value;
            pending = addition.pending;
            if (
              planned.some(
                (c) =>
                  !direct.includes(c) &&
                  (!row.match || courseMatch(row, c, profile) !== false),
              )
            )
              reason =
                "履修後の見込みには、確認表に算入済みの科目の内訳が必要です。";
          }
        } else if (row.match) {
          const addition = independent(row, planned, profile);
          increment = addition.value;
          pending = addition.pending;
        } else if (!row.profileValue) {
          reason = "履修予定の算入先を確認してください。";
        }
      }
      result = {
        ...result,
        rawValue,
        rawIncomplete: !!result.reason || !!result.pending.length,
        covered: new Map(
          [...result.applied].filter(([c]) => c.column === "earned"),
        ),
        applied:
          confirmedPlanned ??
          new Map(
            [...result.applied].filter(
              ([c]) => c.column === "planned" && !reason,
            ),
          ),
        value: balance.current + increment,
        pending,
        reason,
      };
    }
    if (!balance && row.unknown) result.reason ??= row.unknown;
    values.set(key, result);
    visiting.delete(key);
    return result;
  }
  for (const row of rows) get(row.key);
  return values;
}

function deficit(required, result, unknown) {
  if (required === null || result.value === null) return null;
  if (result.value >= required) return 0;
  return result.reason || result.pending.length || unknown
    ? null
    : required - result.value;
}
const status = (deficit) =>
  deficit === null ? "unknown" : deficit === 0 ? "met" : "short";

export function evaluateStage(
  state,
  byCode,
  planned,
  descriptor,
  selector = "graduation",
  prepared,
  onlyKeys,
) {
  const stage = selectStage(descriptor, selector);
  if (!stage && !["graduation", "progress"].includes(selector)) return [];
  const scope = stage ?? { id: selector, goal: selector, rows: [] };
  const balances = balancesFor(state, descriptor, scope);
  const rows = scope.rows
    .filter((row) => !onlyKeys || onlyKeys.has(row.key))
    .map((row) => {
      const b = balances.get(row.key);
      return {
        ...recognitionRule(row, scope),
        officialDecision: isOfficialDecision(row),
        required: b?.required ?? quantity(row.required),
      };
    });
  const keys = new Set(rows.map((r) => r.key));
  for (const b of balances.values()) {
    if (keys.has(b.key) || (onlyKeys && !onlyKeys.has(b.key))) continue;
    const field = isAcademicFieldKey(b.key) && b.key.slice(6);
    rows.push({
      key: b.key,
      label: b.label,
      kind: b.kind,
      unit: b.unit,
      required: b.required,
      source: b.source,
      match: field
        ? (c) => (c.fields?.length ? c.fields.includes(field) : null)
        : undefined,
    });
  }
  const ledger = prepared ?? prepareCourses(state, byCode, planned, descriptor);
  function recognition(course) {
    if (!course.recognized) return course;
    if (!allocationAppliesToStage(course, scope))
      return { ...course, allocationKey: null };
    if (course.allocationKey) {
      const key = curriculumKey(
        course.allocationKey,
        scope,
        state.profile.faculty,
      );
      return key === course.allocationKey
        ? course
        : { ...course, allocationKey: key };
    }
    if (!course.allocationLabel) return course;
    const mapped = matchBalanceRow({ label: course.allocationLabel }, scope);
    return mapped.key ? { ...course, allocationKey: mapped.key } : course;
  }
  const earned = ledger.earned.map(recognition);
  const current = assess(rows, earned, state.profile, balances);
  const future = assess(
    rows,
    [...earned, ...ledger.planned.map(recognition)],
    state.profile,
    balances,
    current,
  );
  return rows.map((row) => {
    const a = current.get(row.key),
      b = future.get(row.key),
      balance = balances.get(row.key);
    const ruleUnknown = balance ? null : row.unknown;
    const remaining = deficit(row.required, a, ruleUnknown);
    const after = deficit(row.required, b, ruleUnknown);
    const source =
      row.source ??
      scope.sources?.[0] ??
      descriptor?.sources?.[0] ??
      balance?.source;
    const refs = (map, column) =>
      [...(map ?? [])]
        .filter(([c, n]) => n > 0 && (!column || c.column === column))
        .map(([c, n]) => evidence(c, n, undefined, source));
    const earned = refs(a.applied),
      planned = refs(b.applied, "planned"),
      projectedEarned = refs(b.applied, "earned");
    const unresolved = [...new Set([...a.pending, ...b.pending])].map((c) =>
      evidence(c, 0, uncertaintyReason(c, state.profile.faculty), source),
    );
    const reason =
      ruleUnknown ||
      a.reason ||
      b.reason ||
      (remaining === null || after === null ? checkCourse : undefined);
    const sources = row.source
      ? [row.source]
      : (scope.sources ?? descriptor?.sources ?? []);
    return {
      key: row.key,
      label: row.label,
      kind: row.kind,
      group: row.group ?? row.kind,
      stageId: scope.id,
      goal: scope.goal,
      unit: row.unit ?? "credits",
      officialDecision: row.officialDecision === true,
      required: row.required,
      current: a.value,
      future: b.value,
      remaining,
      after,
      status: status(remaining),
      futureStatus: status(after),
      historyAvailable: !!(
        (state.grades?.length ?? 0) ||
        balance ||
        row.profileValue
      ),
      source,
      note: row.note,
      balance,
      earned,
      planned,
      reason,
      projectedEarned,
      covered: refs(a.covered),
      evidence: {
        earned,
        planned,
        projectedEarned,
        unknown: unresolved,
        sources,
      },
      unresolved,
      unknown: reason,
      needsBalance: remaining === null || after === null,
      searchable: !!(row.match || row.evaluate || row.pool),
    };
  });
}

export function requirementGroups(rows) {
  return [...groupBy(rows, (row) => row.group ?? row.kind)].map(
    ([label, rows]) => ({ label, rows }),
  );
}

export function stageStatus(rows, projected = false) {
  const statuses = rows
    .filter((r) => !isAcademicFieldKey(r.key))
    .map((r) => {
      const state = projected ? r.futureStatus : r.status;
      return r.historyAvailable === false && state === "short"
        ? "unknown"
        : state;
    });
  return statuses.includes("short")
    ? "short"
    : !statuses.length || statuses.includes("unknown")
      ? "unknown"
      : "met";
}
