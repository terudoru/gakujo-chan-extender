import assert from 'node:assert/strict';
import test from 'node:test';
import vm from 'node:vm';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { formHtml, environment } from './fakes.mjs';

function browser(options = {}) {
  const env = { focused: null, sent: [], success: null, failure: null };
  function element(id) {
    return { id, value: '', checked: false, hidden: false, disabled: false, textContent: '', attributes: {}, listeners: {},
      setAttribute(name, value) { this.attributes[name] = value; },
      focus() { env.focused = id; },
      addEventListener(name, handler) { this.listeners[name] = handler; }
    };
  }
  const ids = [...formHtml.matchAll(/id="([^"]+)"/g)].map(match => match[1]);
  const elements = Object.fromEntries(ids.map(id => [id, element(id)]));
  const form = elements['report-form'];
  const keys = ['title', 'content', 'steps', 'expected', 'version', 'platform', 'consent'];
  form.elements = Object.fromEntries(keys.map(key => [key, elements[key]]));
  form.elements.type = element('type'); form.elements.type.value = 'bug';
  const fieldset = element('fieldset'); form.querySelector = selector => { assert.equal(selector, 'fieldset'); return fieldset; };
  form.reset = () => { for (const key of keys) { form.elements[key].value = ''; form.elements[key].checked = false; } form.elements.type.value = 'bug'; };
  elements.another.hidden = true;
  const run = {
    withSuccessHandler(fn) { env.success = fn; return this; },
    withFailureHandler(fn) { env.failure = fn; return this; },
    submitReport(value) { env.sent.push(JSON.parse(JSON.stringify(value))); }
  };
  vm.runInNewContext(formHtml.match(/<script>([\s\S]*?)<\/script>/)[1], { document: { getElementById: id => elements[id] }, google: { script: { run } }, crypto: options.cryptoAvailable === false ? {} : { randomUUID } });
  env.elements = elements; env.form = form;
  env.submit = () => form.listeners.submit({ preventDefault() {} });
  env.fill = () => { form.elements.title.value = '件名'; form.elements.content.value = '内容'; form.elements.consent.checked = true; };
  return env;
}

test('form has matching maxlength, counters/ARIA, privacy copy and no diagnostic field', () => {
  for (const [key, limit] of Object.entries({ title: 80, content: 4000, steps: 2000, expected: 1000, version: 40 })) {
    assert.match(formHtml, new RegExp(`id="${key}"[^>]*maxlength="${limit}"`));
    assert.match(formHtml, new RegExp(`aria-describedby="${key}-error[^\"]*${key}-count"`));
  }
  assert.doesNotMatch(formHtml, /(?:id|name)="diagnostic"/);
  for (const wording of ['GitHub アカウントは不要', '個別の返信はできません', '新しいタブで開きます', '学籍番号', 'パスワード', '成績', '学情の画面の内容', '公開される場合']) assert.ok(formHtml.includes(wording));
  assert.ok(formHtml.indexOf('id="status"') > formHtml.indexOf('id="submit"'));
  assert.match(formHtml, /id="status" role="status" aria-live="polite" tabindex="-1"/);
  assert.match(formHtml, /上の3つに当てはまらない連絡・報告/);
  assert.equal([...formHtml.matchAll(/個別の返信はできません/g)].length, 1, 'general no-reply note belongs in the introduction');
  assert.match(formHtml, /アプリの設定や状態（診断情報）を添えたい場合は、アプリの 設定 → このアプリについて → アプリから報告する を使ってください。/);
  assert.match(formHtml, /OS（Windows・macOS・Android など）/);
  assert.match(formHtml, /件名・内容・問題が起きるまでの手順・本来どうなってほしかったか・アプリのバージョン・OS/);
  assert.doesNotMatch(formHtml, /再現手順|期待した動き|ブラウザーを更新/);
});

