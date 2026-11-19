import { initialState, normalize, STATUS, validCode } from "../study.mjs";

export const channels = ["plan", "history"];
export const uuid = (s) => typeof s === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(s);
const text = (v) => typeof v === "string" && v.length <= 512;
const number = (v) => Number.isFinite(v) && v >= 0;
const flag = (v) => typeof v === "boolean";
const scalar = (v) => text(v) || number(v);
const positiveInteger = (v) => (typeof v === "number" || (text(v) && /^\d+$/.test(v))) &&
  Number.isSafeInteger(Number(v)) && Number(v) > 0;
const optionalPositiveInteger = (v) => v === "" || positiveInteger(v);
const gpa = (v) => v === "" || ((number(v) || (text(v) && /^(?:\d+(?:\.\d*)?|\.\d+)$/.test(v))) &&
  Number(v) >= 0 && Number(v) <= 5);
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
  if (/^https:\/\/www\.dent\.niigata-u\.ac\.jp\/student\/syllabus\/#p1-syl\d{4}$/.test(v)) return true;
  return officialDocument(v);
}
function officialDocument(v) {
  if (typeof v !== "string" || v.length > 4096) return false;
  try {
    const u = new URL(v);
    return u.protocol === "https:" && !u.username && !u.password && !u.port && !u.search &&
      /^(?:www\.)?(?:(?:dent|eng|agr|sc|ed|human|econ|law|med|clg|create|iess)\.)?niigata-u\.ac\.jp$/.test(u.hostname) &&
      /\.pdf$/i.test(u.pathname) && /^#page=[1-9]\d{0,3}$/.test(u.hash);
  } catch { return false; }
}
const gradeFields = {
  id: text, recordId: text, importId: (s) => typeof s === "string" && s.length <= 6000,
  code: historicCode, title: text, titleFromOffering: flag, year: scalar, grade: text, credits: number,
  fields, category: text, department: text, duplicate: flag, recognized: flag,
  courseId: text, term: text, section: text, alternativeTitle: text, counts: flag,
  duplicateReviewed: flag, finalEvaluation: flag, identityUncertain: flag, allocationLabel: text, allocationKey: text,
  matchStatus: text, equivalentTitle: text, equivalentTo: text, equivalenceKey: text, repeatGroup: text,
  duplicateOf: text, status: (s) => STATUS.includes(s),
  offeringDepartment: text, offeringFaculty: text,
  source: (v) => ["成績確認表", "単位修得状況照会", "成績表", "本人入力"].includes(v),
  possibleDuplicate: flag, repeatable: flag, identityUnresolved: flag,
  studyYear: (v) => Number.isSafeInteger(v) && v > 0,
  legacyOffering: (v) => v === "day" || v === "night",
  exchangeWithoutLeave: flag, facultyApprovedFree: flag, economicsOtherProgramSeminar: flag,
  lawTrainingSection: flag, languageOverlapApproved: flag, openToAll: flag,
  teacherTrainingOnly: flag, museumQualificationOnly: flag, holidayPracticum: flag,
  partTimeInstructor: flag, minorIntro: flag, irregular: flag,
};
const matchFields = {
  code: historicCode, year: scalar, department: text, title: text, fields, category: text,
  credits: number, confirmed: flag, section: text, term: text, courseId: text, sourceUrl: offeringSource,
  sourceKind: (s) => ["syllabus", "public-index", "faculty-index", "manual-record", "saved-syllabus"].includes(s),
  fieldSource: (s) => s === "" || offeringSource(s), aliasSource: offeringSource,
  categorySource: officialDocument, creditSource: officialDocument,
  schedule: text, period: text, semester: text, format: text,
};
const individual = (v) => flag(v) || text(v);
const decisionScopeFields = {
  entryGrade: optionalPositiveInteger,
  assessmentDate: (s) => s === "" || (text(s) && /^\d{4}-\d{2}-\d{2}$/.test(s)),
  graduationYear: (v) => v === "" || (positiveInteger(v) && /^\d{4}$/.test(String(v))),
  graduationMonth: (v) => v === "" || (positiveInteger(v) && Number(v) <= 12),
  package: (v) => typeof v === "string" && /^[\p{L}\p{M}\p{N}・ ]{0,80}$/u.test(v),
};
// The tuple order is part of the persisted balance identity.
const decisionScopeKeys = Object.keys(decisionScopeFields);
const balanceKeysVersion = 3;
const scopeFields = {
  faculty: text, program: text, field: text, handbook: scalar, entry: text, curriculum: text, goal: text, stage: text,
  admitted: scalar, department: text, individual, stageId: text, ...decisionScopeFields,
};
const balanceFields = {
  ...scopeFields,
  key: text, label: text, kind: text, goal: text, required: number, current: number,
  day: number, night: number, sourceLabel: text, source: (s) => s === "履修科目確認表",
  confirmed: flag, duplicateFree: flag,
  unit: (v) => ["credits", "courses", "months", "condition"].includes(v),
};
const profileFields = {
  faculty: text, program: text, admitted: scalar, handbook: scalar, gpa: scalar,
  cap: scalar, months: scalar, entry: text, curriculum: text, field: text,
  ...decisionScopeFields,
  enrolledMonths: scalar, attendanceMonths: scalar, yearMonths: monthCounts,
  yearAttendanceMonths: (v) => scalar(v) || monthCounts(v), earlyGraduation: flag, deanException: flag,
  yearOfStudy: optionalPositiveInteger,
  iStepApproved: flag, lawPaperSubstitutionApproved: flag, thirdYearCumulativeGpa: gpa,
  internationalStudent: flag, enrolledApril2022: flag,
  department: text, individual,
};
function pick(value, schema) {
  const result = {};
  for (const [key, valid] of Object.entries(schema))
    if (valid(value?.[key])) result[key] = value[key];
  return result;
}
function checkedScope(value) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.entries(scopeFields).some(([key, valid]) => value[key] === null
        ? Object.hasOwn(decisionScopeFields, key) : value[key] !== undefined && !valid(value[key])))
    throw Error("履歴の適用範囲を確認してください。");
  return pick(value, scopeFields);
}
function grade(value) {
  const result = pick(value, gradeFields);
  // Absence denotes an older grade eligible for a catalog lookup. Explicit
  // null records the importer's decision to leave its offering unresolved.
  if (value && Object.hasOwn(value, "matchedCourse") && value.matchedCourse === null) result.matchedCourse = null;
  else if (value?.matchedCourse?.confirmed === true) {
    const match = pick(value.matchedCourse, matchFields);
    if (match.code || (match.code === "" && match.sourceUrl)) result.matchedCourse = match;
  }
  if (value?.allocationScope != null && result.allocationKey) result.allocationScope = checkedScope(value.allocationScope);
  return result;
}
function gradeId(g) {
  return g.importId || g.recordId || g.id || JSON.stringify([g.year, g.code, g.title, g.section, g.term, g.courseId].map(normalize));
}
function legacyBalanceId(b) {
  return JSON.stringify([b.faculty, b.program ?? "", b.field ?? "", b.handbook, b.entry ?? "", b.curriculum ?? "", b.goal, b.stage ?? "", b.key]);
}
function balance(row) {
  checkedScope(row);
  const result = pick(row, balanceFields);
  if (row.scope != null) result.scope = checkedScope(row.scope);
  return result;
}
function balanceId(row) {
  const s = row.scope ?? row;
  const parts = [s.faculty ?? null, s.program ?? "", s.field ?? "", s.handbook == null ? null : String(s.handbook),
    s.entry ?? "1年次入学", s.curriculum ?? "", s.goal ?? null, s.stageId || s.stage || "", row.key,
    String(s.admitted ?? ""), s.department ?? "", s.individual ?? "", row.unit ?? "credits"];
  // Keep old rows and their tombstones at their original key. Within an
  // extended key, null means the dimension was absent and "" is a saved blank.
  if (decisionScopeKeys.some((key) => s[key] !== undefined))
    parts.push(...decisionScopeKeys.map((key) => s[key] === undefined ? null : String(s[key])));
  return JSON.stringify(parts);
}
const oldIdentity = (parts) => Array.isArray(parts) && parts.length === 9 &&
  parts.every((v) => v === null || scalar(v)) && text(parts[8]);
