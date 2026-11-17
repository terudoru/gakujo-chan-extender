import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { LIMITS, PLATFORMS, TYPES, validateReport } from '../public/assets/js/report-schema.js';

// Exercise the real client event handlers with a small DOM adapter. No network.
function client({ available = true, siteKey = 'test-key', response = Response.json({ id: 1 }, { status: 201 }) } = {}) {
  const nodes = new Map();
  const element = (name) => {
    if (!nodes.has(name)) nodes.set(name, { value: '', checked: false, hidden: false, disabled: false, textContent: '', events: {}, setAttribute() {}, focus() { this.focused = true; }, scrollIntoView() { this.scrolled = true; }, remove() {}, addEventListener(type, callback) { this.events[type] = callback; } });
    return nodes.get(name);
  };
  const form = element('report-form');
  form.elements = Object.fromEntries([...Object.keys(LIMITS), 'type', 'platform', 'consent', 'website'].map((name) => [name, element(name)]));
  form.elements.type.value = 'bug';
  form.elements.consent.checked = true;
  form.elements.title.value = '保持したい件名';
  form.elements.content.value = '保持したい内容';
  form.elements.diagnostic.value = 'PRIVATE DIAGNOSTIC';
  element('verification-retry').hidden = true;
  form.reset = () => {
    for (const control of Object.values(form.elements)) { control.value = ''; control.checked = false; }
    form.elements.type.value = 'bug';
  };
  form.querySelectorAll = (selector) => selector === '[name=type]' ? [element('type-bug'), element('type-request')] : Object.values(form.elements);
  form.querySelector = () => element('type-bug');
  form.requestSubmit = () => form.events.submit({ preventDefault() {} });
  const scripts = [];
  let options;
  let resets = 0;
  const verificationCallbacks = [];
  const turnstile = { ready: (cb) => cb(), render: (_selector, config) => { options = config; return 0; }, reset: () => { resets++; verificationCallbacks.push(() => options.callback('fresh-reset-token')); } };
  const window = {};
  let now = 0;
  const timers = [];
  const document = {
    querySelector: (selector) => selector === 'meta[name=turnstile-site-key]' ? { content: siteKey } : selector === 'meta[name=report-available]' ? { content: String(available) } : element(selector.slice(1)),
    getElementById: element,
    createElement: () => ({ remove() {} }),
    head: { append: (script) => scripts.push(script) },
  };
  const source = readFileSync(new URL('../public/assets/js/form.js', import.meta.url), 'utf8').replace(/^import .*;\r?\n/, '');
  class FakeFormData {
    constructor() { this.entries = Object.entries(form.elements).filter(([, v]) => !v.disabled).map(([k, v]) => [k, v.value]); }
    [Symbol.iterator]() { return this.entries[Symbol.iterator](); }
  }
  runInNewContext(source, { document, window, performance: { now: () => now }, location: { search: '?type=bug&version=1.2.3&platform=windows' }, FormData: FakeFormData, URLSearchParams, LIMITS, PLATFORMS, TYPES, validateReport, AbortSignal, setTimeout: (fn) => { timers.push(fn); return timers.length; }, clearTimeout() {}, fetch: async () => { if (response instanceof Error) throw response; return response; } });
  now = 5000;
  return { element, form, scripts, timers, flushVerification: () => { for (const callback of verificationCallbacks.splice(0)) callback(); }, load: () => { window.turnstile = turnstile; scripts.at(-1).onload(); }, options: () => options, resets: () => resets, snapshot: () => [form.elements.title.value, form.elements.content.value, form.elements.diagnostic.value] };
}

test('client marks an unconfigured form unavailable without loading Turnstile', () => {
  for (const config of [{ available: false }, { siteKey: '' }]) {
    const ui = client(config);
    assert.equal(ui.scripts.length, 0);
    assert.ok(ui.element('status').textContent.includes('現在は送信できません'));
    assert.equal(ui.element('submit').disabled, true);
    assert.equal(ui.form.elements.title.disabled, true);
  }
});

