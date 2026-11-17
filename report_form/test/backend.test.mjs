import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { environment, payload, headers, source, adminSource } from './fakes.mjs';

test('app submission stores the complete schema and a separate receipt', () => {
  const env = environment();
  const input = payload({ ignored: 'not stored' });
  const result = env.app(input);
  assert.deepEqual(result, { ok: true, receipt: result.receipt, duplicate: false });
  assert.match(result.receipt, /^R-[A-Z2-9]{10}$/);
  assert.notEqual(result.receipt, input.submissionKey);
  assert.deepEqual(env.rows[0], headers);
  const canonical = JSON.stringify(Object.fromEntries(['type', 'title', 'content', 'steps', 'expected', 'version', 'platform', 'diagnostic', 'diagnosticOmitted', 'client'].map(key => [key, input[key]])));
  const hash = createHash('sha256').update(canonical).digest('hex');
  assert.deepEqual(env.rows[1], [result.receipt, input.submissionKey, '2026-11-17T03:15:00.000Z', 'app', 'bug', input.title, input.content, input.steps, input.expected, input.version, 'windows', 'attached', input.diagnostic, 'new', env.rows[1][14], hash]);
  assert.match(env.rows[1][14], /^https:\/\/github\.com\//);
  assert.equal(env.writes.filter(write => write.append).length, 1);
  assert.equal(env.writes.filter(write => write.setValues).length, 0);
  assert.equal(env.rows.length, 2);
  assert.equal(env.releases, 1);
  assert.equal(env.isLocked(), false);
});

test('Sheets fake coerces unquoted numbers/dates/formulas and strips only a text-prefix apostrophe', () => {
  const env = environment(); const row = Array(headers.length).fill('');
  row[5] = '3/4'; row[6] = '=1+1'; row[7] = '+1'; row[8] = "'3/4"; row[9] = '1.10';
  const lock = env.context.LockService.getScriptLock(); assert.equal(lock.tryLock(10000), true);
  const sheet = env.context.SpreadsheetApp.openById('test_spreadsheet_id').getSheetByName('reports');
  sheet.appendRow(row); env.context.SpreadsheetApp.flush(); lock.releaseLock();
  assert.ok(env.rows[1][5] instanceof Date); assert.equal(env.rows[1][9], 1.1); assert.equal(env.rows[1][7], 1);
  assert.equal(env.rows[1][8], '3/4'); assert.equal(env.rows[1][6], '#FAKE_FORMULA');
  assert.deepEqual(env.formulas, [{ row: 2, column: 7, formula: '=1+1' }]);
});

test('all nonempty text cells round-trip exactly, including numeric/date/formula-looking input', () => {
  const env = environment();
  const input = payload({ version: '1.10', title: '3/4', content: '=1+1', steps: '+1', expected: "'literal apostrophe" });
  const result = env.app(input); assert.equal(result.ok, true);
  const lock = env.context.LockService.getScriptLock(); assert.equal(lock.tryLock(10000), true);
  const readback = env.context.SpreadsheetApp.openById('test_spreadsheet_id').getSheetByName('reports').getRange(2, 1, 1, headers.length).getValues()[0];
  env.context.SpreadsheetApp.flush(); lock.releaseLock();
  for (const key of ['version', 'title', 'content', 'steps', 'expected']) {
    assert.equal(readback[headers.indexOf(key)], input[key]); assert.equal(typeof readback[headers.indexOf(key)], 'string');
  }
  const written = env.writes.find(write => write.append).append;
  for (let i = 0; i < headers.length; i++) {
    if (i === 2 || i === 14) { assert.ok(!written[i].startsWith("'")); continue; }
    if (written[i] === '') continue;
    assert.equal(written[i], "'" + env.rows[1][i], headers[i] + ' must be stored as text');
  }
  assert.equal(env.formulas.length, 0);
  assert.deepEqual(env.app(input), { ok: true, receipt: result.receipt, duplicate: true });
});

test('duplicate key returns original receipt even at the quota or row cap', () => {
  const env = environment({ properties: { HOURLY_LIMIT: '1', MAX_ROWS: '1' } });
  const input = payload();
  const first = env.app(input);
  assert.deepEqual(env.app(input), { ok: true, receipt: first.receipt, duplicate: true });
  assert.equal(env.rows.length, 2);
  assert.equal(env.releases, 2);
  const counters = Object.entries(env.properties).filter(([key]) => key.startsWith('quota_'));
  assert.equal(counters.length, 2);
  assert.ok(counters.every(([, value]) => value === '1'));
});

test('dedupe searches only column B with whole-cell match and reads only a matching report row', () => {
  const env = environment(); const target = payload();
  assert.equal(env.app(payload({ title: target.submissionKey, diagnostic: target.submissionKey })).ok, true);
  env.rows[1][1] = 'prefix-' + target.submissionKey + '-suffix';
  const result = env.app(target); assert.equal(result.ok, true); assert.equal(result.duplicate, false);
  assert.equal(env.rows.length, 3); assert.equal(env.searches.length, 1);
  assert.deepEqual(env.searches[0], { text: target.submissionKey, row: 2, column: 2, count: 1, columns: 1, entire: true, caseSensitive: true });
  assert.equal(env.reads.filter(read => read.row > 1 && read.columns === headers.length).length, 0);
  assert.deepEqual(env.app(target), { ok: true, receipt: result.receipt, duplicate: true });
  assert.deepEqual(env.reads.filter(read => read.row > 1 && read.columns === headers.length), [{ row: 3, column: 1, count: 1, columns: headers.length }]);
  assert.doesNotMatch(source, /getDataRange/);
});

test('admin deletion between TextFinder match and row read returns busy until the UUID is rechecked on retry', () => {
  const env = environment(); assert.equal(env.app(payload()).ok, true);
  env.rows[1][2] = new Date(env.now() - 181 * 86400000).toISOString();
  const target = payload(); const original = env.app(target); assert.equal(original.ok, true);
  assert.equal(env.app(payload()).ok, true);
  const appends = env.writes.filter(write => write.append).length;
  env.beforeMatchRead = () => env.adminContext.dailyCleanup();
  assert.deepEqual(env.app(target), { ok: false, code: 'busy' });
  assert.equal(env.writes.filter(write => write.append).length, appends);
  assert.equal(env.rows.length, 3);
  assert.deepEqual(env.app(target), { ok: true, receipt: original.receipt, duplicate: true });
  assert.equal(env.rows.length, 3); assert.equal(env.isLocked(), false);
});

test('app/web share one reports schema, receipt/draft/status, combined quota and retention', () => {
  const env = environment({ properties: { HOURLY_LIMIT: '2', DAILY_LIMIT: '2' } });
  const app = payload();
  const web = payload({ client: 'web', diagnostic: null, diagnosticOmitted: undefined });
  const appResult = env.app(app); const webResult = env.web(web);
  assert.equal(appResult.ok, true); assert.equal(webResult.ok, true);
  assert.deepEqual(env.rows[0], headers); assert.equal(env.rows.length, 3);
  for (const [rowIndex, result, client, diagnosticStatus] of [[1, appResult, 'app', 'attached'], [2, webResult, 'web', 'web_none']]) {
    assert.equal(env.rows[rowIndex].length, headers.length);
    assert.match(result.receipt, /^R-[A-Z2-9]{10}$/);
    assert.equal(env.rows[rowIndex][3], client); assert.equal(env.rows[rowIndex][11], diagnosticStatus);
    assert.equal(env.rows[rowIndex][13], 'new'); assert.match(env.rows[rowIndex][14], /^https:\/\/github\.com\//);
    assert.match(env.rows[rowIndex][15], /^[a-f0-9]{64}$/);
  }
  assert.notEqual(appResult.receipt, webResult.receipt);
  assert.equal(env.rows[1][14], env.rows[2][14], 'same public fields use the same draft builder');
  assert.equal(env.rows[2][12], '');
  assert.equal(env.app(payload()).code, 'rate_limited');
  assert.equal(env.web(payload({ client: 'web', diagnostic: null })).code, 'rate_limited');
  const counters = Object.entries(env.properties).filter(([key]) => key.startsWith('quota_'));
  assert.equal(counters.length, 2); assert.ok(counters.every(([, value]) => value === '2'));
  env.setNow(env.now() + 181 * 86400000); env.adminContext.dailyCleanup();
  assert.deepEqual(env.rows, [headers]); assert.equal(env.rich.size, 0);
  assert.equal(env.releases, 5); assert.equal(env.isLocked(), false);
});

test('same submissionKey across app/web conflicts because canonical client differs', () => {
  const env = environment(); const input = payload(); const result = env.app(input);
  assert.equal(result.ok, true);
  assert.deepEqual(env.web({ ...input, client: 'web', diagnostic: null }), { ok: false, code: 'conflict' });
  assert.equal(env.rows.length, 2);
});

test('same key/same normalized payload deduplicates; changed canonical content conflicts', () => {
  const env = environment(); const input = payload(); const first = env.app(input);
  assert.deepEqual(env.app({ ...input, title: '  ' + input.title + '\u0000 ' }), { ok: true, receipt: first.receipt, duplicate: true });
  for (const changes of [{ content: 'changed' }, { diagnostic: 'changed diagnostic' }, { diagnosticOmitted: true }]) {
    assert.deepEqual(env.app({ ...input, ...changes }), { ok: false, code: 'conflict' });
  }
  assert.equal(env.rows.length, 2); assert.equal(env.writes.filter(write => write.append).length, 1);
});

test('injected digest or pre-write failure stores nothing; retry makes exactly one complete row', () => {
  for (const failure of ['failDigest', 'failAppend']) {
    const env = environment(); const input = payload(); env[failure] = true;
    assert.deepEqual(env.app(input), { ok: false, code: 'unavailable' }); assert.equal(env.rows.length, 1);
    assert.equal(env.writes.filter(write => write.setValues).length, 0);
    env[failure] = false; const result = env.app(input); assert.equal(result.ok, true);
    assert.equal(env.rows.length, 2); assert.match(env.rows[1][14], /^https:\/\/github\.com\//); assert.match(env.rows[1][15], /^[a-f0-9]{64}$/);
    assert.deepEqual(env.app(input), { ok: true, receipt: result.receipt, duplicate: true }); assert.equal(env.rows.length, 2);
  }
});

test('independent admin deletion immediately before intake append creates no holes or false MAX_ROWS full', () => {
  const env = environment({ properties: { MAX_ROWS: '3' } });
  assert.equal(env.app(payload()).ok, true);
  env.rows[1][2] = new Date(env.now() - 181 * 86400000).toISOString();
  assert.equal(env.web(payload({ client: 'web', diagnostic: null })).ok, true);
  env.beforeAppend = () => {
    assert.equal(env.intakeIsLocked(), true); assert.equal(env.adminIsLocked(), false);
    env.adminContext.dailyCleanup();
    assert.equal(env.intakeIsLocked(), true); assert.equal(env.adminIsLocked(), false);
  };
  assert.equal(env.app(payload({ title: '=third' })).ok, true);
  assert.equal(env.rows.length, 3); assert.equal(env.rows.filter(row => row[0]).length, 3);
  assert.equal(env.rows[2][5], '=third'); assert.equal(env.writes.filter(write => write.append).at(-1).append[5], "'=third");
  assert.equal(env.app(payload()).ok, true, 'fourth attempt fills the freed slot');
  assert.equal(env.rows.length, 4); assert.equal(env.app(payload()).code, 'full');
  assert.equal(env.flushes, env.releases); assert.equal(env.isLocked(), false);
});

for (const [name, overrides, field] of [
  ['required title', { title: ' \n\t' }, 'title'],
  ['required content', { content: '' }, 'content'],
  ['title length', { title: 'あ'.repeat(81) }, 'title'],
  ['content length', { content: 'x'.repeat(4001) }, 'content'],
  ['steps length', { steps: 'x'.repeat(2001) }, 'steps'],
  ['expected length', { expected: 'x'.repeat(1001) }, 'expected'],
  ['version length', { version: 'x'.repeat(41) }, 'version'],
  ['diagnostic length', { diagnostic: 'x'.repeat(20001) }, 'diagnostic'],
  ['UTF-16 units', { title: '😀'.repeat(41) }, 'title'],
  ['type enum', { type: 'question' }, 'type'],
  ['unknown platform', { platform: 'unknown' }, 'platform'],
  ['platform type', { platform: null }, 'platform'],
  ['consent false', { consent: false }, 'consent'],
  ['consent type', { consent: 'true' }, 'consent'],
  ['required string type', { title: 12 }, 'title'],
  ['optional string type', { steps: null }, 'steps'],
  ['diagnostic type', { diagnostic: {} }, 'diagnostic'],
  ['omission flag type', { diagnosticOmitted: 'false' }, 'diagnosticOmitted'],
  ['null diagnostic without omission', { diagnostic: null }, 'diagnostic'],
  ['null diagnostic missing omission', { diagnostic: null, diagnosticOmitted: undefined }, 'diagnostic'],
  ['protocol version', { v: '1' }, 'v'],
  ['app route client', { client: 'web' }, 'client'],
  ['UUID version', { submissionKey: '12345678-1234-1234-9234-123456789abc' }, 'submissionKey'],
  ['UUID variant', { submissionKey: '12345678-1234-4234-1234-123456789abc' }, 'submissionKey'],
  ['UUID uppercase', { submissionKey: 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA' }, 'submissionKey']
]) {
  test(`rejects ${name} without writes`, () => {
    const env = environment();
    const result = env.app(payload(overrides));
    assert.equal(result.code, 'invalid'); assert.ok(result.fields[field]);
    assert.equal(env.rows.length, 1); assert.equal(env.writes.length, 0); assert.equal(env.attempts.length, 0);
  });
}

test('null/array/scalar body rejected; unknown keys never become public or stored', () => {
  const env = environment();
  for (const input of [null, [], true, 'text']) assert.equal(env.app(input).code, 'invalid');
  const input = payload({ secretUnknown: 'PRIVATE_UNKNOWN' });
  assert.equal(env.app(input).ok, true);
  assert.ok(!JSON.stringify(env.rows).includes('PRIVATE_UNKNOWN'));
  assert.ok(!env.rows[1][14].includes('PRIVATE_UNKNOWN'));
});

test('controls stripped, whitespace trimmed, newline/tab kept inside values', () => {
  const env = environment();
  assert.equal(env.app(payload({ title: ' \u0000題\r名\u007f ', content: '前\n\t後\u0085' })).ok, true);
  assert.equal(env.rows[1][5], '題名'); assert.equal(env.rows[1][6], '前\n\t後');
});

test('request forces steps/expected empty and uses enhancement label', () => {
  const env = environment();
  assert.equal(env.app(payload({ type: 'request', diagnostic: null, steps: '\tdiscard', expected: '\rdiscard' })).ok, true);
  assert.equal(env.rows[1][7], ''); assert.equal(env.rows[1][8], '');
  const url = new URL(env.rows[1][14]);
  assert.equal(url.searchParams.get('labels'), 'enhancement,from-form');
  assert.ok(!url.searchParams.get('body').includes('discard'));
});

for (const [type, label, contentHeading, labels] of [
  ['bug', 'バグ報告', '起きたこと', 'bug,from-form'],
  ['request', '機能追加の要望', '実現したい機能', 'enhancement,from-form'],
  ['improvement', '既存機能の改善要望', '今困っている点と、どう変わると良いか', 'enhancement,from-form'],
  ['other', 'その他', '内容', 'from-form']
]) {
  test(`type ${type} uses same app/web store with correct public headings/labels and diagnostics`, () => {
    const env = environment();
    const overrides = { type, diagnostic: type === 'bug' ? '{"private":"BUG_ONLY_SECRET"}' : null };
    assert.equal(env.app(payload(overrides)).ok, true);
    assert.equal(env.web(payload({ ...overrides, client: 'web', diagnostic: null })).ok, true);
    assert.equal(env.rows.length, 3);
    assert.equal(env.rows[1][4], type); assert.equal(env.rows[2][4], type);
    assert.equal(env.rows[1][11], type === 'bug' ? 'attached' : 'not_applicable');
    assert.equal(env.rows[2][11], 'web_none'); assert.equal(env.rows[2][12], '');
    for (const row of [2, 3]) {
      const url = new URL(env.rows[row - 1][14]); const body = url.searchParams.get('body');
      assert.equal(url.searchParams.get('labels'), labels);
      assert.ok(body.includes('### 種類\n' + label)); assert.ok(body.includes('### ' + contentHeading + '\n'));
      assert.ok(!body.includes('BUG_ONLY_SECRET'));
      assert.equal(body.includes('### 問題が起きるまでの手順'), type === 'bug');
      if (type !== 'bug') { assert.equal(env.rows[row - 1][7], ''); assert.equal(env.rows[row - 1][8], ''); }
    }
    if (type !== 'bug') {
      const result = env.app(payload({ type, diagnostic: 'DO_NOT_STORE' }));
      assert.equal(result.code, 'invalid'); assert.ok(result.fields.diagnostic); assert.equal(env.rows.length, 3);
      assert.equal(env.web(payload({ client: 'web', type, diagnostic: 'DO_NOT_STORE' })).code, 'invalid');
    }
  });
}

test('explicit diagnostic omission is recorded', () => {
  const env = environment();
  assert.equal(env.app(payload({ diagnostic: null, diagnosticOmitted: true })).ok, true);
  assert.equal(env.rows[1][11], 'omitted_by_user'); assert.equal(env.rows[1][12], '');
});

test('web has no diagnostic; omission flag is ignored and app client rejected', () => {
  const env = environment();
  assert.equal(env.web(payload({ client: 'web', diagnostic: 'PRIVATE' })).code, 'invalid');
  assert.equal(env.web(payload({ diagnostic: null })).code, 'invalid');
  assert.equal(env.web(payload({ client: 'web', diagnostic: null, diagnosticOmitted: 'ignored' })).ok, true);
  assert.equal(env.rows[1][3], 'web'); assert.equal(env.rows[1][11], 'web_none'); assert.equal(env.rows[1][12], '');
});

test('oversized declared body, contents and multibyte bytes rejected before parsing', () => {
  const env = environment();
  for (const post of [
    { contents: '{', length: 65537, type: 'application/json' },
    { contents: '{'.repeat(65537), length: 1, type: 'application/json' },
    { contents: 'あ'.repeat(22000), length: 1, type: 'application/json' }
  ]) assert.equal(env.output({ postData: post }).code, 'too_large');
  assert.equal(env.web(payload({ client: 'web', diagnostic: null, ignored: 'x'.repeat(65536) })).code, 'too_large');
  assert.equal(env.writes.length, 0);
});

test('malformed JSON, missing postData and non JSON media types rejected', () => {
  const env = environment();
  for (const event of [undefined, {}, { postData: {} }, { postData: { contents: '{', type: 'application/json' } }, { postData: { contents: '{}', type: 'text/plain' } }]) assert.equal(env.output(event).code, 'invalid');
  assert.equal(env.app(payload(), { type: 'application/json; charset=utf-8' }).ok, true);
});

for (const properties of [{ SHEET_ID: undefined }, { SHEET_ID: '' }, { ENABLED: undefined }, { ENABLED: 'false' }, { ENABLED: 'TRUE' }, { HOURLY_LIMIT: '0' }, { DAILY_LIMIT: '-1' }, { MAX_ROWS: 'no' }, { ISSUE_REPO: 'bad?repo' }]) {
  test(`unconfigured/invalid properties fail closed: ${JSON.stringify(properties)}`, () => {
    const env = environment({ properties });
    assert.equal(env.app(payload()).code, 'unavailable');
    assert.equal(env.web(payload({ client: 'web', diagnostic: null })).code, 'unavailable');
    assert.equal(env.rows.length, 1); assert.equal(env.writes.length, 0);
    assert.equal(env.context.doGet().frameMode, null);
    assert.doesNotMatch(env.context.doGet().content, /<form\b/i);
    assert.match(env.context.doGet().content, /現在は受け付けていません/);
  });
}

test('lock failure returns busy with no writes or release of unheld lock', () => {
  const env = environment(); env.lockAvailable = false;
  assert.deepEqual(env.app(payload()), { ok: false, code: 'busy' });
  assert.equal(env.writes.length, 0); assert.equal(env.releases, 0); assert.deepEqual(env.attempts, [10000]);
});

test('hourly quota persists across executions, expires at UTC hour, duplicate does not count', () => {
  const env = environment({ properties: { HOURLY_LIMIT: '1' } });
  const input = payload(); assert.equal(env.app(input).ok, true);
  assert.equal(env.app(input).duplicate, true);
  assert.deepEqual(env.app(payload()), { ok: false, code: 'rate_limited', retryAfterSeconds: 2700 });
  assert.equal(env.rows.length, 2); assert.equal(env.releases, 3);
  const restarted = environment({ properties: env.properties, rows: env.rows });
  assert.equal(restarted.app(payload()).code, 'rate_limited');
  restarted.setNow('2026-11-17T04:00:00Z'); assert.equal(restarted.app(payload()).ok, true);
  assert.equal(restarted.isLocked(), false);
});

test('daily quota uses persistent properties and returns longer retry when both exhausted', () => {
  const env = environment({ properties: { HOURLY_LIMIT: '1', DAILY_LIMIT: '1' } });
  assert.equal(env.app(payload()).ok, true);
  assert.deepEqual(env.app(payload()), { ok: false, code: 'rate_limited', retryAfterSeconds: 74700 });
  env.setNow('2026-11-17T04:00:00Z');
  assert.equal(env.app(payload()).retryAfterSeconds, 72000);
  env.setNow('2026-11-18T00:00:00Z'); assert.equal(env.app(payload()).ok, true);
  assert.equal(env.releases, 4);
});

test('MAX_ROWS excludes header and rejects new reports, releasing lock', () => {
  const env = environment({ properties: { MAX_ROWS: '1' } });
  assert.equal(env.app(payload()).ok, true); assert.deepEqual(env.app(payload()), { ok: false, code: 'full' });
  assert.equal(env.rows.length, 2); assert.equal(env.releases, 2);
});

for (const prefix of ['=', '+', '-', '@', '\t', '\r']) {
  test(`formula injection escaped for every free-text column: ${JSON.stringify(prefix)}`, () => {
    const env = environment(); const dangerous = prefix + 'IMPORTXML(1)';
    const input = payload(Object.fromEntries(['title', 'content', 'steps', 'expected', 'version', 'diagnostic'].map(key => [key, dangerous])));
    assert.equal(env.app(input).ok, true);
    for (const column of [5, 6, 7, 8, 9, 12]) {
      assert.equal(env.rows[1][column], dangerous.trim());
      assert.equal(env.writes.find(write => write.append).append[column], "'" + dangerous.trim());
    }
    assert.equal(env.formulas.length, 0);
    assert.doesNotMatch(source, /\.setFormula\s*\(/);
  });
}

test('Issue draft is a plain URL, includes public allowlist only and neutralizes mentions', () => {
  const env = environment(); const input = payload({ title: '@maintainer failure', content: 'Hello @all', diagnostic: 'SECRET_DIAGNOSTIC', ignored: 'SECRET_UNKNOWN' });
  const result = env.app(input); const link = env.rows[1][14]; const url = new URL(link);
  assert.equal(url.origin, 'https://github.com'); assert.equal(url.pathname, '/terudoru/gakujo-chan-extender/issues/new');
  assert.equal(url.searchParams.get('title'), '@\u200bmaintainer failure');
  assert.ok(url.searchParams.get('body').includes('@\u200ball'));
  assert.equal(url.searchParams.get('labels'), 'bug,from-form');
  const decoded = decodeURIComponent(link);
  for (const privateValue of ['SECRET_DIAGNOSTIC', 'SECRET_UNKNOWN', input.submissionKey, result.receipt, '2026-11-17', 'attached']) assert.ok(!decoded.includes(privateValue));
  for (const value of [input.steps, input.expected, input.version, input.platform]) assert.ok(url.searchParams.get('body').includes(value));
  assert.equal(env.rich.size, 0); assert.doesNotMatch(source, /setRichText|newRichText|setFormula/);
});

test('long Japanese/emoji Issue draft URL capped at 6000 with truncation note', () => {
  const env = environment();
  assert.equal(env.app(payload({ title: '😀'.repeat(40), content: 'あ'.repeat(3999) + '\uD800', steps: 'x'.repeat(2000) })).ok, true);
  const link = env.rows[1][14];
  assert.ok(link.length <= 6000); assert.match(new URL(link).searchParams.get('body'), /URL の長さ制限のため省略/);
});

test('bound admin cleanup deletes only expired groups, keeps boundary/newer rows and returns early within 12h', () => {
  const env = environment();
  const cutoff = env.now() - 180 * 86400000;
  for (const created of [cutoff - 10000, cutoff - 5000, cutoff, cutoff - 1, env.now()]) {
    const row = Array(headers.length).fill(''); row[2] = new Date(created).toISOString(); env.rows.push(row);
  }
  assert.equal(env.adminContext.dailyCleanup(), undefined);
  assert.deepEqual(env.rows.map(row => row[2]), ['createdAt', new Date(cutoff).toISOString(), new Date(env.now()).toISOString()]);
  assert.equal(env.properties.cleanup_last_ms, undefined); assert.equal(env.adminProperties.cleanup_last_ms, String(env.now()));
  const writes = env.writes.length;
  env.rows.push(Array(headers.length).fill('expired')); env.rows.at(-1)[2] = new Date(cutoff - 100).toISOString();
  env.setNow(env.now() + 12 * 3600000 - 1); env.adminContext.dailyCleanup(); assert.equal(env.writes.length, writes);
  env.setNow(env.now() + 1); env.adminContext.dailyCleanup(); assert.equal(env.rows.length, 2);
  assert.equal(env.releases, 3); assert.equal(env.isLocked(), false);
});

test('admin cleanup fails closed with invalid retention or lock, but runs with intake disabled', () => {
  const invalid = environment({ adminProperties: { RETENTION_DAYS: 'bad' } }); invalid.adminContext.dailyCleanup(); assert.equal(invalid.attempts.length, 0);
  const env = environment(); env.lockAvailable = false; env.adminContext.dailyCleanup(); assert.equal(env.writes.length, 0); assert.equal(env.adminProperties.cleanup_last_ms, undefined);
  const disabled = environment({ properties: { ENABLED: 'false' } }); disabled.adminContext.dailyCleanup(); assert.equal(disabled.adminProperties.cleanup_last_ms, String(disabled.now()));
});

test('admin retention uses its own configured day count for both clients and keeps newer reports', () => {
  const env = environment({ adminProperties: { RETENTION_DAYS: '1' }, properties: { RETENTION_DAYS: '999' } });
  assert.equal(env.app(payload()).ok, true);
  assert.equal(env.web(payload({ client: 'web', diagnostic: null })).ok, true);
  env.setNow(env.now() + 2 * 86400000);
  const latest = env.app(payload()); assert.equal(latest.ok, true);
  env.adminContext.dailyCleanup();
  assert.equal(env.rows.length, 2); assert.equal(env.rows[1][0], latest.receipt);
});

test('intake prunes its own old quota windows on each write, preserving only current counters', () => {
  const env = environment(); const hour = Math.floor(env.now() / 3600000); const day = Math.floor(env.now() / 86400000);
  Object.assign(env.properties, { [`quota_h_${hour - 1}`]: '20', [`quota_d_${day - 1}`]: '100', unrelated: 'keep' });
  assert.equal(env.app(payload()).ok, true);
  assert.equal(env.properties[`quota_h_${hour - 1}`], undefined); assert.equal(env.properties[`quota_d_${day - 1}`], undefined);
  assert.equal(env.properties[`quota_h_${hour}`], '1'); assert.equal(env.properties[`quota_d_${day}`], '1'); assert.equal(env.properties.unrelated, 'keep');
});

test('service failures expose no content and always release the acquired lock', () => {
  const env = environment(); env.failOpen = true;
  assert.deepEqual(env.app(payload()), { ok: false, code: 'unavailable' }); assert.equal(env.releases, 1);
  env.failOpen = false; env.failAppend = true;
  assert.deepEqual(env.app(payload()), { ok: false, code: 'unavailable' }); assert.equal(env.releases, 2);
  const malformedCounter = environment({ properties: { quota_h_498555: 'bad' } });
  malformedCounter.properties['quota_h_' + Math.floor(malformedCounter.now() / 3600000)] = 'bad';
  assert.equal(malformedCounter.app(payload()).code, 'unavailable'); assert.equal(malformedCounter.rows.length, 1);
});

test('empty, missing or wrong-header sheet fails closed without writes', () => {
  const env = environment({ rows: [] }); assert.equal(env.app(payload()).code, 'unavailable'); assert.deepEqual(env.rows, []);
  assert.equal(environment({ missingSheet: true }).app(payload()).code, 'unavailable');
  assert.equal(environment({ rows: [['wrong header']] }).app(payload()).code, 'unavailable');
});

test('intake exposes only doGet/doPost/submitReport; admin is a separate bound project without public routes', () => {
  const env = environment();
  // vm parses the source; inspect the resulting global function bindings as well as declarations.
  const names = Object.keys(env.context).filter(key => typeof env.context[key] === 'function' && !['Date'].includes(key));
  assert.deepEqual(names.filter(name => !name.endsWith('_')).sort(), ['doGet', 'doPost', 'submitReport']);
  const declarations = [...source.matchAll(/^function\s+(\w+)\s*\(/gm)].map(match => match[1]);
  assert.ok(declarations.every(name => ['doGet', 'doPost', 'submitReport'].includes(name) || name.endsWith('_')));
  assert.doesNotMatch(source, /dailyCleanup|deleteRows|onOpen|getActiveSpreadsheet/);
  assert.match(adminSource, /@OnlyCurrentDoc/); assert.match(adminSource, /getActiveSpreadsheet/); assert.doesNotMatch(adminSource, /HtmlService|doGet|doPost|submitReport|onOpen|getUi/);
  const adminFunctions = Object.keys(env.adminContext).filter(key => typeof env.adminContext[key] === 'function' && key !== 'Date' && !key.endsWith('_'));
  assert.deepEqual(adminFunctions, ['dailyCleanup']);
  const page = env.context.doGet(); assert.match(page.content, /<form\b/); assert.equal(page.frameMode, 'ALLOWALL');
});

test('manifest contains exactly the dedicated-account spreadsheet scope and anonymous deploying-user route', () => {
  const manifest = JSON.parse(readFileSync(new URL('../apps_script/intake/appsscript.json', import.meta.url), 'utf8'));
  assert.deepEqual(manifest.oauthScopes, ['https://www.googleapis.com/auth/spreadsheets']);
  assert.deepEqual(manifest.webapp, { access: 'ANYONE_ANONYMOUS', executeAs: 'USER_DEPLOYING' });
  assert.equal(manifest.runtimeVersion, 'V8'); assert.equal(manifest.timeZone, 'Asia/Tokyo'); assert.equal(manifest.exceptionLogging, 'STACKDRIVER');
  assert.doesNotMatch(source, /CacheService|UrlFetchApp|DriveApp|ScriptApp|GmailApp|Logger\./);
  const adminManifest = JSON.parse(readFileSync(new URL('../apps_script/admin/appsscript.json', import.meta.url), 'utf8'));
  assert.deepEqual(adminManifest.oauthScopes, ['https://www.googleapis.com/auth/spreadsheets.currentonly']); assert.equal(adminManifest.webapp, undefined);
});
