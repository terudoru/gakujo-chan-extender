import React, { useState } from "react";
import { TextInput } from "@astryxdesign/core/TextInput";
import { Button } from "../ui.jsx";

const DECIMAL_RE = /^\d+(?:\.\d+)?$/;

function toCreditText(value) {
  if (value === null || value === undefined) return "";
  return String(value);
}

function cleanCreditText(value) {
  return toCreditText(value).normalize("NFKC").trim();
}

export function validateSemesterSplit(firstRaw, secondRaw, course) {
  const total = course?.credits;
  if (typeof total !== "number" || !Number.isFinite(total) || total < 0) {
    throw Error(
      "この授業の単位数が未確認のため、学期別の配分を保存できません。",
    );
  }
  const firstText = cleanCreditText(firstRaw);
  const secondText = cleanCreditText(secondRaw);
  if (firstText === "" || secondText === "") {
    throw Error(
      "第1学期と第2学期の両方に単位数を入力してください（算入しない学期は0を入力）。",
    );
  }
  if (!DECIMAL_RE.test(firstText) || !DECIMAL_RE.test(secondText)) {
    throw Error("第1学期・第2学期には0以上の数値を入力してください。");
  }
  const first = Number(firstText);
  const second = Number(secondText);
  if (
    !Number.isFinite(first) ||
    !Number.isFinite(second) ||
    first < 0 ||
    second < 0
  ) {
    throw Error("第1学期・第2学期には0以上の数値を入力してください。");
  }
  if (Math.abs(first + second - total) > 1e-9) {
    const title = course?.title ? `「${course.title}」` : "この授業";
    throw Error(
      `第1学期と第2学期の合計が${title}の単位数（${total}単位）と一致しません。`,
    );
  }
  return {
    first: Object.is(first, -0) ? 0 : first,
    second: Object.is(second, -0) ? 0 : second,
  };
}

export function SemesterCreditSplit({ course, split, onSave }) {
  const courseCode = course?.code ?? "";
  const propFirst = toCreditText(split?.first);
  const propSecond = toCreditText(split?.second);

  const [tracked, setTracked] = useState(() => ({
    code: courseCode,
    propFirst,
    propSecond,
    first: propFirst,
    second: propSecond,
    dirty: false,
    error: "",
  }));
  const [busy, setBusy] = useState(false);

  let current = tracked;
  if (tracked.code !== courseCode) {
    current = {
      code: courseCode,
      propFirst,
      propSecond,
      first: propFirst,
      second: propSecond,
      dirty: false,
      error: "",
    };
    setTracked(current);
  } else if (
    !tracked.dirty &&
    (tracked.propFirst !== propFirst || tracked.propSecond !== propSecond)
  ) {
    current = {
      ...tracked,
      propFirst,
      propSecond,
      first: propFirst,
      second: propSecond,
    };
    setTracked(current);
  }

  const hasSavedSplit =
    split != null &&
    typeof split.first === "number" &&
    typeof split.second === "number";

  const setField = (key, value) => {
    setTracked((prev) => ({
      ...prev,
      code: courseCode,
      [key]: value,
      dirty: true,
      error: "",
    }));
  };

  async function handleSave() {
    let validated;
    try {
      validated = validateSemesterSplit(current.first, current.second, course);
    } catch (e) {
      setTracked((prev) => ({
        ...prev,
        error: e?.message ?? "入力内容を確認してください。",
      }));
      return;
    }

    setBusy(true);
    setTracked((prev) => ({ ...prev, error: "" }));
    try {
      const ok = onSave ? await onSave(validated) : true;
      if (ok !== false) {
        const nextFirst = String(validated.first);
        const nextSecond = String(validated.second);
        setTracked((prev) =>
          prev.code === courseCode
            ? {
                ...prev,
                propFirst: nextFirst,
                propSecond: nextSecond,
                first: nextFirst,
                second: nextSecond,
                dirty: false,
                error: "",
              }
            : prev,
        );
      }
    } catch (e) {
      setTracked((prev) =>
        prev.code === courseCode
          ? { ...prev, error: e?.message ?? "保存できませんでした。" }
          : prev,
      );
    } finally {
      setBusy(false);
    }
  }

  async function handleClear() {
    setBusy(true);
    setTracked((prev) => ({ ...prev, error: "" }));
    try {
      const ok = onSave ? await onSave(null) : true;
      if (ok !== false) {
        setTracked((prev) =>
          prev.code === courseCode
            ? {
                ...prev,
                propFirst: "",
                propSecond: "",
                first: "",
                second: "",
                dirty: false,
                error: "",
              }
            : prev,
        );
      }
    } catch (e) {
      setTracked((prev) =>
        prev.code === courseCode
          ? { ...prev, error: e?.message ?? "クリアできませんでした。" }
          : prev,
      );
    } finally {
      setBusy(false);
    }
  }

  const creditsLabel =
    typeof course?.credits === "number" && Number.isFinite(course.credits)
      ? `${course.credits}単位`
      : "単位数要確認";

  return (
    <details>
      <summary>
        <span>学期別のCAP算入単位</span>
        {hasSavedSplit && (
          <small>
            {" "}
            （第1学期 {split.first}・第2学期 {split.second}）
          </small>
        )}
      </summary>
      <div className="form-stack">
        <p className="hint">
          便覧やシラバスに記載された公式の配分を、第1学期と第2学期にそのまま転記してください（合計{" "}
          {creditsLabel}・算入しない学期は0を入力）。
        </p>
        <div className="pair">
          <div style={{ minWidth: 0 }}>
            <TextInput
              label="第1学期"
              placeholder="単位"
              inputMode="decimal"
              value={current.first}
              isDisabled={busy}
              onChange={(v) => setField("first", v)}
            />
          </div>
          <div style={{ minWidth: 0 }}>
            <TextInput
              label="第2学期"
              placeholder="単位"
              inputMode="decimal"
              value={current.second}
              isDisabled={busy}
              onChange={(v) => setField("second", v)}
            />
          </div>
        </div>
        {current.error && (
          <p role="alert" className="error">
            {current.error}
          </p>
        )}
        <div className="actions">
          <Button
            size="sm"
            variant="secondary"
            label={busy ? "保存中…" : "配分を保存"}
            isDisabled={busy}
            onClick={handleSave}
          />
          <Button
            size="sm"
            variant="ghost"
            label="配分をクリア"
            isDisabled={
              busy ||
              (!hasSavedSplit && current.first === "" && current.second === "")
            }
            onClick={handleClear}
          />
        </div>
      </div>
    </details>
  );
}
