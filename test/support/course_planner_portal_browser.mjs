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
async function generatedScript(name) {
  const file = new URL(
    "../../lib/src/generated/course_planner_" + name + ".g.dart",
    import.meta.url,
  );
  const text = await readFile(file, "utf8");
  const [, script] = text.match(/=\s*r'''([\s\S]*?)''';/);
  return script;
}
const capture = await generated("capture");
const fetchScript = await generatedScript("fetch");
const portal = "https://gakujo.iess.niigata-u.ac.jp/campusweb/";
const delayed = new Map();
const redirects = new Map();
const requests = [];
const browser = await chromium.launch({
  channel: process.env.CHROME_CHANNEL || "chrome",
  headless: true,
  chromiumSandbox: true,
});
try {
  const context = await browser.newContext();
  await context.route("**/*", (route) => {
    const req = route.request();
    requests.push({ method: req.method(), url: req.url() });
    if (redirects.has(req.url())) {
      return route.fulfill({
        status: 302,
        headers: { location: redirects.get(req.url()) },
        body: "",
      });
    }
    return route.fulfill({
      status: 200,
      contentType: "text/html; charset=utf-8",
      body: delayed.get(req.url()) || "<main>fixture</main>",
    });
  });
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
      ["年度", "開講番号", "科目名", "単位数"],
      ["2026", "261G7014", "合成英語", "1.0"],
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

  // --- Background fetch tests (discovery, parity, multi-kind, session expiry) ---
  const runFetch = async () => JSON.parse(await page.evaluate(fetchScript));
  const gradesFlowUrl = portal + "campussquare.do?_flowId=SIW0001300-flow";
  const regFlowUrl = portal + "campussquare.do?_flowId=RSW0001000-flow";
  const regSem2Url =
    portal + "campussquare.do?_flowExecutionKey=e1s1&_eventId=search&gakkiKbnCode=2";
  const menuFrameUrl = portal + "campusportal.do?view=menu";

  // Parity fixture: form#taniReferListForm + table (no <h1>), <br> + nested spans,
  // inline hidden elements, balances, and student profile.
  const parityGradesHtml =
    '<table><tr><th>氏名</th><td>PRIVATE-NAME</td><th>所属</th><td>理学部<br><span>物理<span>学科</span></span></td>' +
    '<th>学年</th><td><span>２</span></td></tr></table>' +
    '<form id="taniReferListForm"></form>' +
    '<table><tr><th>開講<br><span>番号</span></th><th>科<span>目</span><br>名</th><th>単位数</th><th>評価</th><th>年度</th><th>担当教員</th></tr>' +
    '<tr><td><span>261G</span><span>7011</span></td><td><span>合成</span><br><span><span>力学</span></span><span style="display:none">SECRET</span><template>TMPL</template></td>' +
    '<td>＊2.0</td><td>認定</td><td>2026</td><td>private-teacher</td></tr>' +
    '<tr style="display:none"><td>261G9999</td><td>非表示科目</td><td>2</td><td>秀</td><td>2026</td><td>x</td></tr></table>' +
    '<table hidden><tr><th>開講番号</th><th>科目名</th><th>単位数</th><th>評価</th></tr>' +
    '<tr><td>261G8888</td><td>隠し表</td><td>2</td><td>優</td></tr></table>' +
    '<table><tr><th>科目<br><span>区分</span></th><th>既修得<br>単位数</th><th>備考</th></tr>' +
    '<tr><td><span>教養</span><br><span>教育</span></td><td>10.5</td><td>private-note</td></tr></table>';

  // Parity fixture for registration: all explicit blue encodings + ?/red + ?/blue + non-blue + denied table.
  const parityRegHtml =
    "<h1>履修登録・登録状況照会</h1>" +
    "<table><tr><td>年度・学期</td><td>2026年度 第1学期</td></tr></table>" +
    "<table><tr>" +
    '<td><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7011\',\'2\',\'3\')" style="color:red">？261G7011 (T1)</a><br>合成申請&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    '<td><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7012\',\'2\',\'3\')" style="color:blue">261G7012 (T1)</a><br>合成青名前&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    '<td><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7013\',\'2\',\'3\')" style="color:#00f">261G7013 (T1)</a><br>合成青短縮&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    '<td><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7014\',\'2\',\'3\')" style="color:#0000ff">261G7014 (T1)</a><br>合成青六桁&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    '<td><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7015\',\'2\',\'3\')" style="color:rgb(0, 0, 255)">261G7015 (T1)</a><br>合成青RGB&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    '<td><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7016\',\'2\',\'3\')"><font color="blue">261G7016 (T1)</font></a><br>合成フォント青&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    '<td><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7017\',\'2\',\'3\')"><font color="#0000ff">261G7017 (T1)</font></a><br>合成フォント六桁&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    '<td><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7018\',\'2\',\'3\')" style="color:blue">？261G7018 (T1)</a><br>合成疑問青&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    '<td><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7019\',\'2\',\'3\')" style="color:purple">261G7019 (T1)</a><br>合成紫&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    "</tr></table>" +
    '<table><tr><td colspan="3">不許可となった科目</td></tr><tr><td>開講番号</td><td>科目名</td><td>単位数</td></tr>' +
    "<tr><td>261G7020 (T1)</td><td>合成不許可</td><td>1.0単位</td></tr></table>";

  // Capture live output on exact same HTML fixtures first.
  delayed.set(gradesFlowUrl, parityGradesHtml);
  await page.goto(gradesFlowUrl);
  assert.deepEqual(await ask({}), ["grades", "balances", "profile"]);
  const liveParityGrades = await ask({ kind: "grades" });
  const liveParityBalances = await ask({ kind: "balances" });
  const liveParityProfile = await ask({ kind: "profile" });
  assert.equal(liveParityGrades.tables[0].rows[1][1], "合成 力学");
  assert.equal(liveParityProfile.tables[0].rows[1][0], "理学部 物理学科");

  delayed.set(regFlowUrl, parityRegHtml);
  await page.goto(regFlowUrl);
  assert.deepEqual(await ask({}), ["registration"]);
  const liveParityReg = await ask({ kind: "registration" });
  assert.deepEqual(
    liveParityReg.tables[0].rows.slice(1).map((r) => r[3]),
    ["申請中", "許可", "許可", "許可", "許可", "許可", "許可", "要確認", "要確認"],
  );

  // Now test background fetch from a non-inquiry portal home page with menu links in a same-origin frame.
  delayed.set(
    menuFrameUrl,
    '<nav>' +
      '<a href="/campusweb/campussquare.do?_flowId=SIW0001300-flow">単位修得状況照会</a>' +
      '<a href="#" onclick="openMenu(\'/campusweb/campussquare.do?_flowId=RSW0001000-flow\')">履修登録・登録状況照会</a>' +
      '</nav>',
  );
  delayed.set(url, '<iframe src="' + menuFrameUrl + '"></iframe>');
  await page.goto(url);
  requests.length = 0;
  const fetchedParity = await runFetch();
  assert.deepEqual(Object.keys(fetchedParity.packets), [
    "profile",
    "grades",
    "balances",
    "registration",
  ]);
  assert.equal(JSON.stringify(fetchedParity.packets.grades), JSON.stringify(liveParityGrades));
  assert.equal(JSON.stringify(fetchedParity.packets.balances), JSON.stringify(liveParityBalances));
  assert.equal(JSON.stringify(fetchedParity.packets.profile), JSON.stringify(liveParityProfile));
  assert.equal(JSON.stringify(fetchedParity.packets.registration), JSON.stringify(liveParityReg));
  assert.deepEqual(requests, [
    { method: "GET", url: gradesFlowUrl },
    { method: "GET", url: regFlowUrl },
  ]);

  // The rs portal tab has no grades link: both inquiries must still be fetched.
  const rsUrl = portal + "campusportal.do?page=main&tabId=rs";
  delayed.set(rsUrl, '<nav><span onclick="loadPortletMenu(\'main\',\'campussquare.do?_flowId=RSW0001000-flow\')">履修登録・登録状況照会</span></nav>');
  await page.goto(rsUrl);
  requests.length = 0;
  assert.deepEqual(await runFetch(), fetchedParity);
  assert.deepEqual(requests, [
    { method: "GET", url: gradesFlowUrl },
    { method: "GET", url: regFlowUrl },
  ]);

  // A discovered grades link takes precedence over the fallback, including its query.
  const discoveredGradesUrl = gradesFlowUrl + "&locale=ja";
  delayed.set(discoveredGradesUrl, parityGradesHtml);
  await page.setContent('<a href="' + discoveredGradesUrl + '">単位修得状況照会</a>');
  requests.length = 0;
  assert.deepEqual(await runFetch(), fetchedParity);
  assert.deepEqual(requests, [
    { method: "GET", url: discoveredGradesUrl },
    { method: "GET", url: regFlowUrl },
  ]);
  await page.goto(url);

  // Static mode MUST NOT promote an unstyled timetable link to 許可 (even inside a blue <td>).
  const unstyledRegHtml =
    "<h1>履修登録・登録状況照会</h1>" +
    "<table><tr>" +
    '<td style="color:blue"><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7021\',\'2\',\'3\')">261G7021 (T1)</a><br>合成無指定&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    '<td><div class="tblDivNml">?<a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7022\',\'2\',\'3\')">261G7022 (T1)</a><br>合成未確定&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    "</tr></table>";
  delayed.set(regFlowUrl, unstyledRegHtml);
  const fetchedUnstyled = await runFetch();
  assert.deepEqual(
    fetchedUnstyled.packets.registration.tables[0].rows.slice(1).map((r) => [r[1], r[3]]),
    [
      ["261G7021", "要確認"],
      ["261G7022", "申請中"],
    ],
  );

  // Semester tab following + deduping + rejection of non-search _eventId links on registration page.
  const sem1Html =
    parityRegHtml +
    '<a href="/campusweb/campussquare.do?_flowExecutionKey=e1s1&_eventId=search&amp;gakkiKbnCode=2">第2学期</a>' +
    '<a href="/campusweb/campussquare.do?_flowExecutionKey=e1s1&_eventId=delete&amp;gakkiKbnCode=2">削除</a>' +
    '<a href="https://evil.example/campusweb/campussquare.do?_flowExecutionKey=e1s1&_eventId=search&amp;gakkiKbnCode=3">外部</a>';
  const sem2Html =
    "<h1>履修登録・登録状況照会</h1>" +
    "<table><tr><td>年度・学期</td><td>2026年度 第2学期</td></tr></table>" +
    "<table><tr>" +
    '<td><div class="tblDivNml"><a href="#" onclick="return CallDetail(\'2026\',\'09\',\'261G7099\',\'2\',\'3\')" style="color:blue">261G7099 (T3)</a><br>合成後期&nbsp;非公開教室&nbsp;2.0単位</div></td>' +
    "</tr></table>" +
    '<table><tr><td colspan="3">不許可となった科目</td></tr><tr><td>開講番号</td><td>科目名</td><td>単位数</td></tr>' +
    "<tr><td>261G7020 (T1)</td><td>合成不許可</td><td>1.0単位</td></tr></table>";
  delayed.set(regFlowUrl, sem1Html);
  delayed.set(regSem2Url, sem2Html);
  requests.length = 0;
  const fetchedMultiSem = await runFetch();
  assert.deepEqual(requests, [
    { method: "GET", url: gradesFlowUrl },
    { method: "GET", url: regFlowUrl },
    { method: "GET", url: regSem2Url },
  ]);
  // Sem1 timetable + Sem1 denied + Sem2 timetable (duplicate Sem2 denied table deduped).
  assert.equal(fetchedMultiSem.packets.registration.tables.length, 3);
  assert.equal(fetchedMultiSem.packets.registration.year, "2026");

  // An advertised past-year tab has the same inquiry action. Denied tables
  // retain their own printed year after combining captures from two years.
  const oldQuery = "_flowExecutionKey=e1s1&_eventId=search&gakkiKbnCode=2&nendo=2025";
  const oldRegUrl = portal + "campussquare.do?" + oldQuery;
  delayed.set(regFlowUrl, sem1Html +
    '<a href="/campusweb/campussquare.do?' + oldQuery.replaceAll("&", "&amp;") + '">2025年度 第2学期</a>' +
    '<a href="/campusweb/campussquare.do?' + oldQuery.replaceAll("&", "&amp;") + '&amp;nendo=2024">重複指定</a>' +
    '<a href="/campusweb/campussquare.do?_flowId=SIW0001300-flow&amp;_eventId=search&amp;gakkiKbnCode=2&amp;nendo=2025">別の照会</a>');
  delayed.set(oldRegUrl, sem2Html.replaceAll("2026年度", "2025年度").replaceAll("'2026'", "'2025'").replaceAll("261G", "251G"));
  requests.length = 0;
  const combined = (await runFetch()).packets.registration;
  assert.equal(combined.year, undefined);
  assert.deepEqual(combined.tables.filter(table => table.heading === "不許可となった科目").map(table => table.rows[1].slice(0, 2)),
    [["2026", "261G7020"], ["2025", "251G7020"]]);
  assert.deepEqual(requests.map(request => request.url), [gradesFlowUrl, regFlowUrl, regSem2Url, oldRegUrl]);
  delayed.set(regFlowUrl, sem1Html);

  // Link discovery: onclick & javascript: href work; cross-origin, _eventId, _flowExecutionKey,
  // non-campussquare, and conflicting duplicate flows are rejected; missing safe links use
  // the grades and registration portlet fallbacks.
  delayed.set(
    url,
    '<nav>' +
      '<a href="https://evil.example/campusweb/campussquare.do?_flowId=EVIL-flow">単位修得状況照会</a>' +
      '<a href="/campusweb/campussquare.do?_flowId=EVIL-flow&_eventId=delete">単位修得状況照会</a>' +
      '<a href="/campusweb/campussquare.do?_flowId=EVIL-flow&_flowExecutionKey=e1s1">単位修得状況照会</a>' +
      '<a href="/campusweb/campusportal.do?_flowId=EVIL-flow">単位修得状況照会</a>' +
      '<a href="/other/campussquare.do?_flowId=EVIL-flow">単位修得状況照会</a>' +
      '</nav>',
  );
  await page.goto(url);
  requests.length = 0;
  const fetchedNoGrades = await runFetch();
  assert.deepEqual(requests, [
    { method: "GET", url: gradesFlowUrl },
    { method: "GET", url: regFlowUrl },
    { method: "GET", url: regSem2Url },
  ]);
  assert.deepEqual(Object.keys(fetchedNoGrades.packets), ["profile", "grades", "balances", "registration"]);
  assert.deepEqual(fetchedNoGrades.packets.grades, liveParityGrades);
  assert.deepEqual(fetchedNoGrades.packets.balances, liveParityBalances);

  // onclick discovery works for grades.
  delayed.set(
    url,
    '<button onclick="go(\'campussquare.do?_flowId=SIW0001300-flow\')">単位修得状況照会</button>',
  );
  await page.goto(url);
  requests.length = 0;
  const fetchedOnclick = await runFetch();
  assert.equal(requests[0].url, gradesFlowUrl);
  assert.ok(fetchedOnclick.packets.grades);

  // javascript: href discovery works for grades.
  delayed.set(
    url,
    '<a href="javascript:openFlow(\'/campusweb/campussquare.do?_flowId=SIW0001300-flow\')">単位修得状況照会</a>',
  );
  await page.goto(url);
  requests.length = 0;
  const fetchedJsHref = await runFetch();
  assert.equal(requests[0].url, gradesFlowUrl);
  assert.ok(fetchedJsHref.packets.grades);

  // Conflicting duplicate grades flows are rejected (ambiguous).
  delayed.set(
    url,
    '<a href="/campusweb/campussquare.do?_flowId=SIW0001300-flow">単位修得状況照会</a>' +
      '<a href="/campusweb/campussquare.do?_flowId=SIW9999999-flow">単位修得状況照会</a>',
  );
  await page.goto(url);
  requests.length = 0;
  const fetchedAmbiguous = await runFetch();
  assert.deepEqual(fetchedAmbiguous.packets.grades, liveParityGrades);
  assert.equal(requests[0].url, gradesFlowUrl);
  assert.ok(!requests.some((r) => r.url.includes("SIW9999999")));

  // Session expired: password or ninshoCode in ANY fetched page returns null (nothing, no partial grades).
  delayed.set(
    url,
    '<a href="/campusweb/campussquare.do?_flowId=SIW0001300-flow">単位修得状況照会</a>',
  );
  await page.goto(url);
  // 1) password in registration page after grades succeeded
  delayed.set(regFlowUrl, '<form><input type="password" name="pw"></form>');
  assert.equal(await runFetch(), null);
  // 2) ninshoCode in semester 2 page after grades + semester 1 succeeded
  delayed.set(regFlowUrl, sem1Html);
  delayed.set(regSem2Url, '<form><input name="ninshoCode"></form>');
  assert.equal(await runFetch(), null);
  // 3) login redirect to campusportal.do containing password input
  delayed.set(portal + "campusportal.do?login=1", '<form><input type="password"></form>');
  redirects.set(regFlowUrl, portal + "campusportal.do?login=1");
  assert.equal(await runFetch(), null);
  redirects.delete(regFlowUrl);
  // 4) visible password input in top page aborts before any XHR
  delayed.set(
    url,
    '<input type="password"><a href="/campusweb/campussquare.do?_flowId=SIW0001300-flow">単位修得状況照会</a>',
  );
  await page.goto(url);
  requests.length = 0;
  assert.equal(await runFetch(), null);
  assert.deepEqual(requests, []);

  console.log(
    "Portal frame, grade, balance, registration, privacy, and background-fetch checks passed.",
  );
} finally {
  await browser.close();
}
