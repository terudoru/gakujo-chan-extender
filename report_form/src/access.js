import { HttpError, UNAVAILABLE, readJson } from './http.js';

// Public keys only, scoped to the fixed configured issuer, with a short lifetime.
const keyCache = new Map();
const decode = (part) => Uint8Array.from(atob(part.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
const parse = (part) => JSON.parse(new TextDecoder().decode(decode(part)));

export async function requireAccess(request, env) {
  const domain = env.ACCESS_TEAM_DOMAIN;
  if (!domain || !/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(domain) || !env.ACCESS_AUD?.trim()) {
    throw new HttpError(503, '管理画面の設定が完了していません。');
  }
  const token = request.headers.get('Cf-Access-Jwt-Assertion');
  if (!token) throw new HttpError(401, '管理者としてログインしてください。');
  let parts, header, claims;
  try {
    if (token.length > 16384) throw new Error();
    parts = token.split('.');
    if (parts.length !== 3 || parts.some((p) => !/^[A-Za-z0-9_-]+$/.test(p))) throw new Error();
    header = parse(parts[0]);
    claims = parse(parts[1]);
    const now = Math.floor(Date.now() / 1000);
    const audience = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    if (header.alg !== 'RS256' || typeof header.kid !== 'string' ||
        claims.iss !== `https://${domain}` || !audience.includes(env.ACCESS_AUD) ||
        !Number.isFinite(claims.exp) || claims.exp <= now ||
        (claims.nbf !== undefined && (!Number.isFinite(claims.nbf) || claims.nbf > now))) throw new Error();
  } catch { throw new HttpError(403, '管理者の認証を確認できませんでした。'); }

  let cached = keyCache.get(domain);
  if (!cached || cached.until <= Date.now()) {
    try {
      const response = await fetch(`https://${domain}/cdn-cgi/access/certs`, { signal: AbortSignal.timeout(10000) });
      if (!response.ok) throw new Error();
      const data = await readJson(response);
      if (!Array.isArray(data.keys) || data.keys.length > 20) throw new Error();
      cached = { keys: data.keys, until: Date.now() + 300000 };
      if (keyCache.size >= 8) keyCache.clear();
      keyCache.set(domain, cached);
    } catch { throw new HttpError(503, UNAVAILABLE); }
  }
  const jwk = cached.keys.find((key) => key.kid === header.kid && key.kty === 'RSA' && (!key.alg || key.alg === 'RS256') && (!key.use || key.use === 'sig'));
  if (!jwk) throw new HttpError(403, '管理者の認証を確認できませんでした。');
  try {
    const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, decode(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
    if (!valid) throw new Error();
  } catch { throw new HttpError(403, '管理者の認証を確認できませんでした。'); }
}
