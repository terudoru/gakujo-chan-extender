import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/worker.js';
import { validateReport } from '../public/assets/js/report-schema.js';
import { ipKey } from '../src/reports.js';
import { fixture, siteverify } from './helpers.mjs';

test('valid report returns only its receipt and stores sanitized fields privately', async (t) => {
  const { call, DB, input } = fixture(t);
  const network = siteverify(t);
  const accepted = await call('/api/reports', { body: { ...input, title: '\u0000  件名\u0007  ', arbitrary: 'ignored' } });
  assert.equal(accepted.status, 201);
  assert.deepEqual(await accepted.json(), { id: 1 });
  const report = DB.sqlite.prepare('SELECT * FROM reports').get();
  assert.equal(report.title, '件名');
  assert.equal(report.content, input.content);
  assert.equal(report.diagnostic, input.diagnostic);
  assert.equal(report.status, 'new');
  assert.equal(report.arbitrary, undefined);
  const rate = DB.sqlite.prepare('SELECT * FROM rate_events').get();
  assert.match(rate.ip_hash, /^[a-f0-9]{64}$/);
  assert.equal(JSON.stringify(rate).includes('192.0.2.42'), false);
  const sent = new URLSearchParams(network.mock.calls[0].arguments[1].body);
  assert.equal(sent.get('remoteip'), '192.0.2.42');
  assert.equal(sent.get('response'), 'test-token');
});

test('schema errors have a field map and never echo input', async (t) => {
  const { call, DB, input } = fixture(t);
  const response = await call('/api/reports', { body: { ...input, title: 'x'.repeat(81), content: 5, consent: false, platform: 'bad', type: 'secret-value' } });
  assert.equal(response.status, 422);
  const result = await response.json();
  assert.deepEqual(Object.keys(result.errors).sort(), ['consent', 'content', 'platform', 'title', 'type']);
  assert.equal(JSON.stringify(result).includes('secret-value'), false);
  assert.equal(DB.sqlite.prepare('SELECT COUNT(*) AS n FROM reports').get().n, 0);
});

test('shared schema validates every limit, trims, strips controls, and ignores unknown keys', () => {
  const base = { type: 'request', title: '  件名  ', content: '内容\u0000\n\tテスト', consent: true, secret: 'ignored' };
  assert.equal(validateReport(base).value.content, '内容\n\tテスト');
  assert.equal(validateReport(base).value.title, '件名');
  assert.equal(validateReport(base).value.secret, undefined);
  for (const [key, max] of Object.entries({ title: 80, content: 4000, steps: 2000, expected: 1000, version: 40, diagnostic: 20000 })) {
    assert.ok(validateReport({ ...base, [key]: 'x'.repeat(max + 1) }).errors[key]);
    assert.ok(validateReport({ ...base, [key]: {} }).errors[key]);
  }
  assert.ok(validateReport({ ...base, title: '\u0001 ' }).errors.title);
  assert.ok(validateReport({ ...base, platform: {} }).errors.platform);
  assert.ok(validateReport([]).errors.form);
  assert.equal(validateReport({ ...base, steps: 'not public for request', expected: 'not public' }).value.steps, '');
});

for (const [label, change, expected] of [
  ['honeypot', { website: 'spam' }, 400],
  ['non-string honeypot', { website: false }, 400],
  ['too fast', { elapsedMs: 2999 }, 400],
  ['missing elapsed time', { elapsedMs: undefined }, 400],
  ['string elapsed time', { elapsedMs: '3000' }, 400],
  ['missing token', { turnstileToken: '' }, 400],
  ['oversize token', { turnstileToken: 'x'.repeat(2049) }, 400],
]) test(`rejects ${label}`, async (t) => {
  const { call, input } = fixture(t);
  assert.equal((await call('/api/reports', { body: { ...input, ...change } })).status, expected);
});

for (const origin of ['', 'https://evil.example', 'null']) test(`rejects wrong or missing Origin: ${origin}`, async (t) => {
  const { call } = fixture(t);
  assert.equal((await call('/api/reports', { headers: { Origin: origin } })).status, 403);
});

test('rejects wrong content-type, malformed JSON, and oversize streaming body', async (t) => {
  const { call, env } = fixture(t);
  assert.equal((await call('/api/reports', { headers: { 'Content-Type': 'text/plain' } })).status, 415);
  for (const [body, expected] of [['{', 400], ['[]', 400], ['null', 400], ['{"content":"' + 'x'.repeat(65536) + '"}', 413]]) {
    const response = await worker.fetch(new Request(`${env.SITE_ORIGIN}/api/reports`, { method: 'POST', headers: { Origin: env.SITE_ORIGIN, 'Content-Type': 'application/json' }, body }), env);
    assert.equal(response.status, expected);
  }
  assert.equal((await call('/api/reports', { headers: { 'Content-Length': '65537' } })).status, 413);
});

