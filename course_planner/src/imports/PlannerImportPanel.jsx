import React, { useLayoutEffect, useMemo, useRef, useState } from "react";
import { Button, Modal, Select } from "../ui.jsx";
import { confirmPlannerImport, reviewPlannerImport } from "./review.mjs";

const titles = {
  grades: "成績確認表",
  registration: "履修登録状況",
  balances: "履修科目確認表",
};
const emptyRows = [];
function detail(kind, value) {
  if (!value) return "";
  if (kind === "registration")
    return [value.year && value.year + "年度", value.status]
      .filter(Boolean)
      .join(" · ");
  if (kind === "balances")
    return [
      "既修得 " + value.current + "単位",
      value.day != null && "昼間 " + value.day + "・夜間 " + value.night,
      value.required != null && "必要 " + value.required + "単位",
    ]
      .filter(Boolean)
      .join(" · ");
  return [
    value.year ? value.year + "年度" : "年度不明",
    value.term,
    value.section,
    value.offeringDepartment,
    value.courseId,
    value.grade,
    value.finalEvaluation
      ? "配当 " + value.credits + "単位・修得 0単位"
      : value.credits + "単位",
    value.allocationLabel && "帳票の区分「" + value.allocationLabel + "」",
    value.matchedCourse && "シラバスと一致",
  ]
    .filter(Boolean)
    .join(" · ");
}

function ReviewForm({
  review,
  previousGrades,
  prepareGrades,
  pending,
  mutate,
  close,
}) {
  const [choices, setChoices] = useState({});
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  useLayoutEffect(() => () => pending.current?.abort(), [pending]);
  const set = (id, update) =>
    setChoices((old) => ({ ...old, [id]: { ...old[id], ...update } }));
  const selected = review.rows.filter((row) => choices[row.id]?.selected);
  async function accept() {
    if (
      !selected.length ||
      (pending.current && !pending.current.signal.aborted)
    )
      return;
    const attempt = new AbortController();
    pending.current = attempt;
    setBusy(true);
    setError("");
    const selections = selected.map(({ id }) => ({ id, ...choices[id] }));
    try {
      if (
        (await confirmPlannerImport({
          review,
          selections,
          previousGrades,
          prepareGrades,
          mutate,
          signal: attempt.signal,
        })) &&
        !attempt.signal.aborted
      )
        close();
    } catch (e) {
      if (!attempt.signal.aborted) setError(e.message);
    } finally {
      if (pending.current === attempt) pending.current = null;
      if (!attempt.signal.aborted) setBusy(false);
    }
  }
  return (
    <>
      {review.kind === "balances" && (
        <>
          <p>
            {[
              review.scope.faculty || "所属未設定",
              review.scope.program,
              review.scope.handbook + "年度便覧",
              review.scope.goal === "graduation" ? "卒業" : "進級",
              review.scope.stage,
            ]
              .filter(Boolean)
              .join(" · ")}
          </p>
          <p>
            既修得単位には認定科目が含まれます。重複や算入上限は成績確認表・便覧と照合してから、対応する区分の合計を選んでください。
          </p>
        </>
      )}
      {!review.rows.length && (
        <p role="status">
          対応する表を読み取れませんでした。科目や区分の列見出しを含む表を選んでください。
        </p>
      )}
      <ul className="rows grade-review">
        {review.rows.map((row) => {
          const choice = choices[row.id] || {},
            value = row.value ?? row.finalEvaluationCandidate;
          const final = !!row.finalEvaluationCandidate;
          const action = final
            ? "の最終評価を確認して履歴に残す"
            : "を取り込む";
          const isBalance = review.kind === "balances";
          const targetKey = choice.targetKey ?? row.targetKey ?? "";
          const target =
            isBalance && review.targets.find((r) => r.key === targetKey);
          const canSelect =
            !!value &&
            (!isBalance ||
              (review.scope.faculty &&
                target &&
                (value.required ?? target.required) != null &&
                (target.key !== "total" || choice.confirmTotal)));
          return (
            <li key={row.id}>
              <label>
                <input
                  type="checkbox"
                  aria-label={row.label + action + "（行" + row.id + "）"}
                  checked={!!choice.selected && !!canSelect}
                  disabled={!canSelect || busy}
                  onChange={(e) =>
                    set(row.id, {
                      selected: e.target.checked,
                      confirmFinalEvaluation: final && e.target.checked,
                    })
                  }
                />{" "}
                {row.label}
                {final && action}
              </label>
              <small>
                第{row.id.split("-")[0]}表 {row.id.split("-")[1]}行目　
                {detail(review.kind, value)}
              </small>
              {row.reason && <small>{row.reason}</small>}
              {value && isBalance && (
                <Select
                  label={row.label + "の照合先"}
                  value={targetKey}
                  change={(key) =>
                    set(row.id, {
                      targetKey: key,
                      selected: false,
                      confirmTotal: false,
                    })
                  }
                  options={review.targets.map((r) => [r.key, r.label])}
                />
              )}
              {value && target?.key === "total" && (
                <label>
                  <input
                    type="checkbox"
                    checked={!!choice.confirmTotal}
                    disabled={busy}
                    onChange={(e) =>
                      set(row.id, {
                        confirmTotal: e.target.checked,
                        selected: false,
                      })
                    }
                  />{" "}
                  成績確認表と照合し、重複単位を除いた合計であることを確認した
                </label>
              )}
              {value &&
                review.kind === "grades" &&
                !final &&
                !value.duplicate &&
                !value.identityUncertain && (
                  <label>
                    <input
                      type="checkbox"
                      checked={!!choice.excludeDuplicate}
                      disabled={busy}
                      onChange={(e) =>
                        set(row.id, {
                          excludeDuplicate: e.target.checked,
                          confirmDistinct: false,
                        })
                      }
                    />{" "}
                    同一科目の重複単位として除外
                  </label>
                )}
              {value?.possibleDuplicate && !value.identityUncertain && (
                <label>
                  <input
                    type="checkbox"
                    checked={!!choice.confirmDistinct}
                    disabled={busy}
                    onChange={(e) =>
                      set(row.id, {
                        confirmDistinct: e.target.checked,
                        excludeDuplicate: false,
                      })
                    }
                  />{" "}
                  別々に算入できる単位と確認した
                </label>
              )}
            </li>
          );
        })}
      </ul>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <Button
        label={busy ? "保存中…" : "選択した" + selected.length + "件を取り込む"}
        variant="primary"
        isDisabled={busy || !selected.length}
        onClick={accept}
      />
    </>
  );
}

