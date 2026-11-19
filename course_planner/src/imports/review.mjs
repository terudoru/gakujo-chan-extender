import { normalize, validCode } from "../study.mjs";
import { mergeGrades, reviewGrades } from "../transcript.mjs";
import {
  readUnits,
  readYear,
  rowStatus,
  scanTables,
  validatePacket,
} from "./tables.mjs";

function scopeOf(profile = {}, goal = "graduation", stage = "") {
  return {
    faculty: profile.faculty || "",
    handbook: String(profile.handbook || ""),
    admitted: String(profile.admitted || ""),
    department: profile.department || "",
    program: profile.program || "",
    entry: profile.entry || "",
    curriculum: profile.curriculum || "",
    individual: profile.individual ?? "",
    goal,
    stage,
  };
}
function sameScope(a, b) {
  return Object.keys(b).every((k) => String(a[k] ?? "") === String(b[k] ?? ""));
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
  const {
    profile,
    goal = "graduation",
    stage = "",
    requirementRows = [],
  } = options;
  const scope = scopeOf(profile, goal, stage);
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

// Used inside the caller's local transaction, against the latest saved state.
export function applyPlannerImport(state, review, selections) {
  if (!Array.isArray(selections) || !selections.length)
    throw Error("取り込む行を選んでください。");
  const byId = new Map(review.rows.map((r) => [r.id, r]));
  const selected = selections.map((s) => ({ choice: s, row: byId.get(s.id) }));
  if (
    new Set(selections.map((s) => s.id)).size !== selections.length ||
    selected.some(({ row }) => !row?.value)
  )
    throw Error("確認できた行だけを選んでください。");
  const scope = review.scope;
  if (
    (review.kind === "balances" ||
      selected.some(({ row }) => row.value.allocationScope)) &&
    !sameScope(scopeOf(state.profile, scope.goal, scope.stage), scope)
  )
    throw Error("適用する便覧・所属が変わりました。帳票を読み直してください。");
  if (review.kind === "grades") {
    mergeGrades(
      state,
      selected.map(({ row, choice }) => {
        if (choice.excludeDuplicate)
          return {
            ...row.value,
            counts: false,
            duplicate: true,
            duplicateReviewed: true,
          };
        if (
          choice.confirmDistinct &&
          row.value.possibleDuplicate &&
          !row.value.identityUncertain &&
          !row.value.duplicate
        )
          return { ...row.value, counts: true, duplicateReviewed: true };
        return row.value;
      }),
    );
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
    if (new Set(balances.map((b) => b.key)).size !== balances.length)
      throw Error(
        "同じ要件に複数の行が選ばれています。対応する区分別の合計を1行選んでください。",
      );
    const keys = new Set(balances.map((b) => b.key));
    state.balances = [
      ...state.balances.filter((b) => !sameScope(b, scope) || !keys.has(b.key)),
      ...balances,
    ];
  } else throw Error("取込形式を確認してください。");
}
