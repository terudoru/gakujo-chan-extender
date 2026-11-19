import { courseMatch, quantity } from "./engine-evidence.mjs";

export function amount(row, course) {
  return row.unit === "courses" ? 1 : quantity(course.credits);
}

// Incremental max-flow. Fill rows in handbook order, but move earlier credits
// to another eligible course when doing so satisfies an additional minimum.
// Capacities may be fractional (e.g. a half-credit clinical course).
export function distribute(
  rows,
  courses,
  capacity,
  target,
  match,
  edgeLimit = (row) => row.maxPerCourse ?? Infinity,
) {
  const free = new Map(capacity);
  const applied = new Map(rows.map((r) => [r, new Map()]));
  const addresses = new Map(
    rows.map((row) => [
      row,
      courses.filter((c) => match(row, c) && (capacity.get(c) ?? 0) > 0),
    ]),
  );
  for (const initial of rows) {
    let need = target(initial);
    while (need > 0) {
      const previous = new Map([[initial, null]]),
        queue = [initial];
      let end;
      for (let i = 0; i < queue.length && !end; i++) {
        const node = queue[i];
        if (applied.has(node)) {
          for (const c of addresses.get(node)) {
            if (previous.has(c)) continue;
            const headroom =
              edgeLimit(node, c) - (applied.get(node).get(c) ?? 0);
            if (headroom <= 0) continue;
            previous.set(c, { parent: node, headroom });
            if (free.get(c) > 0) {
              end = c;
              break;
            }
            queue.push(c);
          }
        } else {
          for (const [row, allocations] of applied) {
            const headroom = allocations.get(node) ?? 0;
            if (headroom > 0 && !previous.has(row)) {
              previous.set(row, { parent: node, headroom });
              queue.push(row);
            }
          }
        }
      }
      if (!end) break;
      let delta = Math.min(need, free.get(end));
      for (let node = end; previous.get(node); node = previous.get(node).parent)
        delta = Math.min(delta, previous.get(node).headroom);
      for (let c = end; c; ) {
        const row = previous.get(c).parent,
          allocations = applied.get(row);
        allocations.set(c, (allocations.get(c) ?? 0) + delta);
        c = previous.get(row)?.parent;
        if (c) allocations.set(c, allocations.get(c) - delta);
      }
      free.set(end, free.get(end) - delta);
      need -= delta;
    }
  }
  return { applied, free };
}

export function sumApplied(map) {
  let total = 0;
  for (const n of map.values()) total += n;
  return total;
}

export function exclusiveGroup(
  rows,
  courses,
  profile,
  official,
  evaluated = new Map(),
) {
  const earned = courses.filter((c) => c.column === "earned");
  const capacity = new Map(courses.map((c) => [c, amount(rows[0], c) ?? 0]));
  const matches = new Map(
    rows.map((r) => [
      r,
      new Map(
        courses.map((c) => {
          const custom = evaluated.get(r);
          if (!custom) return [c, courseMatch(r, c, profile)];
          if (custom.value !== null && custom.applied.get(c) > 0)
            return [c, true];
          if (
            custom.pending.includes(c) ||
            custom.reason ||
            custom.value === null ||
            custom.value > sumApplied(custom.applied)
          )
            return [c, null];
          return [c, false];
        }),
      ),
    ]),
  );
  const known = (r, c) => matches.get(r).get(c) === true;
  // First reserve transcript courses already represented by a statement, even
  // if the statement row follows another matching row in the handbook.
  const reported = rows.filter((r) => official.has(r.key));
  const current = (r) => official.get(r.key)?.current ?? 0;
  const target = (r) =>
    Math.max(
      0,
      Math.min(r.required, evaluated.get(r)?.value ?? Infinity) - current(r),
    );
  const limit = (r, c) =>
    Math.min(
      r.maxPerCourse ?? Infinity,
      evaluated.get(r)?.applied.get(c) ?? Infinity,
    );
  const covered = { applied: new Map(), free: new Map(capacity) };
  if (reported.length) {
    // Reserve the official amounts first, but allow an augmenting path to
    // replace a flexible covered course with a narrower eligible course.
    const reservations = reported.map((row) => ({
      row,
      maxPerCourse: row.maxPerCourse,
    }));
    const preliminary = distribute(
      [...reservations, ...rows],
      courses,
      capacity,
      (r) => (r.row ? current(r.row) : target(r)),
      (r, c) =>
        r.row
          ? c.column === "earned" && known(r.row, c)
          : known(r, c) && !(c.column === "earned" && official.has(r.key)),
      (r, c) => limit(r.row ?? r, c),
    );
    for (const reservation of reservations) {
      const allocation = preliminary.applied.get(reservation);
      covered.applied.set(reservation.row, allocation);
      for (const [c, n] of allocation)
        covered.free.set(c, covered.free.get(c) - n);
    }
  }
  const possible = distribute(
    reported,
    earned,
    covered.free,
    (r) => current(r) - sumApplied(covered.applied.get(r)),
    (r, c) => matches.get(r).get(c) === null,
  );
  const assigned = distribute(
    rows,
    courses,
    possible.free,
    target,
    (r, c) => known(r, c) && !(c.column === "earned" && official.has(r.key)),
    limit,
  );
  const uncertainOverlap = new Set(
    earned.filter((c) => covered.free.get(c) > possible.free.get(c)),
  );
  const results = new Map(
    rows.map((row) => {
      const pending = courses.filter(
        (c) =>
          !(c.column === "earned" && official.has(row.key)) &&
          ((matches.get(row).get(c) === null &&
            (covered.free.get(c) > 0 || amount(row, c) === null)) ||
            (known(row, c) &&
              (uncertainOverlap.has(c) || amount(row, c) === null))),
      );
      return [
        row.key,
        {
          value: current(row) + sumApplied(assigned.applied.get(row)),
          applied: assigned.applied.get(row),
          covered: covered.applied.get(row),
          pending,
          reason: !official.has(row.key)
            ? (evaluated.get(row)?.reason ?? row.unknown)
            : undefined,
        },
      ];
    }),
  );
  const conflicts = rows.filter((r) => official.get(r.key)?.conflict);
  if (
    !conflicts.length &&
    ![...results.values()].some((result) => result.pending.length)
  )
    return results;
  // An uncertain course in A can free a confirmed A/B course for B, even
  // when the uncertain course itself is ineligible for B.
  const connected = new Map(rows.map((row) => [row, new Set()]));
  for (const c of courses) {
    const eligible = rows.filter(
      (r) =>
        matches.get(r).get(c) !== false &&
        (c.column !== "earned" ||
          !official.has(r.key) ||
          official.get(r.key).conflict),
    );
    for (const r of eligible)
      for (const other of eligible) connected.get(r).add(other);
  }
  const visited = new Set();
  for (const row of rows) {
    if (visited.has(row)) continue;
    const component = new Set([row]),
      pending = new Set();
    for (const member of component) {
      visited.add(member);
      for (const c of results.get(member.key).pending) pending.add(c);
      for (const neighbor of connected.get(member)) component.add(neighbor);
    }
    for (const member of component) {
      const result = results.get(member.key);
      if (
        conflicts.some((r) => component.has(r)) &&
        !official.has(member.key)
      ) {
        result.value = null;
        result.applied.clear();
        result.reason =
          "同じ配分枠の確認表が一致しないため、学務担当に算入済み科目の内訳を確認してください。";
      }
      if (result.value < member.required) result.pending = [...pending];
    }
  }
  return results;
}
