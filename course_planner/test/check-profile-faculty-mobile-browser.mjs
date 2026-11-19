// Mobile synthetic Playwright verification (390x844) for ProfileSettings:
// 0..5 GPA scale, conditional faculty disclosures, tri-state clearable booleans,
// supplied package program suggestions, and diff preservation of hidden/concurrent fields.
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
    <title>ProfileSettings Faculty Mobile Harness</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/@profile-faculty-mobile.jsx"></script>
  </body>
</html>`;

const HARNESS_ENTRY = `
import React, { useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Theme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral/built";
import "/src/planner.css";
import { initialState } from "/src/study.mjs";
import { ProfileSettings } from "/src/components/ProfileSettings.jsx";
import { PlannerError } from "/src/ui.jsx";

const SAMPLE_HANDBOOKS = [
  {
    faculty: "創生学部",
    year: "2026",
    title: "2026年度 サンプル創生学部便覧",
    url: "https://example.test/creation-2026.pdf",
    programs: ["サンプル創生コース", "サンプル創生コース（サンプルパッケージA）"],
  },
];

function Harness() {
  const liveRef = useRef(null);
  if (!liveRef.current) {
    const s = initialState();
    s.profile = {
      faculty: "法学部",
      program: "",
      entry: "1年次入学",
      admitted: "2026",
      handbook: "2026",
      yearOfStudy: "3",
      attendanceMonths: "24",
      gpa: "",
      cap: "",
    };
    liveRef.current = s;
  }
  const [state, setState] = useState(() => structuredClone(liveRef.current));
  const [open, setOpen] = useState(true);
  const [error, setError] = useState("");

  async function mutate(updater) {
    try {
      const next = structuredClone(liveRef.current);
      updater(next);
      liveRef.current = next;
      setState(structuredClone(next));
      setError("");
      return true;
    } catch (e) {
      setError(e.message ?? "エラー");
      return false;
    }
  }

  window.__MOBILE_PROFILE_API__ = {
    openDialog: () => {
      setState(structuredClone(liveRef.current));
      setOpen(true);
    },
    injectSync: (patch) => {
      Object.assign(liveRef.current.profile, patch);
    },
    getProfile: () => structuredClone(liveRef.current.profile),
  };

  return (
    <Theme theme={neutralTheme}>
      <PlannerError.Provider value={error}>
        <main className="work-main" style={{ paddingBlock: "12px" }}>
          <button type="button" onClick={() => setOpen(true)}>
            所属を設定
          </button>
          {open && (
            <ProfileSettings
              state={state}
              mutate={mutate}
              close={() => setOpen(false)}
              handbooks={SAMPLE_HANDBOOKS}
            />
          )}
        </main>
      </PlannerError.Provider>
    </Theme>
  );
}

createRoot(document.getElementById("root")).render(<Harness />);
`;

const virtualPlugin = {
  name: "profile-faculty-mobile-harness",
  configureServer(server) {
    server.middlewares.use((req, res, next) => {
      if (req.url === "/profile-faculty-mobile.html") {
        server
          .transformIndexHtml("/profile-faculty-mobile.html", HARNESS_HTML)
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
    if (id === "/@profile-faculty-mobile.jsx") return id;
    return null;
  },
  load(id) {
    if (id === "/@profile-faculty-mobile.jsx") return HARNESS_ENTRY;
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
const url = `http://127.0.0.1:${address.port}/profile-faculty-mobile.html`;

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

  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
  const dialog = page.getByRole("dialog", { name: "所属・適用便覧" });
  await dialog.waitFor({ timeout: 30000 });

  const assertNoOverflow = async (label) => {
    assert.equal(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
      true,
      `Horizontal overflow on 390px mobile during ${label}`,
    );
  };

  // --- 1. GPA 0..5 scale & 法学部 tri-state + thirdYearCumulativeGpa ---
  const gpaInput = dialog.getByLabel("前学期GPA");
  assert.equal(await gpaInput.getAttribute("placeholder"), "0〜5");
  await gpaInput.fill("5.1");
  await dialog.getByRole("button", { name: "設定を保存", exact: true }).click();
  await dialog.getByRole("alert").filter({ hasText: "0〜5" }).waitFor();

  await gpaInput.fill("4.5");
  const lawSummary = dialog.locator("details.pf-disclosure > summary", {
    hasText: "法学部の個別確認項目",
  });
  await lawSummary.click();
  await assertNoOverflow("法学部 disclosure");

  await dialog
    .getByRole("group", { name: "早期卒業を申請" })
    .getByRole("button", { name: "あり", exact: true })
    .click();
  await dialog
    .getByRole("group", { name: "D類履修の学部長特認" })
    .getByRole("button", { name: "なし", exact: true })
    .click();
  // Leave lawPaperSubstitutionApproved at 未設定 (absent)
  await dialog.getByLabel("3年次末累積GPA").fill("5");

  await dialog.getByRole("button", { name: "設定を保存", exact: true }).click();
  await dialog.waitFor({ state: "hidden" });

  let saved = await page.evaluate(() =>
    window.__MOBILE_PROFILE_API__.getProfile(),
  );
  assert.equal(saved.gpa, "4.5");
  assert.strictEqual(saved.earlyGraduation, true);
  assert.strictEqual(saved.deanException, false);
  assert.equal(Object.hasOwn(saved, "lawPaperSubstitutionApproved"), false);
  assert.strictEqual(saved.thirdYearCumulativeGpa, 5);

  // --- 2. Clear tri-state to absent while competing sync updates deanException & hidden iStepApproved ---
  await page.evaluate(() => window.__MOBILE_PROFILE_API__.openDialog());
  await dialog.waitFor();
  await dialog
    .locator("details.pf-disclosure > summary", {
      hasText: "法学部の個別確認項目",
    })
    .click();
  await dialog
    .getByRole("group", { name: "早期卒業を申請" })
    .getByRole("button", { name: "未設定", exact: true })
    .click();
  await page.evaluate(() =>
    window.__MOBILE_PROFILE_API__.injectSync({
      deanException: true,
      iStepApproved: true,
    }),
  );
  await dialog.getByRole("button", { name: "設定を保存", exact: true }).click();
  await dialog.waitFor({ state: "hidden" });

  saved = await page.evaluate(() =>
    window.__MOBILE_PROFILE_API__.getProfile(),
  );
  assert.equal(Object.hasOwn(saved, "earlyGraduation"), false);
  assert.strictEqual(saved.deanException, true);
  assert.strictEqual(saved.iStepApproved, true);

  // --- 3. 経済科学部 iStepApproved ---
  await page.evaluate(() => window.__MOBILE_PROFILE_API__.openDialog());
  await dialog.waitFor();
  await dialog.getByRole("combobox", { name: "学部・学科" }).click();
  await page.getByRole("option", { name: "経済科学部", exact: true }).click();
  await dialog
    .locator("details.pf-disclosure > summary", {
      hasText: "経済科学部の個別確認項目",
    })
    .click();
  await assertNoOverflow("経済科学部 disclosure");
  await dialog
    .getByRole("group", { name: "iStep振替の学務係への申出・確認" })
    .getByRole("button", { name: "なし", exact: true })
    .click();
  await dialog.getByRole("button", { name: "設定を保存", exact: true }).click();
  await dialog.waitFor({ state: "hidden" });

  saved = await page.evaluate(() =>
    window.__MOBILE_PROFILE_API__.getProfile(),
  );
  assert.equal(saved.faculty, "経済科学部");
  assert.strictEqual(saved.iStepApproved, false);
  // Hidden 法学部 fields survive faculty switch!
  assert.strictEqual(saved.deanException, true);
  assert.strictEqual(saved.thirdYearCumulativeGpa, 5);

  // --- 4. 医学部保健学科 + 編入 -> entryGrade ---
  await page.evaluate(() => window.__MOBILE_PROFILE_API__.openDialog());
  await dialog.waitFor();
  await dialog.getByRole("combobox", { name: "学部・学科" }).click();
  await page.getByRole("option", { name: "医学部保健学科", exact: true }).click();
  assert.equal(
    await dialog
      .locator("details.pf-disclosure > summary", {
        hasText: "医学部保健学科の個別確認項目",
      })
      .count(),
    0,
    "entryGrade disclosure must only show when entry is 編入",
  );
  await dialog.getByRole("combobox", { name: "入学区分" }).click();
  await page.getByRole("option", { name: "編入", exact: true }).click();
  await dialog
    .locator("details.pf-disclosure > summary", {
      hasText: "医学部保健学科の個別確認項目",
    })
    .click();
  await dialog.getByLabel("編入した年次").fill("3");
  await assertNoOverflow("医学部保健学科 編入 disclosure");
  await dialog.getByRole("button", { name: "設定を保存", exact: true }).click();
  await dialog.waitFor({ state: "hidden" });

  saved = await page.evaluate(() =>
    window.__MOBILE_PROFILE_API__.getProfile(),
  );
  assert.equal(saved.faculty, "医学部保健学科");
  assert.equal(saved.entry, "編入");
  assert.strictEqual(saved.entryGrade, 3);

  // --- 5. 創生学部 graduationYear/graduationMonth + supplied package program suggestions ---
  await page.evaluate(() => window.__MOBILE_PROFILE_API__.openDialog());
  await dialog.waitFor();
  await dialog.getByRole("combobox", { name: "学部・学科" }).click();
  await page.getByRole("option", { name: "創生学部", exact: true }).click();
  await dialog
    .getByRole("button", { name: "サンプル創生コース（サンプルパッケージA）" })
    .click();
  await dialog
    .locator("details.pf-disclosure > summary", {
      hasText: "創生学部の個別確認項目",
    })
    .click();
  await dialog.getByLabel("卒業予定（暦年）").fill("2027");
  await dialog
    .getByRole("group", { name: "標準の卒業月を選択" })
    .getByRole("button", { name: "3月", exact: true })
    .click();
  assert.equal(await dialog.getByLabel("卒業予定月").inputValue(), "3");
  // Other valid month (e.g. 6) also allowed
  await dialog.getByLabel("卒業予定月").fill("6");
  await assertNoOverflow("創生学部 disclosure");
  await dialog.getByRole("button", { name: "設定を保存", exact: true }).click();
  await dialog.waitFor({ state: "hidden" });

  saved = await page.evaluate(() =>
    window.__MOBILE_PROFILE_API__.getProfile(),
  );
  assert.equal(saved.faculty, "創生学部");
  assert.equal(saved.program, "サンプル創生コース（サンプルパッケージA）");
  assert.strictEqual(saved.graduationYear, 2027);
  assert.strictEqual(saved.graduationMonth, 6);
  assert.strictEqual(saved.entryGrade, 3); // hidden field survived!

  assert.deepEqual(errors, [], `Unexpected page errors: ${errors.join("; ")}`);
  console.log(
    "Mobile ProfileSettings faculty options check passed on 390x844: GPA 0..5, 法学部/経済科学部/医学部保健学科(編入)/創生学部 disclosures, tri-state clearable booleans, and hidden/concurrent diff preservation.",
  );
} finally {
  await browser?.close();
  await viteServer.close();
}
