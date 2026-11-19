import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { createServer } from "vite";

const plannerRoot = fileURLToPath(new URL("..", import.meta.url));

let vite;
let RequirementEvidence;

function findElement(node, predicate) {
  if (!node || typeof node !== "object") return null;
  if (Array.isArray(node)) {
    for (const item of node) {
      const hit = findElement(item, predicate);
      if (hit) return hit;
    }
    return null;
  }
  if (predicate(node)) return node;
  if (node.props && "children" in node.props) {
    return findElement(node.props.children, predicate);
  }
  return null;
}

before(async () => {
  vite = await createServer({
    root: plannerRoot,
    configFile: false,
    server: { middlewareMode: true, watch: null },
    optimizeDeps: { noDiscovery: true },
    appType: "custom",
    logLevel: "silent",
  });
  ({ RequirementEvidence } = await vite.ssrLoadModule(
    "/src/components/RequirementEvidence.jsx",
  ));
});

after(async () => {
  await vite?.close();
});

test("a completed failing assessment is evidence without earned credits", () => {
  const record = { title: "現代教育学概論", column: "evaluation", year: "2026", grade: "不可",
    reason: "最終評価 不可", credits: 2, applied: 1 };
  const html = renderToStaticMarkup(React.createElement(RequirementEvidence, {
    earned: [record], projectedEarned: [], unit: "condition",
  }));
  assert.match(html, /最終評価を受けた科目/);
  assert.match(html, /修得 0単位/);
  assert.match(html, /最終評価 不可/);
  assert.doesNotMatch(html, /修得済み|履修予定/);
});

test("handles plain default empty props cleanly", () => {
  const html = renderToStaticMarkup(React.createElement(RequirementEvidence));
  assert.match(html, /^<details\b/);
  assert.doesNotMatch(html, /^<details[^>]*\bopen\b/);
  assert.match(html, /<summary\b[^>]*>根拠・内訳<\/summary>/);
  assert.match(html, /修得済み/);
  assert.match(html, /履修予定/);
  assert.match(html, /該当する授業はありません/);
  assert.doesNotMatch(html, /要確認/);
  assert.doesNotMatch(html, /確認表/);
  assert.doesNotMatch(html, /履修予定に伴う修得済みの算入変更/);
  assert.doesNotMatch(html, /公式規程・出典/);
  assert.doesNotMatch(html, /不足を埋める授業を探す/);
});

test("renders native details/summary with 修得済み, 履修予定, per-course syllabus links, and credit units", () => {
  const html = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      earned: [
        {
          title: "架空基礎演習A",
          code: "SYN-101",
          year: "2024",
          credits: 2,
          applied: 2,
          sourceUrl: "https://example.test/syllabus/2024/SYN-101",
        },
        {
          title: "仮想データ実践",
          code: "SYN-102",
          year: "2025",
          credits: 2,
          applied: 1,
          reason: "上限調整により1単位のみ算入",
        },
      ],
      planned: [
        {
          title: "模擬応用ゼミ",
          code: "SYN-204",
          year: "2026",
          credits: 2,
          applied: 2,
          reason: "履修予定から見込み算入",
          sourceUrl: "http://example.test/syllabus/2026/SYN-204",
        },
      ],
    }),
  );

  assert.match(html, /修得済み/);
  assert.match(html, /履修予定/);
  assert.doesNotMatch(html, /要確認/);
  assert.match(html, /架空基礎演習A/);
  assert.match(html, /SYN-101 · 2024 · 算入 2単位/);
  assert.match(
    html,
    /href="https:\/\/example\.test\/syllabus\/2024\/SYN-101"[^>]*target="_blank"[^>]*rel="noopener noreferrer"[^>]*>公式シラバス/,
  );
  assert.match(html, /仮想データ実践/);
  assert.match(html, /SYN-102 · 2025 · 算入 1単位（科目 2単位）/);
  assert.match(html, /上限調整により1単位のみ算入/);
  assert.match(html, /模擬応用ゼミ/);
  assert.match(html, /SYN-204 · 2026 · 算入 2単位/);
  assert.match(html, /href="http:\/\/example\.test\/syllabus\/2026\/SYN-204"/);
  assert.doesNotMatch(html, /履修予定に伴う修得済みの算入変更/);
});