test('verification help only suggests retry while its button is visible, including after another report', async () => {
  const ui = client();
  const waiting = '認証が完了するまで送信できません。完了までお待ちください。';
  assert.equal(ui.element('verification-retry').hidden, true);
  assert.equal(ui.element('verification-help').textContent, waiting);
  ui.load();
  ui.options()['error-callback']();
  assert.equal(ui.element('verification-retry').hidden, false);
  assert.ok(ui.element('verification-help').textContent.includes('「もう一度確認する」'));
  ui.options().callback('fresh-token');
  await ui.form.requestSubmit();
  ui.element('another').events.click();
  assert.equal(ui.element('verification-retry').hidden, true);
  assert.equal(ui.element('verification-help').textContent, waiting);
  assert.equal(ui.element('submit').disabled, true);
});

test('script load error can retry by reinserting api.js while retaining all text', () => {
  const ui = client();
  const before = ui.snapshot();
  ui.scripts[0].onerror();
  assert.equal(ui.element('verification-retry').hidden, false);
  assert.equal(ui.element('submit').disabled, true);
  assert.equal(ui.element('status').textContent.includes('開き直'), false);
  ui.element('verification-retry').events.click();
  assert.equal(ui.scripts.length, 2);
  ui.load(); ui.options().callback('fresh-token');
  assert.equal(ui.element('submit').disabled, false);
  assert.equal(ui.element('status').textContent, '');
  assert.equal(ui.element('verification-help').textContent, '認証が完了しました。送信できます。');
  assert.deepEqual(ui.snapshot(), before);
});

for (const callback of ['error-callback', 'expired-callback']) test(`${callback} permits widget reset and retains all text`, () => {
  const ui = client(); ui.load();
  const before = ui.snapshot();
  ui.options().callback('old-token');
  ui.options()[callback]();
  assert.equal(ui.element('verification-retry').hidden, false);
  assert.equal(ui.element('submit').disabled, true);
  const previous = ui.resets();
  ui.element('verification-retry').events.click();
  assert.equal(ui.resets(), previous + 1);
  ui.options().callback('new-token');
  assert.equal(ui.element('submit').disabled, false);
  assert.equal(ui.element('status').textContent, '');
  assert.deepEqual(ui.snapshot(), before);
});

for (const [name, response] of [
  ['network error', new Error('offline')],
  ['503', Response.json({ message: 'unavailable' }, { status: 503 })],
  ['non-JSON 502', new Response('<html>bad gateway</html>', { status: 502 })],
  ['422', Response.json({ errors: { title: '確認してください' } }, { status: 422 })],
  ['429', Response.json({ retryAfter: 600 }, { status: 429, headers: { 'Retry-After': '600' } })],
]) test(`submission ${name} keeps inputs and exposes retry`, async () => {
  const ui = client({ response }); ui.load(); ui.options().callback('token');
  const before = ui.snapshot();
  await ui.form.requestSubmit();
  assert.deepEqual(ui.snapshot(), before);
  assert.equal(ui.element('submit').textContent, 'もう一度送信する');
  assert.equal(ui.form.hidden, false);
  assert.ok(ui.resets() >= 1);
  const failureMessage = ui.element('status').textContent;
  ui.flushVerification();
  assert.equal(ui.element('status').textContent, failureMessage, 'asynchronous reset callback preserves submission result');
  assert.deepEqual(ui.snapshot(), before);
  if (name === '422') {
    assert.equal(ui.element('title-error').textContent, '確認してください');
    assert.equal(ui.element('title').focused, true);
  } else {
    assert.equal(ui.element('status').focused, true);
    assert.equal(ui.element('status').scrolled, true);
  }
  if (name === '429') {
    assert.ok(ui.element('status').textContent.includes('約10分（600秒）'));
    ui.timers.at(-1)();
    assert.ok(ui.element('status').textContent.includes('待機時間が終わりました'));
  }
  if (name === 'non-JSON 502') assert.ok(ui.element('status').textContent.includes('サーバーで問題が起きました'));
});

test('success has one receipt without a GitHub-style number and focuses success heading', async () => {
  const ui = client(); ui.load(); ui.options().callback('token');
  await ui.form.requestSubmit();
  assert.equal(ui.element('receipt').textContent, '受付番号: 1');
  assert.equal(ui.element('status').textContent, '');
  assert.equal(ui.element('success-title').focused, true);
  assert.equal(ui.element('success').hidden, false);
  assert.equal(ui.form.hidden, true);
});
