import assert from "node:assert/strict";
import catalog from "../src/catalog-2026.json" with { type: "json" };
import { matchHistoricalGrades } from "../src/archive/packs.mjs";
import { initialState } from "../src/study.mjs";
import { requirementRows } from "../src/requirements.mjs";

const storageKey = "mbg.course-planner.v1";
const btn = (page, name) => page.getByRole("button", { name, exact: true });
const row = (page, name) => page.locator(".ledger-row").filter({ has: page.getByText(name, { exact: true }) });
const saved = (p) => p.evaluate((key) => JSON.parse(localStorage.getItem(key)), storageKey);
async function seed(page, state) {
  await page.evaluate(([key, data]) => localStorage.setItem(key, JSON.stringify(data)), [storageKey, state]);
  await page.reload();
  await btn(page.locator("nav:visible"), "単位・要件").click();
}
function student(faculty, program, extra = {}) {
  const state = initialState();
  Object.assign(state.profile, { faculty, program, admitted: "2026", handbook: "2026", ...extra });
  return state;
}
async function grade(code) {
  const c = catalog.courses.find((item) => item.code === code);
  const [g] = await matchHistoricalGrades([{ code: c.code, title: c.title, credits: c.credits, year: "2026", grade: "優" }], catalog);
  assert.equal(g.matchedCourse?.confirmed, true);
  return g;
}

async function checkFaculties(cohort) {
  const admissions = [
    ["人文学部", "心理・人間学", "2026", 124],
    ["教育学部", "学校教育学専修", "2026", 131],
    ["法学部", "法学", "2026", 124],
    ["経済科学部", "経済学", "2026", 124],
    ["経済学部（旧課程）", "経済学科（昼間コース）", "2019", 124],
    ["医学部医学科", "", "2026", 219],
    ["医学部保健学科", "看護学専攻", "2026", 124],
    ["歯学部歯学科", "", "2026", 192],
    ["歯学部口腔生命福祉学科", "", "2026", 150],
    ["創生学部", "創生学修コース", "2026", 126],
    ["理学部", "物理学（総合力）", "2026", 124],
    ["工学部", "機械システム工学プログラム", "2026", 124],
    ["農学部", "生物資源科学（植物資源科学分野）", "2026", 124],
  ];
  for (const [faculty, program, handbook, total] of admissions) {
    const state = initialState();
    Object.assign(state.profile, { faculty, program, admitted: handbook, handbook, entry: "1年次入学" });
    await seed(cohort, state);
    const totalRow = cohort.locator(".ledger-row").filter({ hasText: /卒業(単位の合計|の単位合計|に必要な単位数|に算入できる単位)|教養系・学部専門系の合計/ }).first();
    await totalRow.waitFor();
    assert.equal(await totalRow.locator(":scope > span").first().innerText(), String(total), faculty);
    await cohort.getByRole("radio", { name: "進級まで" }).click();
    const sourceSummary = cohort.locator(".ledger-row details summary").first();
    try {
      await sourceSummary.click();
    } catch (error) {
      throw Error(`${faculty}の進級要件に根拠を表示できませんでした。\n${await cohort.locator("main").innerText()}`, { cause: error });
    }
    assert.ok(await cohort.locator(".ledger-row details[open] a[href^='https://']").count(), faculty);
    assert.ok(await cohort.locator("body").evaluate((el) => el.scrollWidth <= innerWidth), faculty);
  }
}

