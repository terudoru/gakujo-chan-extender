import { normalize, validCode } from "../study.mjs";
import { mergeGrades, reviewGrades } from "../transcript.mjs";
import {
  readUnits,
  readYear,
  rowStatus,
  scanTables,
  validatePacket,
} from "./tables.mjs";

export function plannerBalanceScope(profile = {}, goal = "", stage = "") {
  return {
    faculty: profile.faculty || "",
    handbook: String(profile.handbook || ""),
    admitted: String(profile.admitted || ""),
    department: profile.department || "",
    program: profile.program || "",
    field: profile.field || "",
    entry: profile.entry || "1年次入学",
    curriculum: profile.curriculum || "",
    individual: profile.individual ?? "",
    goal: goal || "",
    stage: stage || "",
  };
}
function sameScope(a, b) {
  return Object.keys(b).every((key) => a[key] === b[key]);
}

function recordedScope(balance) {
  const scope = balance.scope ?? balance;
  return plannerBalanceScope(
    scope,
    scope.goal ?? balance.goal,
    scope.stageId || scope.stage || balance.stageId || balance.stage,
  );
}

// Match the engine's sameProfile contract. Older statements without an
// admission year apply to the selected handbook; an explicit year is binding.
export function samePlannerBalance(stored, replacement) {
  if (stored.key !== replacement.key) return false;
  const unit = (balance) => balance.unit || balance.scope?.unit || "credits";
  if (unit(stored) !== unit(replacement)) return false;
  const old = recordedScope(stored);
  const next = recordedScope(replacement);
  if (!old.admitted) old.admitted = next.admitted;
  return sameScope(old, next);
}
function matchingRequirement(label, targets, kind) {
  const exact = targets.filter(
    (r) =>
      [r.key, r.label].some((v) => normalize(v) === normalize(label)) &&
      (!kind || !r.kind || kind === r.kind),
  );
  return exact.length === 1 ? exact[0] : null;
}
function registrationRow(
  v,
  origin,
  { byCode = new Map(), catalogYear = 2026 },
) {
  const code = normalize(v.code)
    .toUpperCase()
    .replace(/\s*\(T[1-4](?:,[1-4])*\)$/, "");
  const year = v.year ? readYear(v.year) : origin.year;
  const course = byCode.get(code);
  const label = [code, v.title || course?.title].filter(Boolean).join(" ");
  if (
    !validCode(code) ||
    !course ||
    (v.year && !year) ||
    (year && year !== String(course.year ?? catalogYear)) ||
    (v.title && normalize(v.title) !== normalize(course.title))
  ) {
    return {
      label,
      reason: "要確認：開講番号・科目名・年度を同じ授業として照合できません。",
    };
  }
  const explicit = rowStatus(v.status);
  const conflict = !!(v.status && origin.status && explicit !== origin.status);
  const status = conflict
    ? "要確認"
    : (v.status ? explicit : origin.status) || "要確認";
  return {
    label,
    value: { code, title: v.title || course.title, year, status },
    reason:
      status === "要確認"
        ? "結果を区別できません。学務の登録状況を確認してください。"
        : "",
  };
}

function balanceRow(v, targets) {
  const label = v.category;
  const day = readUnits(v.day),
    night = readUnits(v.night);
  const current =
    v.day != null && v.night != null
      ? day != null && night != null
        ? day + night
        : null
      : readUnits(v.current);
  const required = readUnits(v.required);
  if (!label || current == null || (v.required && required == null)) {
    return {
      label: label || "区分不明",
      reason: "要確認：区分名・既修得単位・必要単位の列を確認してください。",
    };
  }
  const target = matchingRequirement(label, targets, v.kind);
  return {
    label,
    value: {
      label,
      current,
      required,
      kind: v.kind || "区分計",
      ...(day != null && night != null ? { day, night } : {}),
    },
    targetKey: target?.key || "",
    reason: !target
      ? "要確認：帳票の区分に対応する要件を選んでください。"
      : required == null && target.required == null
        ? "要確認：帳票と便覧の必要単位を確認してください。"
        : "",
  };
}

