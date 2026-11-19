import test from "node:test";
import assert from "node:assert/strict";
import { initialState } from "../src/study.mjs";
import { checkpoint, project, reconcile, validateEntries } from "../src/sync/model.mjs";
import { channelKey, newPairingCode, pairingKey, seal, unseal } from "../src/sync/crypto.mjs";
import { googleTransport, relayURL } from "../src/sync/transports.mjs";
import { PlannerSync } from "../src/sync/controller.mjs";

const a = "00000000-0000-4000-8000-000000000001", b = "00000000-0000-4000-8000-000000000002";
const c1 = "261G7011", c2 = "261G3008";
const owner = "test", channel = "plan";
function run(state, device, batches = [], before = project(channel, state)) {
  return reconcile({ state, device, batches, before, channel, owner });
}
function ack(state) {
  const cp = checkpoint(state, owner, channel);
  const batch = cp.pending;
  if (batch) cp.seen.push(batch.id);
  cp.pending = null;
  return batch;
}
test("causal edits, racing first pull, concurrent additions and old snapshot deletions converge", () => {
  const one = initialState(), two = initialState();
  one.lists[0].codes.push(c1);
  run(one, a);
  const first = ack(one);
  const before = project(channel, two);
  two.plan.push(c2);
  run(two, b, [first], before);
  const second = ack(two);
  run(one, a, [second]);
  assert.deepEqual(one.plan, [c2]);
  assert.deepEqual(two.lists[0].codes, [c1]);
  one.lists[0].codes = [];
  two.lists[0].codes.push(c2);
  one.lists[0].name = "A";
  two.lists[0].name = "B";
  run(one, a); run(two, b);
  const left = ack(one), right = ack(two);
  run(one, a, [right]); run(two, b, [left]);
  assert.deepEqual(one.lists, two.lists);
  assert.deepEqual(one.lists[0].codes, [c2]);
  const late = initialState();
  late.lists[0].codes.push(c1);
  run(late, crypto.randomUUID(), [right, second, first, left]);
  assert.deepEqual(late.lists, one.lists);
  assert.equal(run(one, a, [right]).pending, null);
});
test("pending publication survives reload and edits during a pending download win locally", () => {
  const state = initialState();
  run(state, a);
  const saved = JSON.parse(JSON.stringify(state));
  assert.deepEqual(run(saved, a).pending, run(state, a).pending);
  ack(saved);
  const before = project(channel, saved);
  saved.lists[0].name = "during download";
  run(saved, a, [{ id: crypto.randomUUID(), entries: { '["list","mine"]': [12, b, "remote"] } }], before);
  assert.equal(saved.lists[0].name, "during download");
  assert.equal(checkpoint(saved, owner, channel).pending.entries['["list","mine"]'][0], 13);
});
test("copied lists retain original ordering on a new device", () => {
  const source = initialState(), receiver = initialState();
  source.lists.unshift({ id: "zcopy", name: "配布時の候補", codes: [c1, c2] });
  source.plan = [c1, c2];
  run(source, a);
  run(receiver, b, [ack(source)]);
  assert.deepEqual(receiver.lists, source.lists);
  assert.deepEqual(receiver.plan, source.plan);
});
test("edits and removals after consent survive an offline first pull", () => {
  const remote = initialState(), local = initialState();
  remote.lists[0].codes.push(c1);
  remote.lists[0].name = "remote";
  local.lists[0].codes.push(c1);
  local.plannerSync = { joining: { plan: { owner, values: project(channel, local) } } };
  local.lists[0].name = "offline after consent";
  local.lists[0].codes = [];
  run(remote, a);
  run(local, b, [ack(remote)]);
  assert.equal(local.lists[0].name, "offline after consent");
  assert.deepEqual(local.lists[0].codes, []);
  assert.equal(local.plannerSync.joining, undefined);
});
test("concurrent last-list deletions recover one empty list without reviving orphaned membership", () => {
  const one = initialState(), two = initialState();
  one.lists.push({ id: "second", name: "second", codes: [] });
  run(one, a);
  run(two, b, [ack(one)]);
  one.lists.shift();
  two.lists.pop();
  two.lists[0].codes.push(c1);
  run(one, a); run(two, b);
  const left = ack(one), right = ack(two);
  run(one, a, [right]); run(two, b, [left]);
  assert.deepEqual(one.lists, two.lists);
  assert.notEqual(one.lists[0].id, "mine");
  run(one, a); run(two, b, [ack(one)]);
  assert.deepEqual(one.lists, two.lists);
  assert.deepEqual(two.lists[0].codes, []);
});
test("stale UI callbacks cannot enable or disconnect the next account", async () => {
  const original = Object.getOwnPropertyDescriptor(globalThis, "localStorage");
  const current = JSON.stringify({ session: b, history: false, provider: "google" });
  Object.defineProperty(globalThis, "localStorage", { configurable: true, value: { getItem: () => current } });
  try {
    const sync = new PlannerSync({});
    assert.throws(() => sync.consent("history", true, a), /接続先が変わりました/);
    await assert.rejects(sync.disconnect(a), /接続先が変わりました/);
    await assert.rejects(sync.reauthorize(a), /接続先が変わりました/);
  } finally {
    if (original) Object.defineProperty(globalThis, "localStorage", original);
    else delete globalThis.localStorage;
  }
});
test("strict separate wire schemas strip unrecognized private nested fields", () => {
  const s = initialState();
  s.grades = [{ id: "demo", title: "SYNTHETIC", credits: 2, year: "2001", grade: "優", rawPDF: "PRIVATE",
    matchedCourse: { year: 2001, code: c1, fields: ["70"], confirmed: true, token: "PRIVATE" } }];
  s.profile.gpa = "3.6";
  s.profile.cookie = "PRIVATE";
  s.lists[0].grades = s.grades;
  const plan = project("plan", s), history = project("history", s);
  assert.doesNotMatch(JSON.stringify(plan), /grade|SYNTHETIC|PRIVATE|3\.6/);
  assert.doesNotMatch(JSON.stringify(history), /PRIVATE/);
  assert.match(JSON.stringify(history), /SYNTHETIC/);
  const entries = Object.fromEntries(Object.entries(history).map(([k, v]) => [k, [1, a, v]]));
  validateEntries("history", entries);
  assert.throws(() => validateEntries("plan", entries));
  assert.throws(() => validateEntries("plan", { '["grade","demo"]': [1, a, null] }));
  const replica = initialState();
  reconcile({ state: replica, before: project("history", replica), owner, device: b, channel: "history",
    batches: [{ id: crypto.randomUUID(), entries }] });
  assert.deepEqual(replica.grades[0].matchedCourse, { code: c1, year: 2001, fields: ["70"], confirmed: true });
});
test("encryption authenticates the account, category and immutable batch ID", async () => {
  const root = await pairingKey(newPairingCode()), key = await channelKey(root, owner, channel);
  const batch = { id: crypto.randomUUID(), entries: { example: "synthetic" } };
  const encrypted = await seal(key, owner, channel, batch);
  assert.deepEqual(await unseal(key, owner, channel, batch.id, encrypted), batch.entries);
  await assert.rejects(unseal(key, owner, "history", batch.id, encrypted));
  await assert.rejects(unseal(key, owner + "b", channel, batch.id, encrypted));
  await assert.rejects(unseal(key, owner, channel, a, encrypted));
  assert.throws(() => relayURL("http://192.168.1.30"));
  assert.throws(() => relayURL("https://user:pass@example.test"));
});
test("grade identities, review decisions and official archive evidence survive a history-only join", () => {
  const source = initialState(), receiver = initialState();
  const record = { code: "", year: "2014", title: "合成科目", credits: 1, grade: "認定",
    allocationKey: "major", allocationScope: { faculty: "歯学部", handbook: "2014", stage: "graduation" },
    recognized: true, duplicate: true, counts: false, duplicateReviewed: true, identityUncertain: true,
    matchedCourse: { confirmed: true, sourceKind: "faculty-index", year: "2014", code: "",
      title: "合成科目", department: "08", fields: [], category: "", fieldSource: "",
      sourceUrl: "https://www.dent.niigata-u.ac.jp/student/syllabus/#p1-syl2014" } };
  source.grades = ["first", "second"].map((importId) => ({ ...record, importId }));
  source.balances = ["second-year", "graduation"].map((stage) => ({
    faculty: "歯学部", program: "", stage, key: "total", current: 1, required: 10, day: 1, night: 0,
  }));
  const first = reconcile({ state: source, channel: "history", device: a, owner, before: project("history", source), batches: [] });
  reconcile({ state: receiver, channel: "history", device: b, owner, before: project("history", receiver), batches: [first.pending] });
  assert.deepEqual(receiver.grades, source.grades);
  assert.deepEqual(receiver.balances.sort((x,y) => x.stage.localeCompare(y.stage)),
    source.balances.sort((x,y) => x.stage.localeCompare(y.stage)));
});
function history(state, device, batches = [], before = project("history", state)) {
  return reconcile({ state, before, owner, device, channel: "history", batches });
}
test("plan sends only both explicit semester halves per offering, including updates and removals", () => {
  const local = initialState(), remote = initialState();
  local.semesters = { [c1]: { first: 1.5, second: 0, grade: "SENSITIVE" }, [c2]: { first: 1 }, raw: { first: 0, second: 0 } };
  const batch = run(local, a).pending;
  assert.deepEqual(batch.entries[JSON.stringify(["semesters", c1])][2], { first: 1.5, second: 0 });
  assert.ok(!JSON.stringify(batch.entries).includes("SENSITIVE"));
  assert.ok(!JSON.stringify(project("history", local)).includes("semesters"));
  assert.throws(() => validateEntries("plan", { [JSON.stringify(["semesters", c1])]: [1, a, { first: 1, second: 1, grade: "SENSITIVE" }] }));
  run(remote, b, [batch]);
  assert.deepEqual(remote.semesters, { [c1]: { first: 1.5, second: 0 } });
  delete remote.semesters[c1];
  run(local, a, [run(remote, b).pending]);
  assert.deepEqual(local.semesters[c1], { grade: "SENSITIVE" });
});
const scope = {
  faculty: "法学部", department: "法学科", admitted: "2022", handbook: "2023", program: "法学",
  entry: "編入・転部・再入学", field: "公法", curriculum: "A", individual: false, goal: "progress", stage: "third",
};
const total = { key: "total", label: "計", required: 60, current: 32, duplicateFree: true, confirmed: true, source: "履修科目確認表" };
function v1(row) {
  const old = Object.fromEntries(["faculty", "program", "field", "handbook", "entry", "curriculum", "goal", "stage",
    "key", "label", "kind", "required", "current", "day", "night", "sourceLabel", "source"]
    .filter((k) => row[k] !== undefined).map((k) => [k, row[k]]));
  const id = JSON.stringify([old.faculty, old.program ?? "", old.field ?? "", old.handbook, old.entry ?? "",
    old.curriculum ?? "", old.goal, old.stage ?? "", old.key]);
  return { key: JSON.stringify(["balance", id]), old };
}
test("each academic scope, eligibility decision and typed source survives history only", () => {
  const author = initialState(), receiver = initialState();
  Object.assign(author.profile, scope, { yearOfStudy: "4", sessionKey: "PRIVATE" });
  const variations = [{}, { department: "別学科" }, { admitted: "2021" }, { individual: true }, { field: "別" },
    { handbook: "2020" }, { faculty: "別" }, { program: "別" }, { curriculum: "B" },
    { entry: "1年次入学" }, { goal: "graduation" }, { stage: "fourth" }];
  author.balances = variations.map((v, i) => ({ ...scope, ...v, ...total, current: i + 1 }));
  author.balances.push({ ...total, scope: { ...scope, stageId: "fifth", stage: "", rawPDF: "PRIVATE" }, unit: "credits", confirmed: false });
  author.grades = [{ title: "認定A", credits: 1, grade: "認定", recognized: true, allocationKey: "major",
    allocationScope: { ...scope, cookie: "PRIVATE" }, possibleDuplicate: true, duplicateReviewed: true, counts: true, source: "単位修得状況照会",
    matchedCourse: { code: c1, confirmed: true, categorySource: "https://www.eng.niigata-u.ac.jp/sample.pdf#page=4" } },
    { title: "認定B", credits: 1, source: "PRIVATE", duplicate: true, counts: false }];
  const batch = history(author, a).pending;
  history(receiver, b, [batch]);
  assert.equal(receiver.balances.length, variations.length + 1);
  for (const [i, patch] of variations.entries()) {
    const actual = receiver.balances.find((row) => row.current === i + 1);
    assert.deepEqual(actual, { ...scope, ...patch, ...total, current: i + 1 });
  }
  assert.deepEqual(receiver.balances.find((r) => r.scope)?.scope, { ...scope, stageId: "fifth", stage: "" });
  assert.equal(receiver.balances.find((r) => r.scope)?.confirmed, false);
  assert.equal(receiver.profile.yearOfStudy, "4");
  assert.equal(receiver.profile.individual, false);
  assert.equal(receiver.profile.department, scope.department);
  const g = receiver.grades.find((r) => r.title === "認定A");
  assert.deepEqual(g.allocationScope, scope);
  assert.ok(g.possibleDuplicate && g.duplicateReviewed && g.counts);
  assert.equal(g.source, "単位修得状況照会");
  assert.equal(g.matchedCourse.categorySource, "https://www.eng.niigata-u.ac.jp/sample.pdf#page=4");
  assert.ok(!JSON.stringify(batch).includes("PRIVATE"));
  assert.doesNotMatch(JSON.stringify(project("plan", author)), /total|法学|認定|duplicate|yearOfStudy|PRIVATE/);
  author.grades[0].matchedCourse.categorySource += "?token=PRIVATE";
  assert.ok(!JSON.stringify(project("history", author)).includes("categorySource"));
  author.balances[0].department = { token: "PRIVATE" };
  assert.throws(() => project("history", author), /適用範囲/);
});
test("a scoped local row supersedes a legacy checkpoint, pending write, remote edit and tombstone", () => {
  const local = initialState(), replica = initialState();
  const full = { ...scope, ...total };
  const { old, key } = v1(full);
  const batch = { id: crypto.randomUUID(), entries: { [key]: [3, a, old] } };
  local.balances = [full];
  local.plannerSync = { owner, history: { cells: structuredClone(batch.entries), pending: batch, clock: 3, seen: [] } };
  const upgraded = history(local, a).pending;
  assert.notEqual(upgraded.id, batch.id);
  assert.deepEqual(local.balances, [full]);
  history(replica, b, [batch]);
  assert.equal(replica.balances[0].confirmed, false);
  history(replica, b, [upgraded]);
  assert.deepEqual(replica.balances, [full]);
  const late = { id: crypto.randomUUID(), entries: { [key]: [80, a, { ...old, current: 50 }] } };
  history(replica, b, [late]);
  assert.deepEqual(replica.balances, [full]);
  replica.balances = [];
  const deletion = history(replica, b).pending;
  history(local, a, [deletion, late, { id: crypto.randomUUID(), entries: { [key]: [90, a, null] } }]);
  assert.deepEqual(local.balances, []);
  const newcomer = initialState();
  newcomer.balances = [old];
  history(newcomer, b, [late, deletion, upgraded, batch]);
  assert.deepEqual(newcomer.balances, []);
});
test("legacy-only figures remain available for rechecking without profile attribution or duplicate uploads", () => {
  const s = initialState();
  const { old, key } = v1({ ...scope, ...total });
  const batch = { id: crypto.randomUUID(), entries: { [key]: [2, b, old] } };
  s.balances = [old];
  s.plannerSync = { owner, history: { cells: batch.entries, clock: 2, seen: [batch.id], pending: null } };
  const next = history(s, a);
  assert.deepEqual(s.balances, [{ ...old, confirmed: false }]);
  // The first run may also enqueue initially present profile fields.
  if (next.pending) assert.ok(!Object.keys(next.pending.entries).some((key) => JSON.parse(key)[0] === "balance"));
  const before = JSON.stringify(s.balances);
  history(s, a, [batch]);
  assert.equal(JSON.stringify(s.balances), before);
});
test("legacy handbook aliases converge in any arrival order, even on a newly paired device", () => {
  const numeric = v1({ ...scope, ...total, handbook: 2023 }), string = v1({ ...scope, ...total, current: 45 });
  const older = { id: crypto.randomUUID(), entries: { [numeric.key]: [1, a, numeric.old] } };
  const newer = { id: crypto.randomUUID(), entries: { [string.key]: [3, b, string.old] } };
  const removed = { id: crypto.randomUUID(), entries: { [numeric.key]: [5, a, null] } };
  for (const sequence of [[older, newer], [newer, older]]) {
    const s = initialState();
    history(s, b, sequence);
    assert.deepEqual(s.balances, [{ ...string.old, confirmed: false }]);
    history(s, b, [removed]);
    assert.deepEqual(s.balances, []);
  }
  const fresh = initialState(), peer = initialState();
  fresh.balances = [numeric.old];
  const unconfirmed = history(fresh, a).pending;
  history(peer, b, [unconfirmed]);
  assert.equal(peer.balances[0].confirmed, false);
  const scoped = initialState();
  scoped.balances = [{ ...scope, ...total }];
  history(peer, b, [history(scoped, a).pending, newer]);
  assert.deepEqual(peer.balances, scoped.balances);
});
test("Drive uses account identity and paginates a single private channel; session expiry stops access", async (t) => {
  const group = "group", prefix = "mbg-planner-v1.group.plan.";
  const calls = [], guard = () => {};
  t.mock.method(globalThis, "fetch", async (url, init) => {
    const u = new URL(url);
    calls.push([u, init]);
    if (u.pathname.endsWith("/about")) return Response.json({ user: { permissionId: "demo1" } });
    if (init.method === "POST") return Response.json({ id: "created" });
    if (u.searchParams.has("pageToken")) return Response.json({ files: [{ id: "f", name: prefix + a }] });
    return Response.json({ files: [], nextPageToken: "another" });
  });
  assert.throws(() => googleTransport(null, group, undefined, guard));
  const api = googleTransport({ value: "synthetic", until: Date.now() + 60000 }, group, undefined, guard);
  assert.equal(await api.account(), "demo1");
  assert.deepEqual(await api.list("plan"), [{ id: a, file: "f" }]);
  assert.equal(calls[1][0].searchParams.get("spaces"), "appDataFolder");
  assert.equal(calls[2][0].searchParams.get("pageToken"), "another");
  assert.doesNotMatch(calls[1][0].search, /history/);
  await api.write("plan", b, { v: 1, iv: "synthetic", box: "synthetic" });
  assert.match(calls[3][1].body, /"parents":\["appDataFolder"\]/);
  assert.equal(calls[3][1].redirect, "error");
});
