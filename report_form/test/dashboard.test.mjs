import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import worker from '../src/worker.js';
import { issueDraft, issueUrl } from '../public/assets/js/issue.js';
import { fixture } from './helpers.mjs';

let privateKey, jwk;
before(() => {
  const pair = generateKeyPairSync('rsa', { modulusLength: 2048 });
  privateKey = pair.privateKey;
  jwk = { ...pair.publicKey.export({ format: 'jwk' }), kid: 'test-rsa', alg: 'RS256', use: 'sig' };
});
const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
function jwt(claims = {}, key = privateKey, header = {}) {
  const body = `${encode({ alg: 'RS256', kid: 'test-rsa', ...header })}.${encode({ iss: 'https://gakujo-tests.cloudflareaccess.com', aud: ['maintainer-app'], exp: Math.floor(Date.now() / 1000) + 600, nbf: Math.floor(Date.now() / 1000) - 5, ...claims })}`;
  return `${body}.${sign('RSA-SHA256', Buffer.from(body), key).toString('base64url')}`;
}
function dashboardFixture(t) {
  const f = fixture(t);
  t.mock.method(globalThis, 'fetch', async (url) => {
    assert.equal(String(url), `https://${f.env.ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`);
    return Response.json({ keys: [jwk] });
  });
  const call = (path = '/api/dashboard/reports', options = {}) => {
    const { token = jwt(), method = 'GET', body, headers } = options;
    return worker.fetch(new Request(`${f.env.SITE_ORIGIN}${path}`, {
      method, headers: { 'Cf-Access-Jwt-Assertion': token, Origin: f.env.SITE_ORIGIN, 'Content-Type': 'application/json', ...headers },
      ...(method !== 'GET' ? { body: JSON.stringify(body ?? {}) } : {}),
    }), f.env);
  };
  const insert = (n = 1) => {
    for (let i = 0; i < n; i++) f.DB.sqlite.prepare('INSERT INTO reports (created_at, type, title, content, diagnostic) VALUES (?, ?, ?, ?, ?)').run(Math.floor(Date.now() / 1000), 'bug', `Untrusted <script> #${i}`, 'Public @someone', 'PRIVATE DIAGNOSTIC');
  };
  return { ...f, call, insert };
}

test('dashboard fails 503 when Access or common configuration is absent', async (t) => {
  const { call, env } = dashboardFixture(t);
  for (const key of ['ACCESS_TEAM_DOMAIN', 'ACCESS_AUD', 'DB', 'ISSUE_REPO', 'SITE_ORIGIN', 'REPORT_RETENTION_DAYS']) {
    const saved = env[key]; env[key] = '';
    // Keep a valid request URL even while testing absent SITE_ORIGIN.
    const response = key === 'SITE_ORIGIN' ? await worker.fetch(new Request('https://gakujo-report.terudoru.com/dashboard/', { headers: { 'Cf-Access-Jwt-Assertion': jwt() } }), env) : await call();
    assert.equal(response.status, 503, key); env[key] = saved;
  }
  env.ACCESS_TEAM_DOMAIN = 'attacker.example';
  assert.equal((await call()).status, 503);
});

test('dashboard returns 401 without JWT and rejects malformed assertions', async (t) => {
  const { call } = dashboardFixture(t);
  assert.equal((await call('/dashboard/', { token: '' })).status, 401);
  for (const token of ['abc', 'a.b.c', 'a.b.c.d', 'x'.repeat(16385)]) assert.equal((await call('/api/dashboard/reports', { token })).status, 403);
});

for (const [name, claims] of [
  ['bad audience', { aud: ['other'] }], ['bad issuer', { iss: 'https://evil.cloudflareaccess.com' }],
  ['expired', { exp: 1 }], ['missing exp', { exp: undefined }], ['string exp', { exp: '99999999999' }],
  ['future nbf', { nbf: 99999999999 }], ['invalid nbf', { nbf: 'invalid' }],
]) test(`dashboard rejects ${name}`, async (t) => {
  const { call } = dashboardFixture(t);
  assert.equal((await call('/api/dashboard/reports', { token: jwt(claims) })).status, 403);
});

test('dashboard rejects bad signature, algorithm confusion and unknown kid', async (t) => {
  const { call } = dashboardFixture(t);
  const other = generateKeyPairSync('rsa', { modulusLength: 2048 });
  for (const token of [jwt({}, other.privateKey), jwt({}, privateKey, { alg: 'none' }), jwt({}, privateKey, { kid: 'unknown' })]) {
    assert.equal((await call('/api/dashboard/reports', { token })).status, 403);
  }
});

test('dashboard fails closed when JWKS service is unreachable', async (t) => {
  const { env } = fixture(t);
  env.ACCESS_TEAM_DOMAIN = 'offline-tests.cloudflareaccess.com';
  t.mock.method(globalThis, 'fetch', async () => { throw new Error('offline'); });
  const response = await worker.fetch(new Request(`${env.SITE_ORIGIN}/dashboard/`, { headers: { 'Cf-Access-Jwt-Assertion': jwt({ iss: `https://${env.ACCESS_TEAM_DOMAIN}` }) } }), env);
  assert.equal(response.status, 503);
});

