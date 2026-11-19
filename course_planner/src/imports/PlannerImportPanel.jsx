import React, { useEffect, useMemo, useRef, useState } from "react";
import { Button, Modal, Select } from "../ui.jsx";
import { applyPlannerImport, reviewPlannerImport } from "./review.mjs";

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
    value.courseId,
    value.grade,
    value.credits + "単位",
    value.allocationLabel && "帳票の区分「" + value.allocationLabel + "」",
    value.matchedCourse && "シラバスと一致",
  ]
    .filter(Boolean)
    .join(" · ");
}

function ReviewForm({ review, mutate, close }) {
  const [choices, setChoices] = useState({});
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const submitting = useRef(false);
  const set = (id, update) =>
    setChoices((old) => ({ ...old, [id]: { ...old[id], ...update } }));
  const selected = review.rows.filter((row) => choices[row.id]?.selected);
  async function accept() {
    if (!selected.length || submitting.current) return;
    submitting.current = true;
    setBusy(true);
    setError("");
    const selections = selected.map(({ id }) => ({ id, ...choices[id] }));
    try {
      if (
        await mutate((state) => applyPlannerImport(state, review, selections))
      )
        close();
    } catch (e) {
      setError(e.message);
    } finally {
      submitting.current = false;
      setBusy(false);
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
            value = row.value;
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
                  aria-label={row.label + "を取り込む（行" + row.id + "）"}
                  checked={!!choice.selected && !!canSelect}
                  disabled={!canSelect || busy}
                  onChange={(e) => set(row.id, { selected: e.target.checked })}
                />{" "}
                {row.label}
              </label>
              <small>
                第{row.id.split("-")[0]}表 {row.id.split("-")[1]}行目　{detail(review.kind, value)}
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

function ImportSource({
  kind,
  packet,
  state,
  byCode,
  catalogYear,
  goal,
  stage,
  requirementRows,
  mutate,
  close,
}) {
  const [filePacket, setFilePacket] = useState(null),
    [error, setError] = useState("");
  const [busy, setBusy] = useState(false),
    [version, setVersion] = useState(0);
  const request = useRef(0);
  const fileInput = useRef(null);
  useEffect(
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
  ]);
  async function read(file) {
    if (!file) return;
    const token = ++request.current;
    setFilePacket(null);
    setBusy(true);
    setError("");
    setVersion((v) => v + 1);
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
    <Modal title={titles[kind] + "を取り込む"} close={close}>
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
          mutate={mutate}
          close={close}
        />
      )}
    </Modal>
  );
}

export function PlannerImportPanel({
  kind = "grades",
  packet = null,
  state,
  byCode,
  catalogYear = 2026,
  goal = "graduation",
  stage = "",
  requirementRows = emptyRows,
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
      packet={packet}
      state={state}
      byCode={byCode}
      catalogYear={catalogYear}
      goal={goal}
      stage={stage}
      requirementRows={requirementRows}
      mutate={mutate}
      close={onClose}
    />
  );
}
