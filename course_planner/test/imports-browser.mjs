// node course_planner/test/imports-browser.mjs (Chrome, synthetic data only).
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { build, preview } from "vite";
import { chromium } from "playwright-core";

const root = fileURLToPath(new URL("../", import.meta.url));
const outDir = await mkdtemp(join(tmpdir(), "planner-imports-"));
let server, browser;
try {
  const config = {
    root,
    configFile: false,
    logLevel: "warn",
    build: {
      outDir,
      emptyOutDir: false,
      rollupOptions: { input: join(root, "test/imports-harness.html") },
    },
  };
  await build(config);
  server = await preview({
    ...config,
    preview: { host: "127.0.0.1", port: 0 },
  });
  const origin = "http://127.0.0.1:" + server.httpServer.address().port;
  browser = await chromium.launch({
    channel: process.env.CHROME_CHANNEL || "chrome",
    headless: true,
    chromiumSandbox: true,
  });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    locale: "ja-JP",
  });
  const page = await context.newPage(),
    errors = [],
    outgoing = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.route("**/*", (route) => {
    const req = route.request();
    if (new URL(req.url()).origin !== origin || req.method() !== "GET") {
      outgoing.push(req.method());
      return route.abort();
    }
    return route.continue();
  });
  await page.goto(origin + "/test/imports-harness.html");
  const readState = async () =>
    JSON.parse(await page.locator("#result").textContent());
  const modal = page.getByRole("dialog");
  const accept = () =>
    modal.getByRole("button", { name: "選択した1件を取り込む" }).click();
  const open = async (kind) => {
    await page.getByRole("button", { name: kind, exact: true }).click();
    await modal.waitFor();
  };
  const upload = (name, mimeType, buffer) =>
    modal.locator("input[type=file]").setInputFiles({ name, mimeType, buffer });
  const picked = () => modal.getByRole("checkbox", { name: /を取り込む/ });
  const pdfPage = await context.newPage();
  await pdfPage.setContent(
    '<meta charset="utf-8"><style>td,th{text-align:left;padding-right:22px}</style><h1>成績確認表</h1><table><tr><th>開講番号</th><th>科目名</th><th>単位数</th><th>評語</th><th>年度</th></tr><tr><td>261G7011</td><td>架空科目</td><td>1</td><td>良</td><td>2026</td></tr><tr><td></td><td>架空認定</td><td>2</td><td>認定</td><td>2025</td></tr></table>',
  );
  const pdf = await pdfPage.pdf();
  await pdfPage.close();
  await open("grades");
  await upload("確認用.pdf", "application/pdf", pdf);
  const earned = modal.getByRole("checkbox", { name: /架空科目を取り込む/ });
  await earned.waitFor();
  assert.equal(
    await modal.locator("input[type=file]").evaluate((input) => input.files[0]?.name),
    "確認用.pdf",
  );
  assert.ok(
    await modal.evaluate((dialog) => dialog.clientWidth <= window.innerWidth),
  );
  if (process.env.PLANNER_SHOTS) {
    await page.screenshot({
      path: join(process.env.PLANNER_SHOTS, "imports-review.png"),
      animations: "disabled",
    });
  }
  assert.equal(await earned.isChecked(), false);
  assert.equal((await readState()).grades.length, 0);
  await earned.check();
  await accept();
  await modal.waitFor({ state: "hidden" });
  assert.equal((await readState()).grades[0].matchedCourse.year, "2026");
  await open("registration");
  await upload(
    "履修状況.txt",
    "text/plain",
    Buffer.from("不許可となった科目\r\n開講番号\t科目名\r\n261G7011\t架空科目"),
  );
  await picked().check();
  await accept();
  await modal.waitFor({ state: "hidden" });
  assert.equal((await readState()).status["261G7011"], "不許可");
  await open("balances");
  await upload(
    "区分.csv",
    "text/csv",
    Buffer.from("区分,履修単位,既修得単位\n英語,22,2.5"),
  );
  await picked().check();
  await accept();
  await modal.waitFor({ state: "hidden" });
  assert.equal((await readState()).balances[0].current, 2.5);
  await page.evaluate(() => {
    const packet = {
      v: 1,
      kind: "registration",
      tables: [
        {
          heading: "許可された科目",
          rows: [
            ["開講番号", "科目名"],
            ["261G7011", "架空科目"],
          ],
        },
      ],
    };
    window.dispatchEvent(
      new CustomEvent("mbg:planner-import", { detail: packet }),
    );
  });
  await picked().waitFor();
  assert.equal((await readState()).status["261G7011"], "不許可");
  await picked().check();
  await accept();
  await modal.waitFor({ state: "hidden" });
  assert.equal((await readState()).status["261G7011"], "許可");
  await open("grades");
  await upload("不正.pdf", "application/pdf", Buffer.from("invalid"));
  await modal
    .getByRole("alert")
    .getByText("PDFの形式を確認してください。")
    .waitFor();
  assert.equal((await readState()).grades.length, 1);
  assert.deepEqual(errors, []);
  assert.deepEqual(outgoing, []);
  console.log(
    "Chrome: local PDF/CSV/TSV and native review, selective save, invalid PDF, zero external/upload requests.",
  );
} finally {
  await browser?.close();
  if (server) await server.close();
  if (dirname(outDir) === tmpdir())
    await rm(outDir, { recursive: true, force: true });
}
