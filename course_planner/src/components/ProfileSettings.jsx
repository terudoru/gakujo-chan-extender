import React, { useMemo, useState } from "react";
import { TextInput } from "@astryxdesign/core/TextInput";
import { Button, External, Modal, Select } from "../ui.jsx";
import {
  applyProfilePatch,
  cleanNumericText,
  entryOptionList,
  facultyOptionList,
  handbooksForFaculty,
  initialProfileDraft,
  programChoicesFor,
} from "./profile-settings.mjs";
import "./planner-forms.css";

export function ProfileSettings({
  state,
  mutate,
  close,
  handbooks = [],
  facultyNames = [],
}) {
  const [draft, setDraft] = useState(() => initialProfileDraft(state?.profile));
  const [localError, setLocalError] = useState("");

  const update = (key, value) => {
    setLocalError("");
    setDraft((prev) => ({ ...prev, [key]: value }));
  };

  const faculties = useMemo(
    () => facultyOptionList(facultyNames, handbooks, draft.faculty),
    [facultyNames, handbooks, draft.faculty],
  );
  const entries = useMemo(() => entryOptionList(draft.entry), [draft.entry]);
  const matchingHandbooks = useMemo(
    () =>
      handbooksForFaculty(
        handbooks,
        draft.faculty,
        draft.handbook || draft.admitted,
      ),
    [handbooks, draft.faculty, draft.handbook, draft.admitted],
  );
  const programChoices = useMemo(
    () =>
      programChoicesFor(
        handbooks,
        draft.faculty,
        draft.handbook,
        draft.admitted,
      ),
    [handbooks, draft.faculty, draft.handbook, draft.admitted],
  );
  const normalizedHandbook = cleanNumericText(draft.handbook);
  const isCustomProgram =
    draft.program.trim() !== "" &&
    programChoices.length > 0 &&
    !programChoices.includes(draft.program.trim());

  async function save() {
    setLocalError("");
    try {
      const ok = await mutate((s) => {
        applyProfilePatch(s, draft);
      });
      if (ok) close();
    } catch (e) {
      setLocalError(e?.message ?? "入力内容を確認してください。");
    }
  }

  return (
    <Modal title="所属・適用便覧" close={close}>
      <Select
        label="学部・学科"
        value={draft.faculty}
        options={faculties}
        change={(v) => update("faculty", v)}
      />
      <Select
        label="入学区分"
        value={draft.entry}
        options={entries}
        change={(v) => update("entry", v)}
      />
      {draft.entry !== "1年次入学" && (
        <p className="pf-note">
          編入・転部・再入学では、入学年度と異なる年度の便覧が適用される場合があります。適用便覧の年度を確認してください。
        </p>
      )}
      <div className="pair">
        <TextInput
          label="入学年度"
          placeholder="例 2026"
          inputMode="numeric"
          value={draft.admitted}
          onChange={(v) => {
            setLocalError("");
            setDraft((prev) => ({
              ...prev,
              admitted: v,
              handbook:
                prev.entry === "1年次入学" &&
                prev.admitted !== "" &&
                prev.admitted === prev.handbook
                  ? v
                  : prev.handbook,
            }));
          }}
        />
        <TextInput
          label="適用便覧の年度"
          placeholder="例 2026"
          inputMode="numeric"
          value={draft.handbook}
          onChange={(v) => update("handbook", v)}
        />
      </div>
      {matchingHandbooks.length > 0 && (
        <section className="pf-section" aria-label="便覧の候補">
          <h3 className="pf-section-title">
            {draft.faculty}の便覧候補
          </h3>
          <ul className="pf-handbook-list">
            {matchingHandbooks.map((h) => {
              const selected = normalizedHandbook === h.year;
              return (
                <li
                  key={`${h.faculty}-${h.year}-${h.title}`}
                  className={"pf-handbook-item" + (selected ? " pf-active" : "")}
                >
                  <div className="pf-handbook-info">
                    <strong>{h.title || `${h.year}年度便覧`}</strong>
                    <small>{h.year}年度</small>
                  </div>
                  <div className="pf-handbook-actions">
                    {h.url && <External href={h.url}>公式便覧</External>}
                    <Button
                      size="sm"
                      variant={selected ? "ghost" : "secondary"}
                      label={selected ? "適用中" : "この年度を適用"}
                      isDisabled={selected}
                      onClick={() => update("handbook", h.year)}
                    />
                  </div>
                </li>
              );
            })}
          </ul>
          <p className="pf-note">
            候補にない過年度や編入時の適用年度も、上の「適用便覧の年度」に直接入力できます。
          </p>
        </section>
      )}
      <TextInput
        label="プログラム・分野"
        placeholder="例　融合領域分野"
        value={draft.program}
        onChange={(v) => update("program", v)}
      />
      {programChoices.length > 0 && (
        <div className="pf-section">
          <span className="pf-section-title">選択中の便覧にあるプログラム候補</span>
          <div
            className="pf-program-chips"
            role="group"
            aria-label="プログラム・分野の候補"
          >
            {programChoices.map((name) => (
              <button
                key={name}
                type="button"
                className="pf-chip"
                aria-pressed={draft.program.trim() === name}
                onClick={() => update("program", name)}
              >
                {name}
              </button>
            ))}
          </div>
          {isCustomProgram && (
            <p className="pf-note">
              入力中の値「{draft.program.trim()}」をそのまま保持します。
            </p>
          )}
        </div>
      )}
      <div className="pair">
        <TextInput
          label="現在の年次"
          placeholder="例 3"
          inputMode="numeric"
          value={draft.yearOfStudy}
          onChange={(v) => update("yearOfStudy", v)}
        />
        <TextInput
          label="実在学月数"
          placeholder="例 24"
          inputMode="numeric"
          value={draft.attendanceMonths}
          onChange={(v) => update("attendanceMonths", v)}
        />
      </div>
      <p className="pf-note">
        在学年数などの一般的な条件確認に使います。休学・留年・編入時は実際の年次と在学月数を入力してください。未入力と0は区別されます。
      </p>
      <div className="pair">
        <TextInput
          label="個別のCAP上限"
          placeholder="単位"
          inputMode="decimal"
          value={draft.cap}
          onChange={(v) => update("cap", v)}
        />
        <TextInput
          label="前学期GPA"
          placeholder="0〜4"
          inputMode="decimal"
          value={draft.gpa}
          onChange={(v) => update("gpa", v)}
        />
      </div>
      {localError && (
        <p role="alert" className="error">
          {localError}
        </p>
      )}
      <Button label="設定を保存" variant="primary" onClick={save} />
    </Modal>
  );
}
