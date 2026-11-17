import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import worker from '../src/worker.js';

export function fakeD1() {
  const sqlite = new DatabaseSync(':memory:');
  const migrations = new URL('../migrations/', import.meta.url);
  for (const name of readdirSync(migrations).filter((name) => name.endsWith('.sql')).sort()) sqlite.exec(readFileSync(new URL(name, migrations), 'utf8'));
  class Statement {
    constructor(sql, params = []) { this.sql = sql; this.params = params; }
    bind(...params) { return new Statement(this.sql, params); }
    async first() { return sqlite.prepare(this.sql).get(...this.params) ?? null; }
    execute() {
      const stmt = sqlite.prepare(this.sql);
      if (/^(SELECT|.*RETURNING\s)/is.test(this.sql.trim())) {
        return { success: true, results: stmt.all(...this.params), meta: { changes: 0 } };
      }
      const meta = stmt.run(...this.params);
      return { success: true, results: [], meta: { changes: Number(meta.changes), last_row_id: Number(meta.lastInsertRowid) } };
    }
    async all() { return this.execute(); }
    async run() { return this.execute(); }
  }
  return {
    sqlite,
    prepare: (sql) => new Statement(sql),
    async batch(statements) {
      sqlite.exec('BEGIN');
      try { const results = statements.map((s) => s.execute()); sqlite.exec('COMMIT'); return results; }
      catch (error) { sqlite.exec('ROLLBACK'); throw error; }
    },
  };
}

export function fixture(t) {
  const DB = fakeD1();
  t.after(() => DB.sqlite.close());
  const env = {
    DB,
    SITE_ORIGIN: 'https://gakujo-report.terudoru.com',
    ISSUE_REPO: 'terudoru/gakujo-chan-extender',
    TURNSTILE_SITE_KEY: '1x00000000000000000000AA',
    TURNSTILE_SECRET: '1x0000000000000000000000000000000AA',
    IP_HASH_SALT: 'test-salt',
    TURNSTILE_HOSTNAMES: 'gakujo-report.terudoru.com',
    ACCESS_TEAM_DOMAIN: 'gakujo-tests.cloudflareaccess.com',
    ACCESS_AUD: 'maintainer-app',
    REPORT_RETENTION_DAYS: '180',
    ASSETS: {
      async fetch(request) {
        const path = new URL(request.url).pathname;
        const relative = path === '/' ? 'index.html' : path === '/dashboard/' ? 'dashboard/index.html' : path.slice(1);
        const url = new URL(`../public/${relative}`, import.meta.url);
        try {
          const content = readFileSync(fileURLToPath(url));
          return new Response(content, { headers: { 'Content-Type': path.endsWith('.js') ? 'text/javascript' : path.endsWith('.css') ? 'text/css' : 'text/html' } });
        } catch { return new Response('Not found', { status: 404 }); }
      },
    },
  };
  const input = { type: 'bug', title: '送信の確認', content: 'ボタンを押すとエラーになる', steps: '1. ボタンを押す', expected: '保存される', version: '1.2.3', platform: 'windows', diagnostic: 'PRIVATE DIAGNOSTIC', consent: true, website: '', elapsedMs: 5000, turnstileToken: 'test-token' };
  const call = (path = '/api/reports', options = {}) => {
    const { body, headers, ...rest } = options;
    return worker.fetch(new Request(`${env.SITE_ORIGIN || 'http://localhost:8787'}${path}`, {
      method: 'POST', body: JSON.stringify(body ?? input),
      headers: { Origin: env.SITE_ORIGIN || 'http://localhost:8787', 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.42', ...headers }, ...rest,
    }), env);
  };
  return { DB, env, input, call };
}

export function siteverify(t, value = { success: true, action: 'report', hostname: 'gakujo-report.terudoru.com' }) {
  return t.mock.method(globalThis, 'fetch', async (url) => {
    if (String(url) !== 'https://challenges.cloudflare.com/turnstile/v0/siteverify') throw new Error('Unexpected network call');
    return Response.json(value);
  });
}