export function reviewPlannerImport(packet, options = {}) {
  validatePacket(packet);
  const { profile, goal = "graduation", requirementRows = [] } = options;
  const scope = plannerBalanceScope(
    profile,
    goal,
    options.stageId || options.stage,
  );
  const targets = requirementRows
    .filter((r) => r?.key && r.label && (!r.unit || r.unit === "credits"))
    .map(({ key, label, required, kind }) => ({ key, label, required, kind }));
  let rows = [];
  if (packet.kind === "grades") {
    rows = reviewGrades(packet, options);
    for (const row of rows) {
      const { value } = row;
      if (!value?.recognized || !value.allocationLabel) continue;
      const target = matchingRequirement(value.allocationLabel, targets);
      if (target && target.key !== "total" && scope.faculty && scope.handbook) {
        value.allocationKey = target.key;
        value.allocationScope = scope;
      } else row.reason += " 要確認：認定区分と便覧の対応を確認してください。";
    }
  } else {
    scanTables(
      packet,
      (v, origin) => {
        const result =
          packet.kind === "registration"
            ? registrationRow(v, origin, options)
            : balanceRow(v, targets);
        rows.push({ id: origin.id, ...result });
      },
      (id, reason) => rows.push({ id, label: "要確認", reason }),
    );
    if (packet.kind === "registration") {
      const outcomes = new Map();
      for (const { value } of rows) {
        if (!value) continue;
        if (!outcomes.has(value.code)) outcomes.set(value.code, new Set());
        outcomes.get(value.code).add(value.status);
      }
      for (const row of rows) {
        if (row.value && outcomes.get(row.value.code).size > 1) {
          row.value.status = "要確認";
          row.reason =
            "同じ開講番号に異なる結果があります。学務で確認してください。";
        }
      }
    }
  }
  return { kind: packet.kind, rows, targets, scope };
}

function selectedRows(review, selections) {
  if (!Array.isArray(selections) || !selections.length)
    throw Error("取り込む行を選んでください。");
  const byId = new Map(review.rows.map((r) => [r.id, r]));
  const selected = selections.map((choice) => {
    let row = byId.get(choice.id);
    if (row?.finalEvaluationCandidate) {
      if (choice.confirmFinalEvaluation !== true)
        throw Error("この科目の最終評価を確認してください。");
      row = { ...row, value: row.value ?? row.finalEvaluationCandidate };
    }
    return { choice, row };
  });
  if (
    new Set(selections.map((s) => s.id)).size !== selections.length ||
    selected.some(({ row }) => !row?.value)
  )
    throw Error("確認できた行だけを選んでください。");
  return selected;
}

function reviewedGrade({ row, choice }) {
  const grade = row.value;
  if (grade.finalEvaluation) return grade;
  if (choice.excludeDuplicate)
    return {
      ...grade,
      counts: false,
      duplicate: true,
      duplicateReviewed: true,
    };
  if (
    choice.confirmDistinct &&
    grade.possibleDuplicate &&
    !grade.identityUncertain &&
    !grade.duplicate
  )
    return { ...grade, counts: true, duplicateReviewed: true };
  return grade;
}

const recordId = (grade) => grade.recordId || grade.id || grade.importId;

function matchFingerprint(match) {
  // Store the evidence as it was before awaiting the archive. Object key order
  // may change on sync, while changes to any field or source must be preserved.
  return JSON.stringify(match, (_, value) =>
    value && typeof value === "object" && !Array.isArray(value)
      ? Object.fromEntries(
          Object.keys(value)
            .sort()
            .map((k) => [k, value[k]]),
        )
      : value,
  );
}

function observedMatches(previous, incoming) {
  const unique = new Map();
  for (const row of incoming) {
    const id = recordId(row);
    unique.set(id, !unique.has(id));
  }
  const observed = new Map();
  for (const grade of previous) {
    const id = recordId(grade);
    if (!id || !unique.get(id)) continue;
    observed.set(
      id,
      !observed.has(id) && grade.matchedCourse?.confirmed
        ? matchFingerprint(grade.matchedCourse)
        : null,
    );
  }
  return observed;
}

