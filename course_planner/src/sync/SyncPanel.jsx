import React, { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { Button } from "../ui.jsx";
import { changeLocal, loadLocal } from "../storage.mjs";
import { activeCourses, overlaps } from "../study.mjs";
import { newPairingCode } from "./crypto.mjs";
import { PlannerSync } from "./controller.mjs";
import { googleClientId, prepareGoogle } from "./transports.mjs";
import "./sync.css";

function collisions(state, catalog) {
  const byCode = new Map(catalog.courses.map((c) => [c.code, c]));
  const courses = activeCourses(state, byCode);
  const result = [];
  for (const [i, course] of courses.entries())
    for (const other of courses.slice(i + 1)) {
      const slots = overlaps(course, other);
      if (slots.length) result.push({ course, other, slots });
    }
  return result;
}
function subscribeHostChange(listener) {
  window.addEventListener("mbg:planner-host", listener);
  return () => window.removeEventListener("mbg:planner-host", listener);
}
const inNativePlanner = () => document.documentElement.dataset.plannerHost === "app";

// Mount once at App level; visible only controls the settings UI.
export function SyncPanel({ state, setState, catalog, visible = true }) {
  const [view, setView] = useState({ connection: null, message: "", error: false });
  const native = useSyncExternalStore(subscribeHostChange, inNativePlanner, () => false);
  const googleAvailable = Boolean(googleClientId) && !native;
  const [choice, setProvider] = useState("google");
  const provider = googleAvailable ? choice : "relay";
  const [endpoint, setEndpoint] = useState(""), [code, setCode] = useState("");
  const [show, setShow] = useState(false), [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false), [error, setError] = useState("");
  const [saving, setSaving] = useState({});
  const engine = useRef(null);
  const callback = useRef(setState);
  callback.current = setState;
  useEffect(() => {
    const current = new PlannerSync({ onState: (s) => callback.current(s), onStatus: setView });
    engine.current = current;
    try { current.start(); } catch { setError("同期設定を開けません。端末の保存設定を確認してください。"); }
    return () => { current.stop(); engine.current = null; };
  }, []);
  useEffect(() => { engine.current?.wake(400); }, [state]);
  const connection = view.connection;
  const google = (connection?.provider ?? provider) === "google";
  useEffect(() => {
    let current = true;
    if (visible && google && googleAvailable) prepareGoogle()
      .then(() => { if (current) setReady(true); })
      .catch((e) => { if (current) setError(e.message); });
    return () => { current = false; };
  }, [google, googleAvailable, visible]);
  useEffect(() => {
    if (!visible || connection) { setCode(""); setShow(false); }
  }, [visible, connection?.session]);
  async function act(operation) {
    setBusy(true);
    setError("");
    try { await operation(); } catch (e) { if (e.name !== "AbortError") setError(e.message); }
    finally { setBusy(false); }
  }
  function toggle(channel, enabled) {
    const choice = { session: connection.session, enabled };
    setSaving((s) => ({ ...s, [channel]: choice }));
    act(async () => {
      try { await engine.current.consent(channel, enabled, choice.session); }
      finally {
        setSaving((s) => s[channel] === choice ? { ...s, [channel]: null } : s);
      }
    });
  }
  const checked = (channel) => saving[channel]?.session === connection?.session && saving[channel]
    ? saving[channel].enabled : connection[channel];
  if (!visible) return null;
  return <section className="page-content planner-sync" aria-label="端末間同期">
    {!connection ? <>
      <p>自分の端末で候補リストや時間割を編集できます。共用の端末では接続しないでください。</p>
      <label>同期先
        <select value={provider} disabled={busy} onChange={(e) => { setProvider(e.target.value); setCode(""); setShow(false); setError(""); }}>
          {googleAvailable && <option value="google">Google ドライブのアプリ専用領域</option>}
          <option value="relay">本人専用の同期サーバー</option>
        </select>
      </label>
      {provider === "relay" && <label>同期サーバーのURL
        <input type="url" placeholder="https://…" value={endpoint} disabled={busy}
          autoComplete="off" onChange={(e) => setEndpoint(e.target.value)} />
      </label>}
      <label>ペアリングコード
        <input type={show ? "text" : "password"} value={code} disabled={busy} autoComplete="off"
          autoCapitalize="none" spellCheck={false} onChange={(e) => setCode(e.target.value.trim())} />
      </label>
      <label className="sync-check"><input type="checkbox" checked={show} onChange={(e) => setShow(e.target.checked)} />コードを表示</label>
      <p>{google
        ? "初めて使うときはコードを作成して安全な場所に控えてください。ほかの端末でも同じGoogleアカウントとコードを使います。"
        : "同期サーバーを用意したときのコードを入力してください。ほかの端末でも同じコードを使います。"}</p>
      <div className="sync-actions">
        {google && <Button label="新しいコードを作成" variant="secondary" isDisabled={busy}
          onClick={() => { setCode(newPairingCode()); setShow(true); }} />}
        <Button label={google ? "Googleで接続" : "同期先に接続"}
          isDisabled={busy || !code || (google ? !ready : !endpoint)}
          onClick={() => act(() => engine.current.connect({ provider, endpoint, code }))} />
      </div>
    </> : <>
      <p>{google ? "Google ドライブ" : new URL(connection.endpoint).host} に接続中</p>
      {connection.previousAccount && <p className="notice">以前とは別の同期先に接続しています。オンにした項目には、前の同期先からこの端末に保存した内容も含まれます。</p>}
      <fieldset><legend>この端末で同期する項目</legend>
        <label className="sync-check"><input type="checkbox" checked={checked("plan")}
          onChange={(e) => toggle("plan", e.target.checked)} />
          候補リストと時間割</label>
        <p>リストの名前と授業、履修予定、登録状況、科目別のCAPの扱い、前期・後期に割り当てた単位数を統合します。</p>
        <label className="sync-check"><input type="checkbox" checked={checked("history")}
          onChange={(e) => toggle("history", e.target.checked)} />
          履修履歴と成績</label>
        <p>科目、年度、成績、単位、確認済みのシラバス対応、区分別の単位と所属設定を統合します。PDFは端末内で読み取ります。</p>
      </fieldset>
      <p>オフにすると、この端末での送受信が止まります。すでに同期したデータは各端末と同期先に残ります。</p>
      <div className="sync-actions">
        {google && googleAvailable && <Button label="Googleに再接続" variant="secondary" isDisabled={busy || !ready}
          onClick={() => act(() => engine.current.reauthorize(connection.session))} />}
        <Button label="今すぐ同期" variant="secondary" isDisabled={busy || (!connection.plan && !connection.history)}
          onClick={() => engine.current.wake(0)} />
        <Button label="この端末の接続を解除" variant="secondary" onClick={() => act(() => engine.current.disconnect(connection.session))} />
      </div>
      {connection.plan && catalog && collisions(state, catalog).map(({ course, other, slots }) =>
        <div className="notice" key={course.code + other.code}>
          <strong>{slots.join("・")}で「{course.title}」と「{other.title}」が重なっています。</strong>
          <p>時間割から外す授業を選んでください。申請済みの授業は学務で登録状況を確認してください。</p>
          <div className="sync-actions">{[course, other].filter((c) =>
            !["申請中", "許可"].includes(state.status[c.code])).map((c) =>
            <Button key={c.code} variant="secondary" label={c.title + "を時間割から外す"} onClick={() => act(async () => {
              await changeLocal((s) => {
                if (["申請中", "許可"].includes(s.status[c.code]) || !collisions(s, catalog).some((pair) =>
                  [pair.course.code, pair.other.code].sort().join() === [course.code, other.code].sort().join()))
                  throw Error("授業の状況が変わりました。時間割を確認してください。");
                s.plan = s.plan.filter((code) => code !== c.code);
              });
              setState(loadLocal());
            })} />)}</div>
        </div>)}
    </>}
    {(error || view.message) && <p role={error || view.error ? "alert" : "status"}>{error || view.message}</p>}
  </section>;
}
export default SyncPanel;