test('valid Access JWT permits protected HTML, paginated list and private detail', async (t) => {
  const { call, insert } = dashboardFixture(t); insert(22);
  const html = await call('/dashboard/');
  assert.equal(html.status, 200);
  assert.ok((await html.text()).includes('診断情報 — 非公開'));
  assert.equal(html.headers.get('Cache-Control'), 'no-store');
  const first = await call(); assert.equal(first.status, 200);
  const result = await first.json();
  assert.equal(result.reports.length, 20);
  assert.equal(result.hasMore, true);
  assert.equal(result.reports[0].id, 22);
  assert.equal(JSON.stringify(result).includes('PRIVATE DIAGNOSTIC'), false);
  const second = await (await call('/api/dashboard/reports?page=2')).json();
  assert.equal(second.reports.length, 2); assert.equal(second.hasMore, false);
  const detail = await (await call('/api/dashboard/reports/1')).json();
  assert.equal(detail.report.diagnostic, 'PRIVATE DIAGNOSTIC');
  assert.equal((await call('/api/dashboard/reports/999')).status, 404);
  assert.equal((await call('/api/dashboard/reports?status=bad')).status, 400);
  assert.equal((await call('/api/dashboard/reports?page=-1')).status, 400);
  assert.equal((await call('/dashboard/index.html')).status, 404);
});

test('status changes validate number, filter correctly and delete private data', async (t) => {
  const { call, insert, DB } = dashboardFixture(t); insert();
  assert.equal((await call('/api/dashboard/reports/1', { method: 'POST', body: { status: 'issued' } })).status, 422);
  for (const issueNumber of [0, -1, '12', 1.5]) assert.equal((await call('/api/dashboard/reports/1', { method: 'POST', body: { status: 'issued', issueNumber } })).status, 422);
  assert.equal((await call('/api/dashboard/reports/1', { method: 'POST', body: { status: 'issued', issueNumber: 123 } })).status, 200);
  let row = DB.sqlite.prepare('SELECT * FROM reports').get();
  assert.equal(row.status, 'issued'); assert.equal(row.issue_number, 123);
  assert.equal((await (await call('/api/dashboard/reports?status=issued')).json()).reports.length, 1);
  assert.equal((await (await call()).json()).reports.length, 0);
  for (const status of ['dismissed', 'new']) {
    assert.equal((await call('/api/dashboard/reports/1', { method: 'POST', body: { status } })).status, 200);
    row = DB.sqlite.prepare('SELECT * FROM reports').get();
    assert.equal(row.status, status); assert.equal(row.issue_number, null);
  }
  assert.equal((await call('/api/dashboard/reports/1', { method: 'DELETE' })).status, 200);
  assert.equal(DB.sqlite.prepare('SELECT COUNT(*) AS n FROM reports').get().n, 0);
  assert.equal((await call('/api/dashboard/reports/1', { method: 'DELETE' })).status, 404);
  assert.equal((await call('/api/dashboard/reports/999', { method: 'POST', body: { status: 'new' } })).status, 404);
});

test('status update and delete require same Origin and JSON, in addition to JWT', async (t) => {
  const { call, insert } = dashboardFixture(t); insert();
  for (const method of ['POST', 'DELETE']) {
    assert.equal((await call('/api/dashboard/reports/1', { method, headers: { Origin: 'https://evil.example' } })).status, 403);
    assert.equal((await call('/api/dashboard/reports/1', { method, headers: { Origin: '' } })).status, 403);
    assert.equal((await call('/api/dashboard/reports/1', { method, headers: { 'Content-Type': 'text/plain' } })).status, 415);
    assert.equal((await call('/api/dashboard/reports/1', { method, token: '' })).status, 401);
  }
});

test('issue URL and clipboard draft exclude diagnostic and neutralize all public mentions', () => {
  const report = { title: 'Hello @someone', type: 'bug', content: '@org/team 内容', steps: '@steps', expected: '@expected', version: '@version', platform: '@platform', diagnostic: 'TOP-SECRET-PRIVATE @private', status: 'new', issue_number: 42 };
  const draft = issueDraft(report);
  const url = new URL(issueUrl('terudoru/gakujo-chan-extender', report));
  assert.equal(url.origin, 'https://github.com');
  assert.equal(url.pathname, '/terudoru/gakujo-chan-extender/issues/new');
  assert.equal(url.searchParams.get('title'), 'Hello @\u200bsomeone');
  assert.equal(url.searchParams.get('labels'), 'bug,from-form');
  assert.equal(draft.body.includes('TOP-SECRET-PRIVATE'), false);
  assert.equal(url.href.includes('TOP-SECRET-PRIVATE'), false);
  assert.equal(/@(?!\u200b)/.test(draft.body), false);
  assert.equal(issueDraft({ ...report, type: 'request' }).body.includes('@\u200bsteps'), false);
  assert.equal(issueDraft({ ...report, type: 'request' }).labels, 'enhancement,from-form');
  assert.throws(() => issueUrl('evil.example/../../', report));
});

test('issue URL caps the complete percent-encoded URL and marks truncation without invalid Unicode', () => {
  const report = { title: '件名'.repeat(40), type: 'bug', content: 'あ😀@someone'.repeat(500), diagnostic: 'SECRET' };
  const url = issueUrl('terudoru/gakujo-chan-extender', report);
  assert.ok(url.length <= 6000);
  const body = new URL(url).searchParams.get('body');
  assert.ok(body.includes('省略しました'));
  assert.equal(body.includes('\ufffd'), false);
  assert.equal(url.includes('SECRET'), false);
});