function ManualGrade({ review, onEdit, initiallyOpen }) {
  const editor = useRef(null);
  const [evaluation, setEvaluation] = useState("修得");
  const final = evaluation === "不可" || evaluation === "不合格";
  useLayoutEffect(() => {
    if (initiallyOpen) {
      editor.current.open = true;
      editor.current.querySelector("input")?.focus();
    }
  }, [initiallyOpen]);
  function submit(event) {
    event.preventDefault();
    const values = new FormData(event.currentTarget);
    review({
      v: 1,
      kind: "grades",
      tables: [
        {
          heading: "本人入力",
          rows: [
            ["開講番号", "科目名", "単位数", "評語", "履修年度", "クラス"],
            ["code", "title", "credits", "grade", "year", "section"].map(
              (key) => values.get(key).trim(),
            ),
          ],
        },
      ],
    });
    editor.current.open = false;
    editor.current.querySelector("summary").focus();
  }
  return (
    <details ref={editor}>
      <summary>1科目ずつ入力</summary>
      <form className="form-stack" onSubmit={submit} onChange={onEdit}>
        <label className="input-label">
          授業名
          <input name="title" required maxLength={300} />
        </label>
        <div className="pair">
          <label className="input-label">
            開講番号
            <input name="code" maxLength={20} />
          </label>
          <label className="input-label">
            クラス
            <input name="section" maxLength={80} />
          </label>
        </div>
        <div className="pair">
          <label className="input-label">
            {final ? "履修年度" : "修得年度"}
            <input name="year" inputMode="numeric" maxLength={6} />
          </label>
          <label className="input-label">
            {final ? "配当単位（修得は0単位）" : "修得単位"}
            <input name="credits" inputMode="decimal" required />
          </label>
        </div>
        <label className="input-label">
          評価
          <select
            name="grade"
            aria-label="評価"
            value={evaluation}
            onChange={(event) => setEvaluation(event.target.value)}
          >
            {[
              "修得",
              "秀",
              "優",
              "良",
              "可",
              "合格",
              "認定",
              "不可",
              "不合格",
            ].map((grade) => (
              <option key={grade}>{grade}</option>
            ))}
          </select>
        </label>
        <button type="submit" className="action-link">
          入力内容を確認
        </button>
      </form>
    </details>
  );
}

