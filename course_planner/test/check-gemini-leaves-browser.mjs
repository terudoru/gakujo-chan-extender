// Synthetic browser verification for Discovery + SyllabusFacts, ProfileSettings, and AcademicFields
// using real Meta Astryx Neutral theme and public catalog-2026.json without modifying unowned app files.
import assert from "node:assert/strict";
import { withBrowserHarness } from "./browser-harness.mjs";

const HARNESS_HTML = `<!doctype html>
<html lang="ja">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Gemini UI Leaves Harness</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/@harness-entry.jsx"></script>
  </body>
</html>`;

const HARNESS_ENTRY = `
import React, { useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { Theme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral/built";
import "/src/planner.css";
import catalog from "/src/catalog-2026.json";
import { initialState } from "/src/study.mjs";
import { Discovery } from "/src/Discovery.jsx";
import { ProfileSettings } from "/src/components/ProfileSettings.jsx";
import { AcademicFields } from "/src/components/AcademicFields.jsx";
import { PlannerError } from "/src/ui.jsx";

const SAMPLE_HANDBOOKS = [
  {
    faculty: "サンプル工学部",
    year: 2026,
    title: "2026年度 サンプル工学部便覧",
    url: "https://example.test/handbook-2026.pdf",
    programs: ["サンプル融合プログラム", "サンプル機械プログラム"],
  },
  {
    faculty: "サンプル工学部",
    year: 2022,
    title: "2022年度 サンプル工学部便覧",
    url: "https://example.test/handbook-2022.pdf",
    programs: ["サンプル旧課程プログラム"],
  },
];

const SAMPLE_FACULTIES = ["サンプル工学部", "サンプル農学部"];

const SAMPLE_FIELD_ROWS = [
  {
    field: "70",
    earned: 1,
    planned: 1,
    required: 4,
    remaining: 3,
    after: 2,
    source: { title: "サンプル規程リンク", url: "https://example.test/rule-70" },
    courses: [
      {
        column: "earned",
        course: {
          code: "261G7011",
          title: "英語基礎 L",
          year: "2025",
          credits: 1,
        },
      },
      {
        column: "planned",
        course: {
          code: "260G0017",
          title: "アカデミック英語入門L",
          year: "2026",
          credits: 1,
        },
      },
    ],
  },
  {
    field: "10",
    earned: 2,
    planned: 0,
    courses: [
      {
        column: "earned",
        course: {
          code: "261G3008",
          title: "エンジニアのためのデータサイエンス入門(融合領域分野)",
          year: "2026",
          credits: 2,
        },
      },
    ],
  },
  {
    field: "?",
    earned: 2,
    planned: 0,
    needsReview: true,
    courses: [
      {
        column: "earned",
        course: {
          code: "",
          title: "サンプル認定科目",
          year: "2024",
          credits: 2,
        },
      },
    ],
  },
];

function Harness() {
  const [mode, setMode] = useState("discovery");
  const [discContext, setDiscContext] = useState({});
  const [error, setError] = useState("");
  const [listId, setListId] = useState("mine");
  const [profileOpen, setProfileOpen] = useState(false);

  const liveRef = React.useRef(null);
  if (!liveRef.current) {
    const s = initialState();
    s.plan = ["261G3008"];
    s.profile = {
      faculty: "",
      program: "",
      admitted: "",
      handbook: "2026",
      entry: "1年次入学",
      gpa: "",
      cap: "",
      yearOfStudy: "",
      attendanceMonths: "",
    };
    liveRef.current = s;
  }
  const [state, setState] = useState(() => structuredClone(liveRef.current));
  const [events, setEvents] = useState([]);

  const byCode = useMemo(
    () => new Map(catalog.courses.map((c) => [c.code, c])),
    [],
  );
  const list = state.lists.find((l) => l.id === listId) ?? state.lists[0];

  async function mutate(updater) {
    try {
      const next = structuredClone(liveRef.current);
      updater(next);
      liveRef.current = next;
      setState(structuredClone(next));
      setError("");
      window.__HARNESS_STATE__ = structuredClone(next);
      return true;
    } catch (e) {
      setError(e.message ?? "エラー");
      return false;
    }
  }

  window.__HARNESS_API__ = {
    setMode,
    setDiscContext,
    openProfile: () => setProfileOpen(true),
    injectConcurrentProfileField: (k, v) => {
      liveRef.current.profile[k] = v;
    },
    getState: () => structuredClone(liveRef.current),
    getEvents: () => [...events],
  };
  window.__HARNESS_STATE__ = state;
  window.__HARNESS_EVENTS__ = events;

  const log = (type, payload) => {
    setEvents((prev) => {
      const next = [...prev, { type, payload }];
      window.__HARNESS_EVENTS__ = next;
      return next;
    });
  };

  return (
    <Theme theme={neutralTheme}>
      <PlannerError.Provider value={error}>
        <main className="work-main" style={{ paddingBlock: "16px" }}>
          <div className="actions" style={{ marginBottom: "12px" }}>
            <button type="button" onClick={() => setMode("discovery")}>
              Discovery
            </button>
            <button type="button" onClick={() => setProfileOpen(true)}>
              ProfileDialog
            </button>
            <button type="button" onClick={() => setMode("fields")}>
              AcademicFields
            </button>
          </div>
          {mode === "discovery" && (
            <Discovery
              key={JSON.stringify(discContext)}
              catalog={catalog}
              state={state}
              byCode={byCode}
              context={discContext}
              list={list}
              setListId={setListId}
              mutate={mutate}
              returnTo={() => log("returnTo", discContext)}
              openCourse={(c) => log("openCourse", c.code)}
            />
          )}
          {mode === "fields" && (
            <section className="page-content">
              <AcademicFields
                rows={SAMPLE_FIELD_ROWS}
                fieldNames={catalog.fields}
                onSearch={(payload) => log("fieldSearch", payload)}
                onReview={(row) => log("fieldReview", row.field)}
              />
            </section>
          )}
          {profileOpen && (
            <ProfileSettings
              state={state}
              mutate={mutate}
              close={() => setProfileOpen(false)}
              handbooks={SAMPLE_HANDBOOKS}
              facultyNames={SAMPLE_FACULTIES}
            />
          )}
        </main>
      </PlannerError.Provider>
    </Theme>
  );
}

createRoot(document.getElementById("root")).render(<Harness />);
`;