function currentIdentity(parts) {
  if (!Array.isArray(parts) || !oldIdentity(parts.slice(0, 9)) || !text(parts[9]) ||
      !text(parts[10]) || !individual(parts[11]) || !balanceFields.unit(parts[12])) return false;
  if (parts.length === 13) return true;
  const extra = parts.slice(13);
  return extra.length === decisionScopeKeys.length && extra.some((v) => v !== null) &&
    extra.every((v, i) => v === null || (typeof v === "string" && decisionScopeFields[decisionScopeKeys[i]](v)));
}
function legacyFamily(parts) {
  // The old writer only saw the top level, ignored stageId, and retained the
  // input type of handbook. Compare using the engine's effective scope.
  const [faculty, program, field, handbook, entry, curriculum, goal, stage, key] = parts;
  return JSON.stringify([faculty, program, field, handbook == null ? null : String(handbook),
    entry || "1年次入学", curriculum, goal, stage, key]);
}
function fromOldBalance(value) {
  return value && !value.scope && !["admitted", "department", "individual", "stageId", "unit", "duplicateFree", ...decisionScopeKeys]
    .some((field) => Object.hasOwn(value, field)) && value.confirmed !== true;
}
function scopedOrUnconfirmed(row) {
  return fromOldBalance(row) ? { ...row, confirmed: false } : row;
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
    for (const [code, halves] of Object.entries(state.semesters ?? {}))
      if (validCode(code) && number(halves?.first) && number(halves.second))
        map[encode("semesters", code)] = { first: halves.first, second: halves.second };
  } else if (channel === "history") {
    for (const row of state.grades) {
      const value = grade(row);
      if (value.title && number(value.credits)) map[encode("grade", gradeId(value))] = value;
    }
    for (const row of state.balances ?? []) {
      const value = scopedOrUnconfirmed(balance(row));
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
    if (type === "semesters") return removed || (number(value?.first) && number(value.second) &&
      Object.keys(value).length === 2);
    return type === "cap" && (removed || ["除外", "算入"].includes(value));
  }
  if (parts.length !== 2 || typeof a !== "string" || a.length > 6500) return false;
  if (type === "profile") return Object.hasOwn(profileFields, a) && (removed || profileFields[a](value));
  if (type === "grade") return removed || (value?.title && number(value.credits) &&
    same(value, grade(value)) && a === gradeId(value));
  if (type !== "balance") return false;
  const identity = JSON.parse(a);
  if (!oldIdentity(identity) && !currentIdentity(identity)) return false;
  return removed || (value?.key && number(value.current) && number(value.required) &&
    same(value, balance(value)) && (identity.length === 9
      ? fromOldBalance(value) && value.confirmed === undefined && a === legacyBalanceId(value)
      : a === balanceId(value)));
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
function compareFallback(a, b) {
  if (a.legacy !== b.legacy) return a.legacy ? -1 : 1;
  if (a.clock !== b.clock) return a.clock - b.clock;
  if (a.device !== b.device) return a.device > b.device ? 1 : -1;
  return a.key > b.key ? 1 : -1;
}
function materialized(cells, knownFamilies = new Set()) {
  const values = {};
  const modernFamilies = new Set(), fallback = new Map();
  // Immutable old batches (including an unacknowledged publication) keep their
  // own clocks. They cannot overwrite a later schema's more specific identity,
  // even if an old offline writer returns after that identity was deleted.
  for (const [key, cell] of Object.entries(cells)) {
    const [clock, device, row] = cell;
    const [type, id] = JSON.parse(key);
    if (type !== "balance") {
      if (row !== null) values[key] = row;
      continue;
    }
    const parts = JSON.parse(id);
    const family = legacyFamily(parts), legacy = oldIdentity(parts);
    knownFamilies.add(family);
    if (legacy || (row && fromOldBalance(row))) {
      // Numeric and string handbook years used different old keys. Resolve
      // those aliases in the same order on every device, including deletes.
      const prev = fallback.get(family);
      const candidate = { clock, device, key, row, legacy };
      if (!prev || compareFallback(candidate, prev) > 0) fallback.set(family, candidate);
      continue;
    }
    if (row !== null) values[key] = row;
    modernFamilies.add(family);
    if (row) modernFamilies.add(legacyFamily(JSON.parse(legacyBalanceId(row))));
    modernFamilies.add(legacyFamily([...parts.slice(0, 7), "", parts[8]]));
    modernFamilies.add(legacyFamily([null, "", "", null, "", "", null, "", parts[8]]));
  }
  for (const [family, { row }] of fallback) {
    if (row && !modernFamilies.has(family)) {
      // A v1 batch cannot prove admission, department, individual recognition
      // or duplicate-free totals. Keep the figures available for rechecking.
      values[encode("balance", balanceId(row))] = { ...row, confirmed: false };
    }
  }
  for (const family of modernFamilies) knownFamilies.add(family);
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
  const semesters = { ...state.semesters };
  if (channel === "plan") for (const [code, halves] of Object.entries(semesters)) {
    if (!validCode(code) || !number(halves?.first) || !number(halves.second)) continue;
    const { first, second, ...other } = halves;
    if (Object.keys(other).length) semesters[code] = other;
    else delete semesters[code];
  }
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
      case "semesters": semesters[a] = { ...semesters[a], ...value }; break;
      case "grade": {
        const old = oldGrades.get(a);
        grades.push(old && same(grade(old), value) ? old :
          { ...preserveLocal(old, [...Object.keys(gradeFields), "matchedCourse", "allocationScope"]), ...value });
        break;
      }
      case "balance": balances.push({ ...preserveLocal(oldBalances.get(a), [...Object.keys(balanceFields), "scope"]), ...value }); break;
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
    Object.assign(state, { lists: survivors, plan, status, capOverrides: cap, semesters });
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
  let initial = !old && joining?.owner === owner ? joining.values : before;
  if (channel === "history" && initial !== before) {
    // Older consent snapshots use the old balance key. Translate only the key
    // when comparing offline edits; never infer scope from the current profile.
    initial = Object.fromEntries(Object.entries(initial).map(([key, v]) =>
      JSON.parse(key)[0] === "balance" ? [encode("balance", balanceId(v)), scopedOrUnconfirmed(v)] : [key, v]));
  }
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
  const remoteFamilies = new Set();
  if (!old && channel === "history") materialized(cells, remoteFamilies);
  const edits = {};
  const keys = new Set([...Object.keys(baseline), ...Object.keys(initial), ...Object.keys(before), ...Object.keys(fresh)]);
  for (const key of keys) {
    const raced = !same(before[key], fresh[key]) || !same(initial[key], fresh[key]);
    // On first connection prefer the saved remote entry, including its deletion.
    if (!raced && !old) {
      if (cells[key]) continue;
      if (channel === "history" && JSON.parse(key)[0] === "balance" && fromOldBalance(fresh[key]) &&
          remoteFamilies.has(legacyFamily(JSON.parse(legacyBalanceId(fresh[key]))))) continue;
    }
    if (!raced && same(baseline[key], fresh[key])) continue;
    edits[key] = [(raced || !old ? clock : priorClock) + 1, device, fresh[key] ?? null];
  }
  merge(cells, validateEntries(channel, edits));
  if (Object.keys(edits).length)
    for (const cell of Object.values(edits)) clock = Math.max(clock, cell[0]);
  const pendingEntries = { ...old?.pending?.entries, ...edits };
  const pending = Object.keys(edits).length
    ? { id: crypto.randomUUID(), entries: pendingEntries } : old?.pending ?? null;
  if (old && !batches.length && !Object.keys(edits).length &&
      (channel !== "history" || old.balanceKeysVersion === balanceKeysVersion)) return old;
  apply(channel, state, materialized(cells), cells);
  if (state.plannerSync?.owner !== owner) state.plannerSync = { owner, joining: state.plannerSync?.joining };
  if (state.plannerSync.joining) {
    delete state.plannerSync.joining[channel];
    if (!Object.keys(state.plannerSync.joining).length) delete state.plannerSync.joining;
  }
  return state.plannerSync[channel] = { cells, clock, seen: [...seen], pending,
    ...(channel === "history" && { balanceKeysVersion }) };
}
