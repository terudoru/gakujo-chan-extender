// Focused Playwright browser verification for CandidateOverlaps with real Meta Astryx Neutral theme.
import assert from "node:assert/strict";
import { withBrowserHarness } from "./browser-harness.mjs";

const HARNESS_HTML = `<!doctype html>
<html lang="ja">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>CandidateOverlaps Harness</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/@overlaps-harness.jsx"></script>
  </body>
</html>`;

const HARNESS_ENTRY = `
import React, { useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { Theme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral/built";
import "/src/planner.css";
import { buildCandidateMeetings } from "/src/components/candidate-overlaps.mjs";
import { CandidateOverlaps } from "/src/components/CandidateOverlaps.jsx";
import { commonCourses } from "/test/candidate-overlap-fixtures.mjs";

const COURSES = [
  ...commonCourses,
  {
    code: "261S0005",
    title: "サンプル集中講義",
    semester: "第1学期",
    period: "集中",
    schedule: "他",
  },
];

const LISTS = [
  {
    id: "mine",
    name: "履修候補",
    codes: ["261S0001", "261S0002", "262S0003", "260S0004", "261S0005"],
  },
  {
    id: "copied",
    name: "履修候補（コピー）",
    codes: ["261S0002", "260S0004"],
  },
];

function App() {
  const [opened, setOpened] = useState([]);
  const byCode = useMemo(() => new Map(COURSES.map((c) => [c.code, c])), []);
  const index = useMemo(() => buildCandidateMeetings(LISTS, byCode), [byCode]);
  window.__OPENED_CODES__ = opened;

  return (
    <Theme theme={neutralTheme}>
      <main className="work-main" style={{ paddingBlock: "16px" }}>
        <section className="page-content">
          <ul className="result-list">
            {COURSES.map((course) => (
              <li key={course.code} data-course={course.code}>
                <div>
                  <strong>{course.title}</strong>
                  <small>{course.code}</small>
                  <CandidateOverlaps
                    course={course}
                    index={index}
                    onOpenCourse={(other) => {
                      setOpened((prev) => {
                        const next = [...prev, other.code];
                        window.__OPENED_CODES__ = next;
                        return next;
                      });
                    }}
                  />
                </div>
              </li>
            ))}
          </ul>
        </section>
      </main>
    </Theme>
  );
}

createRoot(document.getElementById("root")).render(<App />);
`;

await withBrowserHarness({
  name: "candidate-overlaps-harness",
  pagePath: "/overlaps.html",
  entryPath: "/@overlaps-harness.jsx",
  html: HARNESS_HTML,
  entry: HARNESS_ENTRY,
  viewport: { width: 1440, height: 930 },
}, async ({ page, url, errors }) => {
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
  await page.locator('[data-course="261S0002"] details.candidate-overlaps').waitFor({
    timeout: 30000,
  });

  // Intensive/unknown course must render no overlap disclosure
  assert.equal(
    await page.locator('[data-course="261S0005"] details.candidate-overlaps').count(),
    0,
  );

  // Lazy DOM check: when collapsed, ZERO detail <li> items exist in the DOM
  assert.equal(
    await page.locator("details.candidate-overlaps li").count(),
    0,
    "Detailed overlap list items must not exist in DOM before expansion",
  );

  // Keyboard toggle via Enter on summary for 261S0002 (overlaps 261S0001 and 260S0004)
  const details = page.locator('[data-course="261S0002"] details.candidate-overlaps');
  const summary = details.locator("summary");
  assert.equal(await summary.innerText(), "他の候補と2件重複");
  await summary.focus();
  await page.keyboard.press("Enter");

  await details.locator("li").nth(1).waitFor();
  assert.equal(await details.locator("li").count(), 2);
  const expandedText = await details.innerText();
  assert.match(expandedText, /サンプル通期演習/);
  assert.match(expandedText, /第1ターム · 月曜2限・木曜2限で重複/);
  assert.match(expandedText, /履修候補・履修候補（コピー）/);
  assert.match(expandedText, /サンプル線形代数A/);
  assert.match(expandedText, /第1ターム · 月曜2限で重複/);

  // Clicking overlapping candidate title opens parent course details
  await details.getByRole("button", { name: "サンプル線形代数A", exact: true }).click();
  assert.deepEqual(
    await page.evaluate(() => window.__OPENED_CODES__),
    ["261S0001"],
  );

  // Term 2 course (262S0003) only overlaps 260S0004 (term 1,2), NOT term 1 courses
  const term2Details = page.locator('[data-course="262S0003"] details.candidate-overlaps');
  assert.equal(await term2Details.locator("summary").innerText(), "他の候補と1件重複");

  // Narrow mobile overflow check with expanded disclosure
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
    "CandidateOverlaps must not overflow narrow mobile viewport",
  );

  // Collapsing via Space removes detail DOM nodes cleanly
  await summary.focus();
  await page.keyboard.press("Space");
  await details.locator("li").first().waitFor({ state: "detached" });
  assert.equal(await details.locator("li").count(), 0);

  assert.deepEqual(errors, [], `Unexpected page errors: ${errors.join("; ")}`);
  console.log(
    "CandidateOverlaps browser check passed: keyboard disclosure, lazy DOM expansion/collapse, deduplication, click-to-open, desktop and mobile.",
  );
});
