import { contribution } from "./rules.mjs";

// P.A.C.E. courses also carry the English syllabus category. Reserve the chosen
// skill route before distributing English, package surplus and free electives.
export function creationAllocation(rows) {
  const ordered = [...rows.filter((r) => r.key === "skill"), ...rows.filter((r) => r.key !== "skill")];
  const cache = new WeakMap();
  return (courses, profile) => {
    const last = cache.get(courses);
    if (last && last.profile === profile) return last.result;
    const remaining = courses.map((c) => Math.max(0, Number(c.credits) || 0));
    const used = courses.map(() => 0);
    const result = new Map();
    let uncertain = false;
    for (const row of ordered) {
      const contributions = [];
      let missing = false;
      let need = row.required ?? 0;
      const take = (i, units) => {
        const value = Math.min(remaining[i], need, units);
        if (value > 0) {
          contributions.push(contribution(courses[i], value));
          need -= value;
          remaining[i] -= value;
          used[i] += value;
        }
      };
      if (row.evaluate) {
        const eligible = courses.filter((c) => row.match(c, profile) === true);
        for (const item of row.evaluate({ courses: eligible, profile }).contributions) {
          const i = courses.findIndex((c) =>
            c.title === item.title && (c.code ?? "") === item.code && (c.year ?? "") === item.year
          );
          if (i >= 0) take(i, item.applied);
        }
        missing = need > 0 && courses.some((c) => row.match(c, profile) == null);
      } else {
        for (let i = 0; i < courses.length && need > 0; i++) {
          if (!remaining[i]) continue;
          const match = row.match(courses[i], profile);
          if (match == null) missing = true;
          if (match === true) take(i, remaining[i]);
        }
      }
      const unknown = row.required == null || (missing && need > 0);
      uncertain ||= unknown;
      result.set(row.key, {
        value: row.required == null ? null : row.required - need,
        contributions,
        ...(unknown
          ? { unknown: "所属コース、領域配属、科目区分または履修時期を創生学部学務係で照合してください。" }
          : {}),
      });
    }
    result.set("total", {
      value: used.reduce((a, b) => a + b, 0),
      contributions: courses.flatMap((c, i) => used[i] ? [contribution(c, used[i])] : []),
      ...(uncertain
        ? { unknown: "区分や履修時期を照合できない科目があります。創生学部学務係で確認してください。" }
        : {}),
    });
    cache.set(courses, { profile, result });
    return result;
  };
}
