// Run against the integrated planner. An optional project directory allows testing a separate import snapshot.
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";
import { build, preview } from "vite";

const root = process.argv[2] ? resolve(process.argv[2]) : fileURLToPath(new URL("../", import.meta.url));
const outDir = await mkdtemp(join(tmpdir(), "planner-archive-identity-"));
const title = "情報通信技術教育論I";
let server, browser;
try {
  const config = { root, logLevel: "error", build: { outDir, emptyOutDir: false } };
  await build(config);
  server = await preview({ ...config, preview: { host: "127.0.0.1", port: 0 } });
  const origin = "http://127.0.0.1:" + server.httpServer.address().port;
  browser = await chromium.launch({ channel: process.env.CHROME_CHANNEL || "chrome", chromiumSandbox: true });
  for (const [code, term, credits, expected] of [
    ["", "第4ターム", 3, null], ["261K0501", "第4ターム", 1, null],
    ["", "第1ターム", 3, null], ["", "第1ターム", 1, "261K0501"],
  ]) {
    const page = await browser.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.route("**/*", (route) => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
    await page.goto(origin);
    const nav = page.locator("nav:visible").getByRole("button", { name: "単位・要件", exact: true });
    const modal = page.getByRole("dialog");
    async function importRow() {
      await nav.waitFor();
      const rows = [["開講番号", "科目名", "履修年度", "学期", "単位数", "評価"],
        [code, title, "2026", term, String(credits), "優"]];
      await page.evaluate((rows) => window.dispatchEvent(new CustomEvent("mbg:planner-import", {
        detail: { v: 1, kind: "grades", tables: [{ heading: "成績確認表", rows }] },
      })), rows);
      await modal.getByRole("checkbox", { name: /情報通信技術教育論Iを取り込む/ }).check();
      await modal.getByRole("button", { name: "選択した1件を取り込む" }).click();
      await modal.waitFor({ state: "hidden" });
      return page.evaluate(() => JSON.parse(localStorage.getItem("mbg.course-planner.v1")).grades);
    }
    const [grade] = await importRow();
    assert.deepEqual([grade.code, grade.title, grade.term, grade.credits, grade.grade], [code, title, term, credits, "優"]);
    assert.equal(grade.matchedCourse?.code ?? null, expected, JSON.stringify(grade));
    assert.deepEqual(grade.fields, expected ? ["10"] : []);
    await nav.click();
    await page.getByRole("radio", { name: "シラバスの分野" }).click();
    const field = page.locator("summary").filter({ hasText: expected ? "10 情報" : "分野要確認" });
    await field.waitFor();
    assert.ok((await field.innerText()).includes("修得 " + credits));
    if (!expected) {
      assert.equal(await page.locator("summary").filter({ hasText: "10 情報" }).count(), 0);
      await page.getByRole("radio", { name: "修得履歴" }).click();
      await page.getByRole("button", { name: /シラバスを照合/ }).click();
      await modal.getByText(/学期・クラス・科目番号・単位数と、授業の開講情報が一致しません/).waitFor();
      assert.equal(await modal.getByRole("button", { name: "この授業との対応を保存" }).count(), 0);
      if (!code && term === "第4ターム") {
        // A document omitting the term and units cannot override contrary evidence for its known code.
        await modal.getByText("履修当時の資料から確認する", { exact: true }).click();
        const filename = "03_261K0501_ja_JP.html";
        const rows = [["科目名", title], ["開講学期", "2026年度"], ["開講番号", "261K0501"], ["分野", "10：情報"]];
        const html = "<table>" + rows.map(([k, v]) => "<tr><th>" + k + "</th><td>" + v + "</td></tr>").join("") + "</table>";
        await modal.getByLabel("元の公式シラバスURL").fill("https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/03/" + filename);
        await modal.getByLabel("公開シラバスのHTML").setInputFiles({ name: filename, mimeType: "text/html", buffer: Buffer.from(html) });
        await modal.getByRole("button", { name: "資料の記載を照合" }).click();
        await modal.getByRole("alert").waitFor();
        assert.equal(await modal.getByRole("button", { name: "この授業との対応を保存" }).count(), 0);
        // Reopen the exact pre-fix persisted correspondence through the transaction owner.
        await page.evaluate(() => {
          const key = "mbg.course-planner.v1", state = JSON.parse(localStorage.getItem(key));
          const g = state.grades[0];
          const saved = { year: g.year, title: g.title, code: "261K0501", department: "03",
            fields: ["10"], category: "人文社会・教育科学", confirmed: true, sourceKind: "syllabus",
            sourceUrl: "https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/03/03_261K0501_ja_JP.html" };
          Object.assign(g, { matchedCourse: saved, fields: saved.fields, department: saved.department, category: saved.category });
          localStorage.setItem(key, JSON.stringify(state));
        });
        await page.reload();
        const repaired = await importRow();
        assert.equal(repaired.length, 1);
        assert.deepEqual([repaired[0].matchedCourse, repaired[0].fields, repaired[0].credits], [null, [], 3]);
        assert.equal(repaired[0].importId, grade.importId);
        assert.equal(repaired[0].matchInvalidated, undefined);
      }
    }
    assert.deepEqual(errors, []);
    await page.close();
  }
  console.log("Chrome: confirmed imports, retained transcript units, field allocation and scoped review passed for four real-offering cases.");
} finally {
  await browser?.close();
  await server?.close();
  await rm(outDir, { recursive: true, force: true });
}
