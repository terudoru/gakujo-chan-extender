import React, { useMemo, useState } from "react";
import { TextInput } from "@astryxdesign/core/TextInput";
import { Button } from "../ui.jsx";
import "./planner-forms.css";

const TRI_STATE_CHOICES = [
  ["", "未設定"],
  ["true", "あり"],
  ["false", "なし"],
];

const LEGACY_OFFERING_CHOICES = [
  ["", "未設定"],
  ["day", "昼間主"],
  ["night", "夜間主"],
];

const FACULTY_FIELD_SPECS = Object.freeze({
  "経済学部（旧課程）": [
    {
      key: "legacyOffering",
      kind: "legacyOffering",
      label: "昼間主・夜間主の開講区分（学生便覧・成績確認表で確認）",
    },
    {
      key: "exchangeWithoutLeave",
      kind: "tristate",
      label: "休学せず協定校で修得した認定単位（成績確認表・学務確認）",
    },
  ],
  人文学部: [
    {
      key: "languageOverlapApproved",
      kind: "tristate",
      label: "同一外国語の重複履修許可（学生便覧・学務確認）",
    },
    {
      key: "openToAll",
      kind: "tristate",
      label: "他学部開講の全学開放・教養算入対象（シラバス・便覧確認）",
    },
    {
      key: "teacherTrainingOnly",
      kind: "tristate",
      label: "教職課程のみ対象科目（シラバス・学生便覧で確認）",
    },
    {
      key: "museumQualificationOnly",
      kind: "tristate",
      label: "学芸員資格のみ対象科目（シラバス・学生便覧で確認）",
    },
    {
      key: "holidayPracticum",
      kind: "tristate",
      label: "休業中開講の実習科目（シラバス・学生便覧で確認）",
    },
    {
      key: "partTimeInstructor",
      kind: "tristate",
      label: "非常勤講師担当の不定期・集中科目（シラバスで確認）",
    },
    {
      key: "irregular",
      kind: "tristate",
      label: "不定期開設・集中科目（シラバスで確認）",
    },
  ],
  経済科学部: [
    {
      key: "facultyApprovedFree",
      kind: "tristate",
      label: "学部認定の自由科目（履修科目確認表・学務確認）",
    },
    {
      key: "economicsOtherProgramSeminar",
      kind: "tristate",
      label: "他プログラムの専門演習等（学生便覧・シラバスで確認）",
    },
    {
      key: "teacherTrainingOnly",
      kind: "tristate",
      label: "教職課程のみ対象科目（シラバス・学生便覧で確認）",
    },
    {
      key: "minorIntro",
      kind: "tristate",
      label: "副専攻プログラムの入門科目（学生便覧・シラバスで確認）",
    },
    {
      key: "irregular",
      kind: "tristate",
      label: "不定期開設・集中科目（シラバスで確認）",
    },
  ],
  法学部: [
    {
      key: "lawTrainingSection",
      kind: "tristate",
      label: "法曹養成プログラム向け開講クラス（シラバス・確認表で確認）",
    },
    {
      key: "teacherTrainingOnly",
      kind: "tristate",
      label: "教職課程のみ対象科目（シラバス・学生便覧で確認）",
    },
  ],
});

const ALL_MANAGED_SPECS = [
  { key: "studyYear", kind: "studyYear" },
  { key: "legacyOffering", kind: "legacyOffering" },
  { key: "exchangeWithoutLeave", kind: "tristate" },
  { key: "languageOverlapApproved", kind: "tristate" },
  { key: "openToAll", kind: "tristate" },
  { key: "teacherTrainingOnly", kind: "tristate" },
  { key: "museumQualificationOnly", kind: "tristate" },
  { key: "holidayPracticum", kind: "tristate" },
  { key: "partTimeInstructor", kind: "tristate" },
  { key: "irregular", kind: "tristate" },
  { key: "facultyApprovedFree", kind: "tristate" },
  { key: "economicsOtherProgramSeminar", kind: "tristate" },
  { key: "minorIntro", kind: "tristate" },
  { key: "lawTrainingSection", kind: "tristate" },
];

export function fieldsForFaculty(faculty) {
  return FACULTY_FIELD_SPECS[faculty] ?? [];
}

function toText(value) {
  if (value === null || value === undefined) return "";
  return String(value);
}

function toTriState(value) {
  if (value === true) return "true";
  if (value === false) return "false";
  return "";
}

function cleanNumeric(value) {
  return toText(value).normalize("NFKC").trim();
}

