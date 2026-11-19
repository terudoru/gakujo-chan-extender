import { maxEnvelope } from "./crypto.mjs";
import { uuid } from "./model.mjs";

const drive = "https://www.googleapis.com/drive/v3";
const scope = "https://www.googleapis.com/auth/drive.appdata";
export const googleClientId = import.meta.env?.VITE_PLANNER_GOOGLE_CLIENT_ID || "";
export function relayURL(input) {
  let url;
  try { url = new URL(input); } catch { throw Error("同期サーバーのURLを確認してください。"); }
  const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if ((url.protocol !== "https:" && !(loopback && url.protocol === "http:")) ||
      url.username || url.password || url.search || url.hash)
    throw Error("同期先にはHTTPS URLを指定してください。ローカルホストではHTTPも使えます。");
  return url.href.replace(/\/+$/, "");
}
let googleReady;
export function prepareGoogle() {
  if (!googleClientId) return Promise.reject(Error("Web用のGoogleクライアントIDが設定されていません。"));
  if (window.google?.accounts?.oauth2) return Promise.resolve();
  if (!googleReady) googleReady = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "https://accounts.google.com/gsi/client";
    script.referrerPolicy = "no-referrer";
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => { script.remove(); googleReady = undefined; reject(Error("Google認証を読み込めませんでした。")); };
    document.head.append(script);
  });
  return googleReady;
}
export function googleSignIn() {
  return new Promise((resolve, reject) => {
    const oauth = window.google?.accounts?.oauth2;
    if (!oauth || !googleClientId) throw Error("Google認証の準備ができていません。");
    const client = oauth.initTokenClient({
      client_id: googleClientId, scope, include_granted_scopes: false,
      callback(response) {
        if (response.error || !response.access_token || !oauth.hasGrantedAllScopes(response, scope))
          return reject(Error("Google ドライブの専用領域へのアクセスを確認できませんでした。"));
        resolve({ value: response.access_token, until: Date.now() + Number(response.expires_in) * 1000 });
      },
      error_callback: () => reject(Error("Googleへの接続を完了できませんでした。")),
    });
    client.requestAccessToken({ prompt: "select_account" });
  });
}
async function readJSON(response, limit = maxEnvelope) {
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.length;
      if (total > limit) {
        await reader.cancel();
        throw Error("同期先の応答が上限を超えました。");
      }
      chunks.push(value);
    }
    return JSON.parse(await new Blob(chunks).text());
  } finally { reader.releaseLock(); }
}
function api(bearer, signal, guard) {
  return async (url, options = {}) => {
    guard();
    const response = await fetch(url, {
      ...options, headers: { ...options.headers, Authorization: "Bearer " + bearer },
      cache: "no-store", credentials: "omit", redirect: "error", referrerPolicy: "no-referrer", signal,
    });
    guard();
    if (!response.ok) {
      if (response.status === 401 || response.status === 403)
        throw Error("接続の権限を確認してください。Googleの場合は再接続してください。");
      throw Error("同期先が応答できませんでした（HTTP " + response.status + "）。");
    }
    return response;
  };
}
export function relayTransport(endpoint, identity, signal, guard) {
  const base = relayURL(endpoint) + "/v1";
  const request = api(identity.bearer, signal, guard);
  return {
    async account() {
      const info = await readJSON(await request(base + "/account"));
      if (info.v !== 1 || info.account !== identity.account) throw Error("同期先の本人確認に失敗しました。");
      return info.account;
    },
    async list(channel) {
      const ids = await readJSON(await request(base + "/" + channel));
      if (!Array.isArray(ids) || !ids.every(uuid)) throw Error("同期先の一覧を確認できません。");
      return ids.map((id) => ({ id, file: id }));
    },
    async read(channel, item) { return readJSON(await request(base + "/" + channel + "/" + item.file)); },
    async write(channel, id, envelope) {
      await request(base + "/" + channel + "/" + id, {
        method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(envelope),
      });
    },
  };
}
export function googleTransport(token, group, signal, guard) {
  if (!token || !(token.until > Date.now() + 5000)) throw Error("Googleに再接続してください。");
  const request = api(token.value, signal, guard);
  const prefix = (channel) => ["mbg-planner-v1", group, channel, ""].join(".");
  return {
    async account() {
      const info = await readJSON(await request(drive + "/about?fields=user(permissionId)"));
      const account = info?.user?.permissionId;
      if (typeof account !== "string" || !/^[\w-]{1,160}$/.test(account)) throw Error("Googleアカウントを確認できません。");
      return account;
    },
    async list(channel) {
      const items = [], pages = new Set();
      const name = prefix(channel);
      let token = "";
      do {
        const params = new URLSearchParams({
          spaces: "appDataFolder", q: "trashed = false and name contains '" + name + "'",
          fields: "nextPageToken,incompleteSearch,files(id,name)", pageSize: "1000",
        });
        if (token) params.set("pageToken", token);
        const page = await readJSON(await request(drive + "/files?" + params));
        if (page.incompleteSearch || !Array.isArray(page.files)) throw Error("Google ドライブの一覧を取得できません。");
        for (const file of page.files) {
          if (!file.name.startsWith(name)) continue;
          const id = file.name.slice(name.length);
          if (!uuid(id) || !/^[\w-]+$/.test(file.id)) throw Error("Google ドライブのファイル形式を確認できません。");
          items.push({ id, file: file.id });
        }
        token = page.nextPageToken;
        if (pages.has(token)) throw Error("Google ドライブの一覧が途中で停止しました。");
        pages.add(token);
      } while (token);
      return items;
    },
    async read(channel, item) { return readJSON(await request(drive + "/files/" + item.file + "?alt=media")); },
    async write(channel, id, envelope) {
      const boundary = crypto.randomUUID();
      const metadata = { name: prefix(channel) + id, parents: ["appDataFolder"], mimeType: "application/json" };
      const body = ["--" + boundary, "Content-Type: application/json; charset=UTF-8", "", JSON.stringify(metadata),
        "--" + boundary, "Content-Type: application/json", "", JSON.stringify(envelope), "--" + boundary + "--", ""].join("\r\n");
      await request("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id", {
        method: "POST", headers: { "Content-Type": "multipart/related; boundary=" + boundary }, body,
      });
    },
  };
}
