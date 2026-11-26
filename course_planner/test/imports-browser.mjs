// node course_planner/test/imports-browser.mjs (Chrome, synthetic data only).
import assert from "node:assert/strict";
import { join } from "node:path";
import { plannerRoot, withPlannerPreview } from "./planner-preview-harness.mjs";

await withPlannerPreview("planner-imports-", {
  configFile: false,
  logLevel: "warn",
  headless: true,
  build: { rollupOptions: { input: join(plannerRoot, "test/imports-harness.html") } },
}, async ({ browser, origin }) => {
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    locale: "ja-JP",
  });
  const page = await context.newPage(),
    errors = [],
    outgoing = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.route("**/*", (route) => {
    const req = route.request();
    if (new URL(req.url()).origin !== origin || req.method() !== "GET") {
      outgoing.push(req.method());
      return route.abort();
    }
    return route.continue();
  });
  await page.goto(origin + "/test/imports-harness.html");
  const readState = async () =>
    JSON.parse(await page.locator("#result").textContent());
  const modal = page.getByRole("dialog");
  const accept = () =>
    modal.getByRole("button", { name: "選択した1件を取り込む" }).click();
  const open = async (kind) => {
    await page.getByRole("button", { name: kind, exact: true }).click();
    await modal.waitFor();
  };
  const upload = (name, mimeType, buffer) =>
    modal.locator("input[type=file]").setInputFiles({ name, mimeType, buffer });
  const picked = () => modal.getByRole("checkbox", { name: /を取り込む/ });
  const pdfPage = await context.newPage();
  await pdfPage.setContent(
    '<meta charset="utf-8"><style>td,th{text-align:left;padding-right:22px}</style><h1>成績確認表</h1><table><tr><th>開講番号</th><th>科目名</th><th>単位数</th><th>評語</th><th>年度</th></tr><tr><td>261G7011</td><td>架空科目</td><td>1</td><td>良</td><td>2026</td></tr><tr><td></td><td>架空認定</td><td>2</td><td>認定</td><td>2025</td></tr><tr><td>260K9202</td><td>初等教育実習I</td><td>2</td><td>不可</td><td>2026</td></tr></table>',
  );
  const pdf = await pdfPage.pdf();
  await pdfPage.close();
  await open("grades");
  await upload("確認用.pdf", "application/pdf", pdf);
  const earned = modal.getByRole("checkbox", { name: /架空科目を取り込む/ });
  const evaluation = modal.getByRole("checkbox", {
    name: /最終評価を確認して履歴に残す/,
  });
  await earned.waitFor().catch(async (error) => {
    console.error(await modal.innerText());
    throw error;
  });
  assert.equal(
    await modal
      .locator("input[type=file]")
      .evaluate((input) => input.files[0]?.name),
    "確認用.pdf",
  );
  assert.ok(
    await modal.evaluate((dialog) => dialog.clientWidth <= window.innerWidth),
  );
  if (process.env.PLANNER_SHOTS) {
    await page.screenshot({
      path: join(process.env.PLANNER_SHOTS, "imports-review.png"),
      animations: "disabled",
    });
  }
  assert.equal(await earned.isChecked(), false);
  assert.equal(await evaluation.isChecked(), false);
  assert.equal((await readState()).grades.length, 0);
  await earned.check();
  await accept();
  await modal.waitFor({ state: "hidden" });
  assert.equal((await readState()).grades[0].matchedCourse.year, "2026");
  assert.deepEqual(await page.evaluate(() => window.testArchive.calls[0]), [
    { title: "架空科目", matchedCourse: null },
  ]);
  await open("registration");
  await upload(
    "履修状況.txt",
    "text/plain",
    Buffer.from("不許可となった科目\r\n開講番号\t科目名\r\n261G7011\t架空科目"),
  );
  await picked().check();
  await accept();
  await modal.waitFor({ state: "hidden" });
  assert.equal((await readState()).status["261G7011"], "不許可");
  await open("balances");
  await upload(
    "区分.csv",
    "text/csv",
    Buffer.from("区分,履修単位,既修得単位\n英語,22,2.5\n卒業単位の合計,28,12"),
  );
  const pickTotal = modal.getByRole("checkbox", { name: /卒業単位の合計を取り込む/ });
  const confirmTotal = modal.getByRole("checkbox", {
    name: "成績確認表と照合し、重複単位を除いた合計であることを確認した",
  });
  await pickTotal.waitFor();
  assert.equal(await confirmTotal.count(), 1);
  assert.equal(await pickTotal.isDisabled(), true);
  await confirmTotal.check();
  await pickTotal.check();
  await confirmTotal.uncheck();
  assert.equal(await pickTotal.isDisabled(), true);
  assert.equal(await pickTotal.isChecked(), false);
  await confirmTotal.check();
  assert.equal(await pickTotal.isChecked(), false);
  await modal.getByRole("checkbox", { name: /英語を取り込む/ }).check();
  await accept();
  await modal.waitFor({ state: "hidden" });
  assert.equal((await readState()).balances[0].current, 2.5);
  await page.evaluate(() => {
    const packet = {
      v: 1,
      kind: "registration",
      tables: [
        {
          heading: "許可された科目",
          rows: [
            ["開講番号", "科目名"],
            ["261G7011", "架空科目"],
          ],
        },
      ],
    };
    window.dispatchEvent(
      new CustomEvent("mbg:planner-import", { detail: packet }),
    );
  });
  await picked().waitFor();
  assert.equal((await readState()).status["261G7011"], "不許可");
  await picked().check();
  await accept();
  await modal.waitFor({ state: "hidden" });
  assert.equal((await readState()).status["261G7011"], "許可");
  await open("grades");
  await upload("不正.pdf", "application/pdf", Buffer.from("invalid"));
  await modal
    .getByRole("alert")
    .getByText("PDFの形式を確認してください。")
    .waitFor();
  assert.equal((await readState()).grades.length, 1);
  await modal.getByText("1科目ずつ入力", { exact: true }).click();
  await modal.getByLabel("授業名", { exact: true }).fill("手入力講義");
  await modal.getByLabel("修得年度", { exact: true }).fill("2019");
  await modal.getByLabel("修得単位", { exact: true }).fill("2");
  await modal.getByRole("button", { name: "入力内容を確認" }).click();
  assert.equal(await modal.locator("details").evaluate((e) => e.open), false);
  await picked().check();
  await accept();
  await modal.waitFor({ state: "hidden" });
  const manual = (await readState()).grades[1];
  assert.deepEqual(
    [manual.title, manual.credits, manual.source, manual.matchedCourse.year],
    ["手入力講義", 2, "本人入力", "2019"],
  );

  const nativeGrade = (title, alternative = "") =>
    page.evaluate(
      ([name, oldName]) =>
        window.dispatchEvent(
          new CustomEvent("mbg:planner-import", {
            detail: {
              v: 1,
              kind: "grades",
              tables: [
                {
                  heading: "単位修得状況照会",
                  rows: [
                    ["科目名", "単位数", "評価", "年度", "読替科目名"],
                    [name, "1", "可", "2018", oldName],
                  ],
                },
              ],
            },
          }),
        ),
      [title, alternative],
    );
  await page.evaluate(() => {
    window.testArchive.wait = true;
  });
  await nativeGrade("取消講義", "架空科目");
  const exclusionLabel = "同一科目の重複単位として除外";
  const excludeDuplicate = modal.getByRole("checkbox", { name: exclusionLabel });
  const confirmDistinct = modal.getByRole("checkbox", { name: "別々に算入できる単位と確認した" });
  await excludeDuplicate.check();
  await confirmDistinct.check();
  assert.equal(await excludeDuplicate.isChecked(), false);
  await excludeDuplicate.check();
  assert.equal(await confirmDistinct.isChecked(), false);
  await picked().check();
  await accept();
  await page.waitForFunction(
    () => typeof window.testArchive.release === "function",
  );
  assert.equal(await excludeDuplicate.isDisabled(), true);
  assert.equal(await confirmDistinct.isDisabled(), true);
  assert.equal(await picked().isDisabled(), true);
  assert.equal(await modal.getByRole("button", { name: "保存中…" }).isDisabled(), true);
  await page.keyboard.press("Escape");
  await modal.waitFor({ state: "hidden" });
  await nativeGrade("新しい講義");
  await picked().check();
  await accept();
  await modal.waitFor({ state: "hidden" });
  await page.evaluate(async () => {
    window.testArchive.release();
    await new Promise(requestAnimationFrame);
  });
  assert.deepEqual(
    (await readState()).grades.map((g) => g.title),
    ["架空科目", "手入力講義", "新しい講義"],
  );
  assert.equal((await readState()).grades[2].source, "単位修得状況照会");
  const takeEvaluation = async () => {
    await evaluation.waitFor();
    const evaluationRow = evaluation.locator("xpath=ancestor::li");
    assert.equal(await evaluationRow.getByRole("checkbox", { name: exclusionLabel }).count(), 0);
    assert.equal(await evaluation.isChecked(), false);
    await modal.getByText(/配当 2単位・修得 0単位/).waitFor();
    await evaluation.check();
    await accept();
    await modal.waitFor({ state: "hidden" });
    const outcomes = (await readState()).grades.filter(
      (grade) => grade.finalEvaluation,
    );
    assert.equal(outcomes.length, 1);
    const [g] = outcomes;
    assert.deepEqual(
      [
        g.title,
        g.grade,
        g.credits,
        g.counts,
        g.duplicate,
        g.matchedCourse.code,
      ],
      ["初等教育実習I", "不可", 2, false, false, "260K9202"],
    );
  };
  await open("grades");
  await upload("最終評価.pdf", "application/pdf", pdf);
  await takeEvaluation();
  await open("grades");
  await upload(
    "最終評価.csv",
    "text/csv",
    Buffer.from(
      "年度,開講番号,科目名,配当単位,修得単位,評価\n2026,260K9202,初等教育実習I,2,0,不可",
    ),
  );
  await takeEvaluation();
  await page.evaluate(() =>
    window.dispatchEvent(
      new CustomEvent("mbg:planner-import", {
        detail: {
          v: 1,
          kind: "grades",
          tables: [
            {
              heading: "単位修得状況照会",
              rows: [
                ["年度", "開講番号", "科目名", "単位数", "評価", "合否"],
                ["2026", "260K9202", "初等教育実習I", "2", "不可", "不合格"],
              ],
            },
          ],
        },
      }),
    ),
  );
  await takeEvaluation();
  await open("grades");
  await modal.getByText("1科目ずつ入力", { exact: true }).click();
  await modal.getByLabel("評価", { exact: true }).selectOption("不可");
  await modal.getByLabel("授業名", { exact: true }).fill("初等教育実習I");
  await modal.getByLabel("開講番号", { exact: true }).fill("260K9202");
  await modal.getByLabel("履修年度", { exact: true }).fill("2026");
  await modal.getByLabel("配当単位（修得は0単位）", { exact: true }).fill("2");
  await modal.getByRole("button", { name: "入力内容を確認" }).click();
  await takeEvaluation();
  assert.deepEqual(errors, []);
  assert.deepEqual(outgoing, []);
  console.log(
    "Chrome: PDF, CSV, TSV, manual and native review; zero-credit final evaluation opt-in across four inputs, selected archive matches, canceled lookup, invalid PDF, zero external/upload requests.",
  );
});
