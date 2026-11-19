// Run after npm --prefix course_planner ci and npm --prefix web_scripts run build.
// Browser requests to the portal and planner origins are fulfilled locally.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
const require = createRequire(
  new URL("../../course_planner/package.json", import.meta.url),
);
const { chromium } = require("playwright-core");
async function generated(name) {
  const file = new URL(
    "../../lib/src/generated/course_planner_" + name + ".g.dart",
    import.meta.url,
  );
  const text = await readFile(file, "utf8");
  const [, prefix, suffix] = text.match(
    /Prefix =\s*r'''([\s\S]*?)''';[\s\S]*?Suffix =\s*r'''([\s\S]*?)''';/,
  );
  return (config) => prefix + JSON.stringify(config) + suffix;
}
const capture = await generated("capture"),
  delivery = await generated("delivery");
const portal = "https://gakujo.iess.niigata-u.ac.jp/campusweb/";
const planner = "https://gakujo.terudoru.com/planner/";
const delayed = new Map();
const browser = await chromium.launch({
  channel: process.env.CHROME_CHANNEL || "chrome",
  headless: true,
  chromiumSandbox: true,
});
try {
  const context = await browser.newContext();
  await context.route("**/*", (route) =>
    route.fulfill({
      status: 200,
      contentType: "text/html; charset=utf-8",
      body: delayed.get(route.request().url()) || "<main>fixture</main>",
    }),
  );
  const page = await context.newPage();
  const url = portal + "campusportal.do";
  const gradeUrl = portal + "campussquare.do?view=grade";
  const table =
    '<form id="taniReferListForm"></form><table><tr><th>開講番号</th><th>科目名</th><th>単位数</th><th>評価</th><th>年度</th><th>担当教員</th><th>在籍番号</th></tr>' +
    "<tr><td>261G7011</td><td>合成科目</td><td>＊2.0</td><td>認定</td><td>2026</td><td>private-teacher</td><td>private-id</td></tr>" +
    '<tr><td colspan="7">個人情報</td></tr>' +
    "<tr><td></td><td>private name</td><td>2</td><td>可</td><td></td><td></td><td></td></tr></table>";
  const balances =
    "<table><tr><th>科目区分</th><th>既修得単位数</th><th>備考</th></tr>" +
    "<tr><td>教養教育に関する科目</td><td>10.5</td><td>private-note</td></tr>" +
    "<tr><td>氏名</td><td>学年</td><td>連絡先</td></tr><tr><td>private name</td><td>2</td><td>private</td></tr></table>";
  delayed.set(gradeUrl, table + balances);
  delayed.set(
    url,
    '<iframe id="main-frame-if" src="' +
      gradeUrl +
      '"></iframe><iframe hidden src="' +
      gradeUrl +
      '"></iframe>',
  );
  await page.goto(url);
  const ask = async (config) =>
    JSON.parse(await page.evaluate(capture({ attempt: "A", ...config })));
  assert.deepEqual(await ask({}), ["grades", "balances"]);
  const grades = await ask({ kind: "grades" });
  assert.deepEqual(grades, {
    v: 1,
    kind: "grades",
    tables: [
      {
        heading: "単位修得状況照会",
        rows: [
          ["開講番号", "科目名", "単位数", "評価", "年度"],
          ["261G7011", "合成科目", "*2.0", "認定", "2026"],
        ],
      },
    ],
  });
  assert.deepEqual((await ask({ kind: "balances" })).tables[0].rows, [
    ["科目区分", "既修得単位数"],
    ["教養教育に関する科目", "10.5"],
  ]);
  await page.locator("#main-frame-if").evaluate((frame) => {
    frame.hidden = true;
  });
  assert.equal(await ask({ kind: "grades" }), null);
  await page.locator("#main-frame-if").evaluate((frame) => {
    frame.hidden = false;
  });
  await page
    .frames()
    .find((f) => f.url() === gradeUrl)
    .goto(gradeUrl);
  assert.equal(await ask({ kind: "grades" }), null);
  await page.goto(gradeUrl);
  function courseCredits(headers, rows) {
    const cells = (tag, values) =>
      values.map(v => `<${tag}>${v}</${tag}>`).join("");
    const body = rows.map(row => `<tr>${cells("td", row)}</tr>`).join("");
    return `<table><tr>${cells("th", headers)}</tr>${body}</table>`;
  }
  const gradeColumns = ["開講番号", "開講所属", "科目区分", "評価", "年度"];
  const identities = [
    ["260K0363", "教育学部", "専門", "不可", "2026"],
    ["250K0363", "教育学部", "専門", "不可", "2025"],
  ];
  for (const earned of ["修得単位", "修得単位数", "取得単位数"]) {
    await page.setContent("<h1>単位修得状況照会</h1>" +
      courseCredits([...gradeColumns, earned, "学籍番号"],
        identities.map(row => [...row, "０", "private-student"])) +
      courseCredits(["科目区分", "修得単位数", "備考"], [["専門", "10", "private-note"]]));
    assert.deepEqual(await ask({}), ["grades", "balances"]);
    assert.deepEqual((await ask({ kind: "grades" })).tables.map(t => t.rows), [[
      [...gradeColumns, "修得単位数"], ...identities.map(row => [...row, "0"]),
    ]]);
    assert.deepEqual((await ask({ kind: "balances" })).tables.map(t => t.rows), [[
      ["科目区分", "既修得単位数"], ["専門", "10"],
    ]]);
  }
  for (const allocated of ["配当単位", "配当単位数"]) {
    const examples = [
      ["260K0363", "不可", "0", "2"],
      ["250K0363", "不可", "1", "2"],
      ["261K0501", "優", "1", "1"],
    ];
    await page.setContent("<h1>単位修得状況照会</h1>" +
      courseCredits(["開講番号", "評価", "修得単位", "学生氏名", allocated],
        examples.map(([code, grade, earned, offered]) => [code, grade, earned, "private-name", offered])));
    assert.deepEqual(await ask({}), ["grades"]);
    assert.deepEqual((await ask({ kind: "grades" })).tables[0].rows, [
      ["開講番号", "評価", "修得単位数", "単位数"], ...examples,
    ]);
  }
  for (const [offering, section, term] of [
    ["開講所属", "クラス", "学期"],
    ["開講所属コード", "クラス名", "履修学期"],
    ["開講学部", "組", "修得学期"],
    ["開設学部", "クラス番号", "ターム"],
  ]) {
    const faculty = offering.endsWith("コード") ? "01" : "人文学部";
    const headers = ["開講番号", "科目名", "単位数", "評価", "年度", offering, section, term,
      "所属", "学部", "所属学部", "学生所属", "氏名", "在籍番号", "担当教員"];
    const academic = ["261K0501", "情報通信技術教育論I", "1", "優", "2026", faculty, "A", "第1ターム"];
    const row = [...academic, ...Array(7).fill("PRIVATE-COLUMN-CANARY")];
    await page.setContent('<form id="taniReferListForm"></form><table><tr>' +
      headers.map((h) => "<th>" + h + "</th>").join("") + "</tr><tr>" +
      row.map((v) => "<td>" + v + "</td>").join("") + "</tr></table>");
    assert.deepEqual(await ask({}), ["grades"]);
    const captureRow = async () => (await ask({ kind: "grades" })).tables[0].rows;
    assert.deepEqual(await captureRow(), [
      ["開講番号", "科目名", "単位数", "評価", "年度", "開講所属", "クラス", "学期"], academic,
    ]);
    await page.locator("td").nth(5).evaluate((cell) => { cell.textContent = "fixture@example.invalid"; });
    assert.deepEqual((await captureRow())[1], [...academic.slice(0, 5), "要確認", "A", "第1ターム"]);
  }
  const registration = portal + "campussquare.do?_flowId=RSW0001000-flow";
  const grid = (code, marker, color) =>
    "<td><div class=\"tblDivNml\"><a href=\"#\" onclick=\"return CallDetail('2026','09','" +
    code +
    "','2','3')\" style=\"color:" +
    color +
    '">' +
    marker +
    code +
    ' (T1)</a><br>合成の授業&nbsp;非公開教室&nbsp;2.0単位<br><input value="削除"></div></td>';
  delayed.set(
    registration,
    "<h1>履修登録・登録状況照会</h1><table><tr><td>氏名</td><td>private-name</td><td>年度・学期</td><td>2026年度 第1学期</td></tr></table>" +
      "<table><tr>" +
      grid("261G7011", "？", "red") +
      grid("261G7012", "", "blue") +
      grid("261G7013", "", "purple") +
      "</tr></table>" +
      '<table><tr><td colspan="5">不許可となった科目</td></tr><tr><td>開講番号</td><td>科目名</td><td>講義室</td><td>開講期間</td><td>単位数</td></tr>' +
      "<tr><td>261G7014 (T1)</td><td>合成英語</td><td>private-room</td><td>月1</td><td>1.0単位</td></tr></table>",
  );
  await page.goto(registration);
  assert.deepEqual(await ask({}), ["registration"]);
  const packet = await ask({ kind: "registration" });
  assert.equal(packet.year, "2026");
  assert.deepEqual(
    packet.tables[0].rows.slice(1).map((r) => r[3]),
    ["申請中", "許可", "要確認"],
  );
  assert.deepEqual(packet.tables[1], {
    heading: "不許可となった科目",
    rows: [
      ["開講番号", "科目名", "単位数"],
      ["261G7014", "合成英語", "1.0"],
    ],
  });
  assert.doesNotMatch(JSON.stringify(packet), /private|非公開|https?:|削除/);
  delayed.set(
    url,
    '<table><tr><td>履修登録・登録状況照会</td></tr></table><iframe src="' +
      registration +
      '"></iframe>',
  );
  await page.goto(url);
  assert.deepEqual(await ask({}), ["registration"]);
  assert.deepEqual(await ask({ kind: "registration" }), packet);
  await page
    .frames()
    .find((f) => f.url() === registration)
    .evaluate(() => {
      const grid = document.querySelector(".tblDivNml").closest("table");
      grid.replaceWith(grid.cloneNode(true));
    });
  assert.equal(await ask({ kind: "registration" }), null);
  await page.goto(registration);
  const profileHeader = '<table><tr><th>氏名</th><td>PRIVATE-NAME-CANARY</td>' +
    '<th>学籍番号</th><td>PRIVATE-ID-CANARY</td></tr>' +
    '<tr><th>所属</th><td>理学部物理学科</td><th>学年</th><td>２</td></tr></table>';
  await page.locator("body").evaluate((body, html) => body.insertAdjacentHTML("afterbegin", html), profileHeader);
  assert.deepEqual(await ask({}), ["registration", "profile"]);
  const profile = await ask({ kind: "profile" });
  assert.deepEqual(profile, {
    v: 1, kind: "profile",
    tables: [{ heading: "学生所属", rows: [["所属", "学年"], ["理学部物理学科", "2"]] }],
  });
  assert.doesNotMatch(JSON.stringify(profile), /PRIVATE-|氏名|学籍番号/);
  await page.goto(gradeUrl);
  await page.setContent("<h1>単位修得状況照会</h1>" + profileHeader.replace("２", "7") + table);
  assert.deepEqual(await ask({}), ["grades", "profile"]);
  assert.deepEqual((await ask({ kind: "profile" })).tables[0].rows[1], ["理学部物理学科", ""]);
  await page.setContent("<h1>単位修得状況照会</h1>" + profileHeader.replace("理学部物理学科", "fixture@example.invalid") + table);
  assert.deepEqual(await ask({}), ["grades"]);
  assert.equal(await ask({ kind: "profile" }), null);
  await page.goto(registration);
  await page.setContent(
    "<h1>履修登録・登録状況照会</h1><table><tr><th>開講番号</th><th>科目名</th></tr><tr><td>261G7011</td><td>検索結果だけの科目</td></tr></table>",
  );
  assert.deepEqual(await ask({}), []);
  await page.goto(portal + "attachment.html");
  await page.setContent(table);
  assert.deepEqual(await ask({}), []);
  await page.goto("https://syllabus.niigata-u.ac.jp/campusweb/campussquare.do");
  await page.setContent(table);
  assert.equal(await ask({}), null);
  await page.goto(planner);
  const step = (phase, data) =>
    page.evaluate(
      delivery({
        origin: new URL(planner).origin,
        path: "/planner/",
        attempt: "ticket",
        phase,
        packet: data,
      }),
    );
  assert.equal(await step("bind"), "bound");
  assert.equal(await step("probe"), "waiting");
  await page.evaluate(() => {
    window.received = [];
    window.addEventListener("mbg:planner-import", (e) =>
      window.received.push(e.detail),
    );
    window.addEventListener("mbg:planner-probe", () =>
      window.dispatchEvent(new Event("mbg:planner-ready")),
    );
  });
  assert.equal(await step("probe"), "ready");
  assert.equal(await step("deliver", packet), "sent");
  assert.equal(await step("deliver", packet), "sent");
  assert.deepEqual(await page.evaluate(() => window.received), [packet]);
  await page.reload();
  assert.equal(await step("deliver", packet), "wrong-document");
  await page.goto(planner + "other");
  assert.equal(await step("bind"), "wrong-document");
  await page.goto(planner + "#list=unrelated");
  assert.equal(await step("bind"), "wrong-document");
  console.log(
    "Portal frame, grade, balance, registration, privacy and planner document checks passed.",
  );
} finally {
  await browser.close();
}
