// Focused Playwright browser verification for ProfileSettings yearAttendanceMonths,
// assessmentDate leap-day validation, yearOfStudy > 12, and diff-based survival of competing updates.
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
    <title>ProfileSettings Diff & Date Harness</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/@profile-diff-harness.jsx"></script>
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

function Harness() {
  const liveRef = useRef(null);
  if (!liveRef.current) {
    const s = initialState();
    s.profile = {
      faculty: "工学部",
      program: "融合領域分野",
      entry: "1年次入学",
      admitted: "2024",
      handbook: "2024",
      yearOfStudy: "3",
      attendanceMonths: "24",
      gpa: "3.2",
      cap: "",
      assessmentDate: "",
      yearAttendanceMonths: { "1": 12 },
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
      window.__LATEST_STATE__ = structuredClone(next);
      return true;
    } catch (e) {
      setError(e.message ?? "エラー");
      return false;
    }
  }

  window.__SYNC_API__ = {
    applyCompetingSync: () => {
      liveRef.current.profile.gpa = "3.9";
      liveRef.current.profile.attendanceMonths = "30";
      liveRef.current.profile.legacyNote = "keep-me";
      liveRef.current.profile.yearAttendanceMonths = {
        ...liveRef.current.profile.yearAttendanceMonths,
        "2": 12,
        legacyYear: 6,
      };
    },
    getLatestProfile: () => structuredClone(liveRef.current.profile),
  };

  return (
    <Theme theme={neutralTheme}>
      <PlannerError.Provider value={error}>
        <main className="work-main" style={{ paddingBlock: "16px" }}>
          <button type="button" onClick={() => setOpen(true)}>
            OpenProfile
          </button>
          {open && (
            <ProfileSettings
              state={state}
              mutate={mutate}
              close={() => setOpen(false)}
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
  name: "profile-diff-harness",
  configureServer(server) {
    server.middlewares.use((req, res, next) => {
      if (req.url === "/profile-diff.html") {
        server
          .transformIndexHtml("/profile-diff.html", HARNESS_HTML)
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
    if (id === "/@profile-diff-harness.jsx") return id;
    return null;
  },
  load(id) {
    if (id === "/@profile-diff-harness.jsx") return HARNESS_ENTRY;
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
const url = `http://127.0.0.1:${address.port}/profile-diff.html`;

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

  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
  const dialog = page.getByRole("dialog", { name: "所属・適用便覧" });
  await dialog.waitFor({ timeout: 30000 });

  // Open the compact disclosure for per-year attendance months & assessment date
  const disclosureSummary = dialog.locator("details.pf-disclosure > summary", {
    hasText: "年次別の在学月数・判定基準日",
  });
  await disclosureSummary.click();
  await dialog.getByLabel("判定基準日（YYYY-MM-DD）").waitFor();

  // Invalid non-leap date (2026-02-29) must fail validation and keep dialog open
  await dialog.getByLabel("判定基準日（YYYY-MM-DD）").fill("2026-02-29");
  await dialog.getByRole("button", { name: "設定を保存", exact: true }).click();
  await dialog.getByRole("alert").filter({ hasText: "YYYY-MM-DD" }).waitFor();
  assert.equal(await dialog.isVisible(), true);

  // Enter valid leap day (2024-02-29), yearOfStudy > 12 ("14"), and year 3 = true zero "0"
  await dialog.getByLabel("判定基準日（YYYY-MM-DD）").fill("2024-02-29");
  await dialog.getByLabel("現在の年次").fill("14");
  await dialog.getByLabel("3年次の在学月数").fill("0");
  // Leave year 2, year 4, total attendanceMonths, and gpa UNEDITED!

  // Simulate competing sync update to year 2, total attendance, gpa, and legacy fields while dialog is open
  await page.evaluate(() => window.__SYNC_API__.applyCompetingSync());

  // Check narrow mobile layout with disclosure open before saving
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
    "ProfileSettings with expanded disclosure must not overflow narrow mobile viewport",
  );
  await page.setViewportSize({ width: 1440, height: 930 });

  await dialog.getByRole("button", { name: "設定を保存", exact: true }).click();
  await dialog.waitFor({ state: "hidden" });

  const saved = await page.evaluate(() =>
    window.__SYNC_API__.getLatestProfile(),
  );
  assert.equal(saved.assessmentDate, "2024-02-29");
  assert.equal(saved.yearOfStudy, "14");
  assert.equal(saved.attendanceMonths, "30"); // competing sync survived
  assert.equal(saved.gpa, "3.9"); // competing sync survived
  assert.equal(saved.legacyNote, "keep-me"); // unknown/legacy preserved
  assert.deepEqual(saved.yearAttendanceMonths, {
    "1": 12,
    "2": 12, // competing update in different year survived!
    "3": 0, // user's edit saved as true zero
    legacyYear: 6, // unknown/legacy key inside mapping preserved
  });
  assert.strictEqual(saved.yearAttendanceMonths["3"], 0);
  assert.equal(Object.hasOwn(saved.yearAttendanceMonths, "4"), false);

  assert.deepEqual(errors, [], `Unexpected page errors: ${errors.join("; ")}`);
  console.log(
    "ProfileSettings browser check passed: leap-day validation, yearOfStudy > 12, true zero vs empty, and competing sync survival across years and owned fields on desktop and mobile.",
  );
} finally {
  await browser?.close();
  await viteServer.close();
}
