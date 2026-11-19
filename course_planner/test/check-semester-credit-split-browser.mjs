// Focused standalone browser verification for SemesterCreditSplit in Meta Astryx Neutral.
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { createServer } from "vite";
import { chromium } from "playwright-core";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const HARNESS_HTML = `<!doctype html>
<html lang="ja">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>SemesterCreditSplit Harness</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/@semester-split-harness.jsx"></script>
  </body>
</html>`;

const HARNESS_ENTRY = `
import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import { Theme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral/built";
import "/src/planner.css";
import { Modal, PlannerError } from "/src/ui.jsx";
import { SemesterCreditSplit } from "/src/components/SemesterCreditSplit.jsx";

const COURSES = {
  A: { code: "260S0001", title: "サンプル通年演習A", period: "通年", credits: 2 },
  B: { code: "260S0002", title: "サンプル通年実習B", period: "通年", credits: 4 },
  C: { code: "260S0003", title: "サンプル通年講義C", period: "通年", credits: 4 },
};

function Harness() {
  const [courseKey, setCourseKey] = useState("A");
  const [tick, setTick] = useState(0);
  const [splits, setSplits] = useState({
    B: { first: 0, second: 4 },
  });
  const [nextResult, setNextResult] = useState(true);
  const [error, setError] = useState("");
  const callsRef = React.useRef([]);

  const course = { ...COURSES[courseKey] };
  const split =
    courseKey === "C"
      ? null
      : splits[courseKey]
        ? { ...splits[courseKey] }
        : undefined;

  async function handleSave(splitOrNull) {
    callsRef.current.push({ course: course.code, arg: splitOrNull });
    window.__SPLIT_CALLS__ = [...callsRef.current];
    await new Promise((r) => setTimeout(r, 30));
    if (!nextResult) {
      setError("別の操作で更新されました。もう一度確認してください。");
      return false;
    }
    setError("");
    setSplits((prev) => {
      const next = { ...prev };
      if (splitOrNull === null) delete next[courseKey];
      else next[courseKey] = splitOrNull;
      window.__SAVED_SPLITS__ = structuredClone(next);
      return next;
    });
    return true;
  }

  window.__SPLIT_HARNESS__ = {
    setCourseKey,
    bumpRender: () => setTick((t) => t + 1),
    setNextResult,
    getCalls: () => [...callsRef.current],
    getSplits: () => structuredClone(splits),
  };
  window.__SAVED_SPLITS__ = structuredClone(splits);
  window.__SPLIT_CALLS__ = [...callsRef.current];

  return (
    <Theme theme={neutralTheme}>
      <PlannerError.Provider value={error}>
        <main className="work-main" data-tick={tick}>
          <Modal title="授業の詳細" close={() => {}}>
            <SemesterCreditSplit
              course={course}
              split={split}
              onSave={handleSave}
            />
          </Modal>
        </main>
      </PlannerError.Provider>
    </Theme>
  );
}

createRoot(document.getElementById("root")).render(<Harness />);
`;

const virtualPlugin = {
  name: "semester-split-harness",
  configureServer(server) {
    server.middlewares.use((req, res, next) => {
      if (req.url === "/semester-split.html") {
        server
          .transformIndexHtml("/semester-split.html", HARNESS_HTML)
          .then((html) => {
            res.statusCode = 200;
            res.setHeader("Content-Type", "text/html; charset=utf-8");
            res.end(html);
          })
          .catch(next);
        return;
      }
      next();
    });
  },
  resolveId(id) {
    if (id === "/@semester-split-harness.jsx") return id;
    return null;
  },
  load(id) {
    if (id === "/@semester-split-harness.jsx") return HARNESS_ENTRY;
    return null;
  },
};

const viteServer = await createServer({
  root,
  server: { host: "127.0.0.1", port: 0, strictPort: false, hmr: false },
  optimizeDeps: { entries: [] },
  logLevel: "error",
  plugins: [virtualPlugin],
});
await viteServer.listen();
const address = viteServer.httpServer.address();
const url = `http://127.0.0.1:${address.port}/semester-split.html`;

