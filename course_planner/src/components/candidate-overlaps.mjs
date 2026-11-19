import { slotsFor, termsFor } from "../study.mjs";

function lookupCourse(byCode, code) {
  if (!byCode || !code) return null;
  if (typeof byCode.get === "function") return byCode.get(code) ?? null;
  return Object.hasOwn(byCode, code) ? byCode[code] : null;
}

function uniqueTerms(course) {
  if (!course?.period && !course?.semester) return [];
  return [...new Set(termsFor(course))].sort((a, b) => a - b);
}

function uniqueSlots(course) {
  if (!course?.schedule) return [];
  return [...new Set(slotsFor(course))];
}

/**
 * Indexes distinct saved offerings across all personal and copied lists
 * by actual (term, weekday/period) meeting keys without building a pairwise N^2 graph.
 */
export function buildCandidateMeetings(lists = [], byCode) {
  const offerings = new Map();
  const byMeeting = new Map();

  for (const list of lists ?? []) {
    if (!list || !Array.isArray(list.codes)) continue;
    const listName = String(list.name ?? "").trim();
    const seenInList = new Set();
    for (const code of list.codes) {
      if (!code || seenInList.has(code)) continue;
      seenInList.add(code);
      const course = lookupCourse(byCode, code);
      if (!course) continue;
      let record = offerings.get(course.code);
      if (!record) {
        record = {
          course,
          lists: [],
          terms: uniqueTerms(course),
          slots: uniqueSlots(course),
        };
        offerings.set(course.code, record);
      }
      if (listName && !record.lists.includes(listName)) {
        record.lists.push(listName);
      }
    }
  }

  for (const record of offerings.values()) {
    if (!record.terms.length || !record.slots.length) continue;
    const entry = { course: record.course, lists: record.lists };
    for (const term of record.terms) {
      for (const slot of record.slots) {
        const key = `${term}:${slot}`;
        let bucket = byMeeting.get(key);
        if (!bucket) {
          bucket = [];
          byMeeting.set(key, bucket);
        }
        bucket.push(entry);
      }
    }
  }

  return { byMeeting, offerings };
}

/**
 * Counts distinct other saved candidates that share at least one confirmed
 * (term, weekday/period) meeting with `course`.
 */
export function countCandidateOverlaps(course, index) {
  if (!course?.code || !index?.byMeeting) return 0;
  const terms = uniqueTerms(course);
  const slots = uniqueSlots(course);
  if (!terms.length || !slots.length) return 0;

  const seen = new Set();
  for (const term of terms) {
    for (const slot of slots) {
      const bucket = index.byMeeting.get(`${term}:${slot}`);
      if (!bucket) continue;
      for (const entry of bucket) {
        if (entry.course.code !== course.code) {
          seen.add(entry.course.code);
        }
      }
    }
  }
  return seen.size;
}

/**
 * Returns deduplicated other saved candidates overlapping `course` on exact
 * confirmed (term, weekday/period) meetings. Intensive/unknown slots never match.
 */
export function overlapsForCourse(course, index) {
  if (!course?.code || !index?.byMeeting) return [];
  const terms = uniqueTerms(course);
  const slots = uniqueSlots(course);
  if (!terms.length || !slots.length) return [];

  const matched = new Map();
  for (const term of terms) {
    for (const slot of slots) {
      const bucket = index.byMeeting.get(`${term}:${slot}`);
      if (!bucket) continue;
      for (const entry of bucket) {
        const otherCode = entry.course.code;
        if (otherCode === course.code) continue;
        let item = matched.get(otherCode);
        if (!item) {
          item = {
            course: entry.course,
            lists: entry.lists,
            termSet: new Set(),
            slotSet: new Set(),
            meetings: [],
          };
          matched.set(otherCode, item);
        }
        item.termSet.add(term);
        item.slotSet.add(slot);
        item.meetings.push({ term, slot });
      }
    }
  }

  return [...matched.values()]
    .map(({ course: other, lists, termSet, slotSet, meetings }) => ({
      course: other,
      lists,
      terms: [...termSet].sort((a, b) => a - b),
      slots: [...slotSet],
      meetings,
    }))
    .sort((a, b) => {
      const termDiff = (a.terms[0] ?? 0) - (b.terms[0] ?? 0);
      if (termDiff !== 0) return termDiff;
      return a.course.code.localeCompare(b.course.code);
    });
}

export function formatOverlapTerms(terms = []) {
  if (!terms.length) return "";
  return `第${terms.join("・")}ターム`;
}
