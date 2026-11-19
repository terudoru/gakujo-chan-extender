import { isAcademicFieldKey } from "./curricula/engine-evidence.mjs";
import { matchBalanceRow } from "./curricula/engine.mjs";
import { plannerBalanceScope, samePlannerBalance } from "./imports/review.mjs";

export function comparableBalances(balances, scope, stage, allowLegacy, key) {
  return balances.filter((balance) => {
    const owner = balance.scope ?? balance;
    const stageId = owner.stageId || owner.stage;
    const normalizedScope = !stageId && allowLegacy ? { ...owner, stage: scope.stage } : owner;
    const match = isAcademicFieldKey(balance.key) ? { key: balance.key } : matchBalanceRow(balance, stage, scope.faculty);
    const storedKey = match.key || (!match.candidates?.length && balance.key);
    return samePlannerBalance({ ...balance, key: storedKey, scope: normalizedScope }, { ...scope, key, unit: "credits" });
  });
}

export function saveCreditBalance(state, original, scope, stage, allowLegacy, balance) {
  if (JSON.stringify(scope) !== JSON.stringify(plannerBalanceScope(state.profile, scope.goal, scope.stage)))
    throw Error("所属設定が変わりました。対象の区分を確認してください。");
  const previous = comparableBalances(state.balances, scope, stage, allowLegacy, balance.key);
  if (JSON.stringify(previous) !== JSON.stringify(original))
    throw Error("この項目の修得単位が更新されました。確認表を開き直してください。");
  state.balances = state.balances.filter((b) => !previous.includes(b));
  state.balances.push({ ...balance, ...scope, unit: "credits", confirmed: true });
}
