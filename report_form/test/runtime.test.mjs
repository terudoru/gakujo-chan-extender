import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';

test('real Worker runtime + local D1 accept and store a report with test-only outbound siteverify', { timeout: 30000 }, async () => {
  const origin = 'https://gakujo-report.terudoru.com';
  let verificationCount = 0;
  const mf = new Miniflare(convertV4MiniflareOptions({ cf: false, unsafeLocalExplorer: false, telemetry: { enabled: false }, workers: [{
    name: 'report-runtime-test',
    modulesRoot: fileURLToPath(new URL('../', import.meta.url)),
    modules: ['src/worker.js', 'src/access.js', 'src/reports.js', 'src/http.js', 'public/assets/js/report-schema.js'].map((name) => ({
      type: 'ESModule', path: fileURLToPath(new URL(`../${name}`, import.meta.url)),
      contents: readFileSync(new URL(`../${name}`, import.meta.url), 'utf8'),
    })),
    compatibilityDate: '2026-11-01',
    d1Databases: ['DB'],
    bindings: {
      SITE_ORIGIN: origin, ISSUE_REPO: 'terudoru/gakujo-chan-extender', REPORT_RETENTION_DAYS: '180',
      TURNSTILE_SITE_KEY: '1x00000000000000000000AA', TURNSTILE_SECRET: '1x0000000000000000000000000000000AA',
      TURNSTILE_HOSTNAMES: 'gakujo-report.terudoru.com', IP_HASH_SALT: 'runtime-test-salt',
    },
    outboundService: async (request) => {
      assert.equal(request.url, 'https://challenges.cloudflare.com/turnstile/v0/siteverify');
      const body = new URLSearchParams(await request.text());
      assert.equal(body.get('response'), 'XXXX.DUMMY.TOKEN.XXXX');
      assert.equal(body.get('remoteip'), '192.0.2.55');
      verificationCount++;
      // Dummy secrets omit action in their real response. This stub supplies the
      // exact production contract without changing the Worker's validation.
      return Response.json({ success: true, action: 'report', hostname: 'gakujo-report.terudoru.com' });
    },
  }] }));
  try {
    const db = await mf.getD1Database('DB');
    const sql = readFileSync(new URL('../migrations/0001_reports.sql', import.meta.url), 'utf8');
    await db.exec(sql.replace(/--[^\n]*/g, '').split(';').map((s) => s.replace(/\s+/g, ' ').trim()).filter(Boolean).join(';\n'));
    const input = { type: 'request', title: 'Runtime test', content: 'Public runtime content', diagnostic: 'PRIVATE runtime data', consent: true, elapsedMs: 5000, website: '', turnstileToken: 'XXXX.DUMMY.TOKEN.XXXX' };
    const request = () => mf.dispatchFetch(`${origin}/api/reports`, { method: 'POST', headers: { Origin: origin, 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.55' }, body: JSON.stringify(input) });
    const response = await request();
    assert.equal(response.status, 201);
    assert.deepEqual(await response.json(), { id: 1 });
    const report = await db.prepare('SELECT * FROM reports WHERE id = 1').first();
    assert.equal(report.title, input.title);
    assert.equal(report.diagnostic, input.diagnostic);
    assert.equal(report.status, 'new');
    assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM rate_events').first()).n, 1);
    assert.equal(verificationCount, 1);
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
    assert.equal((await request()).status, 201);
    assert.equal((await request()).status, 201);
    const limited = await request();
    assert.equal(limited.status, 429);
    assert.ok(Number(limited.headers.get('Retry-After')) > 0);
  } finally {
    await mf.dispose();
  }
});
