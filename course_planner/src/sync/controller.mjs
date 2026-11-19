import { loadLocal, changeLocal } from "../storage.mjs";
import { channels, checkpoint, project, reconcile } from "./model.mjs";
import { channelKey, deviceKey, pairingKey, relayIdentity, seal, unseal } from "./crypto.mjs";
import { googleSignIn, googleTransport, relayTransport, relayURL } from "./transports.mjs";

export const settingsKey = "mbg.planner.sync.connection.v1";
const cancelled = () => new DOMException("接続の設定が変わりました。", "AbortError");
const consentKey = (session, channel) => [settingsKey, session, channel].join(".");
function readSettings() {
  const connection = JSON.parse(localStorage.getItem(settingsKey) || "null");
  if (connection) for (const channel of channels) {
    const choice = JSON.parse(localStorage.getItem(consentKey(connection.session, channel)) || "null");
    connection[channel] = choice?.enabled === true;
    connection[channel + "Revision"] = choice?.revision ?? null;
  }
  return connection;
}
const snapshotSettings = () => JSON.stringify(readSettings());
function currentConnection(session) {
  const connection = readSettings();
  if (!connection || connection.session !== session) throw Error("接続先が変わりました。現在の設定を確認してください。");
  return connection;
}
export class PlannerSync {
  constructor({ onState, onStatus, interval = 15000 }) {
    Object.assign(this, { onState, onStatus, interval, running: false, active: false });
  }
  status(message, error = false) {
    if (this.active) this.onStatus({ connection: readSettings(), message, error });
  }
  start() {
    this.active = true;
    this.storage = (e) => {
      if (e.key === settingsKey || e.key === null || e.key.startsWith(settingsKey + ".")) {
        this.cancel();
        this.status("");
        this.wake();
      }
    };
    this.resume = () => this.wake();
    window.addEventListener("storage", this.storage);
    window.addEventListener("online", this.resume);
    window.addEventListener("focus", this.resume);
    this.timer = setInterval(this.resume, this.interval);
    this.status("");
    this.wake();
  }
  stop() {
    this.active = false;
    this.cancel();
    clearInterval(this.timer);
    clearTimeout(this.debounce);
    window.removeEventListener("storage", this.storage);
    window.removeEventListener("online", this.resume);
    window.removeEventListener("focus", this.resume);
  }
  cancel() {
    this.request?.abort();
    this.setup?.abort();
  }
  wake(delay = 50) {
    if (!this.active) return;
    clearTimeout(this.debounce);
    this.debounce = setTimeout(() => this.run(), delay);
  }
  async connect({ provider, endpoint, code }) {
    if (readSettings()) throw Error("現在の接続を解除してから設定してください。");
    if (!globalThis.isSecureContext || !navigator.locks || !crypto.subtle)
      throw Error("この環境では同期できません。HTTPSでプランナーを開いてください。");
    this.cancel();
    const setup = this.setup = new AbortController();
    const guard = () => { if (setup.signal.aborted || readSettings()) throw cancelled(); };
    // Google requires the popup to originate in this click, before any await.
    const auth = provider === "google" ? googleSignIn() : null;
    const token = auth ? await auth : null;
    const root = await pairingKey(code.trim());
    const identity = await relayIdentity(root);
    endpoint = provider === "relay" ? relayURL(endpoint) : "";
    if (!["google", "relay"].includes(provider)) throw Error("同期先を確認してください。");
    const transport = provider === "relay" ? relayTransport(endpoint, identity, setup.signal, guard) :
      googleTransport(token, identity.account, setup.signal, guard);
    const account = await transport.account();
    guard();
    const session = crypto.randomUUID();
    await deviceKey("put", session, root);
    try {
      guard();
      const lastOwner = loadLocal().plannerSync?.owner;
      const connection = {
        session, provider, endpoint, account, group: identity.account, device: crypto.randomUUID(),
        previousAccount: Boolean(lastOwner && lastOwner !== JSON.stringify([provider, account, identity.account])),
      };
      localStorage.setItem(settingsKey, JSON.stringify(connection));
      this.token = token;
    } catch (e) { await deviceKey("delete", session); throw e; }
    this.status("接続しました。この端末で同期する項目を選んでください。");
  }
  async reauthorize(session) {
    const initial = snapshotSettings();
    const connection = currentConnection(session);
    if (connection?.provider !== "google") throw Error("Google接続を確認してください。");
    this.cancel();
    this.token = null;
    const setup = this.setup = new AbortController();
    const guard = () => { if (setup.signal.aborted || snapshotSettings() !== initial) throw cancelled(); };
    const token = await googleSignIn();
    const transport = googleTransport(token, connection.group, setup.signal, guard);
    if (await transport.account() !== connection.account) throw Error("最初に接続したGoogleアカウントを選んでください。");
    guard();
    this.token = token;
    this.status("Googleに再接続しました。");
    this.wake();
  }
  consent(channel, enabled, session) {
    if (!channels.includes(channel)) throw Error("同期項目を確認してください。");
    const connection = currentConnection(session);
    this.cancel();
    const field = channel + "Revision";
    const check = () => {
      const latest = currentConnection(session);
      if (latest[field] !== connection[field]) throw cancelled();
      return latest;
    };
    const save = () => {
      check();
      // Another tab can toggle the other category at the same instant. Updating
      // just this key cannot reinstate a consent withdrawal in the other tab.
      localStorage.setItem(consentKey(session, channel), JSON.stringify({ enabled: enabled === true, revision: crypto.randomUUID() }));
      this.status(enabled ? "同期を開始します。" : "この項目の同期を停止しました。");
      this.wake();
    };
    if (!enabled || connection[channel]) return save();
    const owner = JSON.stringify([connection.provider, connection.account, connection.group]);
    if (checkpoint(loadLocal(), owner, channel)) return save();
    // A first pull can be delayed for days. Distinguish pre-pairing data
    // from deliberate edits/deletions made offline after this consent.
    const values = project(channel, loadLocal());
    return changeLocal((state) => {
      check();
      state.plannerSync ??= {};
      state.plannerSync.joining ??= {};
      state.plannerSync.joining[channel] = { owner, values };
    }).then(save);
  }
  async disconnect(session) {
    const connection = currentConnection(session);
    this.cancel();
    localStorage.removeItem(settingsKey);
    for (const channel of channels) localStorage.removeItem(consentKey(session, channel));
    this.token = null;
    this.status("この端末の接続を解除しました。");
    await deviceKey("delete", connection.session);
  }
  async run() {
    if (!this.active) return;
    if (this.running) { this.rerun = true; return; }
    this.running = true;
    let timeout;
    try {
      const raw = snapshotSettings();
      const config = JSON.parse(raw);
      const enabled = channels.filter((c) => config?.[c] === true);
      if (!enabled.length) return;
      const request = this.request = new AbortController();
      timeout = setTimeout(() => request.abort(Error("同期先の応答を待っています。自動で再試行します。")), 45000);
      const guard = () => {
        if (!this.active || snapshotSettings() !== raw) throw cancelled();
        request.signal.throwIfAborted();
      };
      await navigator.locks.request(settingsKey + ".exchange", { ifAvailable: true }, async (lock) => {
        if (!lock) return;
        const root = await deviceKey("get", config.session);
        if (!root) throw Error("同期鍵を開けません。接続を解除してペアリングをやり直してください。");
        const identity = await relayIdentity(root);
        if (identity.account !== config.group) throw Error("保存された同期鍵が接続先と一致しません。");
        const transport = config.provider === "relay" ? relayTransport(config.endpoint, identity, request.signal, guard) :
          googleTransport(this.token, config.group, request.signal, guard);
        if (await transport.account() !== config.account) throw Error("同期先アカウントが変わったため停止しました。");
        const owner = JSON.stringify([config.provider, config.account, config.group]);
        const errors = [];
        for (const channel of enabled) {
          guard();
          try {
            await this.exchange({ config, channel, owner, root, transport, guard });
          } catch (e) { guard(); errors.push((channel === "plan" ? "候補・時間割" : "履修履歴") + "：" + e.message); }
        }
        guard();
        if (errors.length) throw Error(errors.join("　"));
        this.status("最終同期 " + new Date().toLocaleTimeString("ja-JP"));
      });
    } catch (e) {
      if (e.name !== "AbortError")
        this.status(e instanceof TypeError ? "同期先に接続できません。端末に保存し、自動で再試行します。" : e.message, true);
    } finally {
      clearTimeout(timeout);
      this.running = false;
      if (this.rerun) { this.rerun = false; this.wake(350); }
    }
  }
  async exchange({ config, channel, owner, root, transport, guard }) {
    guard();
    const local = loadLocal();
    const before = project(channel, local);
    const prior = checkpoint(local, owner, channel);
    const seen = new Set(prior?.seen);
    const key = await channelKey(root, owner, channel);
    const items = await transport.list(channel);
    const batches = [];
    for (const item of items) {
      if (seen.has(item.id)) continue;
      const envelope = await transport.read(channel, item);
      guard();
      const entries = await unseal(key, owner, channel, item.id, envelope);
      batches.push({ id: item.id, entries });
      seen.add(item.id);
    }
    let next;
    // changeLocal reads again under the planner's mutation lock. Preserve any
    // local edits made while listing, downloading or decrypting.
    await changeLocal((state) => {
      guard();
      next = reconcile({ state, before, owner, device: config.device, channel, batches });
    });
    guard();
    if (batches.length || JSON.stringify(prior) !== JSON.stringify(next)) this.onState(loadLocal());
    const batch = next.pending;
    if (!batch) return;
    if (!seen.has(batch.id)) {
      const envelope = await seal(key, owner, channel, batch);
      guard();
      await transport.write(channel, batch.id, envelope);
    }
    await changeLocal((state) => {
      guard();
      const current = checkpoint(state, owner, channel);
      if (current?.pending?.id !== batch.id) return;
      if (!current.seen.includes(batch.id)) current.seen.push(batch.id);
      current.pending = null;
    });
    guard();
    this.onState(loadLocal());
  }
}
