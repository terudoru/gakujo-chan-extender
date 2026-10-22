const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const {script, ...options} = JSON.parse(readFileSync(process.argv[2], 'utf8'));

function fetchAssignments({smartphone = true, count = '', controls = []} = {}) {
  const period = '2026/10/21 17:01 ～ 2026/10/28 16:31';
  const titles = Array.from({length: 12}, (_, i) => {
    const title = `課題 ${i + 1}`;
    const block = {
      textContent: `${title} (テスト科目) 実施期間：${period} 状態：未提出`,
      querySelector() { return null; },
    };
    return {textContent: title, closest() { return block; }};
  });
  const groups = smartphone
    ? ['レポート', '小テスト', '授業アンケート', '一般アンケート', '授業評価アンケート']
      .map((kind, index) => ({
        querySelector(selector) {
          assert.equal(selector, 'li.header');
          return {textContent: kind};
        },
        querySelectorAll(selector) {
          assert.equal(selector, 'span.h3');
          return titles.filter((_, i) => i % 5 === index);
        },
      }))
    : [];
  const table = {
    rows: [{}, ...titles.map(title => ({
      cells: ['レポート', title.textContent, '未提出', '263T0506', 'テスト科目', '', '', period]
        .map(textContent => ({textContent})),
    }))],
  };
  const form = {
    textContent: [count, ...titles.map(title => title.closest().textContent),
      ...controls.map(control => control.textContent || '')].join(' '),
    querySelector(selector) {
      if (selector === 'ul.campussmart-list') return groups[0] || null;
      for (const part of selector.split(',')) {
        const match = part.trim().match(/^(\w+)?\[(\w+)(\*?=)"([^"]*)"\]$/);
        assert.ok(match, `Unsupported form selector: ${part}`);
        const [, tag, attribute, operator, value] = match;
        const found = controls.find(control => {
          const actual = control.attributes?.[attribute];
          return (!tag || control.tag === tag) && actual !== undefined &&
            (operator === '*=' ? actual.includes(value) : actual === value);
        });
        if (found) return found;
      }
      return null;
    },
  };
  const doc = {
    querySelector(selector) {
      if (selector === '#enqListForm') return form;
      assert.equal(selector, '#enqListForm table:nth-of-type(2)');
      return smartphone ? null : table;
    },
    querySelectorAll(selector) {
      assert.equal(selector, '#enqListForm ul.campussmart-list');
      return groups;
    },
  };
  class XMLHttpRequest {
    open(method, url, async) {
      assert.equal(method, 'GET');
      assert.equal(url, '/campusweb/campussquare.do?_flowId=ENW3411100-flow');
      assert.equal(async, false);
    }
    send(body) {
      assert.equal(body, null);
      this.status = 200;
      this.responseText = 'assignment list fixture';
    }
  }
  class DOMParser {
    parseFromString(html, type) {
      assert.equal(html, 'assignment list fixture');
      assert.equal(type, 'text/html');
      return doc;
    }
  }
  return JSON.parse(vm.runInNewContext(script, {XMLHttpRequest, DOMParser}));
}

process.stdout.write(JSON.stringify(fetchAssignments(options)));