test('client validation blocks missing required/consent fields and focuses nearby result', () => {
  const env = browser(); env.submit(); assert.equal(env.sent.length, 0);
  for (const key of ['title', 'content', 'consent']) assert.ok(env.elements[`${key}-error`].textContent);
  assert.equal(env.focused, 'status');
  env.fill(); env.form.elements.title.value = '😀'.repeat(41); env.submit(); assert.equal(env.sent.length, 0); assert.match(env.elements['title-error'].textContent, /80/);
});

test('client counters/cleaning mirror server, requests hide bug fields and force them empty', () => {
  const env = browser(); env.fill();
  env.form.elements.title.value = ' \u0000題\r名\u007f '; env.form.listeners.input(); assert.equal(env.elements['title-count'].textContent, '2 / 80');
  env.form.elements.type.value = 'request'; env.form.elements.steps.value = 'not sent'; env.form.elements.expected.value = 'not sent'; env.form.listeners.change();
  assert.equal(env.elements['bug-fields'].hidden, true); env.submit();
  assert.equal(env.sent[0].title, '題名'); assert.equal(env.sent[0].steps, ''); assert.equal(env.sent[0].expected, '');
  assert.equal(env.sent[0].client, 'web'); assert.equal(env.sent[0].diagnostic, null);
  assert.equal(environment().web(env.sent[0]).ok, true);
});

test('page-load UUID is retained for unchanged transport retries and replaced for edited retries', () => {
  const env = browser(); env.fill(); env.submit(); const key = env.sent[0].submissionKey;
  env.submit(); assert.equal(env.sent.length, 1, 'pending submission cannot repeat');
  env.failure(Error('private transport details')); assert.equal(env.focused, 'status'); assert.equal(env.form.elements.title.value, '件名');
  assert.ok(!env.elements.status.textContent.includes('private transport details'));
  env.submit(); assert.equal(env.sent[1].submissionKey, key);
  env.failure(Error('retry failed')); env.form.elements.content.value += ' changed'; env.submit(); assert.notEqual(env.sent[2].submissionKey, key);
});

test('all four types preserve selection through edits/retries, share web contract, and change keys on type/consent edits', () => {
  const env = browser(); env.fill();
  let previousKey = '';
  for (const [type, heading] of [['bug', '起きたこと'], ['request', '実現したい機能'], ['improvement', '今困っている点と、どう変わると良いか'], ['other', '内容']]) {
    env.form.elements.type.value = type; env.form.listeners.change();
    assert.equal(env.elements['content-label'].textContent, heading);
    assert.equal(env.elements['bug-fields'].hidden, type !== 'bug');
    env.submit(); const sent = env.sent.at(-1);
    assert.equal(sent.type, type); assert.equal(sent.diagnostic, null); assert.equal(sent.client, 'web');
    if (previousKey) assert.notEqual(sent.submissionKey, previousKey);
    previousKey = sent.submissionKey;
    env.failure(Error('timeout'));
    assert.equal(env.form.elements.type.value, type); assert.equal(env.form.elements.title.value, '件名');
    env.submit(); assert.equal(env.sent.at(-1).submissionKey, previousKey);
    assert.equal(environment().web(env.sent.at(-1)).ok, true);
    env.failure(Error('timeout'));
  }
  env.form.elements.consent.checked = false; env.form.listeners.change(); env.submit();
  const count = env.sent.length;
  env.form.elements.consent.checked = true; env.form.listeners.change(); env.submit(); assert.equal(env.sent.length, count + 1); assert.notEqual(env.sent.at(-1).submissionKey, previousKey);
});

test('unknown web type never sends; conflict regenerates key with the required factual retry copy', () => {
  const env = browser(); env.fill(); env.form.elements.type.value = 'question'; env.submit(); assert.equal(env.sent.length, 0); assert.ok(env.elements['type-error'].textContent);
  env.form.elements.type.value = 'other'; env.submit(); const firstKey = env.sent[0].submissionKey;
  env.success({ ok: false, code: 'conflict' }); assert.equal(env.elements.status.textContent, '内容が変わったため、もう一度送信してください。');
  assert.equal(env.focused, 'status'); env.submit(); assert.notEqual(env.sent[1].submissionKey, firstKey);
  env.failure(Error('timeout')); assert.equal(env.elements.status.textContent, '送信できたか確認できませんでした。内容を変えずにもう一度送れば、二重には登録されません。');
});

