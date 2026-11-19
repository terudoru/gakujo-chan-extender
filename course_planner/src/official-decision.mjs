import { sameProfile } from "./curricula/engine-evidence.mjs";

const decisionFields = ["entryGrade", "assessmentDate", "graduationYear", "graduationMonth", "package"];

export function decisionScope(profile, goal, stage) {
  const scope = { goal, stage };
  for (const key of ["faculty", "admitted", "handbook", "program", "department", "field", "individual", "curriculum", ...decisionFields])
    scope[key] = profile[key] ?? "";
  scope.entry = profile.entry || "1年次入学";
  return scope;
}

function matchesDecisionProfile(record, profile) {
  return sameProfile(record, profile) && decisionFields.every((key) =>
    !Object.hasOwn(record, key) || String(record[key] ?? "") === String(profile[key] ?? ""));
}

export function decisionRecords(balances, scope, key) {
  return balances.filter((balance) => {
    const saved = balance.scope ?? balance;
    return balance.unit === "condition" && balance.key === key &&
      saved.goal === scope.goal && (saved.stageId || saved.stage) === scope.stage &&
      matchesDecisionProfile(saved, scope);
  });
}

export function saveDecision(state, row, scope, original, result) {
  if (!row.officialDecision || row.unit !== "condition" || row.required !== 1 ||
      ![null, 0, 1].includes(result)) throw Error("この条件の判定方法を確認してください。");
  if (!matchesDecisionProfile(scope, state.profile))
    throw Error("所属または判定日が変わりました。要件を開き直してください。");
  const previous = decisionRecords(state.balances, scope, row.key);
  if (JSON.stringify(previous) !== JSON.stringify(original))
    throw Error("この条件の確認結果が更新されました。開き直して確認してください。");
  state.balances = state.balances.filter((item) => !previous.includes(item));
  if (result !== null) state.balances.push({
    scope, key: row.key, label: row.label, kind: row.kind, unit: "condition",
    current: result, required: 1, confirmed: true, sourceLabel: "学務の判定結果",
  });
}
