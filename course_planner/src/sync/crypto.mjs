import { openDB } from "idb";

const utf8 = new TextEncoder();
export const maxEnvelope = 4 * 1024 * 1024;
function base64(bytes) {
  let result = "";
  for (let i = 0; i < bytes.length; i += 8192)
    result += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(result).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
function bytes(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) throw Error("暗号化データの形式を確認してください。");
  return Uint8Array.from(atob(value.replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0));
}
export function newPairingCode() {
  return base64(crypto.getRandomValues(new Uint8Array(32)));
}
export async function pairingKey(code) {
  if (typeof code !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(code) || base64(bytes(code)) !== code)
    throw Error("43文字のペアリングコードを確認してください。");
  return crypto.subtle.importKey("raw", bytes(code), "HKDF", false, ["deriveBits", "deriveKey"]);
}
function params(label) {
  return { name: "HKDF", hash: "SHA-256", salt: utf8.encode("mbg.course-planner.sync.v1"), info: utf8.encode(label) };
}
export async function relayIdentity(root) {
  const bearer = base64(new Uint8Array(await crypto.subtle.deriveBits(params("relay authorization"), root, 256)));
  return { bearer, account: await bearerAccount(bearer) };
}
export async function bearerAccount(bearer) {
  return base64(new Uint8Array(await crypto.subtle.digest("SHA-256", utf8.encode(bearer))));
}
export async function channelKey(root, account, channel) {
  return crypto.subtle.deriveKey(params(JSON.stringify([account, channel])), root,
    { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}
function cipher(iv, account, channel, id) {
  return { name: "AES-GCM", iv, additionalData: utf8.encode(JSON.stringify([1, account, channel, id])) };
}
export async function seal(key, account, channel, batch) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt(cipher(iv, account, channel, batch.id), key,
    utf8.encode(JSON.stringify(batch.entries)));
  const envelope = { v: 1, iv: base64(iv), box: base64(new Uint8Array(encrypted)) };
  if (envelope.box.length + 100 > maxEnvelope) throw Error("1回の同期データが4 MiBを超えました。");
  return envelope;
}
export async function unseal(key, account, channel, id, envelope) {
  if (!validEnvelope(envelope)) throw Error("暗号化データを読み取れません。");
  try {
    const plain = await crypto.subtle.decrypt(cipher(bytes(envelope.iv), account, channel, id), key, bytes(envelope.box));
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(plain));
  } catch {
    throw Error("同期データを復号できません。ペアリングコードと同期先を確認してください。");
  }
}
export function validEnvelope(value) {
  return value?.v === 1 && Object.keys(value).length === 3 &&
    typeof value.iv === "string" && /^[A-Za-z0-9_-]{16}$/.test(value.iv) &&
    typeof value.box === "string" && value.box.length >= 22 && value.box.length + 80 <= maxEnvelope &&
    /^[A-Za-z0-9_-]+$/.test(value.box);
}

// Structured cloning a non-extractable CryptoKey avoids storing the pairing
// code in planner state, URLs or serializable local-storage settings.
export async function deviceKey(action, id, key) {
  const db = await openDB("mbg.planner.sync.keys", 1, {
    upgrade: db => db.createObjectStore("keys"),
  });
  try {
    const tx = db.transaction("keys", action === "get" ? "readonly" : "readwrite");
    const request = action === "put" ? tx.store.put(key, id)
      : action === "delete" ? tx.store.delete(id) : tx.store.get(id);
    const [result] = await Promise.all([request, tx.done]);
    return result;
  } catch (error) {
    if (error?.name === "AbortError") throw Error("端末に同期鍵を保存できません。");
    throw error;
  } finally { db.close(); }
}