for (const key of ['DB', 'TURNSTILE_SECRET', 'IP_HASH_SALT', 'SITE_ORIGIN', 'TURNSTILE_SITE_KEY', 'TURNSTILE_HOSTNAMES', 'ISSUE_REPO', 'REPORT_RETENTION_DAYS']) {
  test(`fails closed without ${key}`, async (t) => {
    const { call, env } = fixture(t);
    delete env[key];
    assert.equal((await call()).status, 503);
  });
}

test('only explicit loopback DEV permits missing configured origin or connecting IP', async (t) => {
  const { call, env } = fixture(t);
  siteverify(t);
  delete env.SITE_ORIGIN;
  env.DEV = 'true';
  assert.equal((await call('/api/reports', { headers: { 'CF-Connecting-IP': '' } })).status, 201);
  const remote = await worker.fetch(new Request('https://example.com/api/reports', { method: 'POST' }), env);
  assert.equal(remote.status, 503);
});

for (const [name, verification] of [
  ['failed', { success: false, action: 'report', hostname: 'gakujo-report.terudoru.com' }],
  ['wrong action', { success: true, action: 'signup', hostname: 'gakujo-report.terudoru.com' }],
  ['missing action from official dummy secret', { success: true, hostname: 'example.com' }],
  ['wrong hostname', { success: true, action: 'report', hostname: 'evil.example' }],
]) test(`Turnstile ${name} is rejected`, async (t) => {
  const { call } = fixture(t); siteverify(t, verification);
  assert.equal((await call()).status, 400);
});

test('siteverify network error, non-JSON, and upstream 5xx fail closed', async (t) => {
  const { call } = fixture(t);
  const mock = t.mock.method(globalThis, 'fetch', async () => { throw new Error('offline'); });
  assert.equal((await call()).status, 503);
  mock.mock.mockImplementation(async () => new Response('not json'));
  assert.equal((await call()).status, 503);
  mock.mock.mockImplementation(async () => new Response('error', { status: 500 }));
  assert.equal((await call()).status, 503);
});

test('three reports per ten minutes are reserved atomically and expose Retry-After', async (t) => {
  const { call, DB } = fixture(t); siteverify(t);
  const responses = await Promise.all(Array.from({ length: 8 }, () => call()));
  assert.equal(responses.filter((r) => r.status === 201).length, 3);
  assert.equal(responses.filter((r) => r.status === 429).length, 5);
  const limited = responses.find((r) => r.status === 429);
  const body = await limited.json();
  assert.equal(body.retryAfter, Number(limited.headers.get('Retry-After')));
  assert.ok(body.retryAfter > 590 && body.retryAfter <= 600);
  assert.equal(DB.sqlite.prepare('SELECT COUNT(*) AS n FROM rate_events').get().n, 3);
  assert.equal(DB.sqlite.prepare('SELECT COUNT(*) AS n FROM reports').get().n, 3);
});

test('ten reports per rolling day remain limited after ten-minute window passes', async (t) => {
  const { call, DB } = fixture(t); siteverify(t);
  for (let n = 0; n < 10; n++) {
    const response = await call(); assert.equal(response.status, 201);
    DB.sqlite.prepare('UPDATE rate_events SET created_at = created_at - 601').run();
  }
  assert.equal((await call()).status, 429);
});

test('IPv6 canonicalization groups a /64 and keeps adjacent prefixes separate', async (t) => {
  const { call } = fixture(t); siteverify(t);
  for (const ip of ['2001:db8:0:1::1', '2001:0db8:0000:0001:abcd:2:3:4', '2001:db8:0:1::ffff']) {
    assert.equal((await call('/api/reports', { headers: { 'CF-Connecting-IP': ip } })).status, 201);
  }
  assert.equal((await call('/api/reports', { headers: { 'CF-Connecting-IP': '2001:db8:0:1::99' } })).status, 429);
  assert.equal((await call('/api/reports', { headers: { 'CF-Connecting-IP': '2001:db8:0:2::1' } })).status, 201);
  assert.equal(ipKey('::ffff:192.0.2.42'), '192.0.2.42');
  assert.equal(ipKey('2001:db8::1'), '2001:db8:0:0::/64');
});

