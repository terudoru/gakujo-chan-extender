const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const {script, ...options} = JSON.parse(readFileSync(process.argv[2], 'utf8'));

function assignmentDocument({smartphone = true, count = '', controls = [],
  rows, action = ''} = {}) {
  const period = '2026/10/21 17:01 ～ 2026/10/28 16:31';
  const records = rows || Array.from({length: 12}, (_, i) => ({title: `課題 ${i + 1}`}));
  const titles = records.map(record => {
    const title = record.title;
    const block = {
      textContent: record.text || `${title} (テスト科目) 実施期間：${period} 状態：未提出`,
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
    rows: [{}, ...records.map(record => ({
      cells: ['レポート', record.title, '未提出', '263T0506', 'テスト科目', '', '', record.period || period]
        .map(textContent => ({textContent})),
    }))],
  };
  controls = controls.map(control => ({...control,
    getAttribute(name) { return control.attributes?.[name] || null; },
  }));
  const form = {
    textContent: [count, ...titles.map(title => title.closest().textContent),
      ...controls.map(control => control.textContent || '')].join(' '),
    getAttribute(name) { return name === 'action' ? action : null; },
    querySelectorAll(selector) {
      if (selector === 'input[type="hidden"]') {
        return controls.filter(control => control.tag === 'input' && control.attributes?.type === 'hidden')
          .map(control => ({name: control.attributes.name, value: control.value || ''}));
      }
      assert.equal(selector, 'a, button, input[type="submit"]');
      return controls.filter(control => ['a', 'button'].includes(control.tag) ||
        control.tag === 'input' && control.attributes?.type === 'submit');
    },
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
  return {
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
}

function fetchAssignments(options = {}) {
  const pages = options.pages || [options];
  const requests = [];
  class XMLHttpRequest {
    open(method, url, async) {
      assert.equal(method, 'GET');
      const expected = pages[requests.length]?.url;
      if (expected) assert.equal(url, expected);
      if (!requests.length) assert.equal(url, '/campusweb/campussquare.do?_flowId=ENW3411100-flow');
      assert.equal(async, false);
      requests.push(url);
    }
    send(body) {
      assert.equal(body, null);
      const index = Math.min(requests.length - 1, pages.length - 1);
      this.status = pages[index].status || 200;
      this.responseText = String(index);
    }
  }
  class DOMParser {
    parseFromString(html, type) {
      assert.equal(type, 'text/html');
      return assignmentDocument(pages[Number(html)]);
    }
  }
  return {...JSON.parse(vm.runInNewContext(script, {XMLHttpRequest, DOMParser,
    URL, location: {origin: 'https://gakujo.iess.niigata-u.ac.jp'}})), requests};
}

process.stdout.write(JSON.stringify(fetchAssignments(options)));