export function initialEvidenceDraft(grade = {}) {
  const draft = {};
  for (const spec of ALL_MANAGED_SPECS) {
    const raw = grade?.[spec.key];
    if (spec.kind === "tristate") {
      draft[spec.key] = toTriState(raw);
    } else if (spec.kind === "legacyOffering") {
      draft[spec.key] = toText(raw).trim();
    } else {
      draft[spec.key] = toText(raw);
    }
  }
  return draft;
}

function normalizeForCompare(spec, raw) {
  if (spec.kind === "studyYear") return cleanNumeric(raw);
  if (spec.kind === "tristate") {
    if (raw === true || raw === "true") return "true";
    if (raw === false || raw === "false") return "false";
    return toText(raw).trim();
  }
  return toText(raw).trim();
}

function parseFieldValue(spec, raw) {
  if (spec.kind === "studyYear") {
    const cleaned = cleanNumeric(raw);
    if (cleaned === "") return null;
    if (!/^\d+$/.test(cleaned)) {
      throw Error("履修時の年次は1以上の整数で入力してください。");
    }
    const n = Number(cleaned);
    if (!Number.isSafeInteger(n) || n < 1) {
      throw Error("履修時の年次は1以上の整数で入力してください。");
    }
    if (n >= 1000) {
      throw Error(
        "履修時の年次は西暦ではなく、履修した学年（正の整数）を入力してください。",
      );
    }
    return n;
  }
  if (spec.kind === "legacyOffering") {
    const cleaned = toText(raw).trim();
    if (cleaned === "") return null;
    if (cleaned !== "day" && cleaned !== "night") {
      throw Error("開講区分は「昼間主」「夜間主」または「未設定」を選択してください。");
    }
    return cleaned;
  }
  if (spec.kind === "tristate") {
    if (raw === true || raw === "true") return true;
    if (raw === false || raw === "false") return false;
    const cleaned = toText(raw).trim();
    if (cleaned === "") return null;
    throw Error("あり・なし・未設定から選択してください。");
  }
  return null;
}

export function diffEvidenceDraft(initialDraft, submittedDraft, faculty) {
  const activeSpecs = [
    { key: "studyYear", kind: "studyYear" },
    ...fieldsForFaculty(faculty),
  ];
  const diff = {};
  for (const spec of activeSpecs) {
    const before = normalizeForCompare(spec, initialDraft?.[spec.key]);
    const after = normalizeForCompare(spec, submittedDraft?.[spec.key]);
    if (before !== after) {
      diff[spec.key] = parseFieldValue(spec, submittedDraft?.[spec.key]);
    }
  }
  return diff;
}

function hasDraftChanges(initialDraft, draft, faculty) {
  const activeSpecs = [
    { key: "studyYear", kind: "studyYear" },
    ...fieldsForFaculty(faculty),
  ];
  return activeSpecs.some(
    (spec) =>
      normalizeForCompare(spec, initialDraft?.[spec.key]) !==
      normalizeForCompare(spec, draft?.[spec.key]),
  );
}

function gradeSignature(grade) {
  if (!grade) return "";
  if (grade.id != null) return `id:${grade.id}`;
  return [grade.code ?? "", grade.title ?? "", grade.year ?? ""].join("\0");
}

function draftsEqual(a, b) {
  for (const spec of ALL_MANAGED_SPECS) {
    if (normalizeForCompare(spec, a?.[spec.key]) !== normalizeForCompare(spec, b?.[spec.key])) {
      return false;
    }
  }
  return true;
}

function ChoiceGroup({ label, value, choices, disabled, onChange, note }) {
  return (
    <div className="pf-tristate">
      <span className="pf-tristate-label">{label}</span>
      <div className="pf-program-chips" role="group" aria-label={label}>
        {choices.map(([optionValue, optionLabel]) => (
          <button
            key={optionLabel}
            type="button"
            className="pf-chip"
            disabled={disabled}
            aria-pressed={value === optionValue}
            onClick={() => onChange(optionValue)}
          >
            {optionLabel}
          </button>
        ))}
      </div>
      {note && <p className="pf-note">{note}</p>}
    </div>
  );
}