// The matcher spreads the original grade onto its result. reviewRowId identifies
// a particular selected line even if two identical lines share an importId.
export async function confirmPlannerImport({
  review,
  selections,
  previousGrades = [],
  prepareGrades,
  mutate,
  signal,
}) {
  if (signal?.aborted) return false;
  let ready = review;
  let reconcileMatch;
  if (review.kind === "grades" && prepareGrades) {
    const selected = selectedRows(review, selections);
    const grades = selected.map((selection) => ({
      ...reviewedGrade(selection),
      matchedCourse: null,
      fields: [],
      category: "",
      department: "",
      reviewRowId: selection.row.id,
    }));
    const observed = observedMatches(previousGrades, grades);
    const invalidated = new Set();
    let prepared;
    try {
      prepared = await prepareGrades(grades, previousGrades);
    } catch {
      // An unavailable archive cannot invalidate the original earned credit.
      prepared = [];
    }
    if (signal?.aborted) return false;
    const byRow = new Map();
    for (const result of Array.isArray(prepared) ? prepared : []) {
      const id = result?.reviewRowId;
      byRow.set(id, byRow.has(id) ? null : result);
    }
    ready = {
      ...review,
      rows: selected.map(({ row }) => {
        const result = byRow.get(row.id);
        const candidate = result?.matchedCourse;
        const id = recordId(row.value);
        if (
          result?.matchInvalidated === true &&
          candidate === null &&
          result.importId === row.value.importId &&
          recordId(result) === id &&
          observed.get(id)
        )
          invalidated.add(id);
        const matched =
          result?.importId === row.value.importId &&
          !row.offeringConflict &&
          !row.value.identityUncertain &&
          candidate?.confirmed === true &&
          Array.isArray(candidate.fields) &&
          (!row.value.year || String(candidate.year) === row.value.year) &&
          (!row.value.code || candidate.code === row.value.code)
            ? candidate
            : null;
        return {
          ...row,
          value: {
            ...row.value,
            matchedCourse: matched,
            fields: matched?.fields ?? [],
            category: matched?.category ?? "",
            department: matched?.department ?? "",
          },
        };
      }),
    };
    reconcileMatch = (stored, incoming) => {
      const id = recordId(incoming);
      const snapshot = observed.get(id);
      if (!snapshot || id !== recordId(stored)) return undefined;
      if (matchFingerprint(stored.matchedCourse) !== snapshot)
        return stored.matchedCourse?.confirmed ? stored.matchedCourse : null;
      return invalidated.has(id) ? null : undefined;
    };
  }
  // The local storage transaction can itself wait for a cross-tab lock.
  const saved = await mutate((latest) => {
    if (!signal?.aborted)
      applyPlannerImport(latest, ready, selections, reconcileMatch);
  });
  return !!saved && !signal?.aborted;
}

// Used inside the caller's local transaction, against the latest saved state.
export function applyPlannerImport(state, review, selections, reconcileMatch) {
  const selected = selectedRows(review, selections);
  const scope = recordedScope(review);
  if (
    (review.kind === "balances" ||
      selected.some(({ row }) => row.value.allocationScope)) &&
    !sameScope(
      plannerBalanceScope(state.profile, scope.goal, scope.stage),
      scope,
    )
  )
    throw Error("適用する便覧・所属が変わりました。帳票を読み直してください。");
  if (review.kind === "grades") {
    mergeGrades(state, selected.map(reviewedGrade), reconcileMatch);
  } else if (review.kind === "registration") {
    for (const {
      row: {
        value: { code, status },
      },
    } of selected) {
      // An unlabelled re-export cannot reverse an explicit result.
      if (
        status === "要確認" &&
        ["許可", "不許可", "申請中"].includes(state.status[code])
      )
        continue;
      const previous = state.status[code];
      state.status[code] = status;
      if (
        status === "不許可" &&
        previous !== status &&
        !state.plan.includes(code)
      )
        state.plan.push(code);
    }
  } else if (review.kind === "balances") {
    if (!scope.faculty || !scope.handbook)
      throw Error("先に所属と適用する便覧を選んでください。");
    const balances = selected.map(({ row, choice }) => {
      const target = review.targets.find(
        (r) => r.key === (choice.targetKey || row.targetKey),
      );
      if (!target) throw Error("帳票の区分に対応する要件を選んでください。");
      if (target.key === "total" && choice.confirmTotal !== true)
        throw Error(
          "成績確認表と照合し、重複単位を除いた合計か確認してください。",
        );
      const b = row.value;
      const required = b.required ?? target.required;
      if (!Number.isFinite(required) || required < 0)
        throw Error("帳票または便覧で必要単位を確認できません。");
      return {
        ...scope,
        key: target.key,
        unit: "credits",
        label: target.label,
        kind: target.kind || b.kind,
        required,
        current: b.current,
        sourceLabel: b.label,
        source: "履修科目確認表",
        ...(target.key === "total" ? { duplicateFree: true } : {}),
        ...(b.day != null ? { day: b.day, night: b.night } : {}),
      };
    });
    const replacements = new Map(balances.map((b) => [b.key, b]));
    if (replacements.size !== balances.length)
      throw Error(
        "同じ要件に複数の行が選ばれています。対応する区分別の合計を1行選んでください。",
      );
    state.balances = [
      ...state.balances.filter((b) => {
        const next = replacements.get(b.key);
        return !next || !samePlannerBalance(b, next);
      }),
      ...balances,
    ];
  } else throw Error("取込形式を確認してください。");
}