export async function checkCurriculumWorkflows(page) {
  await checkFaculties(page);
  const creation = student("創生学部", "DX共創コース", { yearOfStudy: 3, attendanceMonths: 36 });
  const rules = requirementRows(creation, new Map(), [], "year-4");
  creation.balances = rules.filter((r) => r.unit === "credits").map((r) => ({
    ...creation.profile, goal: "progress", stage: "year-4", key: r.key === "domain-pool" ? "field-pool" : r.key,
    label: r.label, unit: r.unit, required: r.required, duplicateFree: r.key === "total",
    current: r.key === "domain-pool" ? 0 : r.key === "remaining-pool" ? 70 : r.required,
  }));
  await seed(page, creation);
  await page.getByRole("radio", { name: "進級まで" }).click();
  assert.match(await page.locator(".stage-summary").innerText(), /現在\s*不足あり[\s\S]*履修後\s*不足あり/);
  const domain = row(page, "領域基礎・領域科目");
  assert.deepEqual(await domain.locator(":scope > span").allTextContents(), ["26", "0", "26"]);
  await page.getByRole("radio", { name: "卒業まで" }).click();
  assert.ok((await page.locator(".ledger-row strong").allTextContents()).some((s) => /領域基礎/.test(s)));

  const medical = student("医学部医学科", "", { yearOfStudy: 4, assessmentDate: "2026-10-01" });
  await seed(page, medical);
  await page.getByRole("radio", { name: "進級まで" }).click();
  assert.match(await page.locator(".stage-summary strong").innerText(), /進級・実習の判定を選択|5年次進級/);
  await page.getByRole("combobox", { name: "照合する学年・履修条件" }).click();
  await page.getByRole("option", { name: "診療参加型臨床実習の開始", exact: true }).click();
  const cbt = row(page, "臨床実習前共用試験 CBT");
  for (const [label, expected] of [["条件を満たしていない", 0], ["条件を満たした", 1], ["未確認", null]]) {
    await btn(cbt, "学務の判定を入力").click();
    const d = page.getByRole("dialog", { name: "学務の判定を入力" });
    await d.getByRole("combobox", { name: "学務で確認した結果" }).click();
    await page.getByRole("option", { name: label, exact: true }).click();
    await btn(d, "確認結果を保存").click();
    await d.waitFor({ state: "hidden" });
    const decisions = (await saved(page)).balances.filter((b) => b.key === "clinical-CBT");
    assert.equal(decisions.length, expected === null ? 0 : 1);
    if (expected !== null) {
      assert.equal(decisions[0].current, expected);
      assert.equal(decisions[0].scope.assessmentDate, "2026-10-01");
      assert.equal(await cbt.locator(":scope > span").nth(1).innerText(), expected ? "充足" : "未充足");
    }
  }

  const education = student("教育学部", "英語教育専修（小学校主免）", { yearOfStudy: 2 });
  await seed(page, education);
  await btn(page, "成績を取り込む").click();
  const transcript = page.getByRole("dialog");
  await transcript.locator("input[type=file]").setInputFiles({
    name: "assessment.csv", mimeType: "text/csv",
    buffer: Buffer.from("開講番号,科目名,単位数,評価,年度\n260K0363,現代教育学概論,2,不可,2026\n"),
  });
  const optIn = transcript.getByRole("checkbox", { name: /現代教育学概論.*最終評価を確認/ });
  assert.equal(await optIn.isChecked(), false);
  assert.deepEqual((await saved(page)).grades, []);
  await optIn.check();
  await btn(transcript, "選択した1件を取り込む").click();
  await transcript.waitFor({ state: "hidden" });
  const [evaluation] = (await saved(page)).grades;
  assert.deepEqual([evaluation.grade, evaluation.credits, evaluation.finalEvaluation, evaluation.counts, evaluation.matchedCourse?.code],
    ["不可", 2, true, false, "260K0363"]);
  assert.equal(await row(page, "卒業単位の合計").locator(":scope > span").nth(1).innerText(), "0");
  await page.getByRole("radio", { name: "進級まで" }).click();
  await page.getByRole("combobox", { name: "照合する学年・履修条件" }).click();
  await page.getByRole("option", { name: "初等・中等主専攻実習の履修登録", exact: true }).click();
  const pedagogy = page.locator(".ledger-row").filter({ has: page.locator("strong").filter({ hasText: /^現代教育学概論（/ }) });
  assert.equal(await pedagogy.locator(":scope > span").nth(1).innerText(), "充足");
  await pedagogy.locator("summary").click();
  assert.match(await pedagogy.innerText(), /最終評価を受けた科目[\s\S]*修得 0単位/);
  await page.getByRole("radio", { name: "修得履歴" }).click();
  assert.match(await page.getByRole("listitem").filter({ hasText: "現代教育学概論" }).innerText(), /不可[\s\S]*配当 2単位 · 修得 0単位/);

  const engineering = student("工学部", "機械システム工学プログラム", { entry: "" });
  engineering.grades = [await grade("261G7011")];
  await seed(page, engineering);
  async function manualBalance(current) {
    await btn(page, "確認表の内訳を入力").click();
    const d = page.getByRole("dialog");
    await d.getByRole("combobox", { name: "照合する項目" }).click();
    await page.getByRole("option", { name: "人文社会・教育科学", exact: true }).click();
    await d.getByLabel("必要単位").fill("4");
    await d.getByLabel("修得済み").fill(String(current));
    await btn(d, "単位を保存").click();
    await d.waitFor({ state: "hidden" });
  }
  await manualBalance(1);
  const human = row(page, "人文社会・教育科学");
  await human.locator("summary").click();
  assert.match(await human.innerText(), /確認表の修得済み\s*1単位/);
  assert.match(await human.innerText(), /確認表の修得済みに含まれる科目[\s\S]*英語基礎 L[\s\S]*261G7011 · 2026 · 確認表に含む 1単位/);
  await btn(page, "区分別の単位を取り込む").click();
  const imp = page.getByRole("dialog");
  await imp.locator("input[type=file]").setInputFiles({
    name: "balance.csv", mimeType: "text/csv",
    buffer: Buffer.from("科目区分,既修得単位,必要単位\n人文社会・教育科学,2,4\n"),
  });
  await imp.getByRole("checkbox", { name: /を取り込む（行/ }).check();
  await btn(imp, "選択した1件を取り込む").click();
  await imp.waitFor({ state: "hidden" });
  assert.deepEqual(await human.locator(":scope > span").allTextContents(), ["4", "2", "2"]);
  await manualBalance(1);
  assert.equal((await saved(page)).balances.filter((r) => r.key === "human").length, 1);
  assert.deepEqual(await human.locator(":scope > span").allTextContents(), ["4", "1", "3"]);

  const contradicted = await grade("261K0501");
  engineering.grades = [{ ...contradicted, code: "", term: "第4ターム", credits: 3 }];
  await seed(page, engineering);
  await page.getByRole("radio", { name: "修得履歴" }).click();
  const history = page.getByRole("listitem").filter({ hasText: "情報通信技術教育論I" });
  assert.match(await history.innerText(), /3単位[\s\S]*要確認/);
  await btn(history, "要確認 · シラバスを照合").click();
  const details = page.getByRole("dialog");
  await details.getByText("科目ごとの確認事項", { exact: true }).click();
  await details.getByLabel("履修時の年次（西暦ではなく学年）", { exact: true }).fill("3");
  await btn(details, "確認事項を保存").click();
  await page.waitForFunction((key) => JSON.parse(localStorage.getItem(key)).grades[0].studyYear === 3, storageKey);
  await page.keyboard.press("Escape");
  await page.getByRole("radio", { name: "シラバスの分野" }).click();
  const unknown = page.locator(".af-row").filter({ has: page.getByText("分野要確認", { exact: true }) });
  await unknown.locator("summary").click();
  assert.match(await unknown.innerText(), /情報通信技術教育論I[\s\S]*3単位/);
  assert.equal(await page.locator(".af-row").filter({ has: page.getByText("10 情報", { exact: true }) }).count(), 0);
  assert.equal((await saved(page)).grades[0].matchedCourse.confirmed, true);

  const teacherTraining = student("工学部", "機械システム工学プログラム", { yearOfStudy: 1 });
  teacherTraining.lists[0].codes = ["261K0034"];
  await seed(page, teacherTraining);
  await btn(page.locator("nav:visible"), "時間割").click();
  await btn(page, "木曜4限の候補").click();
  const teachingCourse = page.getByRole("listitem").filter({ hasText: "教職入門" });
  await btn(teachingCourse, "この授業を選ぶ").click();
  await page.waitForFunction((key) => JSON.parse(localStorage.getItem(key)).plan.includes("261K0034"), storageKey);
  const sheet = page.getByRole("dialog", { name: "木曜4限の授業" });
  if (await sheet.isVisible()) await btn(sheet, "閉じる").click();
  assert.match(await page.locator(".cap-body b").innerText(), /0\s*\/\s*28\s*単位/);
  assert.match(await page.locator(".cap-body").innerText(), /対象外 2単位/);
}
