import React, { useMemo, useState } from "react";
import { TextInput } from "@astryxdesign/core/TextInput";
import { Button, External, Modal, Select } from "../ui.jsx";
import {
  ACADEMIC_YEARS,
  applyProfilePatch,
  cleanNumericText,
  entryOptionList,
  facultyOptionList,
  handbooksForFaculty,
  initialProfileDraft,
  programChoicesFor,
} from "./profile-settings.mjs";
import "./planner-forms.css";

const TRI_STATE_CHOICES = [
  ["", "未設定"],
  ["true", "あり"],
  ["false", "なし"],
];

function TriStateField({ label, value, onChange }) {
  return (
    <div className="pf-tristate">
      <span className="pf-tristate-label">{label}</span>
      <div className="pf-program-chips" role="group" aria-label={label}>
        {TRI_STATE_CHOICES.map(([optionValue, optionLabel]) => (
          <button
            key={optionLabel}
            type="button"
            className="pf-chip"
            aria-pressed={value === optionValue}
            onClick={() => onChange(optionValue)}
          >
            {optionLabel}
          </button>
        ))}
      </div>
    </div>
  );
}

export function ProfileSettings({
  state,
  mutate,
  close,
  handbooks = [],
  facultyNames = [],
}) {
  const [initialDraft] = useState(() => initialProfileDraft(state?.profile));
  const [draft, setDraft] = useState(() => initialProfileDraft(state?.profile));
  const [localError, setLocalError] = useState("");

  const update = (key, value) => {
    setLocalError("");
    setDraft((prev) => ({ ...prev, [key]: value }));
  };

  const updateYearMonths = (year, value) => {
    setLocalError("");
    setDraft((prev) => ({
      ...prev,
      yearAttendanceMonths: {
        ...prev.yearAttendanceMonths,
        [year]: value,
      },
    }));
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

  const detailedCount =
    (cleanNumericText(draft.assessmentDate) !== "" ? 1 : 0) +
    ACADEMIC_YEARS.filter(
      (year) => cleanNumericText(draft.yearAttendanceMonths[year]) !== "",
    ).length;

  const isLaw = draft.faculty === "法学部";
  const isEconomics = draft.faculty === "経済科学部";
  const isHealthTransfer =
    draft.faculty === "医学部保健学科" && draft.entry === "編入";
  const isCreation = draft.faculty === "創生学部";
  const showFacultySection =
    isLaw || isEconomics || isHealthTransfer || isCreation;

  const facultyOptionCount = isLaw
    ? [
        draft.earlyGraduation,
        draft.deanException,
        draft.lawPaperSubstitutionApproved,
        cleanNumericText(draft.thirdYearCumulativeGpa),
      ].filter((v) => v !== "").length
    : isEconomics
      ? draft.iStepApproved !== ""
        ? 1
        : 0
      : isHealthTransfer
        ? cleanNumericText(draft.entryGrade) !== ""
          ? 1
          : 0
        : isCreation
          ? [
              cleanNumericText(draft.graduationYear),
              cleanNumericText(draft.graduationMonth),
            ].filter((v) => v !== "").length
          : 0;

  async function save() {
    setLocalError("");
    try {
      const ok = await mutate((s) => {
        applyProfilePatch(s, draft, initialDraft);
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
          <h3 className="pf-section-title">{draft.faculty}の便覧候補</h3>
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
          <span className="pf-section-title">
            選択中の便覧にあるプログラム候補
          </span>
          <div
            className="pf-program-chips"
            role="group"
            aria-label="便覧のプログラム候補"
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
      <details className="pf-disclosure">
        <summary className="pf-disclosure-summary">
          <span>年次別の在学月数・判定基準日（任意）</span>
          {detailedCount > 0 && (
            <small className="pf-disclosure-count">
              {detailedCount}項目入力中
            </small>
          )}
        </summary>
        <div className="pf-disclosure-body">
          <p className="pf-note">
            年次ごとの確定した在学月数（1〜6年次・整数月）と個別の判定基準日が必要な場合に入力します。未入力と0は区別され、日付や判定結果は自動補完しません。
          </p>
          <TextInput
            label="判定基準日（YYYY-MM-DD）"
            placeholder="例 2026-04-01"
            value={draft.assessmentDate}
            onChange={(v) => update("assessmentDate", v)}
          />
          <div
            className="pf-year-months-grid"
            role="group"
            aria-label="年次別の在学月数"
          >
            {ACADEMIC_YEARS.map((year) => (
              <div className="pf-year-cell" key={year}>
                <TextInput
                  label={`${year}年次の在学月数`}
                  placeholder="月"
                  inputMode="numeric"
                  value={draft.yearAttendanceMonths[year]}
                  onChange={(v) => updateYearMonths(year, v)}
                />
              </div>
            ))}
          </div>
        </div>
      </details>
      {showFacultySection && (
        <details className="pf-disclosure">
          <summary className="pf-disclosure-summary">
            <span>{draft.faculty}の個別確認項目（任意）</span>
            {facultyOptionCount > 0 && (
              <small className="pf-disclosure-count">
                {facultyOptionCount}項目入力中
              </small>
            )}
          </summary>
          <div className="pf-disclosure-body">
            {isLaw && (
              <>
                <p className="pf-note">
                  申請・認定済みの特例のみ選択してください。未設定の項目は自動判定しません。
                </p>
                <TriStateField
                  label="早期卒業を申請"
                  value={draft.earlyGraduation}
                  onChange={(v) => update("earlyGraduation", v)}
                />
                <TriStateField
                  label="D類履修の学部長特認"
                  value={draft.deanException}
                  onChange={(v) => update("deanException", v)}
                />
                <TriStateField
                  label="ジュニア・リサーチ・ペーパーのE類8単位代替の学部長認定"
                  value={draft.lawPaperSubstitutionApproved}
                  onChange={(v) => update("lawPaperSubstitutionApproved", v)}
                />
                <TextInput
                  label="3年次末累積GPA"
                  placeholder="0〜5"
                  inputMode="decimal"
                  value={draft.thirdYearCumulativeGpa}
                  onChange={(v) => update("thirdYearCumulativeGpa", v)}
                />
              </>
            )}
            {isEconomics && (
              <>
                <p className="pf-note">
                  学務係へ申出・確認済みの場合のみ「あり」を選択してください。
                </p>
                <TriStateField
                  label="iStep振替の学務係への申出・確認"
                  value={draft.iStepApproved}
                  onChange={(v) => update("iStepApproved", v)}
                />
              </>
            )}
            {isHealthTransfer && (
              <>
                <p className="pf-note">
                  編入時の年次（例：3年次編入なら3）を入力してください。
                </p>
                <TextInput
                  label="編入した年次"
                  placeholder="例 3"
                  inputMode="numeric"
                  value={draft.entryGrade}
                  onChange={(v) => update("entryGrade", v)}
                />
              </>
            )}
            {isCreation && (
              <>
                <p className="pf-note">
                  春季・夏季休業中科目の算入可否の確認に使います。卒業予定は暦年（例：2026年度3月卒業は2027）で入力し、通常は3月または9月（その他は1〜12の月）を指定します。
                </p>
                <div className="pair">
                  <TextInput
                    label="卒業予定（暦年）"
                    placeholder="例 2027"
                    inputMode="numeric"
                    value={draft.graduationYear}
                    onChange={(v) => update("graduationYear", v)}
                  />
                  <TextInput
                    label="卒業予定月"
                    placeholder="3・9（1〜12）"
                    inputMode="numeric"
                    value={draft.graduationMonth}
                    onChange={(v) => update("graduationMonth", v)}
                  />
                </div>
                <div
                  className="pf-program-chips"
                  role="group"
                  aria-label="標準の卒業月を選択"
                >
                  {[
                    ["3", "3月"],
                    ["9", "9月"],
                    ["", "未設定"],
                  ].map(([mVal, mLabel]) => (
                    <button
                      key={mLabel}
                      type="button"
                      className="pf-chip"
                      aria-pressed={cleanNumericText(draft.graduationMonth) === mVal}
                      onClick={() => update("graduationMonth", mVal)}
                    >
                      {mLabel}
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>
        </details>
      )}
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
          placeholder="0〜5"
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