test('delayed callback freezes every input, failure unlocks unchanged values, success stays frozen until another report', () => {
  const env = browser(); env.fill(); env.form.elements.type.value = 'improvement'; env.submit();
  assert.equal(env.elements['report-inputs'].disabled, true);
  assert.equal(env.elements.submit.disabled, true); assert.equal(env.form.attributes['aria-busy'], 'true');
  assert.equal(typeof env.success, 'function');
  assert.match(formHtml, /<fieldset id="report-inputs"[\s\S]*name="type"[\s\S]*id="title"[\s\S]*id="content"[\s\S]*id="steps"[\s\S]*id="expected"[\s\S]*id="version"[\s\S]*id="platform"[\s\S]*id="consent"[\s\S]*<\/fieldset>\s*<button id="submit"/);
  env.failure(Error('held request failed')); assert.equal(env.elements['report-inputs'].disabled, false);
  assert.equal(env.form.elements.type.value, 'improvement'); assert.equal(env.form.elements.content.value, '内容');
  env.form.elements.content.value = '変更後'; env.form.listeners.input(); env.submit();
  assert.equal(env.sent.at(-1).content, '変更後'); assert.equal(env.elements['report-inputs'].disabled, true);
  env.success({ ok: true, receipt: 'R-ABCDEF2345', duplicate: false }); assert.equal(env.elements['report-inputs'].disabled, true);
  env.elements.another.listeners.click(); assert.equal(env.elements['report-inputs'].disabled, false);
});

test('rate limit wait, busy/unavailable and server field errors retain input and focus result', () => {
  const env = browser(); env.fill();
  for (const result of [
    { ok: false, code: 'rate_limited', retryAfterSeconds: 123 },
    { ok: false, code: 'busy' }, { ok: false, code: 'unavailable' },
    { ok: false, code: 'invalid', fields: { title: 'もう少し短くしてください。' } }
  ]) {
    env.submit(); env.success(result); assert.equal(env.form.elements.content.value, '内容'); assert.equal(env.elements.submit.disabled, false); assert.equal(env.focused, 'status');
    if (result.code === 'rate_limited') assert.match(env.elements.status.textContent, /123秒/);
    if (result.code === 'busy' || result.code === 'unavailable') assert.match(env.elements.status.textContent, /もう一度送って/);
    if (result.code === 'invalid') assert.equal(env.elements['title-error'].textContent, result.fields.title);
  }
});

test('rate_limited without a valid wait time still explains congestion and preserves input', () => {
  const env = browser(); env.fill();
  for (const wait of [undefined, null, 0, -1, 1.5, '60', NaN, Infinity]) {
    env.submit(); env.success({ ok: false, code: 'rate_limited', retryAfterSeconds: wait });
    assert.equal(env.elements.status.textContent, '送信が集中しています。少し待ってから、もう一度送信してください。入力内容は残っています。');
    assert.equal(env.form.elements.title.value, '件名'); assert.equal(env.focused, 'status'); assert.equal(env.elements['report-inputs'].disabled, false);
  }
});

test('unsupported browser keeps input and explicitly warns that reloading clears it', () => {
  const env = browser({ cryptoAvailable: false }); env.fill(); env.submit();
  assert.equal(env.sent.length, 0); assert.equal(env.form.elements.content.value, '内容');
  assert.match(env.elements.status.textContent, /ページを再読み込みすると入力内容は消えます。別のブラウザーで試すか、時間をおいてください。/);
  assert.equal(env.focused, 'status');
});

