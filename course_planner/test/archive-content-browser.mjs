// Mount the same production leaf as a comparison card and a dialog without editing the parent-owned UI.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";
import { build } from "vite";

const entry = "content-test-entry";
const root = fileURLToPath(new URL("../", import.meta.url));
const bundle = await build({
  root, configFile: fileURLToPath(new URL("../vite.config.js", import.meta.url)), logLevel: "error",
  plugins: [{
    name: "content-test-entry",
    resolveId(id) { if (id === entry) return "\0" + entry; },
    load(id) {
      if (id !== "\0" + entry) return;
      return `import React from "react"; import {createRoot} from "react-dom/client";
        import SyllabusContent from "/src/archive/content/SyllabusContent.jsx";
        const root = createRoot(document.getElementById("fixture"));
        window.showCourses = (...specs) => root.render(React.createElement(React.Fragment, null,
          ...specs.map(([department, code, year, asDialog], i) => React.createElement(asDialog ? "dialog" : "article",
            {open: asDialog || undefined, key: i}, React.createElement(SyllabusContent,
              {course:{department, code, title: code, year:"2026"}, year})))));
        window.showCourses();`;
    },
  }],
  build: { write: false, rollupOptions: { input: entry, output: { entryFileNames: "entry.js" } } },
});
const files = new Map(bundle.output.map((f) => ["/" + f.fileName, f.code ?? f.source]));
const assets = [...files.keys()].filter((p) => p.endsWith(".json"));
assert.equal(assets.length, 11);
assert.ok(!files.get("/entry.js").includes("Sociolinguistics"));
const html = '<!doctype html><html lang="ja"><meta charset="utf-8"><main id="fixture"></main><script type="module" src="./entry.js"></script></html>';
const accessed = [];
const server = createServer((req, res) => {
  const pathname = new URL(req.url, "http://localhost").pathname;
  if (!pathname.startsWith("/planner/")) return res.writeHead(404).end();
  const path = pathname.slice("/planner".length);
  accessed.push(path);
  if (path === "/") return res.writeHead(200, { "Content-Type": "text/html" }).end(html);
  if (!files.has(path)) return res.writeHead(404).end();
  res.writeHead(200, { "Content-Type": path.endsWith(".json") ? "application/json" : "text/javascript" }).end(files.get(path));
});
await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
const origin = "http://127.0.0.1:" + server.address().port;
let browser;
try {
  browser = await chromium.launch({ channel: process.env.CHROME_CHANNEL ?? "chrome", headless: true, chromiumSandbox: true });
  const page = await browser.newPage({ viewport: { width: 375, height: 800 } });
  const errors = [], external = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("request", (req) => { if (new URL(req.url()).origin !== origin) external.push(req.url()); });
  await page.goto(origin + "/planner/");
  const show = (...specs) => page.evaluate((courses) => window.showCourses(...courses), specs);
  const countAssets = () => accessed.filter((p) => assets.includes(p)).length;
  assert.equal(countAssets(), 0);
  await show(["08", "260DS217", "2025"]);
  await page.getByText(/この年度・開講番号/).waitFor();
  assert.equal(countAssets(), 0);
  await show(["08", "260DS217", "2026"], ["84", "261G3008", "2026", true]);
  await page.getByText("Written examination 75% ／ participation in class discussions 25%").waitFor();
  const dialog = page.getByRole("dialog");
  await dialog.getByText("課題レポート").waitFor();
  assert.equal(await dialog.getByText("原則対面").count(), 1);
  assert.equal(await page.getByRole("link", { name: "260DS217の公式シラバス" }).getAttribute("href"),
    "https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/08/08_260DS217_ja_JP.html");
  assert.equal(countAssets(), 2);
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  await show(["84", "261G7011", 2026], ["84", "261G9999", 2026]);
  await page.getByText(/この授業の比較項目は未収録/).waitFor();
  await page.getByText("この授業の比較用データは未収録です。").waitFor();
  assert.equal(countAssets(), 2);

  // Stale faculty fetch completion must not replace a newly selected course.
  let release, started;
  const delayed = new Promise((resolve) => { started = resolve; });
  await page.route("**/2026-09*.json", async (route) => {
    await new Promise((resolve) => { release = resolve; started(); });
    await route.continue();
  });
  await show(["09", "260T0017", 2026]);
  await delayed;
  await show(["01", "260H2049", 2026]);
  const english = page.getByRole("link", { name: "260H2049の公式シラバス" });
  await english.waitFor();
  assert.match(await english.getAttribute("href"), /_en_US\.html$/);
  const downloaded = page.waitForResponse((response) => response.url().includes("/2026-09"));
  release();
  await (await downloaded).finished();
  assert.equal(await english.count(), 1);
  await show(["09", "260T0017", 2026]);
  await page.getByText("オンデマンド型授業").waitFor();
  assert.equal(await page.getByText("英語", { exact: true }).count(), 1);

  // A malformed local asset and a failed fetch both release the cache for a manual retry.
  let attempts = 0;
  await page.route("**/2026-07*.json", async (route) => {
    attempts++;
    if (attempts === 1) return route.fulfill({ json: { year: "2026", department: "07", courses: { "260M1101": { weights: "invalid" } } } });
    if (attempts === 2) return route.fulfill({ status: 503, body: "" });
    return route.continue();
  });
  await show(["07", "260M1101", 2026]);
  const retry = page.getByRole("button", { name: "再読み込み" });
  await retry.click();
  await retry.click();
  await page.getByText("多職種連携協働、地域医療").waitFor();
  assert.equal(attempts, 3);
  assert.deepEqual(errors, []);
  assert.deepEqual(external, []);
  console.log("Chrome: production lazy packs, mobile comparison and dialog, source locale, sparse/missing record, wrong year, stale fetch, malformed pack and HTTP retry passed.");
} finally {
  await browser?.close();
  server.close();
}