function ImportSource({
  kind,
  manual,
  packet,
  state,
  byCode,
  catalogYear,
  goal,
  stage,
  requirementRows,
  prepareGrades,
  mutate,
  close,
}) {
  const [filePacket, setFilePacket] = useState(null),
    [error, setError] = useState("");
  const [busy, setBusy] = useState(false),
    [version, setVersion] = useState(0);
  const request = useRef(0);
  const fileInput = useRef(null);
  const pending = useRef(null);
  useLayoutEffect(
    () => () => {
      request.current++;
    },
    [],
  );
  const source = packet || filePacket;
  const parsed = useMemo(() => {
    if (!source) return null;
    try {
      return {
        review: reviewPlannerImport(source, {
          profile: state.profile,
          grades: state.grades,
          byCode,
          catalogYear,
          goal,
          stage,
          requirementRows,
          deferMatch: !!prepareGrades,
        }),
      };
    } catch (e) {
      return { error: e.message };
    }
  }, [
    source,
    state.profile,
    state.grades,
    byCode,
    catalogYear,
    goal,
    stage,
    requirementRows,
    prepareGrades,
  ]);
  function closeSource() {
    pending.current?.abort();
    request.current++;
    close();
  }
  function replaceSource() {
    pending.current?.abort();
    setVersion((v) => v + 1);
    setError("");
    return ++request.current;
  }
  async function read(file) {
    if (!file) return;
    const token = replaceSource();
    setFilePacket(null);
    setBusy(true);
    try {
      const { readPlannerFile } = await import("../read-grade-file.js");
      const next = await readPlannerFile(file, kind);
      if (token === request.current) setFilePacket(next);
    } catch (e) {
      if (token === request.current) {
        setError(e.message);
        if (fileInput.current) fileInput.current.value = "";
      }
    } finally {
      if (token === request.current) setBusy(false);
    }
  }
  return (
    <Modal title={titles[kind] + "を取り込む"} close={closeSource}>
      <p>
        端末内で読み取ります。帳票と照合し、保存する行にチェックを入れてください。
      </p>
      {!packet && (
        <label className="input-label">
          {titles[kind]}（PDF・CSV・TSV・テキスト）
          <input
            type="file"
            ref={fileInput}
            accept=".pdf,.csv,.tsv,.txt"
            onChange={(e) => read(e.currentTarget.files?.[0])}
          />
        </label>
      )}
      {!packet && kind === "grades" && (
        <ManualGrade
          initiallyOpen={manual}
          onEdit={() => {
            if (filePacket || busy) {
              replaceSource();
              if (fileInput.current) fileInput.current.value = "";
              setFilePacket(null);
              setBusy(false);
            }
          }}
          review={(manualPacket) => {
            replaceSource();
            if (fileInput.current) fileInput.current.value = "";
            setBusy(false);
            setFilePacket(manualPacket);
          }}
        />
      )}
      {busy && <p role="status">読み取り中…</p>}
      {(error || parsed?.error) && (
        <p role="alert" className="error">
          {error || parsed.error}
        </p>
      )}
      {parsed?.review && (
        <ReviewForm
          key={JSON.stringify([
            version,
            parsed.review.scope,
            parsed.review.targets,
          ])}
          review={parsed.review}
          previousGrades={state.grades}
          prepareGrades={prepareGrades}
          pending={pending}
          mutate={mutate}
          close={closeSource}
        />
      )}
    </Modal>
  );
}

export function PlannerImportPanel({
  kind = "grades",
  manual = false,
  packet = null,
  state,
  byCode,
  catalogYear = 2026,
  goal = "graduation",
  stage = "",
  requirementRows = emptyRows,
  prepareGrades,
  mutate,
  onClose,
}) {
  // A new native delivery must not inherit checked rows from an older packet.
  const [delivery, setDelivery] = useState({ packet, version: 0 });
  if (packet !== delivery.packet)
    setDelivery({ packet, version: delivery.version + 1 });
  const type = packet?.kind ?? kind;
  return (
    <ImportSource
      key={type + "/" + delivery.version}
      kind={type}
      manual={manual}
      packet={packet}
      state={state}
      byCode={byCode}
      catalogYear={catalogYear}
      goal={goal}
      stage={stage}
      requirementRows={requirementRows}
      prepareGrades={prepareGrades}
      mutate={mutate}
      close={onClose}
    />
  );
}