test('success shows receipt near submit, prevents repeat and explicit another resets', () => {
  const env = browser(); env.fill(); env.submit(); env.success({ ok: true, receipt: 'R-ABCDEF2345', duplicate: false });
  assert.match(env.elements.status.textContent, /受付番号：R-ABCDEF2345/); assert.match(env.elements.status.textContent, /Issue 番号とは別/);
  assert.match(env.elements.status.textContent, /受付番号は送信の控えです。個別の返信はありません。すべての報告が公開されるとは限りません。/);
  assert.equal(env.focused, 'status'); assert.equal(env.elements.submit.disabled, true);
  env.submit(); assert.equal(env.sent.length, 1);
  const firstKey = env.sent[0].submissionKey;
  env.elements.another.listeners.click(); assert.equal(env.form.elements.title.value, ''); assert.equal(env.elements.submit.disabled, false); assert.equal(env.focused, 'title');
  env.fill(); env.submit(); assert.notEqual(env.sent[1].submissionKey, firstKey);
});

const siteHtml = readFileSync(new URL('../../site/report/index.html', import.meta.url), 'utf8');
function siteWithUrl(url) {
  const declaration = /const REPORT_APP_URL = [^;\r\n]+;/g;
  assert.equal([...siteHtml.matchAll(declaration)].length, 1);
  return siteHtml.replace(declaration, `const REPORT_APP_URL = ${JSON.stringify(url)};`);
}

function renderSite(html) {
  const nodes = { available: { hidden: true }, unavailable: { hidden: false }, fallback: {}, 'form-container': { children: [], appendChild(child) { this.children.push(child); } } };
  const created = [];
  vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], { document: { getElementById: id => nodes[id], createElement(tag) { const node = { tag }; created.push(node); return node; } } });
  return { nodes, created };
}

test('Pages is fail closed: null configuration renders preparation copy with no iframe', () => {
  assert.doesNotMatch(siteHtml, /<iframe\b/i);
  assert.match(siteHtml, /フォームは現在準備中/);
  assert.match(siteHtml, /href="https:\/\/github.com\/terudoru\/gakujo-chan-extender\/issues\/new"/);
  assert.match(siteHtml, /アカウントが必要・投稿はすぐ公開/);
  assert.match(siteHtml, /氏名・学籍番号・パスワード・成績・学情の画面の内容は書かないでください。/);
  assert.match(siteHtml, /個別の返信はありません。すべての報告が公開されるとは限りません。/);
  assert.equal([...siteHtml.matchAll(/<script\b/g)].length, 1);
  const rendered = renderSite(siteWithUrl(null)); assert.equal(rendered.created.length, 0); assert.equal(rendered.nodes.available.hidden, true); assert.equal(rendered.nodes.unavailable.hidden, false);
});

test('configured Pages embeds only a validated exec URL with title and fallback link', () => {
  const exec = 'https://script.google.com/macros/s/EXAMPLE_ID/exec';
  const rendered = renderSite(siteWithUrl(exec));
  assert.equal(rendered.created.length, 1); assert.equal(rendered.created[0].tag, 'iframe'); assert.equal(rendered.created[0].src, exec); assert.ok(rendered.created[0].title);
  assert.equal(rendered.nodes.fallback.href, exec); assert.equal(rendered.nodes.available.hidden, false); assert.equal(rendered.nodes.unavailable.hidden, true);
  for (const invalid of ['javascript:alert(1)', 'https://example.com/exec', 'https://script.google.com/macros/s/EXAMPLE_ID/dev']) assert.equal(renderSite(siteWithUrl(invalid)).created.length, 0);
});

test('published app and Pages use the same validated intake URL', () => {
  const app = readFileSync(new URL('../../lib/src/report_form.dart', import.meta.url), 'utf8');
  const endpoint = app.match(/const _reportEndpointUrl =\s*'([^']+)';/)[1];
  assert.match(endpoint, /^https:\/\/script\.google\.com\/macros\/s\/[A-Za-z0-9_-]+\/exec$/);
  const rendered = renderSite(siteHtml);
  assert.equal(rendered.created.length, 1);
  assert.equal(rendered.created[0].src, endpoint);
  assert.equal(rendered.nodes.fallback.href, endpoint);
});
