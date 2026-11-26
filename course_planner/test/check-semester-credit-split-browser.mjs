// Focused standalone browser verification for SemesterCreditSplit in Meta Astryx Neutral.
import assert from "node:assert/strict";
import { withBrowserHarness } from "./browser-harness.mjs";

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

  async function handleSave(splitOrNull, original) {
    callsRef.current.push({ course: course.code, arg: splitOrNull, original });
    window.__SPLIT_CALLS__ = [...callsRef.current];
    if (nextResult === "defer") {
      await new Promise((resolve) => { window.__FINISH_SPLIT__ = resolve; });
    }
    await new Promise((r) => setTimeout(r, 30));
    if (nextResult === "throw") throw null;
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

await withBrowserHarness({
  name: "semester-split-harness",
  pagePath: "/semester-split.html",
  entryPath: "/@semester-split-harness.jsx",
  html: HARNESS_HTML,
  entry: HARNESS_ENTRY,
  viewport: { width: 1440, height: 930 },
  optimizeDeps: { entries: [] },
}, async ({ page, url, errors }) => {
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

  // Rejected commits preserve inputs and pass the saved baseline on both actions.
  await page.evaluate(() => window.__SPLIT_HARNESS__.setNextResult("throw"));
  await clearBtn.click();
  await dialog.getByRole("alert").filter({ hasText: "クリアできませんでした。" }).waitFor();
  assert.equal(await firstInput.inputValue(), "0");
  assert.equal(await secondInput.inputValue(), "4");
  await firstInput.fill("1");
  await secondInput.fill("3");
  await saveBtn.click();
  await dialog.getByRole("alert").filter({ hasText: "保存できませんでした。" }).waitFor();
  assert.equal(await firstInput.inputValue(), "1");
  assert.equal(await secondInput.inputValue(), "3");
  assert.deepEqual(await page.evaluate(() => window.__SPLIT_CALLS__.slice(-2)), [
    { course: "260S0002", arg: null, original: { first: 0, second: 4 } },
    { course: "260S0002", arg: { first: 1, second: 3 }, original: { first: 0, second: 4 } },
  ]);

  // A saved split must stay with the originating course when its callback finishes late.
  await page.evaluate(() => window.__SPLIT_HARNESS__.setNextResult("defer"));
  await saveBtn.click();
  await page.waitForFunction(() => typeof window.__FINISH_SPLIT__ === "function");

  // Switch to course C (split: null): empty, never guessed halves
  await page.evaluate(() => window.__SPLIT_HARNESS__.setCourseKey("C"));
  await dialog.getByText(/第1学期 0・第2学期 4/).waitFor({ state: "detached" });
  await page.evaluate(() => window.__FINISH_SPLIT__());
  await page.waitForFunction(() => window.__SAVED_SPLITS__?.B?.first === 1);
  await saveBtn.waitFor();
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
    "SemesterCreditSplit browser check passed: validation, true 0, save/clear baselines and rejections, async completion after course switch, and narrow mobile layout.",
  );
});