export function CourseEvidenceForm({ grade, faculty, onSave }) {
  const sig = gradeSignature(grade);
  const propDraft = useMemo(() => initialEvidenceDraft(grade), [grade]);
  const facultySpecs = useMemo(() => fieldsForFaculty(faculty), [faculty]);

  const [tracked, setTracked] = useState(() => ({
    sig,
    initial: propDraft,
    draft: propDraft,
    dirty: false,
    error: "",
  }));
  const [busy, setBusy] = useState(false);

  let current = tracked;
  if (tracked.sig !== sig) {
    current = {
      sig,
      initial: propDraft,
      draft: propDraft,
      dirty: false,
      error: "",
    };
    setTracked(current);
  } else if (!tracked.dirty && !draftsEqual(tracked.initial, propDraft)) {
    current = {
      ...tracked,
      initial: propDraft,
      draft: propDraft,
    };
    setTracked(current);
  }

  const changed = hasDraftChanges(current.initial, current.draft, faculty);

  const configuredCount =
    (cleanNumeric(current.draft.studyYear) !== "" ? 1 : 0) +
    facultySpecs.filter(
      (spec) => normalizeForCompare(spec, current.draft[spec.key]) !== "",
    ).length;

  const setField = (key, value) => {
    setTracked((prev) => {
      const nextDraft = { ...prev.draft, [key]: value };
      return {
        ...prev,
        sig,
        draft: nextDraft,
        dirty: hasDraftChanges(prev.initial, nextDraft, faculty),
        error: "",
      };
    });
  };

  async function handleSave() {
    let diff;
    try {
      diff = diffEvidenceDraft(current.initial, current.draft, faculty);
    } catch (e) {
      setTracked((prev) => ({
        ...prev,
        error: e?.message ?? "入力内容を確認してください。",
      }));
      return;
    }
    if (!Object.keys(diff).length) return;

    setBusy(true);
    setTracked((prev) => ({ ...prev, error: "" }));
    try {
      const ok = onSave ? await onSave(diff) : true;
      if (ok !== false) {
        const nextBaseline = { ...current.initial };
        for (const [k, v] of Object.entries(diff)) {
          if (v === null) nextBaseline[k] = "";
          else if (typeof v === "boolean") nextBaseline[k] = v ? "true" : "false";
          else nextBaseline[k] = String(v);
        }
        setTracked((prev) =>
          prev.sig === sig
            ? {
                ...prev,
                initial: nextBaseline,
                draft: nextBaseline,
                dirty: false,
                error: "",
              }
            : prev,
        );
      }
    } catch (e) {
      setTracked((prev) =>
        prev.sig === sig
          ? { ...prev, error: e?.message ?? "保存できませんでした。" }
          : prev,
      );
    } finally {
      setBusy(false);
    }
  }

  function handleReset() {
    setTracked((prev) => ({
      ...prev,
      draft: prev.initial,
      dirty: false,
      error: "",
    }));
  }

  return (
    <details className="pf-disclosure">
      <summary className="pf-disclosure-summary">
        <span>科目ごとの確認事項</span>
        {configuredCount > 0 && (
          <small className="pf-disclosure-count">
            {configuredCount}項目設定中
          </small>
        )}
      </summary>
      <div className="pf-disclosure-body">
        <p className="pf-note">
          成績確認表・履修科目確認表・シラバス・学生便覧で確認できた内容のみ入力してください。未設定の項目は自動認定や推測をしません。
        </p>
        <TextInput
          label="履修時の年次（西暦ではなく学年）"
          placeholder="例 3"
          inputMode="numeric"
          value={current.draft.studyYear}
          isDisabled={busy}
          onChange={(v) => setField("studyYear", v)}
        />
        {facultySpecs.map((spec) => {
          if (spec.kind === "legacyOffering") {
            const val = current.draft[spec.key];
            const isHistoricalUnknown =
              val !== "" && val !== "day" && val !== "night";
            return (
              <ChoiceGroup
                key={spec.key}
                label={spec.label}
                value={val}
                choices={LEGACY_OFFERING_CHOICES}
                disabled={busy}
                onChange={(nextVal) => setField(spec.key, nextVal)}
                note={
                  isHistoricalUnknown
                    ? `現在の保存値「${val}」を保持しています。変更する場合は昼間主・夜間主・未設定から選んでください。`
                    : undefined
                }
              />
            );
          }
          return (
            <ChoiceGroup
              key={spec.key}
              label={spec.label}
              value={current.draft[spec.key]}
              choices={TRI_STATE_CHOICES}
              disabled={busy}
              onChange={(nextVal) => setField(spec.key, nextVal)}
            />
          );
        })}
        {current.error && (
          <p role="alert" className="error">
            {current.error}
          </p>
        )}
        <div className="actions">
          <Button
            size="sm"
            variant="secondary"
            label={busy ? "保存中…" : "確認事項を保存"}
            isDisabled={busy || !changed}
            onClick={handleSave}
          />
          {changed && (
            <Button
              size="sm"
              variant="ghost"
              label="変更を戻す"
              isDisabled={busy}
              onClick={handleReset}
            />
          )}
        </div>
      </div>
    </details>
  );
}