await withBrowserHarness({
  name: "gemini-leaves-harness",
  pagePath: "/harness.html",
  entryPath: "/@harness-entry.jsx",
  html: HARNESS_HTML,
  entry: HARNESS_ENTRY,
  viewport: { width: 1440, height: 930 },
}, async ({ page, url, errors }) => {
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
  await page.getByRole("searchbox").waitFor({ timeout: 30000 });

  // --- 1. Discovery + SyllabusFacts ---
  // Exact official syllabus URL search
  const officialUrl =
    "https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/84/84_261G7011_ja_JP.html";
  await page.getByRole("searchbox").fill(officialUrl);
  await page.getByText("1件の授業", { exact: true }).waitFor();
  await page.locator(".result-list .title-link", { hasText: "英語基礎 L" }).click();

  const panel = page.getByRole("complementary", { name: "選択中の授業の詳細" });
  await panel.waitFor();
  const panelText = await panel.innerText();
  assert.match(panelText, /261G7011/);
  assert.match(panelText, /月曜2限・木曜2限/);
  assert.match(panelText, /1単位/);
  assert.match(panelText, /84 教養教育/);
  assert.match(panelText, /70 英語/);
  assert.match(panelText, /演習/);
  assert.equal(
    await panel.locator(`a[href="${officialUrl}"]`).count(),
    1,
    "Official syllabus link must use exact official builder URL",
  );
  assert.equal(
    await page.locator("iframe").count(),
    0,
    "Must never frame official syllabus",
  );

  // Purpose-specific filters: teacher, department, explicit day and period
  await page.getByRole("searchbox").fill("");
  await page.getByRole("combobox", { name: "開講部局" }).click();
  await page.getByRole("option", { name: "84 教養教育", exact: true }).click();
  await page.getByRole("combobox", { name: "曜日" }).click();
  await page.getByRole("option", { name: "木曜", exact: true }).click();
  await page.getByRole("combobox", { name: "時限" }).click();
  await page.getByRole("option", { name: "2限", exact: true }).click();
  await page.getByLabel("担当教員").fill("英語");
  await page.getByRole("button", { name: "条件を戻す" }).click();

  // In-place comparison and list action without losing term/query/selection
  await page.getByRole("searchbox").fill("英語基礎");
  await page.getByRole("combobox", { name: "開講ターム" }).click();
  await page.getByRole("option", { name: "第1ターム", exact: true }).click();
  await page.locator(".result-list li").nth(1).waitFor();

  const firstRow = page.locator(".result-list li").first();
  const secondRow = page.locator(".result-list li").nth(1);
  await firstRow.getByRole("button", { name: "比較", exact: true }).click();
  await secondRow.getByRole("button", { name: "比較", exact: true }).click();
  await page.getByRole("region", { name: "比較中の授業" }).waitFor();
  await page.getByText("比較中の授業（2件）").waitFor();

  // Add to list in-place (non-slot mode): must keep query, term, panel, and comparison intact
  await firstRow.getByRole("button", { name: "リストに追加", exact: true }).click();
  await firstRow.getByRole("button", { name: "追加済み", exact: true }).waitFor();
  assert.equal(await page.getByRole("searchbox").inputValue(), "英語基礎");
  assert.equal(await panel.isVisible(), true);
  assert.equal(
    await page.getByRole("region", { name: "比較中の授業" }).isVisible(),
    true,
  );

  // Remove firstRow from list in-place via comparison card without losing query/term/selection
  const compareRegion = page.getByRole("region", { name: "比較中の授業" });
  await compareRegion.getByRole("button", { name: "リストから外す", exact: true }).first().click();
  await firstRow.getByRole("button", { name: "リストに追加", exact: true }).waitFor();
  assert.equal(await page.getByRole("searchbox").inputValue(), "英語基礎");
  assert.equal(await panel.isVisible(), true);

  // Eligible codes requirement context: available-first ranking
  const freeCode = await page.evaluate(() => {
    return "260G0017"; // 水2 (no conflict with 261G3008 at 月1,月2)
  });
  await page.evaluate((fc) => {
    window.__HARNESS_API__.setDiscContext({
      label: "英語の不足枠",
      term: 1,
      eligibleCodes: ["261G7011", fc], // 261G7011 conflicts with plan's 261G3008
    });
  }, freeCode);
  await page.getByRole("heading", { name: "英語の不足枠" }).waitFor();
  const rankedFirstText = await page.locator(".result-list li").first().innerText();
  assert.match(rankedFirstText, /260G0017/);

  // Slot context: adding to list returns directly to slot
  await page.evaluate(() => {
    window.__HARNESS_API__.setDiscContext({ slot: "月2", term: 1 });
  });
  await page.getByRole("heading", { name: "月曜2限" }).waitFor();
  await page.getByRole("searchbox").fill("261G7011");
  await page
    .locator(".result-list li")
    .filter({ hasText: "261G7011" })
    .getByRole("button", { name: "リストに追加", exact: true })
    .click();
  const afterSlotAdd = await page.evaluate(() => window.__HARNESS_EVENTS__);
  assert.ok(
    afterSlotAdd.some((e) => e.type === "returnTo"),
    "Slot add-to-list must invoke returnTo",
  );

  // Mobile overflow check on Discovery
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
    "Discovery must not overflow narrow mobile viewport",
  );
  await page.setViewportSize({ width: 1440, height: 930 });

  // --- 2. ProfileSettings ---
  await page.getByRole("button", { name: "ProfileDialog" }).click();
  const dialog = page.getByRole("dialog", { name: "所属・適用便覧" });
  await dialog.waitFor();

  // Select faculty & verify real handbook suggestions appear
  await dialog.getByRole("combobox", { name: "学部・学科" }).click();
  await page.getByRole("option", { name: "サンプル工学部", exact: true }).click();
  await dialog.getByText("2026年度 サンプル工学部便覧").waitFor();
  await dialog.getByText("2022年度 サンプル工学部便覧").waitFor();
  assert.equal(
    await dialog.locator('a[href="https://example.test/handbook-2022.pdf"]').count(),
    1,
  );

  // Select entry = 編入 (all 4 alternatives available)
  await dialog.getByRole("combobox", { name: "入学区分" }).click();
  for (const label of ["1年次入学", "編入", "転部", "再入学"]) {
    assert.equal(
      await page.getByRole("option", { name: label, exact: true }).count(),
      1,
      `Entry option ${label} must exist`,
    );
  }
  await page.getByRole("option", { name: "編入", exact: true }).click();

  // Apply 2022 handbook suggestion -> program choices update to 2022
  await dialog
    .locator(".pf-handbook-item", { hasText: "2022年度 サンプル工学部便覧" })
    .getByRole("button", { name: "この年度を適用" })
    .click();
  await dialog.getByRole("button", { name: "サンプル旧課程プログラム" }).waitFor();

  // Override handbook year to any valid transfer year (2020) and custom program
  await dialog.getByLabel("適用便覧の年度").fill("2020");
  await dialog.getByLabel("プログラム・分野").fill("旧課程カスタム分野");
  // Leave 入学年度 empty (never inferred), set 0 for attendanceMonths and gpa, leave cap empty
  assert.equal(await dialog.getByLabel("入学年度").inputValue(), "");
  await dialog.getByLabel("現在の年次").fill("3");
  await dialog.getByLabel("実在学月数").fill("0");
  await dialog.getByLabel("前学期GPA").fill("0");
  await dialog.getByLabel("個別のCAP上限").fill("");

  // Inject concurrent unrelated profile field before saving
  await page.evaluate(() => {
    window.__HARNESS_API__.injectConcurrentProfileField(
      "concurrentUnrelated",
      "keep-value",
    );
  });

  // Narrow mobile overflow check on ProfileSettings dialog
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
    "ProfileSettings dialog must not overflow narrow mobile viewport",
  );
  await page.setViewportSize({ width: 1440, height: 930 });

  await dialog.getByRole("button", { name: "設定を保存", exact: true }).click();
  await dialog.waitFor({ state: "hidden" });

  const savedProfile = await page.evaluate(
    () => window.__HARNESS_API__.getState().profile,
  );
  assert.equal(savedProfile.faculty, "サンプル工学部");
  assert.equal(savedProfile.entry, "編入");
  assert.equal(savedProfile.admitted, "");
  assert.equal(savedProfile.handbook, "2020");
  assert.equal(savedProfile.program, "旧課程カスタム分野");
  assert.equal(savedProfile.yearOfStudy, "3");
  assert.equal(savedProfile.attendanceMonths, "0");
  assert.equal(savedProfile.gpa, "0");
  assert.equal(savedProfile.cap, "");
  assert.equal(savedProfile.concurrentUnrelated, "keep-value");

  // --- 3. AcademicFields ---
  await page.getByRole("button", { name: "AcademicFields" }).click();
  await page.getByText("70 英語", { exact: true }).waitFor();
  await page.getByText("10 情報", { exact: true }).waitFor();
  await page.getByText("分野要確認", { exact: true }).waitFor();

  // Field 10 has no requirement -> must NOT print made-up zero
  const field10 = page.locator("details.field-row", { hasText: "10 情報" });
  await field10.locator("summary").click();
  const field10Text = await field10.innerText();
  assert.doesNotMatch(field10Text, /必要|残り/);
  assert.match(field10Text, /2026年度/);
  assert.match(field10Text, /2単位/);
  assert.equal(
    await field10.getByRole("button", { name: "この分野の授業を探す" }).count(),
    0,
  );

  // Field 70 has unmet requirement -> shows supplied numbers, source, and triggers onSearch
  const field70 = page.locator("details.field-row", { hasText: "70 英語" });
  await field70.locator("summary").click();
  const field70Text = await field70.innerText();
  assert.match(field70Text, /必要単位[\s\S]*4単位/);
  assert.match(field70Text, /現在の残り[\s\S]*3単位/);
  assert.match(field70Text, /履修後の残り[\s\S]*2単位/);
  assert.match(field70Text, /2025年度/);
  assert.equal(
    await field70.locator('a[href="https://example.test/rule-70"]').count(),
    1,
  );
  await field70.getByRole("button", { name: "この分野の授業を探す" }).click();

  // Unknown field (?) -> triggers onReview
  const fieldUnknown = page.locator("details.field-row", { hasText: "分野要確認" });
  await fieldUnknown.locator("summary").click();
  await fieldUnknown.getByRole("button", { name: "分野を確認する" }).click();

  const events = await page.evaluate(() => window.__HARNESS_EVENTS__);
  const searchEvent = events.find((e) => e.type === "fieldSearch");
  assert.equal(searchEvent?.payload?.field, "70");
  assert.equal(searchEvent?.payload?.requirement, "field-70");
  const reviewEvent = events.find((e) => e.type === "fieldReview");
  assert.equal(reviewEvent?.payload, "?");

  // Narrow mobile overflow check on AcademicFields
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
    "AcademicFields must not overflow narrow mobile viewport",
  );

  assert.deepEqual(errors, [], `Unexpected page errors: ${errors.join("; ")}`);
  console.log(
    "Synthetic browser check passed for Discovery + SyllabusFacts, ProfileSettings, and AcademicFields on desktop and mobile.",
  );
});
