import { academicFieldRows } from "./requirements.mjs";

export function fieldProgress(state, byCode, planned, selector) {
  return academicFieldRows(state, byCode, planned, selector).map((row) => {
    const rule = row.requirement;
    const conflicted = Boolean(rule?.balance?.conflict);
    const confirmed = rule?.balance && !conflicted;
    const earned = confirmed ? rule.balance.current : row.earned;
    return {
      ...row,
      earned,
      earnedKnown: !conflicted && (Boolean(state.grades.length) || Boolean(confirmed)),
      forecast: confirmed && Number.isFinite(rule.future) ? rule.future : earned + row.planned,
      conflicted,
      required: rule?.required,
      remaining: rule?.historyAvailable ? rule.remaining : null,
      after: rule?.historyAvailable ? rule.after : null,
      needsReview: row.needsReview || rule?.needsBalance,
      source: rule?.source ?? rule?.evidence?.sources?.[0],
    };
  });
}