test("formats courses unit accurately for applied counts and confirmed balance", () => {
  const html = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      unit: "courses",
      balance: { current: 2, required: 4, unit: "courses" },
      earned: [
        {
          title: "架空実験科目",
          code: "SYN-301",
          year: "2025",
          credits: 2,
          applied: 1,
        },
      ],
      planned: [
        {
          title: "仮想演習科目",
          code: "SYN-302",
          year: "2026",
          credits: 1,
          applied: 1,
        },
      ],
    }),
  );

  assert.match(html, /確認表の修得済み[\s\S]*2科目/);
  assert.match(html, /照合できた修得科目/);
  assert.match(html, /SYN-301 · 2025 · 算入 1科目（科目 2単位）/);
  assert.match(html, /SYN-302 · 2026 · 算入 1科目（科目 1単位）/);
});

test("renders months and condition rules with reason/note and without misleading empty course groups", () => {
  const monthsHtml = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      unit: "months",
      balance: { current: 24, required: 48, unit: "months" },
      reason: "休学期間を除いた在学月数を確認してください。",
      note: "在学年数は入学年度からの経過年数ではなく認定月数で扱います。",
      sources: [{ title: "架空学則", url: "https://example.test/regulations" }],
    }),
  );

  assert.match(monthsHtml, /確認表の記録[\s\S]*24か月/);
  assert.match(monthsHtml, /確認事項/);
  assert.match(monthsHtml, /休学期間を除いた在学月数を確認してください。/);
  assert.match(monthsHtml, /注記/);
  assert.match(
    monthsHtml,
    /在学年数は入学年度からの経過年数ではなく認定月数で扱います。/,
  );
  assert.doesNotMatch(monthsHtml, /修得済み/);
  assert.doesNotMatch(monthsHtml, /履修予定/);
  assert.doesNotMatch(monthsHtml, /該当する授業はありません/);

  const conditionHtml = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      unit: "condition",
      balance: { current: 1, unit: "condition" },
      note: "個別条件の確認対象です。",
    }),
  );

  assert.match(conditionHtml, /確認表の記録[\s\S]*条件 1/);
  assert.match(conditionHtml, /個別条件の確認対象です。/);
  assert.doesNotMatch(conditionHtml, /修得済み/);
  assert.doesNotMatch(conditionHtml, /履修予定/);
  assert.doesNotMatch(conditionHtml, /該当する授業はありません/);

  const bareConditionHtml = renderToStaticMarkup(
    React.createElement(RequirementEvidence, { unit: "condition" }),
  );
  assert.match(bareConditionHtml, /科目以外の条件に基づく項目です/);
  assert.doesNotMatch(bareConditionHtml, /該当する授業はありません/);
});

test("shows projectedEarned reallocation changes only when earned allocation differs under forecast", () => {
  const earned = [
    {
      recordId: "rec-1",
      title: "架空共通科目A",
      code: "SYN-501",
      year: "2024",
      credits: 2,
      applied: 2,
      sourceUrl: "https://example.test/syllabus/2024/SYN-501",
    },
    {
      recordId: "rec-2",
      title: "架空選択科目B",
      code: "SYN-502",
      year: "2025",
      credits: 2,
      applied: 2,
    },
  ];

  const unchangedHtml = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      earned,
      projectedEarned: [earned[1], earned[0]],
    }),
  );
  assert.doesNotMatch(unchangedHtml, /履修予定に伴う修得済みの算入変更/);

  const changedHtml = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      earned,
      projectedEarned: [
        { ...earned[0], applied: 1 },
        {
          recordId: "rec-3",
          title: "架空振替科目C",
          code: "SYN-503",
          year: "2024",
          credits: 2,
          applied: 2,
        },
      ],
    }),
  );

  assert.match(changedHtml, /履修予定に伴う修得済みの算入変更/);
  assert.match(changedHtml, /SYN-501 · 2024 · 算入 2単位 → 1単位/);
  assert.match(changedHtml, /SYN-502 · 2025 · 算入 2単位 → 0単位/);
  assert.match(changedHtml, /SYN-503 · 2024 · 算入 0単位 → 2単位/);
  assert.match(
    changedHtml,
    /href="https:\/\/example\.test\/syllabus\/2024\/SYN-501"/,
  );
});

