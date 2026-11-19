import { initialState, validCode } from "./study.mjs";
export const STORAGE_KEY = "mbg.course-planner.v1";
export function parseSaved(text) {
  if (!text) return initialState();
  const raw = JSON.parse(text);
  const object = (v) => v != null && typeof v === "object" && !Array.isArray(v);
  if (
    raw?.v !== 1 ||
    !Array.isArray(raw.lists) ||
    !raw.lists.length ||
    !Array.isArray(raw.plan) ||
    !raw.plan.every(validCode) ||
    !Array.isArray(raw.grades) ||
    !raw.grades.every(
      (g) =>
        object(g) && typeof g.title === "string" && Number.isFinite(g.credits),
    ) ||
    !Array.isArray(raw.balances ?? []) ||
    !(raw.balances ?? []).every(
      (b) =>
        object(b) &&
        typeof b.key === "string" &&
        Number.isFinite(b.required) &&
        Number.isFinite(b.current),
    ) ||
    !object(raw.status ?? {}) ||
    !object(raw.capOverrides ?? {}) ||
    !object(raw.semesters ?? {}) ||
    !object(raw.profile ?? {}) ||
    !raw.lists.every(
      (l) =>
        object(l) &&
        typeof l.id === "string" &&
        typeof l.name === "string" &&
        Array.isArray(l.codes) &&
        l.codes.every(validCode),
    )
  ) {
    throw Error("保存データの形式を読み取れません。");
  }
  return {
    ...initialState(),
    ...raw,
    status: raw.status ?? {},
    capOverrides: raw.capOverrides ?? {},
    semesters: raw.semesters ?? {},
    balances: raw.balances ?? [],
    profile: { ...initialState().profile, ...raw.profile },
  };
}
export function loadLocal() {
  return parseSaved(localStorage.getItem(STORAGE_KEY));
}
export async function changeLocal(update) {
  const commit = () => {
    const fresh = loadLocal();
    update(fresh);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(fresh));
    return fresh;
  };
  return globalThis.navigator?.locks
    ? navigator.locks.request(STORAGE_KEY, commit)
    : commit();
}
