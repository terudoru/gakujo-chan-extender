import { initialState, normalize, STATUS, validCode } from "../study.mjs";

export const channels = ["plan", "history"];
export const uuid = (s) => typeof s === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(s);
const text = (v) => typeof v === "string" && v.length <= 512;
const number = (v) => Number.isFinite(v) && v >= 0;
const flag = (v) => typeof v === "boolean";
const scalar = (v) => text(v) || number(v);
const monthCounts = (v) => v && typeof v === "object" && !Array.isArray(v) &&
  Object.entries(v).every(([k, n]) => /^[1-6]$/.test(k) && (number(n) || (text(n) && /^\d{0,3}$/.test(n))));
const fields = (v) => Array.isArray(v) && v.length <= 100 && v.every(text);
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const id = (v) => typeof v === "string" && /^[a-zA-Z0-9_-]{1,100}$/.test(v);
const name = (v) => text(v) && v.trim() && [...v].length <= 80;
const historicCode = (v) => typeof v === "string" && /^[\p{L}\d._-]{0,25}$/u.test(v);
const syllabusLink = (v) => typeof v === "string" &&
  /^https:\/\/syllabus\.niigata-u\.ac\.jp\/syllabusHtml\/\d{4}\/[A-Z\d]{2}\/[\w-]+\.html$/.test(v);
