// Invoked by the Flutter smoke fixture after its native academic import.
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { createRequire } from "node:module";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { setTimeout as delay } from "node:timers/promises";

const [project, run, url, marker] = process.argv.slice(2);
const { chromium } = createRequire(join(project, "package.json"))("playwright-core");
const { createRelay, provision } = await import(pathToFileURL(join(project, "sync/relay.mjs")));
const storage = "mbg.course-planner.v1";
const nativeTitle = "情報通信技術教育論I", browserTitle = "ブラウザー合成履歴";
const button = (page, name) => page.getByRole("button", { name, exact: true });
const plan = (page) => page.getByLabel("候補リストと時間割");
const history = (page) => page.getByLabel("履修履歴と成績");
const nav = (page, name) => button(page.locator("nav:visible"), name).click();
const dialog = (page) => page.getByRole("dialog");
const until = (page, predicate, value) =>
  page.waitForFunction(predicate, [storage, value], { timeout: 35000 });
const grades = (page) => page.evaluate((key) =>
  (JSON.parse(localStorage.getItem(key))?.grades ?? [])
    .map(({ title, grade, credits }) => [title, grade, credits])
    .sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0), storage);
const nativeGrade = [nativeTitle, "優", 1], browserGrade = [browserTitle, "良", 1];

async function importFile(page, csv, title) {
  await nav(page, "単位・要件");
  await page.getByRole("button", { name: /^(?:成績|成績確認表)(?:を取り込む|の取り込み)$/ }).click();
  const review = dialog(page);
  await review.locator("input[type=file]").setInputFiles({ name: "synthetic.csv", mimeType: "text/csv",
    buffer: Buffer.from(csv) });
  await review.getByRole("checkbox", { name: new RegExp(title + "を取り込む") }).check();
  assert.deepEqual(await grades(page), []);
  await button(review, "選択した1件を取り込む").click();
  await review.waitFor({ state: "hidden" });
}
async function offeringEvidence(page) {
  return page.evaluate((key) => {
    const state = JSON.parse(localStorage.getItem(key));
    const grade = state.grades.find((g) => g.code === "261K0501");
    return [grade.offeringDepartment, grade.matchedCourse, JSON.stringify(grade).includes("PRIVATE-COLUMN-CANARY")];
  }, storage);
}

async function openPanel(page) {
  if (!(await page.locator(".planner-sync").isVisible()))
    await page.getByRole("button", { name: /^(端末間同期|同期|同期設定|端末間の同期)$/ }).first().click();
}
async function pair(page, endpoint, code) {
  await openPanel(page);
  await page.locator(".planner-sync select").selectOption("relay");
  await page.getByLabel("同期サーバーのURL").fill(endpoint);
  await page.getByLabel("ペアリングコード", { exact: true }).fill(code);
  await button(page, "同期先に接続").click();
  await plan(page).waitFor();
  assert.equal(await plan(page).isChecked(), false);
  assert.equal(await history(page).isChecked(), false);
  await plan(page).check();
}
async function rename(page, name) {
  await nav(page, "候補リスト");
  await button(page, "名前を変更").click();
  await page.getByLabel("リスト名", { exact: true }).fill(name);
  await button(dialog(page), "保存").click();
  await waitName(page, name);
}
async function waitName(page, name) {
  await until(page, ([key, expected]) =>
    JSON.parse(localStorage.getItem(key))?.lists.some((l) => l.id === "mine" && l.name === expected), name);
}

async function webviewSocket() {
  // Edge writes this only for --remote-debugging-port=0. Read from the fresh
  // fixture profile and connect to that exact browser rather than a fixed port.
  for (const directory of [join(run, "profile", "EBWebView"), join(run, "profile")]) {
    let info;
    try {
      info = await readFile(join(directory, "DevToolsActivePort"), "utf8");
    } catch (error) {
      if (error.code === "ENOENT") continue;
      throw error;
    }
    const [port, path] = info.trim().split(/\r?\n/);
    assert.match(port, /^\d{1,5}$/);
    assert.ok(Number(port) > 0 && Number(port) < 65536);
    assert.match(path, /^\/devtools\/browser\/[a-f0-9-]+$/i);
    return "ws://127.0.0.1:" + port + path;
  }
  throw Error("WebView2 fixture endpoint missing");
}

