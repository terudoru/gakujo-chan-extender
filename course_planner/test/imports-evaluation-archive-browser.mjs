// Production planner, public catalogs and synthetic transcript rows only.
import assert from "node:assert/strict";
import { initialState } from "../src/study.mjs";
import { withPlannerPreview } from "./planner-preview-harness.mjs";

const key = "mbg.course-planner.v1";
const header = ["履修年度", "開講番号", "科目名", "開講所属", "修得単位", "評価"];
const title = "現代教育学概論";
const row = (year, faculty = "教育学部") => [year, year.slice(2) + "0K0363", title, faculty, "0", "不可"];
await withPlannerPreview("planner-failed-credit-review-", {}, async ({ browser, origin }) => {
  const page = await browser.newPage();
  const errors = [], outside = [], years = [];
  let interruptPack;
  page.on("pageerror", (e) => errors.push(e.message));
  await page.route("**/*", async (route) => {
    const request = route.request(), url = new URL(request.url());
    if (request.method() !== "GET" || url.origin !== origin) {
      outside.push(request.method());
      return route.abort();
    }
    const pack = /\/(20\d{2})(?:-[\w-]+)?\.json$/.exec(url.pathname);
    if (pack) {
      years.push(pack[1]);
      if (interruptPack) {
        const handle = interruptPack;
        interruptPack = null;
        return handle(route);
      }
    }
    return route.continue();
  });
  const state = initialState();
  Object.assign(state.profile, { faculty: "教育学部", program: "英語教育専修（小学校主免）",
    handbook: "2026", admitted: "2026", yearOfStudy: 2 });
  await page.addInitScript(([k, s]) => localStorage.setItem(k, JSON.stringify(s)), [key, state]);
  await page.goto(origin);
  await page.locator("nav:visible").getByRole("button", { name: "単位・要件", exact: true }).click();
  const modal = page.getByRole("dialog");
  const open = () => page.getByRole("button", { name: "成績を取り込む", exact: true }).click();
  const saved = () => page.evaluate((k) => JSON.parse(localStorage.getItem(k)).grades, key);
  const upload = (values, labels = header) => modal.locator("input[type=file]").setInputFiles({
    name: "assessment.csv", mimeType: "text/csv",
    buffer: Buffer.from([labels, ...(Array.isArray(values[0]) ? values : [values])].map((r) => r.join(",")).join("\n")),
  });
  const optIn = modal.getByRole("checkbox", { name: /現代教育学概論.*最終評価を確認/ });
  const accept = async (before) => {
    await optIn.waitFor();
    assert.equal(await optIn.isChecked(), false);
    assert.deepEqual(await saved(), before);
    await modal.getByText(/配当 2単位・修得 0単位/).waitFor();
    await optIn.check();
    assert.deepEqual(await saved(), before);
    await modal.getByRole("button", { name: "選択した1件を取り込む" }).click();
    await modal.waitFor({ state: "hidden" });
    return saved();
  };
  function holdPack() {
    let release;
    const released = new Promise((resolve) => { release = resolve; });
    const requested = new Promise((resolve) => {
      interruptPack = async (route) => { resolve(); await released; return route.continue(); };
    });
    return { requested, release };
  }

  await open();
  await upload(row("2026"));
  const current = await accept([]);
  assert.deepEqual(years, []);
  assert.deepEqual(current.map((g) => [g.year, g.credits, g.finalEvaluation, g.counts, g.duplicate, g.matchedCourse?.code]),
    [["2026", 2, true, false, false, "260K0363"]]);

  await open();
  interruptPack = (route) => route.abort();
  await upload(row("2025"));
  await modal.getByText(/要確認：評価・履修状況・配当単位/).waitFor();
  assert.equal(await optIn.count(), 0);
  assert.deepEqual(await saved(), current);

  const retry = holdPack();
  await upload([row("2025", "03"), ["2020", "200G0105", "実践コミュニケーション英語I", "84", "1", "優"]]);
  await modal.getByRole("status").filter({ hasText: "2025年度" }).waitFor();
  await retry.requested;
  await modal.getByRole("checkbox", { name: /実践コミュニケーション英語Iを取り込む/ }).check();
  assert.deepEqual(await saved(), current);
  // The same table/row ID in the replacement file cannot receive the old lookup's consent.
  await upload([...row("2026"), "後期"], [...header, "学期"]);
  await modal.getByText(/要確認：評価・履修状況・配当単位/).waitFor();
  const completed = page.waitForEvent("requestfinished", (req) => /\/2025[-.]/.test(req.url()));
  retry.release();
  await completed;
  assert.equal(await optIn.count(), 0);
  assert.equal(await modal.getByRole("button", { name: "選択した0件を取り込む" }).isDisabled(), true);
  assert.deepEqual(await saved(), current);
  await upload(row("2025", "03"));
  const both = await accept(current);
  assert.deepEqual(both.map((g) => [g.year, g.code, g.title, g.grade, g.credits, g.counts, g.duplicate, g.matchedCourse.year]),
    [["2026", "260K0363", title, "不可", 2, false, false, "2026"],
     ["2025", "250K0363", title, "不可", 2, false, false, "2025"]]);
  assert.match(both[1].matchedCourse.creditSource, /\.pdf#page=90$/);
  await page.evaluate((rows) => window.dispatchEvent(new CustomEvent("mbg:planner-import", {
    detail: { v: 1, kind: "grades", tables: [{ heading: "成績確認表", rows }] },
  })), [header, row("2025")]);
  const reread = await accept(both);
  assert.deepEqual(reread.map((g) => g.importId), both.map((g) => g.importId));
  assert.equal(await page.locator(".ledger-row").filter({ has: page.getByText("卒業単位の合計", { exact: true }) })
    .locator(":scope > span").nth(1).innerText(), "0");

  await open();
  const canceled = holdPack();
  await upload(row("2024"));
  await modal.getByRole("status").filter({ hasText: "2024年度" }).waitFor();
  await canceled.requested;
  await page.keyboard.press("Escape");
  await modal.waitFor({ state: "hidden" });
  const finished = page.waitForEvent("requestfinished", (req) => /\/2024[-.]/.test(req.url()));
  canceled.release();
  await finished;
  assert.equal(await modal.count(), 0);
  assert.deepEqual(await saved(), reread);
  assert.deepEqual(years, ["2025", "2025", "2024"]);
  assert.deepEqual(outside, []);
  assert.deepEqual(errors, []);
  console.log("Chrome passed both academic years, earned zero, explicit consent, native re-import, offline retry, replacement, cancellation and scoped pack requests.");
});
