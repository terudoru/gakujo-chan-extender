export const UNAVAILABLE = '現在は送信できません。しばらく待ってから、もう一度お試しください。';

export class HttpError extends Error {
  constructor(status, message, extra = {}, headers = {}) {
    super(message);
    this.status = status;
    this.extra = extra;
    this.headers = headers;
  }
}

export function json(value, status = 200, headers = {}) {
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json; charset=utf-8', ...headers } });
}

export function secure(response, api = false) {
  const headers = new Headers(response.headers);
  headers.set('Content-Security-Policy', "default-src 'self'; script-src 'self' https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'");
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('Referrer-Policy', 'no-referrer');
  headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  if (api) headers.set('Cache-Control', 'no-store');
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

export function localDev(request, env) {
  return env.DEV === 'true' && ['localhost', '127.0.0.1', '[::1]'].includes(new URL(request.url).hostname);
}

export function requireOrigin(request, env) {
  const expected = env.SITE_ORIGIN || (localDev(request, env) ? new URL(request.url).origin : '');
  if (!expected) throw new HttpError(503, UNAVAILABLE);
  if (request.headers.get('Origin') !== expected) throw new HttpError(403, 'このページから送信し直してください。');
}

export async function readJson(request) {
  if (request.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() !== 'application/json') {
    throw new HttpError(415, '送信形式を確認してください。');
  }
  if (Number(request.headers.get('Content-Length')) > 65536) throw new HttpError(413, '送信内容が大きすぎます。');
  const reader = request.body?.getReader();
  const chunks = [];
  let size = 0;
  if (reader) {
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > 65536) {
          await reader.cancel();
          throw new HttpError(413, '送信内容が大きすぎます。');
        }
        chunks.push(value);
      }
    } finally {
      reader.releaseLock();
    }
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try {
    const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value;
  } catch {
    throw new HttpError(400, '入力内容を確認して送信し直してください。');
  }
}

export function commonConfigured(request, env) {
  if (!env.DB || !env.ISSUE_REPO || !/^[\w.-]+\/[\w.-]+$/.test(env.ISSUE_REPO) ||
      !/^\d+$/.test(env.REPORT_RETENTION_DAYS ?? '') || !Number.isSafeInteger(Number(env.REPORT_RETENTION_DAYS)) || Number(env.REPORT_RETENTION_DAYS) < 1 ||
      (!env.SITE_ORIGIN && !localDev(request, env))) return false;
  if (env.SITE_ORIGIN) {
    try {
      const origin = new URL(env.SITE_ORIGIN);
      if (origin.origin !== env.SITE_ORIGIN || (origin.protocol !== 'https:' && !localDev(request, env))) return false;
    } catch { return false; }
  }
  return true;
}

export function submissionConfigured(request, env) {
  return commonConfigured(request, env) &&
    ['TURNSTILE_SECRET', 'IP_HASH_SALT', 'TURNSTILE_SITE_KEY', 'TURNSTILE_HOSTNAMES'].every((key) => typeof env[key] === 'string' && env[key].trim());
}
