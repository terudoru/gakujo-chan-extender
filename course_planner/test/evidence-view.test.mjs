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

test("renders native details/summary with 修得済み, 履修予定, reason, and units using synthetic rows", () => {
  const html = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      earned: [
        {
          title: "架空基礎演習A",
          code: "SYN-101",
          year: "2024",
          credits: 2,
          applied: 2,
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
        },
      ],
    }),
  );

  assert.match(html, /^<details\b/);
  assert.doesNotMatch(html, /^<details[^>]*\bopen\b/);
  assert.match(html, /<summary\b[^>]*>根拠・内訳<\/summary>/);
  assert.match(html, /修得済み/);
  assert.match(html, /履修予定/);
  assert.doesNotMatch(html, /要確認/);
  assert.match(html, /架空基礎演習A/);
  assert.match(html, /SYN-101 · 2024 · 算入 2単位/);
  assert.match(html, /仮想データ実践/);
  assert.match(html, /SYN-102 · 2025 · 算入 1単位（科目 2単位）/);
  assert.match(html, /上限調整により1単位のみ算入/);
  assert.match(html, /模擬応用ゼミ/);
  assert.match(html, /SYN-204 · 2026 · 算入 2単位/);
  assert.match(html, /履修予定から見込み算入/);
  assert.doesNotMatch(html, /不足を埋める授業を探す/);
});

test("renders unknown rows only when provided and handles zero applied units", () => {
  const html = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      earned: [],
      planned: [],
      unknown: [
        {
          title: "サンプル認定科目",
          code: "SYN-999",
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
  assert.match(html, /該当する授業はありません/);
});

test("renders only valid HTTP(S) official source links and rejects unsafe URLs", () => {
  const html = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
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
  assert.match(html, /架空履修規程（HTTPS）/);
  assert.match(html, /href="http:\/\/example\.test\/archive"/);
  assert.match(html, /架空便覧アーカイブ（HTTP）/);
  assert.match(html, /target="_blank"/);
  assert.match(html, /rel="noopener noreferrer"/);
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
  assert.match(html, /<button\b[^>]*>[\s\S]*不足を埋める授業を探す[\s\S]*<\/button>/);

  const buttonNode = findElement(
    tree,
    (el) => el?.props?.label === "不足を埋める授業を探す",
  );
  assert.ok(buttonNode, "expected Meta Astryx Button with label");
  assert.equal(typeof buttonNode.props.onClick, "function");
  buttonNode.props.onClick();
  assert.equal(calls, 1);
});

test("handles default empty props cleanly", () => {
  const html = renderToStaticMarkup(React.createElement(RequirementEvidence));
  assert.match(html, /<details\b/);
  assert.match(html, /根拠・内訳/);
  assert.match(html, /修得済み/);
  assert.match(html, /履修予定/);
  assert.doesNotMatch(html, /公式規程・出典/);
  assert.doesNotMatch(html, /不足を埋める授業を探す/);
});

test("displays precomputed fields verbatim without recalculation and handles missing titles", () => {
  const html = renderToStaticMarkup(
    React.createElement(RequirementEvidence, {
      earned: [
        { code: "SYN-401", year: "2025", credits: 2, applied: 5 },
      ],
      planned: [
        { title: "仮想演習B", year: "2026", applied: 1 },
      ],
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
