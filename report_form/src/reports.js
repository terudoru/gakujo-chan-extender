import { validateReport } from '../public/assets/js/report-schema.js';
import { HttpError, UNAVAILABLE, json, readJson, requireOrigin, localDev, submissionConfigured } from './http.js';

export function ipKey(ip) {
  if (/^(\d{1,3}\.){3}\d{1,3}$/.test(ip)) {
    const parts = ip.split('.').map(Number);
    if (parts.some((p) => p > 255)) throw new Error('Invalid IP');
    return parts.join('.');
  }
  // URL's IPv6 parser validates and canonicalizes compressed and IPv4-mapped forms.
  const host = new URL(`http://[${ip}]/`).hostname.slice(1, -1);
  const [left, right] = host.split('::');
  const start = left ? left.split(':') : [];
  const end = right ? right.split(':') : [];
  const words = host.includes('::') ? [...start, ...Array(8 - start.length - end.length).fill('0'), ...end] : start;
  if (words.length !== 8) throw new Error('Invalid IP');
  if (words.slice(0, 5).every((w) => Number.parseInt(w, 16) === 0) && words[5] === 'ffff') {
    const a = Number.parseInt(words[6], 16), b = Number.parseInt(words[7], 16);
    return `${a >> 8}.${a & 255}.${b >> 8}.${b & 255}`;
  }
  return `${words.slice(0, 4).map((w) => Number.parseInt(w, 16).toString(16)).join(':')}::/64`;
}

export async function submit(request, env) {
  if (!submissionConfigured(request, env)) throw new HttpError(503, UNAVAILABLE);
  requireOrigin(request, env);
  const input = await readJson(request);
  if (input.website !== '' && input.website !== undefined) throw new HttpError(400, '入力内容を確認してください。');
  if (!Number.isFinite(input.elapsedMs) || input.elapsedMs < 3000) throw new HttpError(400, '内容を確認してから、もう一度送信してください。');
  const { value, errors } = validateReport(input);
  if (Object.keys(errors).length) throw new HttpError(422, '入力内容を確認してください。', { errors });
  if (typeof input.turnstileToken !== 'string' || !input.turnstileToken || input.turnstileToken.length > 2048) {
    throw new HttpError(400, '認証をやり直してから送信してください。');
  }
  const ip = request.headers.get('CF-Connecting-IP') || (localDev(request, env) ? '127.0.0.1' : '');
  let key;
  try { key = ipKey(ip); } catch { throw new HttpError(503, UNAVAILABLE); }
  let verification;
  try {
    const response = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ secret: env.TURNSTILE_SECRET, response: input.turnstileToken, remoteip: ip }),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error();
    verification = await readJson(response);
  } catch { throw new HttpError(503, UNAVAILABLE); }
  const hostnames = env.TURNSTILE_HOSTNAMES.split(',').map((s) => s.trim()).filter(Boolean);
  if (verification.success !== true || verification.action !== 'report' || !hostnames.includes(verification.hostname)) {
    throw new HttpError(400, '認証をやり直してから送信してください。');
  }
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${env.IP_HASH_SALT}\n${key}`));
  const ipHash = Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, '0')).join('');
  const now = Math.floor(Date.now() / 1000);
  const eventId = crypto.randomUUID();
  // D1 batch is transactional. The conditional INSERT serializes all quota checks;
  // the report INSERT can only run if this request reserved its quota slot.
  const result = await env.DB.batch([
    env.DB.prepare(`INSERT INTO rate_events (id, ip_hash, created_at)
      SELECT ?, ?, ? WHERE
      (SELECT COUNT(*) FROM rate_events WHERE ip_hash = ? AND created_at > ?) < 3 AND
      (SELECT COUNT(*) FROM rate_events WHERE ip_hash = ? AND created_at > ?) < 10 AND
      (SELECT COUNT(*) FROM rate_events WHERE created_at > ?) < 200`).bind(eventId, ipHash, now, ipHash, now - 600, ipHash, now - 86400, now - 86400),
    env.DB.prepare(`INSERT INTO reports (created_at, type, title, content, steps, expected, version, platform, diagnostic)
      SELECT ?, ?, ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM rate_events WHERE id = ?) RETURNING id`)
      .bind(now, value.type, value.title, value.content, value.steps, value.expected, value.version, value.platform, value.diagnostic, eventId),
  ]);
  const id = result[1].results[0]?.id;
  if (id === undefined) {
    const limits = await env.DB.prepare(`SELECT
      SUM(CASE WHEN ip_hash = ? AND created_at > ? THEN 1 ELSE 0 END) AS short_count,
      MIN(CASE WHEN ip_hash = ? AND created_at > ? THEN created_at END) AS short_start,
      SUM(CASE WHEN ip_hash = ? THEN 1 ELSE 0 END) AS day_count,
      MIN(CASE WHEN ip_hash = ? THEN created_at END) AS day_start,
      COUNT(*) AS global_count, MIN(created_at) AS global_start
      FROM rate_events WHERE created_at > ?`).bind(ipHash, now - 600, ipHash, now - 600, ipHash, ipHash, now - 86400).first();
    const waits = [1];
    if (limits.short_count >= 3) waits.push(limits.short_start + 600 - now);
    if (limits.day_count >= 10) waits.push(limits.day_start + 86400 - now);
    if (limits.global_count >= 200) waits.push(limits.global_start + 86400 - now);
    const retryAfter = Math.max(...waits);
    throw new HttpError(429, '送信が続いています。時間をおいてお試しください。', { retryAfter }, { 'Retry-After': String(retryAfter) });
  }
  return json({ id }, 201);
}
