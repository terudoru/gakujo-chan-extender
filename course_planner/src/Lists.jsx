import React, { useState } from "react";
import { TextInput } from "@astryxdesign/core/TextInput";
import {
  ArrowLeft,
  ChevronRight,
  Copy,
  List,
  Plus,
  Share2,
} from "lucide-react";
import { shareLink, validName } from "./study.mjs";
import { CandidateOverlaps } from "./components/CandidateOverlaps.jsx";
import { ActionLink, Button, Modal } from "./ui.jsx";

export function Lists({
  state,
  byCode,
  candidateIndex,
  year,
  activeId,
  setId,
  mutate,
  openCourse,
  search,
  base,
}) {
  const [editing, setEditing] = useState(""),
    [name, setName] = useState(""),
    [link, setLink] = useState(""),
    [copied, setCopied] = useState(false);

  const list = state.lists.find((l) => l.id === activeId) ?? state.lists[0];
  async function saveName() {
    const id = editing === "create" ? crypto.randomUUID() : list.id;
    if (
      await mutate((s) => {
        const n = validName(name);
        if (editing === "create") s.lists.push({ id, name: n, codes: [] });
        else {
          const target = s.lists.find((l) => l.id === id);
          if (!target) throw Error("リストが見つかりません。");
          target.name = n;
        }
      })
    ) {
      setId(id);
      setEditing("");
    }
  }
  function sharing() {
    setCopied(false);
    setLink(shareLink(list, year, base));
  }
  return (
    <section className="page-content">
      <div className="split list-heading">
        <span>{state.lists.length}件のリスト</span>
        <Button
          label="リストを作成"
          variant="secondary"
          icon={<Plus size={15} />}
          onClick={() => {
            setName("");
            setEditing("create");
          }}
        />
      </div>
      <div className="lists-layout">
        <nav aria-label="候補リスト一覧">
          {state.lists.map((l) => (
            <button
              className={"list-nav" + (l.id === list.id ? " chosen" : "")}
              key={l.id}
              onClick={() => setId(l.id)}
            >
              <List size={16} />
              <strong>{l.name}</strong>
              <small>{l.codes.length}</small>
              <ChevronRight size={14} />
            </button>
          ))}
        </nav>
        <div className="list-details">
          <div className="split">
            <h2>{list.name}</h2>
            <Button
              label="共有"
              icon={<Share2 size={15} />}
              size="sm"
              variant="secondary"
              onClick={sharing}
            />
          </div>
          <div className="list-controls">
            <ActionLink
              onClick={() => {
                setName(list.name);
                setEditing("rename");
              }}
            >
              名前を変更
            </ActionLink>
            {state.lists.length > 1 && (
              <ActionLink onClick={() => setEditing("delete")}>
                リストを削除
              </ActionLink>
            )}
          </div>
          {!list.codes.length ? (
            <div className="empty">
              <p>このリストにはまだ授業がありません。</p>
              <Button label="授業を探す" variant="secondary" onClick={search} />
            </div>
          ) : (
            <ul className="result-list">
              {list.codes.map((code) => (
                <li key={code}>
                  <div>
                    {byCode.has(code) ? (
                      <button
                        className="title-link"
                        onClick={() => openCourse(byCode.get(code))}
                      >
                        {byCode.get(code).title}
                      </button>
                    ) : (
                      <strong>要確認　{code}</strong>
                    )}
                    <small>{[code, byCode.get(code)?.period, byCode.get(code)?.schedule].filter(Boolean).join(" · ")}</small>
                    <CandidateOverlaps course={byCode.get(code)} index={candidateIndex} onOpenCourse={openCourse} />
                  </div>
                  <ActionLink
                    onClick={() =>
                      mutate((s) => {
                        const target = s.lists.find((l) => l.id === list.id);
                        if (target)
                          target.codes = target.codes.filter((k) => k !== code);
                      })
                    }
                  >
                    候補から外す
                  </ActionLink>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
      {(editing === "create" || editing === "rename") && (
        <Modal
          title={editing === "create" ? "候補リストを作成" : "リスト名を変更"}
          close={() => setEditing("")}
        >
          <TextInput
            label="リスト名"
            value={name}
            onChange={setName}
            maxLength={80}
          />
          <Button
            variant="primary"
            label="保存"
            onClick={saveName}
            isDisabled={!name.trim()}
          />
        </Modal>
      )}
      {editing === "delete" && (
        <Modal title="リストを削除" close={() => setEditing("")}>
          <p>
            「{list.name}
            」を削除します。時間割に選んだ授業は引き続き表示されます。
          </p>
          <Button
            label="削除する"
            variant="primary"
            onClick={async () => {
              if (
                await mutate((s) => {
                  if (s.lists.length < 2)
                    throw Error("候補リストは1件以上必要です。");
                  s.lists = s.lists.filter((l) => l.id !== list.id);
                })
              )
                setEditing("");
            }}
          />
        </Modal>
      )}
      {link && (
        <Modal title="候補リストを共有" close={() => setLink("")}>
          <p>
            受け取った人は「{list.name}」の{list.codes.length}
            件を、自分用にコピーして編集できます。リンクには今のリスト名と科目コードが入ります。
          </p>
          <label className="input-label">
            共有リンク
            <input readOnly value={link} onFocus={(e) => e.target.select()} />
          </label>
          <Button
            variant="primary"
            label={copied ? "コピーしました" : "リンクをコピー"}
            icon={<Copy size={15} />}
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(link);
                setCopied(true);
              } catch {
                document.querySelector("input[readonly]")?.select();
              }
            }}
          />
        </Modal>
      )}
    </section>
  );
}
export function SharedList({ list, byCode, copy, dismiss }) {
  return (
    <section className="shared page-content">
      <span className="meta-line">
        <Share2 size={15} />
        共有された候補リスト
      </span>
      <h1>{list.name}</h1>
      <p>
        {list.codes.length}件の授業を自分のリストに保存して、時間割を組めます。
      </p>
      <div className="actions">
        <Button
          label="自分用にコピー"
          variant="primary"
          icon={<Copy size={16} />}
          onClick={copy}
        />
        <ActionLink onClick={dismiss}>
          <ArrowLeft size={14} />
          自分の時間割へ
        </ActionLink>
      </div>
      <ul className="result-list">
        {list.codes.map((code) => (
          <li key={code}>
            <div>
              <strong>{byCode.get(code)?.title ?? "開講情報を要確認"}</strong>
              <small>
                {code}　{byCode.get(code)?.period}　{byCode.get(code)?.schedule}
              </small>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
