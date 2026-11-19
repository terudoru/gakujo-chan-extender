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
