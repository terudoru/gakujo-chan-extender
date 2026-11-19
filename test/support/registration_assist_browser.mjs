// Run after npm --prefix course_planner ci and npm --prefix web_scripts run build.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";

const require = createRequire(new URL("../../course_planner/package.json", import.meta.url));
const { chromium } = require("playwright-core");
const source = await readFile(new URL("../../lib/src/generated/registration_assist.g.dart", import.meta.url), "utf8");
const [, prefix, suffix] = source.match(/Prefix =\s*r'''([\s\S]*?)''';[\s\S]*?Suffix =\s*r'''([\s\S]*?)''';/);
const token = (await readFile(new URL("./registration_handoff.txt", import.meta.url), "utf8")).trim();
const plan = JSON.parse(Buffer.from(token.slice("MBGREG1.".length), "base64url").toString("utf8"));

const portal = "https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do";
const flow = `${portal}?_flowId=RSW0001000-flow`;
const stepUrl = (view, semester) => `${portal}?_flowExecutionKey=e1s2&view=${view}&semester=${semester}`;
const heading = "<h1>履修登録・登録状況照会</h1>";
const days = ["月", "火", "水", "木", "金", "土"];
const registered = new Set(["261A0001"]);
let closed = false;
let bothTabs = false;
let matches = 1;
let permitSelection = true;
let alert = "";
let facultyOption = true;
const searchRequests = [];
const selections = [];

function grid(semester) {
  const gridTable = (term) => `<table><caption>第${term}学期</caption>
    <tr><th>時限</th>${days.map((day) => `<th>${day}</th>`).join("")}</tr>
    <tr><th>1限</th>${days.map((day, index) => {
      const code = index === 0 && term === 1
        ? (registered.has("171G0057") ? "171G0057" : "261A0001")
        : index === 1 && term === 2 && registered.has("174G5512") ? "174G5512" : "";
      return `<td>${closed ? "" : `<a href="${stepUrl("condition", term)}&day=${day}">追加</a>`}
        ${!code ? "" : `<div class="tblDivNml"><a href="#" onclick="CallDetail('2026','09','${code}','1','1')">? ${code} (T1)</a>
          <br>合成科目<input type="button" value="削除" onclick="confirm('fixture delete')"><a href="#syllabus">シラバス</a></div>`}</td>`;
    }).join("")}</tr></table>`;
  return `${heading}<table><tr><th>年度・学期</th><td>2026年度 第${semester}学期</td></tr></table>
    <nav><a href="${stepUrl("grid", 1)}">第1学期</a> <a href="${stepUrl("grid", 2)}">第2学期</a></nav>
    <a href="#intensive">集中講義を登録</a>
    ${gridTable(semester)}${bothTabs ? gridTable(3 - semester) : ""}
    <table><caption>不許可となった科目</caption><tr><th>開講番号</th><th>科目名</th></tr>
    <tr><td>171G0057</td><td>過年度の合成科目</td></tr></table>
    ${alert ? `<p role="alert">${alert}</p>` : ""}`;
}

function condition(semester, day) {
  return `${heading}<h2>条件入力</h2>
    <form method="post" action="${stepUrl("results", semester)}">
    <table>
      <tr><th>開講所属</th><td><select name="faculty"><option>合成学部</option>${facultyOption ? "<option>指示なし</option>" : ""}</select></td></tr>
      <tr><th>開講番号</th><td><input name="code"></td></tr>
      <tr><th>科目名</th><td><input name="title" value="keep"></td></tr>
      <tr><th>曜日</th><td><select name="day"><option>${day}</option></select></td></tr>
      <tr><th>時限</th><td><select name="period"><option>1限</option></select></td></tr>
    </table><button>検索開始</button><button type="button">開講番号検索</button>
    <a href="${stepUrl("grid", semester)}">戻る</a></form>`;
}

function results(semester, code) {
  const resultRow = (actualCode) => `<tr><td><a href="${stepUrl("selected", semester)}&code=${actualCode}">選択</a></td>
    <td><label><input type="radio" name="${actualCode}" value="high">高</label>
    <label><input type="radio" name="${actualCode}" value="normal" checked>なし</label></td>
    <td>${actualCode}</td><td>合成科目</td></tr>`;
  return `${heading}<h2>検索結果</h2><table>
    <tr><th>選択</th><th>優先度</th><th>開講番号</th><th>科目名</th></tr>
    ${resultRow(code + "X")}${resultRow(code.replace(/[0-9A-Z]/g, (c) => String.fromCharCode(c.charCodeAt(0) + 0xfee0)))}
    ${Array.from({ length: matches }, () => resultRow(code)).join("")}
    </table><a href="${stepUrl("grid", semester)}">戻る</a>
    <button>登録</button><button>確定</button><button>申請</button><button>OK</button>`;
}