let browser;
try {
  browser = await chromium.launch({
    channel: process.env.CHROME_CHANNEL ?? "chrome",
    headless: true,
    chromiumSandbox: true,
  });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 930 },
  });
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));

  await page.goto(url, { waitUntil: "commit", timeout: 45000 });
  const dialog = page.getByRole("dialog", { name: "授業の詳細" });
  await dialog.waitFor({ timeout: 45000 });

  // Open native disclosure via keyboard
  const summary = dialog.locator("details > summary");
  assert.match(await summary.innerText(), /学期別のCAP算入単位/);
  await summary.focus();
  await page.keyboard.press("Enter");

  const firstInput = dialog.getByLabel("第1学期");
  const secondInput = dialog.getByLabel("第2学期");
  const saveBtn = dialog.getByRole("button", { name: "配分を保存", exact: true });
  const clearBtn = dialog.getByRole("button", { name: "配分をクリア", exact: true });

  // Missing split must start empty — never guesses halves (1 / 1)
  assert.equal(await firstInput.inputValue(), "");
  assert.equal(await secondInput.inputValue(), "");
  assert.match(await dialog.innerText(), /公式の配分/);

  // Reject one missing value
  await firstInput.fill("1");
  await saveBtn.click();
  await dialog.getByRole("alert").filter({ hasText: "両方" }).waitFor();
  assert.equal((await page.evaluate(() => window.__SPLIT_CALLS__)).length, 0);

  // Reject negative value
  await firstInput.fill("-1");
  await secondInput.fill("3");
  await saveBtn.click();
  await dialog.getByRole("alert").filter({ hasText: "0以上の数値" }).waitFor();

  // Reject wrong sum (naming the course)
  await firstInput.fill("1");
  await secondInput.fill("2");
  await saveBtn.click();
  await dialog.getByRole("alert").filter({ hasText: "サンプル通年演習A" }).waitFor();
  assert.equal((await page.evaluate(() => window.__SPLIT_CALLS__)).length, 0);

  // Unrelated parent re-renders preserve unsaved edits
  await firstInput.fill("0.5");
  await secondInput.fill("1.5");
  await page.evaluate(() => window.__SPLIT_HARNESS__.bumpRender());
  await page.evaluate(() => window.__SPLIT_HARNESS__.bumpRender());
  assert.equal(await firstInput.inputValue(), "0.5");
  assert.equal(await secondInput.inputValue(), "1.5");

  // Async onSave resolving false preserves unsaved edits
  await page.evaluate(() => window.__SPLIT_HARNESS__.setNextResult(false));
  await firstInput.fill("0");
  await secondInput.fill("2");
  await saveBtn.click();
  await dialog.getByRole("alert").filter({ hasText: "別の操作で更新" }).waitFor();
  assert.equal(await firstInput.inputValue(), "0");
  assert.equal(await secondInput.inputValue(), "2");
  await page.evaluate(() => window.__SPLIT_HARNESS__.bumpRender());
  assert.equal(await firstInput.inputValue(), "0");
  assert.equal(await secondInput.inputValue(), "2");

  // Async onSave resolving true saves true 0 cleanly
  await page.evaluate(() => window.__SPLIT_HARNESS__.setNextResult(true));
  await saveBtn.click();
  await page.waitForFunction(
    () => window.__SAVED_SPLITS__?.A?.first === 0 && window.__SAVED_SPLITS__?.A?.second === 2,
  );
  assert.deepEqual(
    await page.evaluate(() => window.__SAVED_SPLITS__.A),
    { first: 0, second: 2 },
  );
  assert.match(await summary.innerText(), /第1学期 0・第2学期 2/);

  // Clear when async onSave(null) returns false preserves current values
  await page.evaluate(() => window.__SPLIT_HARNESS__.setNextResult(false));
  await clearBtn.click();
  await dialog.getByRole("alert").filter({ hasText: "別の操作で更新" }).waitFor();
  assert.equal(await firstInput.inputValue(), "0");
  assert.equal(await secondInput.inputValue(), "2");

  // Clear passes null and resets inputs when resolving true
  await page.evaluate(() => window.__SPLIT_HARNESS__.setNextResult(true));
  await clearBtn.click();
  await page.waitForFunction(() => !window.__SAVED_SPLITS__?.A);
  assert.equal(await firstInput.inputValue(), "");
  assert.equal(await secondInput.inputValue(), "");
  assert.equal(
    await page.evaluate(() => window.__SPLIT_CALLS__.at(-1).arg),
    null,
  );

  // Dirty unsaved edit + validation error must refresh cleanly when course changes
  await firstInput.fill("99");
  await saveBtn.click();
  await dialog.getByRole("alert").waitFor();

  // Switch to course B (has split { first: 0, second: 4 }): true 0 shown, error cleared
  await page.evaluate(() => window.__SPLIT_HARNESS__.setCourseKey("B"));
  await dialog.getByText(/第1学期 0・第2学期 4/).waitFor();
  assert.equal(await firstInput.inputValue(), "0");
  assert.equal(await secondInput.inputValue(), "4");
  assert.equal(await dialog.getByRole("alert").count(), 0);

  // Switch to course C (split: null): empty, never guessed halves
  await page.evaluate(() => window.__SPLIT_HARNESS__.setCourseKey("C"));
  await dialog.getByText(/第1学期 0・第2学期 4/).waitFor({ state: "detached" });
  assert.equal(await firstInput.inputValue(), "");
  assert.equal(await secondInput.inputValue(), "");

  // Small mobile viewport (390x844) inside Modal: zero horizontal overflow
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
    "SemesterCreditSplit must not overflow narrow mobile viewport",
  );

  assert.deepEqual(errors, [], `Unexpected page errors: ${errors.join("; ")}`);
  console.log(
    "SemesterCreditSplit browser check passed: validation, true 0, no half guessing, clear null, async false preservation, course switch refresh, and narrow mobile layout.",
  );
} finally {
  await browser?.close();
  await viteServer.close();
}