let stage = "attaching to the private flutter planner document";
let ownerDir, relay, browser, nativeBrowser, release;
try {
  const origin = new URL(url).origin;
  assert.match(url, /^http:\/\/127\.0\.0\.1:\d+\/planner\/$/);
  nativeBrowser = await chromium.connectOverCDP(await webviewSocket(), { timeout: 10000 });
  const targets = nativeBrowser.contexts().flatMap((c) => c.pages()).filter((p) => p.url() === url);
  assert.equal(targets.length, 1);
  const native = targets[0];
  assert.equal(await native.evaluate(() => document.__mbgSmokeHost), marker);
  assert.deepEqual(await grades(native), [nativeGrade]);

  stage = "provisioning the local relay and isolated chrome";
  ownerDir = await mkdtemp(join(run, "relay-"));
  const account = join(ownerDir, "owner");
  const code = await provision(account);
  relay = await createRelay(account, [origin]);
  await new Promise((done) => relay.listen(0, "127.0.0.1", done));
  const endpoint = "http://127.0.0.1:" + relay.address().port;
  assert.equal((await fetch(endpoint + "/v1/account")).status, 401);
  const historyTraffic = { requests: 0, puts: 0 };
  relay.on("request", (req) => {
    if (req.url.startsWith("/v1/history")) {
      historyTraffic.requests++;
      if (req.method === "PUT") historyTraffic.puts++;
    }
  });
  browser = await chromium.launch({ channel: process.env.CHROME_CHANNEL || "chrome",
    headless: true, chromiumSandbox: true, args: ["--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
  const chrome = await (await browser.newContext()).newPage();
  for (const page of [chrome, native]) page.setDefaultTimeout(15000);
  await chrome.goto(url);
  assert.equal(await chrome.evaluate(() => document.__mbgSmokeHost), undefined);
  assert.deepEqual(await grades(chrome), []);

  stage = "comparing native and file import offering identity";
  assert.deepEqual(await offeringEvidence(native), ["人文学部", null, false]);
  for (const faculty of ["人文学部", "教育学部"]) {
    const context = await browser.newContext();
    try {
      const filePage = await context.newPage();
      await filePage.goto(url);
      await importFile(filePage, "開講番号,科目名,単位数,評価,年度,開講所属,学生所属,担当教員\n" +
        "261K0501," + nativeTitle + ",1,優,2026," + faculty + ",教育学部,PRIVATE-COLUMN-CANARY\n", nativeTitle);
      const evidence = await offeringEvidence(filePage);
      if (faculty === "人文学部") assert.deepEqual(evidence, await offeringEvidence(native));
      else {
        assert.equal(evidence[0], "教育学部");
        assert.equal(evidence[1]?.department, "03");
        assert.equal(evidence[1]?.confirmed, true);
        assert.equal(evidence[2], false);
      }
    } finally {
      await context.close();
    }
  }

  stage = "importing the independent chrome history through the review";
  await importFile(chrome, "科目名,単位数,評価,年度\n" + browserTitle + ",1,良,2026\n", browserTitle);
  assert.deepEqual(await grades(chrome), [browserGrade]);

  stage = "pairing both clients with independent plan consent";
  assert.equal(await chrome.evaluate(() => document.documentElement.dataset.plannerHost), undefined);
  assert.equal(await native.evaluate(() => document.documentElement.dataset.plannerHost), "app");
  await openPanel(native);
  assert.deepEqual(await native.locator(".planner-sync select option").evaluateAll((options) =>
    options.map((option) => option.value)), ["relay"]);
  await pair(chrome, endpoint, code);
  await pair(native, endpoint, code);
  stage = "syncing the chrome list edit to webview";
  await rename(chrome, "ブラウザーで変更");
  await waitName(native, "ブラウザーで変更");
  stage = "syncing the webview list edit back to chrome";
  await rename(native, "アプリで変更");
  await waitName(chrome, "アプリで変更");
  assert.deepEqual(await grades(native), [nativeGrade]);
  assert.deepEqual(await grades(chrome), [browserGrade]);
  assert.deepEqual(historyTraffic, { requests: 0, puts: 0 });

  stage = "enabling chrome history while webview remains private";
  await openPanel(chrome);
  await openPanel(native);
  await history(chrome).check();
  await until(chrome, ([key]) => JSON.parse(localStorage.getItem(key))?.plannerSync?.history?.seen.length > 0);
  assert.ok(historyTraffic.puts > 0);
  assert.deepEqual(await grades(native), [nativeGrade]);
  assert.deepEqual(await grades(chrome), [browserGrade]);

  stage = "withdrawing webview consent during a private download";
  let arrived;
  const pending = new Promise((done) => { arrived = done; });
  const hold = new Promise((done) => { release = done; });
  const historyPath = endpoint + "/v1/history/*";
  await native.route(historyPath, async (route) => {
    if (route.request().method() !== "GET") return route.continue();
    const response = await route.fetch();
    arrived(response.status());
    await hold;
    await route.fulfill({ response }).catch(() => {});
  });
  const before = historyTraffic.puts;
  await history(native).check();
  assert.equal(await Promise.race([pending, delay(15000, 0, { ref: false })]), 200);
  await history(native).uncheck();
  release();
  await native.unrouteAll({ behavior: "wait" });
  await button(native, "今すぐ同期").click();
  await native.getByRole("status").filter({ hasText: "最終同期" }).waitFor();
  assert.equal(historyTraffic.puts, before);
  assert.deepEqual(await grades(native), [nativeGrade]);
  assert.deepEqual(await grades(chrome), [browserGrade]);

  stage = "receiving both histories after independent opt in";
  await history(native).check();
  for (const page of [native, chrome])
    await until(page, ([key]) => JSON.parse(localStorage.getItem(key))?.grades.length === 2);
  const expected = [browserGrade, nativeGrade];
  assert.deepEqual(await grades(native), expected);
  assert.deepEqual(await grades(chrome), expected);
  assert.deepEqual(await offeringEvidence(chrome), ["人文学部", null, false]);
  stage = "verifying both histories after withdrawal and continued plan edits";
  await history(native).uncheck();
  await history(chrome).uncheck();
  const stopped = { ...historyTraffic };
  await rename(chrome, "履歴共有を停止した後の変更");
  await waitName(native, "履歴共有を停止した後の変更");
  assert.deepEqual(historyTraffic, stopped);
  for (const page of [native, chrome]) {
    assert.deepEqual(await grades(page), expected);
    await openPanel(page);
    await button(page, "この端末の接続を解除").click();
    await page.getByLabel("ペアリングコード", { exact: true }).waitFor();
    assert.equal(await page.evaluate(() => localStorage.getItem("mbg.planner.sync.connection.v1")), null);
  }
  console.log("PASS");
} catch {
  // Form actions can include the ephemeral pairing code in Playwright errors.
  console.log("FAIL " + stage);
  process.exitCode = 1;
} finally {
  release?.();
  await browser?.close();
  await nativeBrowser?.close();
  if (relay) {
    relay.closeAllConnections();
    await new Promise((done) => relay.close(done));
  }
  if (ownerDir) await rm(ownerDir, { recursive: true, force: true });
}