const browser = await chromium.launch({
  channel: process.env.CHROME_CHANNEL || "chrome",
  headless: true,
  chromiumSandbox: true,
});
try {
  const context = await browser.newContext({ serviceWorkers: "block" });
  const interactions = [];
  const witnessed = [];
  const forbidden = [];
  await context.exposeBinding("fixtureInteraction", (_, event) => interactions.push(event));
  await context.exposeBinding("fixtureChoice", (_, ticket) => witnessed.push(ticket));
  await context.addInitScript(() => {
    window.MbgRegistrationChoice = { postMessage: (ticket) => window.fixtureChoice(ticket) };
    const checked = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "checked");
    Object.defineProperty(HTMLInputElement.prototype, "checked", {
      ...checked,
      set(value) {
        if (this.type === "radio") window.fixtureInteraction({ type: "radio assignment" });
        checked.set.call(this, value);
      },
    });
    const submit = HTMLFormElement.prototype.submit;
    HTMLFormElement.prototype.submit = function () {
      window.fixtureInteraction({ type: "direct form submit" });
      return submit.call(this);
    };
    for (const type of ["click", "input", "change", "submit"]) {
      document.addEventListener(type, (event) => {
        const control = event.target.closest?.("a,button,input,select,form");
        if (!control) return;
        window.fixtureInteraction({
          type,
          trusted: event.isTrusted,
          text: control.value || control.innerText?.trim(),
          role: control.type,
          name: control.name,
          submitter: event.submitter?.innerText,
        });
      }, true);
    }
    window.confirm = () => {
      window.fixtureInteraction({ type: "confirm" });
      return false;
    };
  });
  await context.route("**/*", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (!request.isNavigationRequest()) {
      forbidden.push(request.resourceType());
      await route.abort();
      return;
    }
    const semester = Number(url.searchParams.get("semester") || "1");
    const view = url.searchParams.get("view") || "grid";
    let body = grid(semester);
    if (view === "condition") body = condition(semester, url.searchParams.get("day"));
    if (view === "results") {
      const data = Object.fromEntries(new URLSearchParams(request.postData()));
      searchRequests.push(data);
      body = results(semester, data.code);
    }
    if (view === "selected") {
      const code = url.searchParams.get("code");
      selections.push(code);
      if (permitSelection) registered.add(code);
      body = grid(semester);
    }
    await route.fulfill({ contentType: "text/html; charset=utf-8", body });
  });
  const page = await context.newPage();
  page.on("dialog", async (dialog) => {
    forbidden.push(dialog.type());
    await dialog.dismiss();
  });
  const run = async (command, options = {}) => JSON.parse(await page.evaluate(
    prefix + JSON.stringify({ command, href: page.url(), ...options }) + suffix,
  ));
  const clickAndNavigate = async (command, options) => {
    const [result] = await Promise.all([run(command, options), page.waitForNavigation()]);
    assert.equal(result, true);
  };

  await page.goto(flow);
  let snapshot = await run("inspect");
  assert.deepEqual(snapshot.registered, ["261A0001"]);
  assert.deepEqual(snapshot.slots[1], days.map((day) => day + "1"));
  assert.equal(snapshot.slots[2], undefined);
  assert.equal(await run("add", { documentId: snapshot.documentId + 1, year: plan.year,
    semester: 1, slot: "月1", code: "171G0057" }), null);

  for (const course of plan.courses.filter((item) => item.slots.length)) {
    const config = { year: plan.year, semester: course.semester, code: course.code, slot: course.slots[0] };
    if (snapshot.semester !== course.semester) {
      await clickAndNavigate("semester", { ...config, documentId: snapshot.documentId });
      snapshot = await run("inspect");
    }
    assert.equal(snapshot.semester, course.semester);
    await clickAndNavigate("add", { ...config, documentId: snapshot.documentId });
    snapshot = await run("inspect", config);
    assert.equal(snapshot.page, "condition");
    await clickAndNavigate("search", { ...config, documentId: snapshot.documentId });
    snapshot = await run("inspect", config);
    assert.equal(snapshot.count, 1);
    assert.equal(snapshot.selectable, true);
    assert.equal(await run("highlight", { ...config, documentId: snapshot.documentId, ticket: course.code }), true);
    const target = page.getByRole("row").filter({ has: page.getByRole("cell", { name: course.code, exact: true }) });
    assert.match(await target.evaluate((row) => row.style.outline), /3px/);
    await assert.doesNotReject(async () => {
      assert.ok(await target.locator("input[value=normal]").isChecked());
      assert.ok(!await target.locator("input[value=high]").isChecked());
    });
    assert.equal(selections.includes(course.code), false);
    await Promise.all([page.waitForNavigation(), target.getByRole("link", { name: "選択" }).click()]);
    snapshot = await run("inspect");
    assert.ok(snapshot.registered.includes(course.code));
  }

  assert.deepEqual(searchRequests, [
    { faculty: "指示なし", code: "171G0057", title: "keep", day: "月", period: "1限" },
    { faculty: "指示なし", code: "174G5512", title: "keep", day: "火", period: "1限" },
  ]);
  assert.deepEqual(selections, ["171G0057", "174G5512"]);
  assert.deepEqual(witnessed, selections);
  assert.deepEqual(plan.courses[2].slots, []);

  permitSelection = false;
  alert = "定員に達しています。";
  const denied = { code: "175A0010", year: 2026, semester: 2, slot: "火1" };
  await clickAndNavigate("add", { ...denied, documentId: snapshot.documentId });
  snapshot = await run("inspect", denied);
  await clickAndNavigate("search", { ...denied, documentId: snapshot.documentId });
  snapshot = await run("inspect", denied);
  assert.equal(await run("highlight", { ...denied, documentId: snapshot.documentId, ticket: "denied" }), true);
  const deniedRow = page.getByRole("row").filter({ has: page.getByRole("cell", { name: denied.code, exact: true }) });
  await Promise.all([page.waitForNavigation(), deniedRow.getByRole("link", { name: "選択" }).click()]);
  snapshot = await run("inspect");
  assert.ok(!snapshot.registered.includes(denied.code));
  assert.equal(snapshot.message, alert);
  assert.equal(witnessed.at(-1), "denied");
  alert = "";

  bothTabs = true;
  await page.goto(flow);
  snapshot = await run("inspect");
  assert.deepEqual(snapshot.registered, ["171G0057", "174G5512"]);
  assert.deepEqual(Object.keys(snapshot.slots), ["1", "2"]);
  closed = true;
  alert = "時間割が重複しています。";
  await page.goto(flow);
  snapshot = await run("inspect");
  assert.deepEqual(snapshot.slots, { 1: [], 2: [] });
  assert.equal(snapshot.message, alert);
  alert = "学籍番号 12A0000B の履修登録ができません。";
  await page.goto(flow);
  assert.equal((await run("inspect")).message, "");
  await page.goto(flow.replace("RSW0001000", "RSW0002000"));
  assert.equal(await run("inspect"), null);
  await page.goto(flow.replace("campussquare.do", "attachment.html"));
  assert.equal(await run("inspect"), null);
  await page.goto(flow.replace("gakujo.iess", "syllabus"));
  assert.equal(await run("inspect"), null);

  for (const count of [0, 2]) {
    matches = count;
    facultyOption = false;
    const config = { code: "175A0010", year: 2026, semester: 1, slot: "月1" };
    await page.goto(`${stepUrl("condition", 1)}&day=月`);
    snapshot = await run("inspect", config);
    assert.equal(await run("search", { ...config, slot: "火1", documentId: snapshot.documentId }), null);
    await clickAndNavigate("search", { ...config, documentId: snapshot.documentId });
    assert.equal(searchRequests.at(-1).faculty, "合成学部");
    snapshot = await run("inspect", config);
    assert.equal(snapshot.count, count);
    assert.equal(await run("highlight", { ...config, documentId: snapshot.documentId, ticket: "unused" }), null);
    await clickAndNavigate("back", { ...config, documentId: snapshot.documentId });
    assert.equal((await run("inspect")).page, "grid");
  }
  for (const event of interactions) {
    assert.notEqual(event.type, "confirm");
    assert.notEqual(event.role, "radio");
    if (event.type === "submit") assert.equal(event.submitter, "検索開始");
    else if (event.type === "click" && event.trusted) assert.equal(event.text, "選択");
    else if (event.type === "click") assert.ok(["追加", "第1学期", "第2学期", "検索開始", "戻る"].includes(event.text));
    else assert.fail(JSON.stringify(event));
  }
  assert.deepEqual(forbidden, []);
  console.log("Registration assist: fixed vector, both semesters, exact matching, skip, closed period, and forbidden-action checks passed.");
} finally {
  await browser.close();
}
