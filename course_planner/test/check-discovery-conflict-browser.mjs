// Desktop (1440x930) and mobile (390x844) Chrome verification for Discovery overlap status:
// definite overlap vs confirmed no overlap vs 時限未定・重複要確認, free filter, and ranking.
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
    <title>Discovery Conflict Status Harness</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/@discovery-conflict-harness.jsx"></script>
  </body>
</html>`;

const HARNESS_ENTRY = `
import React, { useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Theme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral/built";
import "/src/planner.css";
import catalog from "/src/catalog-2026.json";
import { initialState } from "/src/study.mjs";
import { Discovery } from "/src/Discovery.jsx";

function Harness() {
  const liveRef = useRef(null);
  if (!liveRef.current) {
    const s = initialState();
    s.plan = ["261G7011"]; // 第1ターム 月2, 木2
    liveRef.current = s;
  }
  const [state, setState] = useState(() => structuredClone(liveRef.current));
  const [context, setContext] = useState({});
  const [listId, setListId] = useState("mine");
  const byCode = useMemo(
    () => new Map(catalog.courses.map((c) => [c.code, c])),
    [],
  );
  const list = state.lists.find((l) => l.id === listId) ?? state.lists[0];

  async function mutate(updater) {
    const next = structuredClone(liveRef.current);
    updater(next);
    liveRef.current = next;
    setState(structuredClone(next));
    window.__CONFLICT_STATE__ = structuredClone(next);
    return true;
  }

  window.__CONFLICT_HARNESS__ = {
    setPlan: (codes) => {
      liveRef.current.plan = [...codes];
      setState(structuredClone(liveRef.current));
    },
    setContext,
  };
  window.__CONFLICT_STATE__ = state;

  return (
    <Theme theme={neutralTheme}>
      <main className="work-main" style={{ paddingBlock: "16px" }}>
        <Discovery
          key={JSON.stringify(context)}
          catalog={catalog}
          state={state}
          byCode={byCode}
          context={context}
          list={list}
          setListId={setListId}
          mutate={mutate}
        />
      </main>
    </Theme>
  );
}

createRoot(document.getElementById("root")).render(<Harness />);
`;

const virtualPlugin = {
  name: "discovery-conflict-harness",
  configureServer(server) {
    server.middlewares.use((req, res, next) => {
      if (req.url === "/discovery-conflict.html") {
        server
          .transformIndexHtml("/discovery-conflict.html", HARNESS_HTML)
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
    if (id === "/@discovery-conflict-harness.jsx") return id;
    return null;
  },
  load(id) {
    if (id === "/@discovery-conflict-harness.jsx") return HARNESS_ENTRY;
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
const url = `http://127.0.0.1:${address.port}/discovery-conflict.html`;

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
  const searchbox = page.getByRole("searchbox");
  await searchbox.waitFor({ timeout: 30000 });
  const freeCheckbox = page.getByLabel("重ならない授業");

  // --- 1. Exact reviewer repro: plan has 261G7011 (月2・木2 第1ターム), candidate 261E6002 (他 第1ターム) ---
  await searchbox.fill("261E6002");
  const businessRow = page.locator(".result-list li", { hasText: "261E6002" });
  await businessRow.waitFor();
  assert.match(await businessRow.innerText(), /時限未定・重複要確認/);

  await businessRow.locator(".title-link").click();
  const panel = page.getByRole("complementary", { name: "選択中の授業の詳細" });
  await panel.waitFor();
  const businessPanelText = await panel.innerText();
  assert.match(businessPanelText, /時限未定・重複要確認/);
  assert.doesNotMatch(businessPanelText, /現在の時間割と重複なし/);
  assert.equal(
    await panel
      .locator(
        'a[href="https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/0C/0C_261E6002_ja_JP.html"]',
      )
      .count(),
    1,
  );

  // Free filter excludes 261E6002 (not proven non-overlapping)
  await freeCheckbox.check();
  await page.getByText("0件の授業", { exact: true }).waitFor();
  await freeCheckbox.uncheck();

  // --- 2. Confirmed clear (260G0017 水2) vs definite overlap (261G3008 月1・月2) ---
  await searchbox.fill("260G0017");
  const clearRow = page.locator(".result-list li", { hasText: "260G0017" });
  await clearRow.waitFor();
  assert.doesNotMatch(await clearRow.innerText(), /重複/);
  await clearRow.locator(".title-link").click();
  assert.match(await panel.innerText(), /現在の時間割と重複なし/);

  // Saved-list action & exact label preserved
  await clearRow.getByRole("button", { name: "リストに追加", exact: true }).click();
  await clearRow.getByRole("button", { name: "追加済み", exact: true }).waitFor();
  assert.match(await panel.innerText(), /保存先リスト：履修候補/);

  await freeCheckbox.check();
  await page.getByText("1件の授業", { exact: true }).waitFor();
  await freeCheckbox.uncheck();

  await searchbox.fill("261G3008");
  const conflictRow = page.locator(".result-list li", { hasText: "261G3008" });
  await conflictRow.waitFor();
  assert.match(await conflictRow.innerText(), /月曜2限で「英語基礎 L」と重複/);
  await conflictRow.locator(".title-link").click();
  assert.match(await panel.innerText(), /月曜2限で「英語基礎 L」と重複/);

  // --- 3. Requirement context ranking: proven clear -> uncertain -> definite conflict ---
  await page.evaluate(() => {
    window.__CONFLICT_HARNESS__.setContext({
      label: "第1ターム要件",
      term: 1,
      eligibleCodes: ["261G3008", "261E6002", "260G0017"],
    });
  });
  await page.getByRole("heading", { name: "第1ターム要件" }).waitFor();
  const orderedTexts = await page.locator(".result-list li").allInnerTexts();
  assert.equal(orderedTexts.length, 3);
  assert.match(orderedTexts[0], /260G0017/);
  assert.match(orderedTexts[1], /261E6002[\s\S]*時限未定・重複要確認/);
  assert.match(orderedTexts[2], /261G3008[\s\S]*月曜2限で「英語基礎 L」と重複/);

  await page.getByLabel("重ならない授業").check();
  await page.getByText("1件の授業", { exact: true }).waitFor();
  assert.match(
    await page.locator(".result-list li").first().innerText(),
    /260G0017/,
  );
  await page.getByLabel("重ならない授業").uncheck();

  // --- 4. Active undetermined course (261E6002) makes same-term 260G0017 uncertain, ignores self ---
  await page.evaluate(() => {
    window.__CONFLICT_HARNESS__.setPlan(["261E6002"]);
  });
  const wedRowAfter = page.locator(".result-list li", { hasText: "260G0017" });
  await wedRowAfter.locator(".title-link").click();
  const wedPanel = page.getByRole("complementary", { name: "選択中の授業の詳細" });
  assert.match(await wedPanel.innerText(), /時限未定・重複要確認[\s\S]*経営学入門/);

  const selfRow = page.locator(".result-list li", { hasText: "261E6002" });
  await selfRow.locator(".title-link").click();
  assert.match(await wedPanel.innerText(), /現在の時間割と重複なし/);

  // --- 5. Mobile 390x844 layout & no horizontal overflow ---
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
    true,
    "Discovery conflict view must not overflow narrow mobile viewport",
  );

  assert.deepEqual(errors, [], `Unexpected page errors: ${errors.join("; ")}`);
  console.log(
    "Discovery conflict status browser check passed on desktop and mobile: 261E6002 repro, definite vs clear vs 時限未定・重複要確認, free filter, and 3-tier ranking.",
  );
} finally {
  await browser?.close();
  await viteServer.close();
}
