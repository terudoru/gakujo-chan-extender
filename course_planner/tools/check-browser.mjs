// Verify the production bundle in two isolated browser profiles.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { basename, extname, join } from "node:path";
import { chromium } from "playwright-core";
import { initialState } from "../src/study.mjs";
import { checkCurriculumWorkflows } from "../test/curriculum-workflow-browser.mjs";

const dist = fileURLToPath(new URL("../../site/planner/", import.meta.url));
const types = {
  ".js": "text/javascript",
  ".css": "text/css",
  ".html": "text/html",
  ".json": "application/json",
};
const server = createServer(async (req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;
  if (!/^\/planner\/(?:[\w.-]+)?$/.test(path)) {
    res.writeHead(404).end();
    return;
  }
  const name = path.endsWith("/") ? "index.html" : basename(path);
  try {
    const data = await readFile(join(dist, name));
    res
      .writeHead(200, {
        "Content-Type": types[extname(name)] ?? "application/octet-stream",
      })
      .end(data);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const base = "http://127.0.0.1:" + server.address().port + "/planner/";
let browser;
try {
  browser = await chromium.launch({
    channel: process.env.CHROME_CHANNEL ?? "chrome",
    headless: true,
    chromiumSandbox: true,
  });
  const author = await browser.newContext({
    viewport: { width: 1440, height: 930 },
  });
  const recipient = await browser.newContext({
    viewport: { width: 1440, height: 930 },
  });
  const errors = [];
  const open = async (context, url) => {
    const p = await context.newPage();
    p.setDefaultTimeout(5000);
    p.on("pageerror", (e) => errors.push(e.message));
    await p.goto(url);
    return p;
  };
  const a = await open(author, base);
  const btn = (p, name) => p.getByRole("button", { name, exact: true });
  const nav = (p, name) =>
    p.locator("nav:visible").getByRole("button", { name, exact: true });
  const closeDialog = (p) => p.keyboard.press("Escape");
  const saved = (p) =>
    p.evaluate(() => JSON.parse(localStorage.getItem("mbg.course-planner.v1")));
  await a.getByRole("heading", { name: "時間割", exact: true }).waitFor();
  for (const code of ["261G3008", "261G7011"]) {
    await btn(a, "月曜2限の候補").click();
    await btn(a, "このコマの授業を探す").click();
    await a.getByRole("searchbox").fill(code);
    await btn(
      a.locator(".result-list li").filter({ hasText: code }),
      "リストに追加",
    ).click();
    await btn(a, "月曜2限の候補").waitFor();
  }
  assert.equal((await saved(a)).lists[0].codes.length, 2);
  await nav(a, "候補リスト").click();
  const overlap = a.locator(".list-details .candidate-overlaps").first();
  await overlap.locator("summary").click();
  await overlap.getByRole("button", { name: "英語基礎 L", exact: true }).waitFor();
  assert.match(await overlap.innerText(), /月曜2限/);
  await btn(overlap, "英語基礎 L").click();
  const syllabus = a.getByRole("dialog", { name: "授業の詳細" });
  assert.match(await syllabus.innerText(), /分野／Academic Field[\s\S]*70[^\n]*英語/);
  assert.match(await syllabus.getByRole("link", { name: "公式シラバス" }).getAttribute("href"), /261G7011_/);
  await closeDialog(a);
  await btn(a.locator(".list-details"), "エンジニアのためのデータサイエンス入門(融合領域分野)").click();
  const courseFacts = a.getByRole("dialog", { name: "授業の詳細" });
  await courseFacts.getByText("授業計画の例", { exact: true }).waitFor();
  assert.match(await courseFacts.innerText(), /課題レポート/);
  await closeDialog(a);
  await btn(a, "共有").click();
  const link = await a.getByLabel("共有リンク", { exact: true }).inputValue();
  await closeDialog(a);
  const p = await open(recipient, link);
  await btn(p, "自分用にコピー").click();
  await nav(p, "時間割").click();
  await btn(p, "月曜2限の候補").click();
  const row = (title) =>
    p.locator(".inspector .rows li").filter({ hasText: title });
  const forecast = p.getByRole("region", { name: "選択したコマの修得見込み" });
  await btn(row("データサイエンス入門"), "この授業を選ぶ").click();
  await p.locator(".cap-body b").filter({ hasText: "2 /" }).waitFor();
  assert.match(await forecast.innerText(), /10 情報\s+履修予定 2単位/);
  await btn(row("英語基礎 L"), "この授業を選ぶ").click();
  const replacement = p.getByRole("dialog", { name: "重なる授業を確認" });
  assert.match(await replacement.innerText(), /月曜2限/);
  await btn(replacement, "今の予定を残す").click();
  assert.deepEqual((await saved(p)).plan, ["261G3008"]);
  await btn(row("英語基礎 L"), "この授業を選ぶ").click();
  await btn(p, "入れ替える").click();
  await p.locator(".cap-body b").filter({ hasText: "1 /" }).waitFor();
  assert.deepEqual((await saved(p)).plan, ["261G7011"]);
  assert.match(await forecast.innerText(), /70 英語\s+履修予定 1単位/);
  assert.doesNotMatch(await forecast.innerText(), /10 情報/);
  assert.deepEqual((await saved(a)).plan, []);
  assert.match(await btn(p, "木曜2限の候補").innerText(), /英語基礎 L/);
  assert.doesNotMatch(
    await btn(p, "月曜1限の候補").innerText(),
    /データサイエンス/,
  );
  await p.getByRole("radio", { name: "第2ターム" }).click();
  assert.doesNotMatch(await btn(p, "木曜2限の候補").innerText(), /英語基礎 L/);
  assert.match(await p.locator(".cap-body b").innerText(), /1/);
  await p.getByRole("radio", { name: "第1ターム" }).click();

  await nav(p, "単位・要件").click();
  await btn(p, "所属を設定").click();
  await p
    .getByRole("dialog")
    .getByRole("combobox", { name: "学部・学科" })
    .click();
  await p.getByRole("option", { name: "工学部", exact: true }).click();
  await p.getByLabel("プログラム・分野", { exact: true }).fill("融合領域分野");
  assert.equal(await p.getByLabel("適用便覧の年度", { exact: true }).inputValue(), "");
  await p.getByLabel("適用便覧の年度", { exact: true }).fill("2026");
  await p.getByLabel("入学年度", { exact: true }).fill("2026");
  await btn(p, "設定を保存").click();
  await btn(p, "成績を取り込む").click();
  await p.locator("input[type=file]").setInputFiles({
    name: "grades.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(
      "科目コード,科目名,単位数,評価,年度\n261G3008,エンジニアのためのデータサイエンス入門(融合領域分野),2,優,2026\n",
    ),
  });
  await p.getByRole("dialog").getByRole("checkbox", { name: /を取り込む（行/ }).first().check();
  await btn(p, "選択した1件を取り込む").click();
  const human = p
    .locator(".ledger-row")
    .filter({ has: p.getByText("人文社会・教育科学", { exact: true }) });
  assert.deepEqual(await human.locator(":scope > span").allTextContents(), [
    "4",
    "0",
    "4",
  ]);
  assert.equal(await human.locator("b").innerText(), "3");
  const promotion = p.getByRole("radio", { name: "進級まで" });
  await promotion.click();
  await p.getByRole("combobox", { name: "照合する学年・履修条件" }).click();
  await p.getByRole("option", { name: "4年次進級", exact: true }).click();
  await btn(p, "確認表の内訳を入力").click();
  const balanceDialog = p.getByRole("dialog");
  await balanceDialog.getByRole("combobox", { name: "照合する項目" }).click();
  await p.getByRole("option", { name: "人文社会・教育科学", exact: true }).click();
  await balanceDialog.getByLabel("必要単位").fill("4");
  await balanceDialog.getByLabel("修得済み").fill("1");
  await btn(balanceDialog, "単位を保存").click();
  const evidence = human.locator("details");
  await evidence.locator("summary").click();
  assert.match(await evidence.innerText(), /確認表の修得済み\s*1単位/);
  await btn(human, "授業を探す").click();
  await btn(p, "単位・要件に戻る").click();
  assert.ok(await promotion.isChecked());
  await p.waitForFunction(() =>
    document.activeElement?.matches(".ledger-row summary"),
  );
  assert.equal(await evidence.evaluate((details) => details.open), true);
  assert.ok(
    await evidence.locator("summary").evaluate((el) => el === document.activeElement),
  );
  await p.getByRole("radio", { name: "シラバスの分野" }).click();
  await p.getByText("70 英語", { exact: true }).waitFor();
  await p.getByText("10 情報", { exact: true }).waitFor();

  await nav(p, "時間割").click();
  await btn(p, "月曜2限の候補").click();
  assert.match(await forecast.innerText(), /70 英語\s+修得 0 → 履修後 1単位/);
  await nav(p, "単位・要件").click();
  await p.getByRole("radio", { name: "シラバスの分野" }).click();
  await btn(p, "分野の必要単位を入力").click();
  await p.getByRole("combobox", { name: "照合する項目" }).click();
  await p.getByRole("option", { name: "分野 70 英語", exact: true }).click();
  await p.getByLabel("必要単位").fill("8");
  await p.getByLabel("修得済み").fill("4");
  await btn(p, "単位を保存").click();
  await p.getByRole("dialog").waitFor({ state: "hidden" });
  const confirmedEnglish = p.locator(".af-list details").filter({ has: p.getByText("70 英語", { exact: true }) });
  assert.match(await confirmedEnglish.innerText(), /修得 4 · 履修後 5 単位/);
  await nav(p, "時間割").click();
  await btn(p, "月曜2限の候補").click();
  assert.match(await forecast.innerText(), /70 英語\s+修得 4 → 履修後 5単位/);
  await forecast.locator("summary").click();
  const humanImpact = forecast.locator("dl > div").filter({
    has: p.getByText("卒業 · 人文社会・教育科学", { exact: true }),
  });
  assert.equal(await humanImpact.locator("dd").innerText(), "4 → 3単位");
  if (process.env.PLANNER_SHOTS)
    await p.screenshot({
      path: join(process.env.PLANNER_SHOTS, "planner-desktop.png"),
      fullPage: true,
    });
  await p.setViewportSize({ width: 390, height: 844 });
  await btn(p, "月曜2限の候補").click();
  await p.getByRole("dialog", { name: "月曜2限の授業" }).waitFor();
  const mobileForecast = p.getByRole("dialog", { name: "月曜2限の授業" })
    .getByRole("region", { name: "選択したコマの修得見込み" });
  assert.match(await mobileForecast.innerText(), /70 英語\s+修得 4 → 履修後 5単位/);
  assert.equal(
    await p.locator("body").evaluate((el) => el.scrollWidth <= innerWidth),
    true,
  );
  await p
    .getByRole("dialog", { name: "月曜2限の授業" })
    .evaluate(async (sheet) => {
      await Promise.all(
        sheet
          .getAnimations({ subtree: true })
          .map((a) => a.finished.catch(() => {})),
      );
    });
  if (process.env.PLANNER_SHOTS)
    await p.screenshot({
      path: join(process.env.PLANNER_SHOTS, "planner-mobile.png"),
      animations: "disabled",
    });
  await btn(p, "閉じる").click();
  await p.reload();
  await btn(p, "木曜2限の候補").waitFor();
  assert.match(await btn(p, "木曜2限の候補").innerText(), /英語基礎 L/);
  await nav(p, "候補リスト").click();
  await p
    .locator(".list-nav")
    .filter({ hasText: "履修候補（コピー）" })
    .click();
  await btn(p, "候補から外す").first().click();
  await p
    .locator(".list-details .result-list li")
    .nth(1)
    .waitFor({ state: "detached" });
  assert.equal((await saved(a)).lists[0].codes.length, 2);
  assert.equal((await saved(p)).lists.at(-1).codes.length, 1);
  assert.equal((await saved(a)).grades.length, 0);

  const documentPage = await recipient.newPage();
  await documentPage.setContent(
    '<meta charset="utf-8"><style>th,td{text-align:left;padding:0 14px}</style><table><tr><th>科目コード</th><th>科目名</th><th>単位数</th><th>評価</th><th>年度</th></tr><tr><td>261G7011</td><td>英語基礎 L</td><td>1</td><td>良</td><td>2026</td></tr></table>',
  );
  const example = await documentPage.pdf();
  await documentPage.close();
  await nav(p, "単位・要件").click();
  await btn(p, "成績を取り込む").click();
  await p
    .locator("input[type=file]")
    .setInputFiles({
      name: "確認用成績.pdf",
      mimeType: "application/pdf",
      buffer: example,
    });
  await p.getByRole("dialog").getByRole("checkbox", { name: /を取り込む（行/ }).first().check();
  await btn(p, "選択した1件を取り込む").click();
  await p.getByRole("dialog").waitFor({ state: "hidden" });
  assert.equal(
    (await saved(p)).grades.find((g) => g.code === "261G7011").credits,
    1,
  );
  await nav(p, "時間割").click();
  await btn(p, "登録状況を取り込む").click();
  const importDialog = p.getByRole("dialog");
  await importDialog.locator("input[type=file]").setInputFiles({
    name: "履修登録状況.csv", mimeType: "text/csv",
    buffer: Buffer.from("開講番号,科目名,状態\n261G7011,英語基礎 L,不許可\n261G3008,データサイエンス入門,申請中\n"),
  });
  await importDialog.getByRole("checkbox", { name: /英語基礎/ }).waitFor();
  assert.ok(await importDialog.getByRole("checkbox", { name: /データサイエンス/ }).isDisabled());
  assert.equal((await saved(p)).status["261G7011"], undefined);
  const ready = await p.evaluate(() => {
    let announced = false;
    window.addEventListener("mbg:planner-ready", () => { announced = true; }, { once: true });
    window.dispatchEvent(new Event("mbg:planner-probe"));
    window.dispatchEvent(new CustomEvent("mbg:planner-import", { detail: {
      v: 1, kind: "registration", tables: [{
        heading: "許可された科目", rows: [["開講番号", "科目名"], ["261G3008", "エンジニアのためのデータサイエンス入門(融合領域分野)"]],
      }],
    } }));
    return announced;
  });
  assert.equal(ready, true);
  await importDialog.getByRole("checkbox", { name: /英語基礎/ }).check();
  await btn(importDialog, "選択した1件を取り込む").click();
  const queued = p.getByRole("dialog");
  await queued.getByRole("checkbox", { name: /英語基礎/ }).waitFor({ state: "detached" });
  await queued.getByRole("checkbox", { name: /データサイエンス/ }).waitFor();
  assert.equal(await queued.getByRole("checkbox", { name: /データサイエンス/ }).isChecked(), false);
  assert.equal((await saved(p)).status["261G7011"], "不許可");
  assert.equal((await saved(p)).status["261G3008"], undefined);
  await queued.getByRole("checkbox", { name: /データサイエンス/ }).check();
  await btn(queued, "選択した1件を取り込む").click();
  await queued.waitFor({ state: "hidden" });
  assert.equal((await saved(p)).status["261G3008"], "許可");
  assert.match(await btn(p, "月曜2限の候補").innerText(), /不許可/);
  assert.match(await p.locator(".cap-body b").innerText(), /2\s*\/\s*28/);
  const application = p.getByRole("link", { name: "学務で申請", exact: true }).first();
  assert.match(await application.getAttribute("href"), /gakujo\.iess\.niigata-u\.ac\.jp/);
  await nav(p, "単位・要件").click();
  await p.getByRole("radio", { name: "修得履歴" }).click();
  await btn(p, "修得科目を入力").click();
  const manual = p.getByRole("dialog");
  await manual.getByLabel("授業名", { exact: true }).fill("実践コミュニケーション英語I");
  await manual.getByLabel("開講番号", { exact: true }).fill("200G0105");
  await manual.getByLabel("修得年度", { exact: true }).fill("2020");
  await manual.getByLabel("修得単位", { exact: true }).fill("1");
  await btn(manual, "入力内容を確認").click();
  await manual.getByRole("checkbox", { name: /を取り込む（行/ }).check();
  await btn(manual, "選択した1件を取り込む").click();
  await manual.waitFor({ state: "hidden" });
  const historic = (await saved(p)).grades.find((g) => g.code === "200G0105");
  assert.equal(historic.matchedCourse?.year, "2020");
  assert.deepEqual(historic.matchedCourse?.fields, ["70"]);
  const historicalRow = p.getByRole("listitem").filter({ hasText: "実践コミュニケーション英語I" });
  await btn(historicalRow, "シラバスの対応を確認").click();
  const matched = p.getByRole("dialog", { name: "履修年度のシラバス" });
  assert.match(await matched.innerText(), /照合済み/);
  assert.match(await matched.getByRole("link", { name: "この年度の公式シラバス" }).getAttribute("href"), /syllabusHtml\/2020\//);
  await closeDialog(p);
  await p.getByRole("radio", { name: "シラバスの分野" }).click();
  await btn(p, "分野の必要単位を入力").click();
  const target = p.getByRole("dialog");
  await target.getByRole("combobox", { name: "照合する項目" }).click();
  await p.getByRole("option", { name: "分野 70 英語", exact: true }).click();
  await target.getByLabel("必要単位").fill("4");
  await target.getByLabel("修得済み").fill("2");
  await btn(target, "単位を保存").click();
  const field = p.locator(".af-list details").filter({ has: p.getByText("70 英語", { exact: true }) });
  await field.getByText(/現在の残り 2/).waitFor();
  await field.locator("summary").click();
  assert.match(await field.innerText(), /実践コミュニケーション英語I/);
  assert.match(await field.innerText(), /2020年度/);
  await btn(field, "この分野の授業を探す").click();
  await p.locator(".result-list li").first().waitFor();
  await btn(p, "単位・要件に戻る").click();
  await p.waitForFunction(() => document.activeElement?.matches(".af-list summary"));
  assert.ok(await field.evaluate((el) => el.open));
  await nav(p, "同期").click();
  await p.getByRole("heading", { name: "同期", exact: true }).waitFor();
  const unplannedDenial = await browser.newContext();
  const deniedState = initialState();
  deniedState.status["261G7011"] = "不許可";
  deniedState.status["261G3008"] = "要確認";
  await unplannedDenial.addInitScript((state) => {
    localStorage.setItem("mbg.course-planner.v1", JSON.stringify(state));
  }, deniedState);
  const deniedPage = await open(unplannedDenial, base);
  const deniedSlot = btn(deniedPage, "月曜2限の候補");
  assert.match(await deniedSlot.innerText(), /不許可/);
  assert.match(await deniedSlot.innerText(), /261G3008 · 要確認/);
  assert.match(await deniedPage.locator(".cap-body b").innerText(), /^0\s*\//);
  await unplannedDenial.close();

  const cohortBrowser = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const cohort = await open(cohortBrowser, base);
  await checkCurriculumWorkflows(cohort);
  await cohortBrowser.close();
  assert.deepEqual(errors, []);
  console.log(
    "Desktop and mobile passed: candidate and timetable conflicts, list copying, CAP, private grade and registration review, historical syllabus, field deficits and all undergraduate faculties.",
  );
} finally {
  await browser?.close();
  await new Promise((resolve) => server.close(resolve));
}