test('global rolling-day cap accepts the 200th report and rejects the 201st', async (t) => {
  const { call, DB } = fixture(t); siteverify(t);
  const insert = DB.sqlite.prepare('INSERT INTO rate_events VALUES (?, ?, ?)');
  const now = Math.floor(Date.now() / 1000);
  for (let i = 0; i < 199; i++) insert.run(`event-${i}`, `hash-${i}`, now);
  assert.equal((await call()).status, 201);
  const limited = await call('/api/reports', { headers: { 'CF-Connecting-IP': '192.0.2.99' } });
  assert.equal(limited.status, 429);
  assert.ok(Number(limited.headers.get('Retry-After')) > 86390);
});

test('failed report insert rolls back quota reservation without returning content', async (t) => {
  const { call, DB, input } = fixture(t); siteverify(t);
  DB.sqlite.exec("CREATE TRIGGER reject_report BEFORE INSERT ON reports BEGIN SELECT RAISE(ABORT, 'test'); END;");
  const response = await call();
  assert.equal(response.status, 503);
  const body = await response.text();
  assert.equal(body.includes(input.title), false);
  assert.equal(body.includes(input.diagnostic), false);
  assert.equal(DB.sqlite.prepare('SELECT COUNT(*) AS n FROM rate_events').get().n, 0);
});

test('missing or invalid production IP fails closed', async (t) => {
  const { call } = fixture(t);
  for (const ip of ['', 'bad-ip', '999.0.0.1']) assert.equal((await call('/api/reports', { headers: { 'CF-Connecting-IP': ip } })).status, 503);
});

test('cleanup deletes expired reports and rate hashes with independent retention', async (t) => {
  const { call, DB, env } = fixture(t); siteverify(t);
  await call(); await call();
  const now = Math.floor(Date.now() / 1000);
  DB.sqlite.prepare('UPDATE reports SET created_at = ? WHERE id = 1').run(now - 181 * 86400);
  DB.sqlite.prepare('UPDATE rate_events SET created_at = ? WHERE id = (SELECT id FROM rate_events LIMIT 1)').run(now - 86401);
  await worker.scheduled({}, env);
  assert.equal(DB.sqlite.prepare('SELECT COUNT(*) AS n FROM reports').get().n, 1);
  assert.equal(DB.sqlite.prepare('SELECT COUNT(*) AS n FROM rate_events').get().n, 1);
  env.REPORT_RETENTION_DAYS = '';
  await assert.rejects(worker.scheduled({}, env));
});

test('HTML placeholders are injected; missing site key closes and marks form unavailable', async (t) => {
  const { env } = fixture(t);
  let response = await worker.fetch(new Request(`${env.SITE_ORIGIN}/`), env);
  assert.equal(response.status, 200);
  let html = await response.text();
  assert.ok(html.includes(`content="${env.TURNSTILE_SITE_KEY}"`));
  assert.ok(html.includes('name="report-available" content="true"'));
  assert.equal(/__[A-Z_]+__/.test(html), false);
  env.TURNSTILE_SITE_KEY = '';
  response = await worker.fetch(new Request(`${env.SITE_ORIGIN}/`), env);
  assert.equal(response.status, 503);
  html = await response.text();
  assert.ok(html.includes('name="turnstile-site-key" content=""'));
  assert.ok(html.includes('name="report-available" content="false"'));
  assert.equal(/__[A-Z_]+__/.test(html), false);
  env.TURNSTILE_SITE_KEY = '\"><script>bad</script>';
  html = await (await worker.fetch(new Request(`${env.SITE_ORIGIN}/index.html`), env)).text();
  assert.equal(html.includes('<script>bad</script>'), false);
  assert.ok(html.includes('&quot;&gt;&lt;script&gt;'));
});

test('invalid retention configuration fails closed before any external verification', async (t) => {
  const { env, call } = fixture(t);
  for (const days of ['0', '-1', 'invalid', '999999999999999999999999999999999']) {
    env.REPORT_RETENTION_DAYS = days;
    assert.equal((await call()).status, 503);
  }
});

test('security headers on HTML, assets, API success, failure, and unknown routes; no CORS', async (t) => {
  const { env, call } = fixture(t); siteverify(t);
  const responses = [await call(), await worker.fetch(new Request(`${env.SITE_ORIGIN}/`), env), await worker.fetch(new Request(`${env.SITE_ORIGIN}/assets/style.css`), env), await call('/api/missing'), await call('/not-found')];
  for (const response of responses) {
    assert.ok(response.headers.get('Content-Security-Policy').includes("frame-ancestors 'none'"));
    assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
    assert.equal(response.headers.get('Referrer-Policy'), 'no-referrer');
    assert.equal(response.headers.get('Access-Control-Allow-Origin'), null);
  }
  assert.equal(responses[0].headers.get('Cache-Control'), 'no-store');
  assert.equal(responses[3].headers.get('Cache-Control'), 'no-store');
});
