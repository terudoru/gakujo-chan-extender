// Focused 390px mobile + keyboard Playwright verification for CourseEvidenceForm in Meta Astryx Neutral.
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
    <title>CourseEvidenceForm Harness</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/@course-evidence-harness.jsx"></script>
  </body>
</html>`;

const HARNESS_ENTRY = `
import React, { useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Theme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral/built";
import "/src/planner.css";
import { CourseEvidenceForm } from "/src/components/CourseEvidenceForm.jsx";

function Harness() {
  const [faculty, setFaculty] = useState("");
  const [nextOk, setNextOk] = useState(true);
  const [grade, setGrade] = useState({
    code: "261S0001",
    title: "サンプル確認科目",
    year: "2026",
    credits: 2,
    legacyOffering: "night",
    customNote: "keep-me",
  });
  const callsRef = useRef([]);

  async function handleSave(diff) {
    callsRef.current.push(structuredClone(diff));
    window.__EVIDENCE_CALLS__ = structuredClone(callsRef.current);
    await new Promise((r) => setTimeout(r, 20));
    if (!nextOk) return false;
    setGrade((prev) => {
      const next = { ...prev };
      for (const [k, v] of Object.entries(diff)) {
        if (v === null) delete next[k];
        else next[k] = v;
      }
      window.__EVIDENCE_GRADE__ = structuredClone(next);
      return next;
    });
    return true;
  }

  window.__EVIDENCE_API__ = {
    setFaculty,
    setGrade: (next) => {
      window.__EVIDENCE_GRADE__ = structuredClone(next);
      setGrade(structuredClone(next));
    },
    setNextOk,
    clearCalls: () => {
      callsRef.current = [];
      window.__EVIDENCE_CALLS__ = [];
    },
  };
  window.__EVIDENCE_GRADE__ = structuredClone(grade);
  window.__EVIDENCE_CALLS__ = structuredClone(callsRef.current);

  return (
    <Theme theme={neutralTheme}>
      <main className="work-main" style={{ paddingBlock: "12px" }}>
        <section className="page-content">
          <CourseEvidenceForm
            grade={grade}
            faculty={faculty}
            onSave={handleSave}
          />
        </section>
      </main>
    </Theme>
  );
}

createRoot(document.getElementById("root")).render(<Harness />);
`;

const virtualPlugin = {
  name: "course-evidence-harness",
  configureServer(server) {
    server.middlewares.use((req, res, next) => {
      if (req.url === "/course-evidence.html") {
        server
          .transformIndexHtml("/course-evidence.html", HARNESS_HTML)
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
    if (id === "/@course-evidence-harness.jsx") return id;
    return null;
  },
  load(id) {
    if (id === "/@course-evidence-harness.jsx") return HARNESS_ENTRY;
    return null;
  },
};

const viteServer = await createServer({
  root,
  server: { host: "127.0.0.1", port: 0, strictPort: false, hmr: false },
  logLevel: "error",
  plugins: [virtualPlugin],
});
await viteServer.listen();
const address = viteServer.httpServer.address();
const url = `http://127.0.0.1:${address.port}/course-evidence.html`;

let browser;
try {
  browser = await chromium.launch({
    channel: process.env.CHROME_CHANNEL ?? "chrome",
    headless: true,
    chromiumSandbox: true,
  });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
  });
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));

  const assertNoOverflow = async (label) => {
    assert.equal(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
      true,
      `Horizontal overflow at 390px during ${label}`,
    );
  };

  await page.goto(url, { waitUntil: "commit", timeout: 30000 });
  const summary = page.locator("details.pf-disclosure > summary");
  await summary.waitFor({ timeout: 30000 });
  assert.match(await summary.innerText(), /科目ごとの確認事項/);

  // Keyboard open via Enter
  await summary.focus();
  await page.keyboard.press("Enter");
  const studyYearInput = page.getByLabel("履修時の年次（西暦ではなく学年）");
  await studyYearInput.waitFor();
  const saveBtn = page.getByRole("button", { name: "確認事項を保存", exact: true });

  // Unidentified faculty shows studyYear only and keeps save disabled until edited
  assert.equal(await page.locator(".pf-tristate [role='group']").count(), 0);
  assert.equal(await saveBtn.isDisabled(), true);
  assert.match(await page.locator("details.pf-disclosure").innerText(), /成績確認表|シラバス/);

  // Validation rejects 0, negative, decimal, and calendar year 2026
  for (const bad of ["0", "-1", "2.5", "2026"]) {
    await studyYearInput.fill(bad);
    await saveBtn.click();
    await page.getByRole("alert").waitFor();
    assert.equal((await page.evaluate(() => window.__EVIDENCE_CALLS__)).length, 0);
  }

  // Draft-only: typing valid "3" does not save until explicit Save click; async false preserves draft
  await studyYearInput.fill("3");
  assert.equal((await page.evaluate(() => window.__EVIDENCE_CALLS__)).length, 0);
  await page.evaluate(() => window.__EVIDENCE_API__.setNextOk(false));
  await saveBtn.click();
  await page.waitForFunction(() => window.__EVIDENCE_CALLS__.length === 1);
  assert.equal(await studyYearInput.inputValue(), "3");
  assert.equal(await saveBtn.isDisabled(), false);

  // Explicit save with ok=true emits ONLY { studyYear: 3 } and preserves hidden legacyOffering & customNote
  await page.evaluate(() => {
    window.__EVIDENCE_API__.clearCalls();
    window.__EVIDENCE_API__.setNextOk(true);
  });
  await saveBtn.click();
  await page.waitForFunction(() => window.__EVIDENCE_GRADE__.studyYear === 3);
  assert.deepEqual(await page.evaluate(() => window.__EVIDENCE_CALLS__), [
    { studyYear: 3 },
  ]);
  let currentGrade = await page.evaluate(() => window.__EVIDENCE_GRADE__);
  assert.equal(currentGrade.legacyOffering, "night");
  assert.equal(currentGrade.customNote, "keep-me");
  assert.equal(await saveBtn.isDisabled(), true);

  // Clearing studyYear emits { studyYear: null }
  await page.evaluate(() => window.__EVIDENCE_API__.clearCalls());
  await studyYearInput.fill("");
  await saveBtn.click();
  await page.waitForFunction(() => !Object.hasOwn(window.__EVIDENCE_GRADE__, "studyYear"));
  assert.deepEqual(await page.evaluate(() => window.__EVIDENCE_CALLS__), [
    { studyYear: null },
  ]);

  // --- Old economics (経済学部（旧課程）): legacyOffering day/night + exchangeWithoutLeave ---
  await page.evaluate(() => {
    window.__EVIDENCE_API__.clearCalls();
    window.__EVIDENCE_API__.setFaculty("経済学部（旧課程）");
  });
  const offeringGroup = page.getByRole("group", { name: /昼間主・夜間主/ });
  await offeringGroup.waitFor();
  assert.equal(
    await offeringGroup.getByRole("button", { name: "夜間主", exact: true }).getAttribute("aria-pressed"),
    "true",
  );
  // Keyboard toggle via Space on 昼間主 and click なし on exchangeWithoutLeave
  const dayBtn = offeringGroup.getByRole("button", { name: "昼間主", exact: true });
  await dayBtn.focus();
  await page.keyboard.press("Space");
  await page
    .getByRole("group", { name: /休学せず協定校/ })
    .getByRole("button", { name: "なし", exact: true })
    .click();
  await assertNoOverflow("経済学部（旧課程）");
  await saveBtn.click();
  await page.waitForFunction(() => window.__EVIDENCE_GRADE__.legacyOffering === "day");
  assert.deepEqual(await page.evaluate(() => window.__EVIDENCE_CALLS__), [
    { legacyOffering: "day", exchangeWithoutLeave: false },
  ]);

  // Clear ONLY legacyOffering -> emits { legacyOffering: null } without resaving exchangeWithoutLeave
  await page.evaluate(() => window.__EVIDENCE_API__.clearCalls());
  await offeringGroup.getByRole("button", { name: "未設定", exact: true }).click();
  await saveBtn.click();
  await page.waitForFunction(() => !Object.hasOwn(window.__EVIDENCE_GRADE__, "legacyOffering"));
  assert.deepEqual(await page.evaluate(() => window.__EVIDENCE_CALLS__), [
    { legacyOffering: null },
  ]);
  assert.strictEqual(
    (await page.evaluate(() => window.__EVIDENCE_GRADE__)).exchangeWithoutLeave,
    false,
  );

  // --- Humanities (人文学部): all 7 tri-state fields, true/false/absent distinct ---
  await page.evaluate(() => {
    window.__EVIDENCE_API__.clearCalls();
    window.__EVIDENCE_API__.setGrade({
      code: "261H0001",
      title: "サンプル人文科目",
      year: "2026",
      credits: 2,
      languageOverlapApproved: true,
      openToAll: false,
      exchangeWithoutLeave: false, // hidden field from another faculty
    });
    window.__EVIDENCE_API__.setFaculty("人文学部");
  });
  await page.getByRole("group", { name: /同一外国語の重複履修許可/ }).waitFor();
  assert.equal(await page.locator(".pf-tristate [role='group']").count(), 7);
  assert.equal(
    await page
      .getByRole("group", { name: /同一外国語の重複履修許可/ })
      .getByRole("button", { name: "あり", exact: true })
      .getAttribute("aria-pressed"),
    "true",
  );
  assert.equal(
    await page
      .getByRole("group", { name: /全学開放/ })
      .getByRole("button", { name: "なし", exact: true })
      .getAttribute("aria-pressed"),
    "true",
  );
  assert.equal(
    await page
      .getByRole("group", { name: /不定期開設/ })
      .getByRole("button", { name: "未設定", exact: true })
      .getAttribute("aria-pressed"),
    "true",
  );
  await page
    .getByRole("group", { name: /教職課程のみ対象科目/ })
    .getByRole("button", { name: "なし", exact: true })
    .click();
  await page
    .getByRole("group", { name: /不定期開設/ })
    .getByRole("button", { name: "あり", exact: true })
    .click();
  await assertNoOverflow("人文学部");
  await saveBtn.click();
  await page.waitForFunction(() => window.__EVIDENCE_GRADE__.irregular === true);
  assert.deepEqual(await page.evaluate(() => window.__EVIDENCE_CALLS__), [
    { teacherTrainingOnly: false, irregular: true },
  ]);
  currentGrade = await page.evaluate(() => window.__EVIDENCE_GRADE__);
  assert.strictEqual(currentGrade.languageOverlapApproved, true);
  assert.strictEqual(currentGrade.openToAll, false);
  assert.strictEqual(currentGrade.exchangeWithoutLeave, false); // hidden survived!

  // --- Economics (経済科学部): all 5 tri-state fields ---
  await page.evaluate(() => {
    window.__EVIDENCE_API__.clearCalls();
    window.__EVIDENCE_API__.setFaculty("経済科学部");
  });
  await page.getByRole("group", { name: /学部認定の自由科目/ }).waitFor();
  assert.equal(await page.locator(".pf-tristate [role='group']").count(), 5);
  await page
    .getByRole("group", { name: /学部認定の自由科目/ })
    .getByRole("button", { name: "あり", exact: true })
    .click();
  await page
    .getByRole("group", { name: /副専攻プログラムの入門科目/ })
    .getByRole("button", { name: "なし", exact: true })
    .click();
  await assertNoOverflow("経済科学部");
  await saveBtn.click();
  await page.waitForFunction(() => window.__EVIDENCE_GRADE__.facultyApprovedFree === true);
  assert.deepEqual(await page.evaluate(() => window.__EVIDENCE_CALLS__), [
    { facultyApprovedFree: true, minorIntro: false },
  ]);

  // --- Law (法学部): lawTrainingSection + teacherTrainingOnly ---
  await page.evaluate(() => {
    window.__EVIDENCE_API__.clearCalls();
    window.__EVIDENCE_API__.setFaculty("法学部");
  });
  await page.getByRole("group", { name: /法曹養成プログラム向け開講クラス/ }).waitFor();
  assert.equal(await page.locator(".pf-tristate [role='group']").count(), 2);
  await page
    .getByRole("group", { name: /法曹養成プログラム向け開講クラス/ })
    .getByRole("button", { name: "なし", exact: true })
    .click();
  await page
    .getByRole("group", { name: /教職課程のみ対象科目/ })
    .getByRole("button", { name: "未設定", exact: true })
    .click();
  await assertNoOverflow("法学部");
  await saveBtn.click();
  await page.waitForFunction(
    () => window.__EVIDENCE_GRADE__.lawTrainingSection === false,
  );
  assert.deepEqual(await page.evaluate(() => window.__EVIDENCE_CALLS__), [
    { lawTrainingSection: false, teacherTrainingOnly: null },
  ]);
  currentGrade = await page.evaluate(() => window.__EVIDENCE_GRADE__);
  assert.strictEqual(currentGrade.facultyApprovedFree, true); // hidden field preserved!

  assert.deepEqual(errors, [], `Unexpected page errors: ${errors.join("; ")}`);
  console.log(
    "CourseEvidenceForm 390px + keyboard check passed: studyYear validation, diff-only save/clear, true/false/absent distinctness, hidden field retention, and all faculty schemas.",
  );
} finally {
  await browser?.close();
  await viteServer.close();
}
