// Exercise the independently owned panel from its compiled production module on an isolated random port.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";
import { build } from "vite";

const root = fileURLToPath(new URL("../", import.meta.url));
const entry = "archive-panel-entry";
const bundle = await build({
  root, base: "./", configFile: false, logLevel: "error",
  plugins: [{
    name: "archive-test-entry",
    resolveId(id) { if (id === entry) return "\0" + id; },
    load(id) {
      if (id !== "\0" + entry) return;
      return `import React from "react";
        import {createRoot} from "react-dom/client";
        import Panel from "/src/archive/HistoricalMatchPanel.jsx";
        import {matchHistoricalGrades} from "/src/archive/packs.mjs";
        const old = location.hash === "#old";
        const historical = location.hash.startsWith("#2020");
        const grade = historical ? { id:"annual", year:"2020", code:"200G0105", title:"実践コミュニケーション英語I",
          term:"第1,2ターム", credits:location.hash.endsWith("-3") ? 3 : 1, grade:"優" } :
          { id:"synthetic", title:old ? "年度資料の科目" : "英語基礎 L", credits:1, year:old ? "2011" : "2025" };
        async function show() {
          const row = historical ? (await matchHistoricalGrades([grade]))[0] : grade;
          window.imported = row;
          createRoot(document.getElementById("app")).render(React.createElement(Panel,{grade:row, onConfirm: match => window.result = match}));
        }
        show();`;
    },
  }],
  build: { write: false, rollupOptions: { input: entry, output: { entryFileNames: "entry.js" } } },
});
const files = new Map(bundle.output.map((chunk) => ["/" + chunk.fileName, chunk.code ?? chunk.source]));
const html = '<!doctype html><meta charset="utf-8"><div id="app"></div><script type="module" src="./entry.js"></script>';
const accessed = [];
const server = createServer((req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;
  accessed.push(path);
  if (path === "/") return res.writeHead(200, { "Content-Type": "text/html" }).end(html);
  if (!files.has(path)) return res.writeHead(404).end();
  res.writeHead(200, { "Content-Type": path.endsWith(".json") ? "application/json" : "text/javascript" }).end(files.get(path));
});
await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
const base = "http://127.0.0.1:" + server.address().port;
let browser;
try {
  browser = await chromium.launch({ channel: process.env.CHROME_CHANNEL ?? "chrome", headless: true, chromiumSandbox: true });
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (err) => errors.push(err.message));
  await page.goto(base);
  const picker = page.getByLabel("履修した授業", { exact: true });
  await picker.waitFor({ timeout: 10000 }).catch(async (error) => {
    throw Error([error.message, await page.locator("body").innerText(), JSON.stringify(errors),
      JSON.stringify(accessed)].join("\n"));
  });
  const button = page.getByRole("button", { name: "この授業との対応を保存" });
  assert.equal(await button.count(), 0);
  await picker.selectOption("1");
  const official = page.getByRole("link", { name: "この年度の公式シラバス" });
  const selected = await official.getAttribute("href");
  assert.match(selected, /\/2025\/84\/84_25\dG/);
  await button.click();
  await page.getByText("照合済み", { exact: true }).waitFor();
  const result = await page.evaluate(() => window.result);
  assert.equal(result.sourceUrl, selected);
  assert.deepEqual(result.fields, ["70"]);
  assert.equal(result.confirmed, true);
  assert.equal(accessed.filter((p) => p.endsWith(".json")).length, 1);
  await page.goto(base + "/#2020");
  await page.reload();
  await page.getByText("照合済み", { exact: true }).waitFor();
  const printed = page.getByRole("link", { name: "単位数の出典（授業科目開設一覧）" });
  assert.equal(await printed.getAttribute("href"), "https://www.iess.niigata-u.ac.jp/pdf/subject_list_2020/all.pdf#page=10");
  assert.equal(await official.getAttribute("href"), "https://syllabus.niigata-u.ac.jp/syllabusHtml/2020/84/84_200G0105_ja_JP.html");
  assert.deepEqual(await page.evaluate(() => window.imported.matchedCourse.fields), ["70"]);
  await page.goto(base + "/#2020-3");
  await page.reload();
  await page.getByText(/授業の開講情報が一致しません/).waitFor();
  assert.deepEqual(await page.evaluate(() => [window.imported.credits, window.imported.matchedCourse]), [3, null]);
  assert.equal(await button.count(), 0);
  assert.equal(await picker.count(), 0);
  await page.goto(base + "/#old");
  await page.reload();
  await page.getByText(/この年度の全学索引はありません/).waitFor();
  await page.getByText("履修当時の資料から確認する", { exact: true }).click();
  const url = "https://syllabus.niigata-u.ac.jp/syllabusHtml/2011/01/01_110H0001_ja_JP.html";
  const rows = [["科目名／Course Title","年度資料の科目／Old course"], ["開講番号","110H0001"],
    ["開講学期","2011年度／Academic Year"], ["分野","29：文学、30：言語学"], ["科目区分","人文社会・教育科学　人文科学"]];
  const file = '<img src="/should-never-load"><script>window.executed=true</script><table>' +
    rows.map(([k,v]) => '<tr><th>'+k+'</th><td>'+v+'</td></tr>').join("") + '</table>';
  const input = page.getByLabel("公開シラバスのHTML");
  await input.setInputFiles({ name: "01_110H0001_ja_JP.html", mimeType: "text/html", buffer: Buffer.from(file) });
  const source = page.getByLabel("元の公式シラバスURL");
  await source.fill(url.replace("/2011/", "/2026/"));
  await page.getByRole("button", { name: "資料の記載を照合" }).click();
  await page.getByRole("alert").waitFor();
  assert.equal(await button.count(), 0);
  await source.fill(url.replace("/01/01_", "/03/03_"));
  await page.getByRole("button", { name: "資料の記載を照合" }).click();
  await page.getByRole("alert").waitFor();
  assert.equal(await button.count(), 0);
  await source.fill(url);
  await page.getByRole("button", { name: "資料の記載を照合" }).click();
  await button.click();
  await page.getByText("照合済み", { exact: true }).waitFor();
  const saved = await page.evaluate(() => window.result);
  assert.deepEqual(saved.fields, ["29", "30"]);
  assert.equal(saved.fieldSource, url);
  assert.equal(saved.sourceKind, "saved-syllabus");
  assert.equal(await page.evaluate(() => window.executed), undefined);
  assert.ok(!accessed.includes("/should-never-load"));
  assert.deepEqual(errors, []);
  console.log("Compiled panel: lazy year packs, 2020 exact and conflicting credits, namesake choice, missing year and local HTML confirmation passed.");
} finally {
  await browser?.close();
  server.close();
}
