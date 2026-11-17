import { requireAccess } from './access.js';
import { submit } from './reports.js';
import { HttpError, UNAVAILABLE, json, secure, readJson, requireOrigin, commonConfigured, submissionConfigured } from './http.js';

async function dashboard(request, env, url) {
  await requireAccess(request, env);
  if (!commonConfigured(request, env)) throw new HttpError(503, UNAVAILABLE);
  if (url.pathname === '/dashboard' || url.pathname === '/dashboard/') {
    if (request.method !== 'GET') throw new HttpError(405, 'この操作は使えません。');
    return assetPage(request, env, '/dashboard/index.html');
  }
  if (url.pathname === '/api/dashboard/reports' && request.method === 'GET') {
    const status = url.searchParams.get('status') || 'new';
    if (!['new', 'issued', 'dismissed'].includes(status)) throw new HttpError(400, '状態を選び直してください。');
    const page = Number(url.searchParams.get('page') || 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 100000) throw new HttpError(400, 'ページ番号を確認してください。');
    const { results } = await env.DB.prepare('SELECT id, created_at, type, title, status, issue_number FROM reports WHERE status = ? ORDER BY id DESC LIMIT 21 OFFSET ?').bind(status, (page - 1) * 20).all();
    return json({ reports: results.slice(0, 20), hasMore: results.length > 20, page, repo: env.ISSUE_REPO });
  }
  const match = /^\/api\/dashboard\/reports\/([1-9]\d*)$/.exec(url.pathname);
  if (!match || !Number.isSafeInteger(Number(match[1]))) throw new HttpError(404, '見つかりません。');
  const id = Number(match[1]);
  if (!['GET', 'POST', 'DELETE'].includes(request.method)) throw new HttpError(405, 'この操作は使えません。');
  let body;
  if (request.method !== 'GET') { requireOrigin(request, env); body = await readJson(request); }
  if (request.method === 'GET') {
    const report = await env.DB.prepare('SELECT * FROM reports WHERE id = ?').bind(id).first();
    if (!report) throw new HttpError(404, '見つかりません。');
    return json({ report, repo: env.ISSUE_REPO });
  }
  if (request.method === 'DELETE') {
    const result = await env.DB.prepare('DELETE FROM reports WHERE id = ?').bind(id).run();
    if (!result.meta.changes) throw new HttpError(404, '見つかりません。');
    return json({ ok: true });
  }
  if (!['new', 'issued', 'dismissed'].includes(body.status) ||
      (body.status === 'issued' && (!Number.isSafeInteger(body.issueNumber) || body.issueNumber < 1))) {
    throw new HttpError(422, '状態と Issue 番号を確認してください。');
  }
  const result = await env.DB.prepare('UPDATE reports SET status = ?, issue_number = ? WHERE id = ?')
    .bind(body.status, body.status === 'issued' ? body.issueNumber : null, id).run();
  if (!result.meta.changes) throw new HttpError(404, '見つかりません。');
  return json({ ok: true });
}

async function assetPage(request, env, path, inject = false) {
  const target = new URL(request.url);
  target.pathname = path;
  target.search = '';
  const response = await env.ASSETS.fetch(new Request(target, { method: 'GET' }));
  // The assets service canonicalizes /index.html to /. Do not redirect back to
  // the Worker; request the canonical URL when the service suggests it.
  const asset = response.status >= 300 && response.status < 400 && response.headers.has('Location')
    ? await env.ASSETS.fetch(new Request(new URL(response.headers.get('Location'), target))) : response;
  const html = await asset.text();
  const escapedKey = String(env.TURNSTILE_SITE_KEY || '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  return new Response(inject ? html.replaceAll('__TURNSTILE_SITE_KEY__', escapedKey).replaceAll('__REPORT_AVAILABLE__', String(Boolean(submissionConfigured(request, env)))) : html, {
    status: asset.status,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

async function route(request, env) {
  const url = new URL(request.url);
  if (url.pathname === '/dashboard' || url.pathname.startsWith('/dashboard/') || url.pathname === '/api/dashboard' || url.pathname.startsWith('/api/dashboard/')) {
    return dashboard(request, env, url);
  }
  if (url.pathname === '/api/reports') {
    if (request.method !== 'POST') throw new HttpError(405, 'この操作は使えません。');
    return submit(request, env);
  }
  if (url.pathname.startsWith('/api/')) throw new HttpError(404, '見つかりません。');
  if (!['GET', 'HEAD'].includes(request.method)) throw new HttpError(405, 'この操作は使えません。');
  if (url.pathname === '/' || url.pathname === '/index.html') {
    // Serve the explanation even while unconfigured, but clearly close submission.
    const response = await assetPage(request, env, '/index.html', true);
    if (!submissionConfigured(request, env)) {
      return new Response(response.body, { status: 503, headers: response.headers });
    }
    return response;
  }
  // Never let an alternate HTML URL bypass site-key injection or dashboard auth.
  if (!/^\/assets\/[a-zA-Z0-9_./-]+\.(css|js)$/.test(url.pathname)) throw new HttpError(404, '見つかりません。');
  return env.ASSETS.fetch(request);
}

export default {
  async fetch(request, env) {
    let response;
    try { response = await route(request, env); }
    catch (error) {
      response = error instanceof HttpError ? json({ message: error.message, ...error.extra }, error.status, error.headers)
        : json({ message: UNAVAILABLE }, 503);
    }
    if (request.method === 'HEAD') response = new Response(null, { status: response.status, headers: response.headers });
    return secure(response, new URL(request.url).pathname.startsWith('/api/'));
  },
  async scheduled(_event, env) {
    const days = Number(env.REPORT_RETENTION_DAYS);
    if (!env.DB || !Number.isSafeInteger(days) || days < 1) throw new Error('Retention is not configured');
    const now = Math.floor(Date.now() / 1000);
    await env.DB.batch([
      env.DB.prepare('DELETE FROM reports WHERE created_at < ?').bind(now - days * 86400),
      env.DB.prepare('DELETE FROM rate_events WHERE created_at <= ?').bind(now - 86400),
    ]);
  },
};