test("shows confirmed balance aggregate distinctly without empty course groups and ignores unconfirmed balance", () => {
  const confirmedHtml = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      balance: { current: 1, required: 4 },
    }),
  );
  assert.match(confirmedHtml, /確認表の修得済み[\s\S]*1単位/);
  assert.doesNotMatch(confirmedHtml, /確認表の修得済みに含まれる科目/);
  assert.doesNotMatch(confirmedHtml, /照合できた修得科目/);
  assert.doesNotMatch(confirmedHtml, /履修予定/);
  assert.doesNotMatch(confirmedHtml, /該当する授業はありません/);

  const unconfirmedHtml = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      balance: { current: 3, confirmed: false },
      reason: "未確定の入力値です。",
    }),
  );
  assert.doesNotMatch(unconfirmedHtml, /確認表の修得済み/);
  assert.match(unconfirmedHtml, /未確定の入力値です。/);
});

test("renders covered earned rows included in confirmed subtotal without summation, duplicates, or phantoms", () => {
  const props = {
    balance: { current: 1, required: 4 },
    earned: [],
    covered: [
      {
        recordId: "rec-cov-1",
        title: "架空語学基礎 L",
        code: "SYN-701",
        year: "2026",
        credits: 1,
        applied: 1,
        sourceUrl: "https://example.test/syllabus/2026/SYN-701",
      },
      {
        recordId: "rec-cov-1",
        title: "架空語学基礎 L",
        code: "SYN-701",
        year: "2026",
        credits: 1,
        applied: 1,
        sourceUrl: "https://example.test/syllabus/2026/SYN-701",
      },
    ],
    planned: [],
    projectedEarned: [],
  };

  const firstHtml = renderToStaticMarkup(
    React.createElement(RequirementEvidence, props),
  );
  const reopenedHtml = renderToStaticMarkup(
    React.createElement(RequirementEvidence, props),
  );

  assert.equal(reopenedHtml, firstHtml);
  assert.match(firstHtml, /確認表の修得済み[\s\S]*>1単位<\/span>/);
  assert.doesNotMatch(firstHtml, />2単位<\/span>/);
  assert.match(firstHtml, /確認表の修得済みに含まれる科目/);
  assert.equal((firstHtml.match(/架空語学基礎 L/g) ?? []).length, 1);
  assert.match(firstHtml, /SYN-701 · 2026 · 確認表に含む 1単位/);
  assert.match(
    firstHtml,
    /href="https:\/\/example\.test\/syllabus\/2026\/SYN-701"[^>]*target="_blank"[^>]*rel="noopener noreferrer"[^>]*>公式シラバス/,
  );
  assert.doesNotMatch(firstHtml, /照合できた修得科目/);
  assert.doesNotMatch(firstHtml, /履修予定/);
  assert.doesNotMatch(firstHtml, /要確認/);
  assert.doesNotMatch(firstHtml, /履修予定に伴う修得済みの算入変更/);
  assert.doesNotMatch(firstHtml, /該当する授業はありません/);
});

test("deduplicates covered rows against earned, rejects unsafe covered sourceUrl, and formats courses unit", () => {
  const html = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      unit: "courses",
      balance: { current: 1, required: 2, unit: "courses" },
      earned: [
        {
          title: "架空演習A",
          code: "SYN-710",
          year: "2025",
          credits: 2,
          applied: 1,
        },
      ],
      covered: [
        {
          title: "架空演習A",
          code: "SYN-710",
          year: "2025",
          credits: 2,
          applied: 1,
        },
        {
          title: "架空演習B",
          code: "SYN-711",
          year: "2026",
          credits: 2,
          applied: 1,
          sourceUrl: "javascript:alert(1)",
        },
      ],
    }),
  );

  assert.match(html, /確認表の修得済み[\s\S]*>1科目<\/span>/);
  assert.equal((html.match(/架空演習A/g) ?? []).length, 1);
  assert.equal((html.match(/架空演習B/g) ?? []).length, 1);
  assert.match(html, /SYN-711 · 2026 · 確認表に含む 1科目（科目 2単位）/);
  assert.doesNotMatch(html, /公式シラバス/);
  assert.doesNotMatch(html, /javascript:/i);
});

