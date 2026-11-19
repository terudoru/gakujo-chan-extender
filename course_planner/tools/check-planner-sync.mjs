// Compile the actual planner with the worker's panel mounted. Use a private
// HTTP origin, a disk-backed relay and fresh Chrome contexts for each run.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtemp, readFile, readdir, rm, stat } from "node:fs/promises";
import { basename, dirname, extname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";
import { build } from "vite";
import { createRelay, provision } from "../sync/relay.mjs";
import { channelKey, pairingKey, relayIdentity, unseal } from "../src/sync/crypto.mjs";
import { validateEntries } from "../src/sync/model.mjs";
import { initialState } from "../src/study.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const dir = await mkdtemp(join(tmpdir(), "planner-sync-test-"));
const dist = join(dir, "web"), accountDir = join(dir, "account");
const listen = (server) => new Promise((r) => server.listen(0, "127.0.0.1", () => r("http://127.0.0.1:" + server.address().port)));
const button = (page, name) => page.getByRole("button", { name, exact: true });
const storage = "mbg.course-planner.v1";
const canary = "合成の成績テスト", privateMarker = "PDF-PRIVATE-CANARY";
let web, relay, browser;
try {
  await build({
    root, configFile: false, base: "./", logLevel: "error",
    plugins: [{ name: "mount-worker-panel", enforce: "pre", transform(source, id) {
      if (!id.replaceAll("\\", "/").endsWith("/src/App.jsx")) return;
      if (source.includes("<SyncPanel")) return;
      const anchor = '<main id="planner-main" className="work-main">';
      assert.ok(source.includes(anchor), "update integration fixture for new main layout");
      return 'import {SyncPanel} from "./sync/SyncPanel.jsx";\n' +
        source.replace(anchor, anchor + "<SyncPanel {...{state,setState,catalog}} />");
    } }],
    build: { outDir: dist, assetsDir: "", minify: false },
  });
  web = createServer(async (req, res) => {
    const name = basename(new URL(req.url, "http://localhost").pathname) || "index.html";
    const types = { ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".html": "text/html" };
    try {
      const body = await readFile(join(dist, name));
      res.writeHead(200, { "Content-Type": types[extname(name)] || "application/octet-stream" }).end(body);
    } catch { res.writeHead(404).end(); }
  });
  const origin = await listen(web);
  const code = await provision(accountDir);
  relay = await createRelay(accountDir, [origin]);
  const endpoint = await listen(relay);
  const routes = [];
  relay.on("request", (req) => routes.push([req.method, req.url]));
  assert.equal((await fetch(endpoint + "/v1/plan")).status, 401);
  assert.equal((await fetch(endpoint + "/v1/plan", { headers: { Origin: "https://unrelated.invalid" } })).status, 403);
  browser = await chromium.launch({ channel: process.env.CHROME_CHANNEL || "chrome", chromiumSandbox: true, headless: true });
  const contextA = await browser.newContext(), contextB = await browser.newContext();
  const a = await contextA.newPage(), b = await contextB.newPage();
  const errors = [];
  for (const p of [a, b]) {
    p.setDefaultTimeout(12000);
    p.on("pageerror", () => errors.push("page error"));
    await p.goto(origin);
    await p.getByRole("heading", { name: "時間割", exact: true }).waitFor();
  }
  const seed = initialState();
  seed.grades = [{ id: "synthetic", title: canary, grade: "優", credits: 2, year: "2001",
    matchedCourse: { confirmed: true, code: "261G7011", year: "2001", fields: ["70"] }, rawPDF: privateMarker }];
  seed.lists[0].rawPDF = privateMarker;
  await a.evaluate(([k, s]) => localStorage.setItem(k, JSON.stringify(s)), [storage, seed]);
  await a.reload();
  const enterPanel = async (p) => {
    if (!await p.getByLabel("同期サーバーのURL").isVisible() && !await p.getByLabel("この端末で同期する項目").isVisible()) {
      const nav = p.locator("nav:visible").getByRole("button", { name: /同期/ }).first();
      if (await nav.count()) await nav.click();
    }
  };
  const pair = async (p) => {
    await enterPanel(p);
    await p.getByLabel("同期サーバーのURL").fill(endpoint);
    await p.getByLabel("ペアリングコード", { exact: true }).fill(code);
    await button(p, "同期先に接続").click();
    await p.getByLabel("候補リストと時間割").waitFor();
    assert.equal(await p.getByLabel("履修履歴と成績").isChecked(), false);
    assert.equal(await p.getByLabel("候補リストと時間割").isChecked(), false);
  };
  const planOpt = (p) => p.getByLabel("候補リストと時間割");
  const historyOpt = (p) => p.getByLabel("履修履歴と成績");
  const tick = async (p) => { await enterPanel(p); await button(p, "今すぐ同期").click(); };
  const until = async (p, predicate, arg) => {
    await p.waitForFunction(predicate, [storage, arg], { timeout: 40000 });
  };
  const nav = (p, name) => p.locator("nav:visible").getByRole("button", { name, exact: true }).click();
  await pair(a); await pair(b);
  await planOpt(a).check(); await planOpt(b).check();
  await nav(a, "時間割");
  await button(a, "月曜2限の候補").click();
  await button(a, "このコマの授業を探す").click();
  await a.getByRole("searchbox").fill("261G7011");
  await button(a.locator(".result-list li").filter({ hasText: "261G7011" }), "リストに追加").click();
  await until(b, ([k]) => JSON.parse(localStorage.getItem(k))?.lists[0].codes.includes("261G7011"));
  await nav(b, "時間割");
  await button(b, "月曜2限の候補").click();
  await button(b.locator(".inspector .rows li").filter({ hasText: "英語基礎 L" }), "この授業を選ぶ").click();
  await until(a, ([k]) => JSON.parse(localStorage.getItem(k))?.plan.includes("261G7011"));
  assert.equal(await b.evaluate((k) => JSON.parse(localStorage.getItem(k)).grades.length, storage), 0);
  assert.equal(routes.filter(([, path]) => path.includes("/history")).length, 0);
  await nav(a, "候補リスト");
  await button(a, "共有").click();
  const link = await a.getByLabel("共有リンク", { exact: true }).inputValue();
  const snapshot = JSON.parse(Buffer.from(new URL(link).hash.slice(6), "base64url"));
  assert.deepEqual(Object.keys(snapshot).sort(), ["codes", "name", "v", "year"]);
  assert.deepEqual(snapshot.codes, ["261G7011"]);
  assert.ok(!link.includes(code));
  await a.keyboard.press("Escape");
  // An offline deletion survives a reload and propagates after reconnection.
  await contextA.setOffline(true);
  await button(a, "候補から外す").first().click();
  await until(a, ([k]) => !JSON.parse(localStorage.getItem(k)).lists[0].codes.length);
  await contextA.setOffline(false);
  await a.reload();
  await until(b, ([k]) => !JSON.parse(localStorage.getItem(k)).lists[0].codes.length);
  await enterPanel(a); await enterPanel(b);
  await historyOpt(a).check();
  await until(a, ([k]) => JSON.parse(localStorage.getItem(k))?.plannerSync?.history?.seen.length > 0);
  assert.equal(await b.evaluate((k) => JSON.parse(localStorage.getItem(k)).grades.length, storage), 0);
  // Hold the first private download after the server has accepted it. Turning
  // consent off must fence decryption, local application and any upload.
  let arrived, release;
  const requested = new Promise((r) => { arrived = r; });
  const paused = new Promise((r) => { release = r; });
  await b.route(endpoint + "/v1/history/*", async (route) => {
    const response = await route.fetch();
    arrived();
    await paused;
    await route.fulfill({ response }).catch(() => {});
  });
  await historyOpt(b).check();
  await Promise.race([requested, new Promise((_, reject) => { const t = setTimeout(() => reject(Error("private download missing")), 12000); t.unref(); })]);
  await historyOpt(b).uncheck();
  release();
  await b.unrouteAll({ behavior: "wait" });
  await tick(b);
  await b.getByRole("status").filter({ hasText: "最終同期" }).waitFor();
  assert.equal(await b.evaluate((k) => JSON.parse(localStorage.getItem(k)).grades.length, storage), 0);
  await planOpt(b).uncheck();
  await historyOpt(b).check();
  await until(b, ([k, title]) => JSON.parse(localStorage.getItem(k)).grades.some((g) =>
    g.title === title && g.matchedCourse?.confirmed && g.matchedCourse.fields.includes("70")), canary);
  const rootKey = await pairingKey(code), { account } = await relayIdentity(rootKey);
  const owner = JSON.stringify(["relay", account, account]);
  const output = {};
  for (const channel of ["plan", "history"]) {
    const key = await channelKey(rootKey, owner, channel);
    const ids = await readdir(join(accountDir, channel));
    assert.ok(ids.length);
    output[channel] = [];
    for (const id of ids) {
      const wire = await readFile(join(accountDir, channel, id), "utf8");
      assert.doesNotMatch(wire, /PDF-PRIVATE-CANARY|合成の成績テスト|261G7011/);
      const entries = await unseal(key, owner, channel, id, JSON.parse(wire));
      validateEntries(channel, entries);
      assert.ok(!JSON.stringify(entries).includes(privateMarker));
      output[channel].push(entries);
    }
  }
  assert.ok(!JSON.stringify(output.plan).includes(canary));
  assert.ok(JSON.stringify(output.history).includes(canary));
  assert.equal(await planOpt(b).isChecked(), false);
  await planOpt(b).check();
  // Disconnect during a manifest request with an unpublished local edit.
  // Even if the response is already in the network stack it must not upload.
  let sawManifest, finishManifest;
  const manifestRequested = new Promise((r) => { sawManifest = r; });
  const holdManifest = new Promise((r) => { finishManifest = r; });
  await b.route(endpoint + "/v1/plan", async (route) => {
    const response = await route.fetch();
    sawManifest();
    await holdManifest;
    await route.fulfill({ response }).catch(() => {});
  });
  await b.evaluate((k) => {
    const s = JSON.parse(localStorage.getItem(k));
    s.lists[0].name = "接続解除中の端末限定編集";
    localStorage.setItem(k, JSON.stringify(s));
  }, storage);
  const uploadsBefore = routes.filter(([method]) => method === "PUT").length;
  await tick(b);
  await Promise.race([manifestRequested, new Promise((_, reject) => { const t = setTimeout(() => reject(Error("manifest missing")), 12000); t.unref(); })]);
  await button(b, "この端末の接続を解除").click();
  finishManifest();
  await b.unrouteAll({ behavior: "wait" });
  await b.getByLabel("ペアリングコード", { exact: true }).waitFor();
  assert.equal(await b.evaluate(() => localStorage.getItem("mbg.planner.sync.connection.v1")), null);
  assert.equal(routes.filter(([method]) => method === "PUT").length, uploadsBefore);
  const sameDevice = await contextA.newPage();
  await sameDevice.goto(origin);
  await enterPanel(sameDevice);
  await historyOpt(sameDevice).waitFor();
  await Promise.all([planOpt(a).uncheck(), historyOpt(sameDevice).uncheck()]);
  for (const p of [sameDevice, a])
    await p.waitForFunction(() => {
      const boxes = document.querySelectorAll(".planner-sync fieldset input[type=checkbox]");
      return boxes.length === 2 && [...boxes].every((box) => !box.checked);
    });
  assert.deepEqual(errors, []);
  console.log("PASS: two isolated Chrome contexts, bidirectional automatic edits, private share snapshot, offline deletion, reload, separate opt-ins, in-flight withdrawal, disconnect, authenticated relay and decrypted wire allowlists.");
} finally {
  await browser?.close();
  for (const server of [web, relay]) if (server) {
    server.closeAllConnections();
    await new Promise((r) => server.close(r));
  }
  if (dirname(resolve(dir)) === resolve(tmpdir()) && basename(dir).startsWith("planner-sync-test-") && (await stat(dir)).isDirectory())
    await rm(dir, { recursive: true, force: true });
}
