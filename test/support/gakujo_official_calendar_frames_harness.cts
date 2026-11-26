import type {} from 'node:vm';
const assert = require('node:assert/strict');
const vm = require('node:vm');
const [, , script, kind, activate] = process.argv;
const accessed: string[] = [];
const clicks: string[] = [];
const labels = {
  google: 'Google Calendar',
  execution: 'executeExport',
};

function page(title: string, contents = 'empty', frames: object[] = []) {
  const location = new URL('https://example.test/' + title + '?key=test');
  const control = {
    tagName: 'BUTTON',
    innerText: labels[kind] + ' ' + title,
    getAttribute() { return null; },
    closest(selector: string) { return selector.startsWith('a,button') ? this : null; },
    querySelectorAll() { return []; },
    click() { clicks.push(title); },
  };
  const eventId = {value: ''};
  const form = {
    name: 'scheduleExportForm',
    querySelector() { return eventId; },
    querySelectorAll(selector: string) {
      return contents === 'match' && selector === 'button,input,a,[onclick]' ? [control] : [];
    },
  };
  return {
    frames,
    document: {
      location,
      title,
      querySelectorAll(selector: string) {
        accessed.push(title);
        if (contents === 'throw') throw new Error('inspection failed');
        if (selector === 'form') return contents === 'empty' ? [] : [form];
        return contents === 'match' ? [control] : [];
      },
    },
  };
}

function evaluate(root: object) {
  accessed.length = 0;
  clicks.length = 0;
  return JSON.parse(vm.runInNewContext(script, {window: root, URL}));
}

function checkMatch(result: any, title: string, expectedAccesses: string[]) {
  assert.equal(result.status, activate === 'true' ? 'clicked' : 'clickable');
  assert.equal(result.label, labels[kind] + ' ' + title);
  assert.equal(result.url, '');
  assert.equal(result.diagnostics.title, title);
  assert.equal(result.diagnostics.url, 'https://example.test/' + title);
  assert.deepEqual(clicks, activate === 'true' ? [title] : []);
  assert.deepEqual([...new Set(accessed)], expectedAccesses);
}

checkMatch(evaluate(page('root', 'match', [page('child', 'match')])), 'root', ['root']);

const denied = {get document() {
  accessed.push('inaccessible');
  throw new Error('cross-origin');
}};
const branch = page('broken', 'throw', [page('pruned', 'match')]);
const winner = page('container', 'empty', [page('nested', 'match')]);
const root = page('root', 'empty', [denied, branch, winner, page('later', 'match')]);
checkMatch(evaluate(root), 'nested', ['root', 'inaccessible', 'broken', 'container', 'nested']);

if (kind === 'execution') {
  const result = evaluate(page('missing', 'no-button', [page('child', 'match')]));
  assert.equal(result.status, 'not_found');
  assert.equal(result.label, '');
  assert.equal(result.url, '');
  assert.equal(result.diagnostics.title, 'missing');
  assert.deepEqual(result.diagnostics.controls, []);
  assert.deepEqual(clicks, []);
  assert.deepEqual([...new Set(accessed)], ['missing']);
}