test("renders unknown rows without misleading empty earned/planned groups and falls back to matchedCode", () => {
  const html = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      earned: [],
      planned: [],
      unknown: [
        {
          title: "サンプル認定科目",
          code: "",
          matchedCode: "SYN-999",
          year: "2023",
          credits: 2,
          applied: 0,
          reason: "区分照合が未確定のため要確認",
        },
      ],
    }),
  );

  assert.match(html, /要確認/);
  assert.match(html, /サンプル認定科目/);
  assert.match(html, /SYN-999 · 2023 · 算入 0単位（科目 2単位）/);
  assert.match(html, /区分照合が未確定のため要確認/);
  assert.doesNotMatch(html, /修得済み/);
  assert.doesNotMatch(html, /履修予定/);
});

test("rejects unsafe rule and per-course URLs and escapes script-like text", () => {
  const html = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      earned: [
        {
          title: "安全テスト科目<script>alert(1)</script>",
          code: "SYN-601",
          year: "2025",
          credits: 2,
          applied: 2,
          reason: "<img src=x onerror=alert(1)>",
          sourceUrl: "javascript:alert(1)",
        },
        {
          title: "安全テスト科目B",
          code: "SYN-602",
          year: "2025",
          credits: 2,
          applied: 2,
          sourceUrl: "data:text/html,<script>alert(1)</script>",
        },
      ],
      sources: [
        { title: "架空履修規程（HTTPS）", url: "https://example.test/rules/2026" },
        { title: "架空便覧アーカイブ（HTTP）", url: "http://example.test/archive" },
        { title: "危険リンクJS", url: "javascript:alert(1)" },
        { title: "危険リンクData", url: "data:text/html,<script>alert(1)</script>" },
        { title: "ローカルファイル", url: "file:///etc/hosts" },
        { title: "相対パス", url: "/internal/only" },
        { title: "プロトコル相対", url: "//example.test/relative" },
        { title: "空URL", url: "   " },
      ],
    }),
  );

  assert.match(html, /href="https:\/\/example\.test\/rules\/2026"/);
  assert.match(html, /href="http:\/\/example\.test\/archive"/);
  assert.doesNotMatch(html, /公式シラバス/);
  assert.doesNotMatch(html, /<script/i);
  assert.doesNotMatch(html, /<img\b/i);
  assert.doesNotMatch(html, /javascript:/i);
  assert.doesNotMatch(html, /data:text\/html/i);
  assert.doesNotMatch(html, /file:\/\//i);
  assert.doesNotMatch(html, /危険リンクJS/);
  assert.doesNotMatch(html, /危険リンクData/);
  assert.doesNotMatch(html, /ローカルファイル/);
  assert.doesNotMatch(html, /相対パス/);
  assert.doesNotMatch(html, /プロトコル相対/);
  assert.doesNotMatch(html, /空URL/);
});

test("renders optional Meta Astryx search button and invokes onSearch when triggered", () => {
  let calls = 0;
  const onSearch = () => {
    calls += 1;
  };

  const tree = RequirementEvidence({
    earned: [
      {
        title: "架空入門講義",
        code: "SYN-110",
        year: "2025",
        credits: 2,
        applied: 2,
      },
    ],
    onSearch,
  });

  const html = renderToStaticMarkup(tree);
  assert.match(
    html,
    /<button\b[^>]*>[\s\S]*不足を埋める授業を探す[\s\S]*<\/button>/,
  );

  const buttonNode = findElement(
    tree,
    (el) => el?.props?.label === "不足を埋める授業を探す",
  );
  assert.ok(buttonNode, "expected Meta Astryx Button with label");
  assert.equal(typeof buttonNode.props.onClick, "function");
  buttonNode.props.onClick();
  assert.equal(calls, 1);
});

test("displays precomputed fields verbatim without recalculation and handles missing titles", () => {
  const html = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      earned: [{ code: "SYN-401", year: "2025", credits: 2, applied: 5 }],
      planned: [{ title: "仮想演習B", year: "2026", applied: 1 }],
      sources: [{ url: "https://example.test/handbook" }],
    }),
  );

  assert.match(html, />SYN-401<\/span>/);
  assert.doesNotMatch(html, /SYN-401 · SYN-401/);
  assert.match(html, /2025 · 算入 5単位（科目 2単位）/);
  assert.match(html, /仮想演習B/);
  assert.match(html, /2026 · 算入 1単位/);
  assert.match(html, /公式規程/);
  assert.match(html, /href="https:\/\/example\.test\/handbook"/);
});
