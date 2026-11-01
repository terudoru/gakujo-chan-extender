import type {} from 'node:fs';
const assert: any = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm: any = require('node:vm');
const {script, ...options} = JSON.parse(readFileSync(process.argv[2], 'utf8'));

function assignmentDocument({smartphone = true, count = '', controls = [],
  rows, action = ''}: any = {}) {
  const period: any = '2026/10/21 17:01 ～ 2026/10/28 16:31';
  const records: any = rows || Array.from({length: 12}, (_: any, i: any) => ({title: `課題 ${i + 1}`}));
  const titles: any = records.map((record: any) => {
    const title: any = record.title;
    const block: any = {
      textContent: record.text || `${title} (テスト科目) 実施期間：${period} 状態：未提出`,
      querySelector() { return null; },
    };
    return {textContent: title, closest() { return block; }};
  });
  const groups: any = smartphone
    ? ['レポート', '小テスト', '授業アンケート', '一般アンケート', '授業評価アンケート']
      .map((kind: any, index: any) => ({
        querySelector(selector: any) {
          assert.equal(selector, 'li.header');
          return {textContent: kind};
        },
        querySelectorAll(selector: any) {
          assert.equal(selector, 'span.h3');
          return titles.filter((_: any, i: any) => i % 5 === index);
        },
      }))
    : [];
  const table: any = {
    rows: [{}, ...records.map((record: any) => ({
      cells: ['レポート', record.title, '未提出', '263T0506', 'テスト科目', '', '', record.period || period]
        .map((textContent: any) => ({textContent})),
    }))],
  };
  controls = controls.map((control: any) => ({...control,
    getAttribute(name: any) { return control.attributes?.[name] || null; },
  }));
  const form: any = {
    textContent: [count, ...titles.map((title: any) => title.closest().textContent),
      ...controls.map((control: any) => control.textContent || '')].join(' '),
    getAttribute(name: any) { return name === 'action' ? action : null; },
    querySelectorAll(selector: any) {
      if (selector === 'input[type="hidden"]') {
        return controls.filter((control: any) => control.tag === 'input' && control.attributes?.type === 'hidden')
          .map((control: any) => ({name: control.attributes.name, value: control.value || ''}));
      }
      assert.equal(selector, 'a, button, input[type="submit"]');
      return controls.filter((control: any) => ['a', 'button'].includes(control.tag) ||
        control.tag === 'input' && control.attributes?.type === 'submit');
    },
    querySelector(selector: any) {
      if (selector === 'ul.campussmart-list') return groups[0] || null;
      for (const part of selector.split(',')) {
        const match: any = part.trim().match(/^(\w+)?\[(\w+)(\*?=)"([^"]*)"\]$/);
        assert.ok(match, `Unsupported form selector: ${part}`);
        const [, tag, attribute, operator, value] = match;
        const found: any = controls.find((control: any) => {
          const actual: any = control.attributes?.[attribute];
          return (!tag || control.tag === tag) && actual !== undefined &&
            (operator === '*=' ? actual.includes(value) : actual === value);
        });
        if (found) return found;
      }
      return null;
    },
  };
  return {
    querySelector(selector: any) {
      if (selector === '#enqListForm') return form;
      assert.equal(selector, '#enqListForm table:nth-of-type(2)');
      return smartphone ? null : table;
    },
    querySelectorAll(selector: any) {
      assert.equal(selector, '#enqListForm ul.campussmart-list');
      return groups;
    },
  };
}

function fetchAssignments(options: any = {}) {
  const pages: any = options.pages || [options];
  const requests: any = [];
  class XMLHttpRequest {
  [key: string]: any;
    open(method: any, url: any, async: any) {
      assert.equal(method, 'GET');
      const expected: any = pages[requests.length]?.url;
      if (expected) assert.equal(url, expected);
      if (!requests.length) assert.equal(url, '/campusweb/campussquare.do?_flowId=ENW3411100-flow');
      assert.equal(async, false);
      requests.push(url);
    }
    send(body: any) {
      assert.equal(body, null);
      const index: any = Math.min(requests.length - 1, pages.length - 1);
      this.status = pages[index].status || 200;
      this.responseText = String(index);
    }
  }
  class DOMParser {
  [key: string]: any;
    parseFromString(html: any, type: any) {
      assert.equal(type, 'text/html');
      return assignmentDocument(pages[Number(html)]);
    }
  }
  return {...JSON.parse(vm.runInNewContext(script, {XMLHttpRequest, DOMParser,
    URL, location: {origin: 'https://gakujo.iess.niigata-u.ac.jp'}})), requests};
}

process.stdout.write(JSON.stringify(fetchAssignments(options)));