function offeringSource(v) {
  if (syllabusLink(v) || v === "https://syllabus.niigata-u.ac.jp/campus-sy/") return true;
  if (typeof v !== "string" || v.length > 4096) return false;
  if (/^https:\/\/www\.dent\.niigata-u\.ac\.jp\/student\/syllabus\/#p1-syl\d{4}$/.test(v)) return true;
  try {
    const u = new URL(v);
    return u.protocol === "https:" && !u.username && !u.password && !u.port && !u.search &&
      /^(?:www\.)?(?:(?:dent|eng|agr|sc|ed|human|econ|law|med|clg|create|iess)\.)?niigata-u\.ac\.jp$/.test(u.hostname) &&
      /\.pdf$/i.test(u.pathname) && /^#page=[1-9]\d{0,3}$/.test(u.hash);
  } catch { return false; }
}
const gradeFields = {
  id: text, recordId: text, importId: (s) => typeof s === "string" && s.length <= 6000,
  code: historicCode, title: text, year: scalar, grade: text, credits: number,
  fields, category: text, department: text, duplicate: flag, recognized: flag,
  courseId: text, term: text, section: text, alternativeTitle: text, counts: flag,
  duplicateReviewed: flag, identityUncertain: flag, allocationLabel: text, allocationKey: text,
  matchStatus: text, equivalentTitle: text, equivalentTo: text, equivalenceKey: text, repeatGroup: text,
  duplicateOf: text, status: (s) => STATUS.includes(s),
  offeringDepartment: text, offeringFaculty: text,
};
const matchFields = {
  code: historicCode, year: scalar, department: text, title: text, fields, category: text,
  credits: number, confirmed: flag, section: text, term: text, courseId: text, sourceUrl: offeringSource,
  sourceKind: (s) => ["syllabus", "public-index", "faculty-index", "manual-record", "saved-syllabus"].includes(s),
  fieldSource: (s) => s === "" || offeringSource(s), aliasSource: offeringSource,
  schedule: text, period: text, semester: text, format: text,
};
const scopeFields = { faculty: text, program: text, field: text, handbook: scalar, entry: text, curriculum: text, goal: text, stage: text };
const balanceFields = {
  ...scopeFields,
  key: text, label: text, kind: text, goal: text, required: number, current: number,
  day: number, night: number, sourceLabel: text, source: (s) => s === "履修科目確認表",
};
const profileFields = {
  faculty: text, program: text, admitted: scalar, handbook: scalar, gpa: scalar,
  cap: scalar, months: scalar, entry: text, curriculum: text, field: text,
  assessmentDate: (s) => s === "" || (text(s) && /^\d{4}-\d{2}-\d{2}$/.test(s)),
  enrolledMonths: scalar, attendanceMonths: scalar, yearMonths: monthCounts,
  yearAttendanceMonths: (v) => scalar(v) || monthCounts(v), earlyGraduation: flag, deanException: flag,
};
function pick(value, schema) {
  const result = {};
  for (const [key, valid] of Object.entries(schema))
    if (valid(value?.[key])) result[key] = value[key];
  return result;
}
function grade(value) {
  const result = pick(value, gradeFields);
  if (value?.matchedCourse?.confirmed === true) {
    const match = pick(value.matchedCourse, matchFields);
    if (match.code || (match.code === "" && match.sourceUrl)) result.matchedCourse = match;
  }
  if (value?.allocationScope && result.allocationKey) result.allocationScope = pick(value.allocationScope, scopeFields);
  return result;
}
function gradeId(g) {
  return g.importId || g.recordId || g.id || JSON.stringify([g.year, g.code, g.title, g.section, g.term, g.courseId].map(normalize));
}
function balanceId(b) {
  return JSON.stringify([b.faculty, b.program ?? "", b.field ?? "", b.handbook, b.entry ?? "", b.curriculum ?? "", b.goal, b.stage ?? "", b.key]);
}
const encode = (...parts) => JSON.stringify(parts);
export function project(channel, state) {
  const map = {};
  if (channel === "plan") {
    map[encode("listOrder")] = state.lists.map((list) => list.id);
    map[encode("planOrder")] = [...new Set(state.plan.filter(validCode))];
    for (const list of state.lists) {
      if (!id(list.id) || !name(list.name)) throw Error("候補リストの形式を確認してください。");
      map[encode("list", list.id)] = list.name;
      map[encode("codeOrder", list.id)] = [...new Set(list.codes.filter(validCode))];
      for (const code of list.codes)
        if (validCode(code)) map[encode("member", list.id, code)] = true;
    }
    for (const code of state.plan)
      if (validCode(code)) map[encode("plan", code)] = true;
    for (const [code, value] of Object.entries(state.status ?? {}))
      if (validCode(code) && STATUS.includes(value)) map[encode("status", code)] = value;
    for (const [code, value] of Object.entries(state.capOverrides ?? {}))
      if (validCode(code) && ["除外", "算入"].includes(value)) map[encode("cap", code)] = value;
  } else if (channel === "history") {
    for (const row of state.grades) {
      const value = grade(row);
      if (value.title && number(value.credits)) map[encode("grade", gradeId(value))] = value;
    }
    for (const row of state.balances ?? []) {
      const value = pick(row, balanceFields);
      if (value.key && number(value.current) && number(value.required))
        map[encode("balance", balanceId(value))] = value;
    }
    for (const [key, value] of Object.entries(pick(state.profile, profileFields)))
      map[encode("profile", key)] = value;
  } else throw Error("不明な同期項目です。");
  return map;
}
// Reject a cross-channel record even after authenticated decryption. Tombstones
// have the same key grammar as live values and carry no former value.
function validRecord(channel, key, value) {
  const parts = JSON.parse(key);
  if (!Array.isArray(parts) || JSON.stringify(parts) !== key) return false;
  const [type, a, b] = parts;
  const removed = value === null;
  if (channel === "plan") {
    const sequence = (check) => Array.isArray(value) && value.every(check) && new Set(value).size === value.length;
    if (type === "listOrder" || type === "planOrder")
      return parts.length === 1 && (removed || sequence(type === "listOrder" ? id : validCode));
    if (type === "codeOrder") return parts.length === 2 && id(a) && (removed || sequence(validCode));
    if (type === "member") return parts.length === 3 && id(a) && validCode(b) && (removed || value === true);
    if (parts.length !== 2) return false;
    if (type === "list") return id(a) && (removed || name(value));
    if (!validCode(a)) return false;
    if (type === "plan") return removed || value === true;
    if (type === "status") return removed || STATUS.includes(value);
    return type === "cap" && (removed || ["除外", "算入"].includes(value));
  }
  if (parts.length !== 2 || typeof a !== "string" || a.length > 6500) return false;
  if (type === "profile") return Object.hasOwn(profileFields, a) && (removed || profileFields[a](value));
  if (type === "grade") return removed || (value?.title && number(value.credits) &&
    same(value, grade(value)) && a === gradeId(value));
  return type === "balance" && (removed || (value?.key && number(value.current) &&
    number(value.required) && same(value, pick(value, balanceFields)) && a === balanceId(value)));
}
export function validateEntries(channel, entries) {
  if (!channels.includes(channel) || !entries || Array.isArray(entries) ||
      typeof entries !== "object") throw Error("同期データの形式を確認できません。");
  for (const [key, cell] of Object.entries(entries)) {
    if (!Array.isArray(cell) || cell.length !== 3 || !Number.isSafeInteger(cell[0]) ||
        cell[0] <= 0 || cell[0] >= Number.MAX_SAFE_INTEGER - 1 || !uuid(cell[1]) ||
        !validRecord(channel, key, cell[2])) throw Error("同期データの項目を確認できません。");
  }
  return entries;
}
function materialized(cells) {
  const values = {};
  for (const [key, [, , value]] of Object.entries(cells)) if (value !== null) values[key] = value;
  // Deleting a list also hides a member concurrently added to that list.
  const orderMembers = new Map();
  function includes(order, item) {
    if (!orderMembers.has(order)) orderMembers.set(order, new Set());
    orderMembers.get(order).add(item);
  }
  for (const key of Object.keys(values)) {
    const [type, list, code] = JSON.parse(key);
    if (["member", "codeOrder"].includes(type) && !Object.hasOwn(values, encode("list", list))) {
      delete values[key];
    } else if (type === "list") includes(encode("listOrder"), list);
    else if (type === "member") includes(encode("codeOrder", list), code);
    else if (type === "plan") includes(encode("planOrder"), list);
  }
  // Merge membership independently of ordering. Project the same order that
  // the UI sees so receiving a concurrent addition/deletion is not a local edit.
  for (const key of Object.keys(values)) {
    const [type] = JSON.parse(key);
    if (!["listOrder", "planOrder", "codeOrder"].includes(type)) continue;
    const members = orderMembers.get(key) ?? new Set();
    const order = values[key].filter((item) => members.delete(item));
    values[key] = [...order, ...[...members].sort()];
  }
  return values;
}
function merge(into, entries) {
  for (const [key, cell] of Object.entries(entries)) {
    const old = into[key];
    if (!old || old[0] < cell[0] || (old[0] === cell[0] && old[1] < cell[1])) into[key] = cell;
  }
}
function apply(channel, state, values, cells) {
  const lists = new Map(), members = [], plan = [], status = {}, cap = {};
  const grades = [], balances = [], profile = { ...state.profile };
  const oldLists = new Map(state.lists.map((row) => [row.id, row]));
  const oldGrades = new Map(state.grades.map((row) => [gradeId(row), row]));
  const oldBalances = new Map((state.balances ?? []).map((row) => [balanceId(row), row]));
  function preserveLocal(row, allowed) {
    const copy = { ...row };
    for (const key of allowed) delete copy[key];
    return copy;
  }
  // Existing order is significant to people editing a list on this device.
  const localKeys = Object.keys(project(channel, state));
  const ordered = new Set([...localKeys, ...Object.keys(values).sort()]);
  if (channel === "history")
    for (const key of Object.keys(profileFields)) delete profile[key];
  for (const key of ordered) {
    if (!Object.hasOwn(values, key)) continue;
    const value = values[key], [type, a, b] = JSON.parse(key);
    switch (type) {
      case "list": lists.set(a, { ...oldLists.get(a), id: a, name: value, codes: [] }); break;
      case "member": members.push([a, b]); break;
      case "plan": plan.push(a); break;
      case "status": status[a] = value; break;
      case "cap": cap[a] = value; break;
      case "grade": {
        const old = oldGrades.get(a);
        grades.push(old && same(grade(old), value) ? old :
          { ...preserveLocal(old, [...Object.keys(gradeFields), "matchedCourse", "allocationScope"]), ...value });
        break;
      }
      case "balance": balances.push({ ...preserveLocal(oldBalances.get(a), Object.keys(balanceFields)), ...value }); break;
      case "profile": profile[a] = value; break;
    }
  }
  if (channel === "plan") {
    for (const [list, code] of members) lists.get(list)?.codes.push(code);
    function ordered(items, sequence, getKey) {
      const rank = new Map((sequence ?? []).map((key, i) => [key, i]));
      return items.sort((a, b) => (rank.get(getKey(a)) ?? Infinity) - (rank.get(getKey(b)) ?? Infinity) ||
        (getKey(a) < getKey(b) ? -1 : getKey(a) > getKey(b) ? 1 : 0));
    }
    for (const list of lists.values()) ordered(list.codes, values[encode("codeOrder", list.id)], (c) => c);
    ordered(plan, values[encode("planOrder")], (c) => c);
    // Concurrent deletion of the last two lists must leave the planner usable.
    const survivors = ordered([...lists.values()], values[encode("listOrder")], (l) => l.id);
    if (!survivors.length) {
      let deletion;
      for (const [key, cell] of Object.entries(cells)) {
        if (JSON.parse(key)[0] !== "list" || cell[2] !== null) continue;
        if (!deletion || cell[0] > deletion[0] || (cell[0] === deletion[0] && cell[1] > deletion[1])) deletion = cell;
      }
      const [empty] = initialState().lists;
      if (deletion) empty.id = "empty-" + deletion[1] + "-" + deletion[0];
      survivors.push(empty);
    }
    Object.assign(state, { lists: survivors, plan, status, capOverrides: cap });
  } else Object.assign(state, { grades, balances, profile });
}
export function checkpoint(state, owner, channel) {
  return state.plannerSync?.owner === owner ? state.plannerSync[channel] : undefined;
}
// The planner, baseline, downloaded IDs and pending publication are committed
// together by changeLocal. A crash at any network boundary can replay the batch.
export function reconcile({ state, before, owner, device, channel, batches }) {
  const old = checkpoint(state, owner, channel);
  const joining = state.plannerSync?.joining?.[channel];
  const initial = !old && joining?.owner === owner ? joining.values : before;
  const cells = { ...old?.cells };
  const baseline = materialized(cells);
  let clock = old?.clock ?? 0;
  const priorClock = clock;
  const seen = new Set(old?.seen);
  for (const { id, entries } of batches) {
    if (seen.has(id)) continue;
    merge(cells, validateEntries(channel, entries));
    for (const cell of Object.values(entries)) clock = Math.max(clock, cell[0]);
    seen.add(id);
  }
  const fresh = project(channel, state);
  const edits = {};
  const keys = new Set([...Object.keys(baseline), ...Object.keys(initial), ...Object.keys(before), ...Object.keys(fresh)]);
  for (const key of keys) {
    const raced = !same(before[key], fresh[key]) || !same(initial[key], fresh[key]);
    // On first connection prefer the saved remote entry, including its deletion.
    if (!raced && !old && cells[key]) continue;
    if (!raced && same(baseline[key], fresh[key])) continue;
    edits[key] = [(raced || !old ? clock : priorClock) + 1, device, fresh[key] ?? null];
  }
  merge(cells, validateEntries(channel, edits));
  if (Object.keys(edits).length)
    for (const cell of Object.values(edits)) clock = Math.max(clock, cell[0]);
  const pendingEntries = { ...old?.pending?.entries, ...edits };
  const pending = Object.keys(edits).length
    ? { id: crypto.randomUUID(), entries: pendingEntries } : old?.pending ?? null;
  if (old && !batches.length && !Object.keys(edits).length) return old;
  apply(channel, state, materialized(cells), cells);
  if (state.plannerSync?.owner !== owner) state.plannerSync = { owner, joining: state.plannerSync?.joining };
  if (state.plannerSync.joining) {
    delete state.plannerSync.joining[channel];
    if (!Object.keys(state.plannerSync.joining).length) delete state.plannerSync.joining;
  }
  return state.plannerSync[channel] = { cells, clock, seen: [...seen], pending };
}
