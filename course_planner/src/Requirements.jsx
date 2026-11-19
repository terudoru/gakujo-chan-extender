import React, { useEffect, useMemo, useRef, useState } from "react";
import { RequirementEvidence } from "./components/RequirementEvidence.jsx";
import { AcademicFields } from "./components/AcademicFields.jsx";
import { ProfileSettings } from "./components/ProfileSettings.jsx";
import { HistoricalMatchPanel } from "./archive/HistoricalMatchPanel.jsx";
import { sameProfile } from "./curricula/engine-evidence.mjs";
import { TextInput } from "@astryxdesign/core/TextInput";
import {
  ArrowRight,
  BookOpen,
  FileUp,
  Plus,
  SlidersHorizontal,
} from "lucide-react";
import {
  FACULTIES,
  academicFieldRows,
  facultyInfo,
  gradeCourses,
  sourceLinks,
  stageStatus,
} from "./requirements.mjs";
import { activeCourses, normalize } from "./study.mjs";
import {
  ActionLink,
  Button,
  External,
  Modal,
  Segments,
  Select,
} from "./ui.jsx";



function Balance({ state, goal, stageId, mutate, close, fields, rows }) {
  const [label, setLabel] = useState(""),
    [kind, setKind] = useState("必修"),
    [req, setReq] = useState(""),
    [current, setCurrent] = useState(""),
    [key, setKey] = useState("custom");
  return (
    <Modal title="便覧・履修科目確認表の内訳を入力" close={close}>
      <Select
        label="照合する項目"
        value={key}
        change={setKey}
        options={[
          ["custom", "自分の便覧の区分"],
          ...rows.filter((r) => (!r.unit || r.unit === "credits") && !r.key.startsWith("field-")).map((r) => [r.key, r.label]),
          ...Object.entries(fields).map(([f, n]) => [
            "field-" + f,
            "分野 " + f + " " + n,
          ]),
        ]}
      />
      {key === "custom" && (
        <TextInput label="便覧の区分名" value={label} onChange={setLabel} />
      )}
      <Select
        label="履修区分"
        value={kind}
        change={setKind}
        options={["必修", "選択必修", "選択", "区分計", "合計"]}
      />
      <div className="pair">
        <TextInput label="必要単位" value={req} onChange={setReq} />
        <TextInput label="修得済み" value={current} onChange={setCurrent} />
      </div>
      <Button
        label="単位を保存"
        variant="primary"
        onClick={async () => {
          if (
            await mutate((s) => {
              const name =
                key === "custom"
                  ? label.trim()
                  : (rows.find((r) => r.key === key)?.label ??
                    fields[key.slice(6)]);
              if (
                !name ||
                !req.trim() ||
                !current.trim() ||
                ![req, current].every(
                  (v) => Number.isFinite(Number(v)) && Number(v) >= 0,
                )
              )
                throw Error("区分名と単位数を確認してください。");
              const id = key === "custom" ? "manual-" + normalize(name) : key;
              const p = state.profile;
              const b = {
                key: id,
                label: name,
                kind,
                required: Number(req),
                current: Number(current),
                faculty: p.faculty, handbook: p.handbook, program: p.program, admitted: p.admitted,
                department: p.department ?? "", field: p.field ?? "", individual: p.individual ?? "",
                entry: p.entry ?? "1年次入学", curriculum: p.curriculum ?? "", goal, stage: stageId,
              };
              if (!sameProfile(b, s.profile)) throw Error("所属設定が変わりました。対象の区分を確認してください。");
              const previous = rows.find((row) => row.key === id)?.balance;
              s.balances = s.balances.filter(
                (r) => !(r.key === id && r.goal === goal && sameProfile(r, p) &&
                  ((r.stageId || r.stage || "") === stageId ||
                    (!r.stageId && !r.stage && previous && !previous.stageId && !previous.stage))),
              );
              s.balances.push(b);
            })
          )
            close();
        }}
      />
    </Modal>
  );
}
const statusLabel = { met: "充足", short: "不足あり", unknown: "要確認" };
function rowValue(value, unit, remaining = false, required = 1) {
  if (!Number.isFinite(value)) return "—";
  if (unit === "months") return value + "か月";
  if (unit === "courses") return value + "科目";
  if (unit === "condition" && required === 1)
    return (remaining ? value === 0 : value >= 1) ? "充足" : "未充足";
  return value;
}
const gradeKey = (g) => g.recordId || g.importId || g.id ||
  JSON.stringify([g.year, g.code, g.title, g.term, g.section, g.courseId, g.credits, g.grade]);
export function Requirements({
  state,
  catalog,
  byCode,
  mutate,
  search,
  goal,
  setGoal,
  view,
  setView,
  returnKey,
  rows,
  requestImport,
  handbooks = [],
  stages,
  stageId,
  setStage,
}) {
  const [dialog, setDialog] = useState("");
  const [historySelection, setHistorySelection] = useState(null);
  const returnRow = useRef(null);
  useEffect(() => {
    const row = returnRow.current;
    if (!row) return;
    const details = row.querySelector("details");
    if (details) details.open = true;
    (row.querySelector("summary") ?? row).focus();
  }, [returnKey]);
  const info = facultyInfo(state.profile),
    active = activeCourses(state, byCode),
    grades = gradeCourses(state, byCode);
  const fieldRows = useMemo(() => view === "fields"
    ? academicFieldRows(state, byCode, active, stageId || goal).map((r) => {
      const rule = r.requirement;
      return {
        ...r,
        earned: rule?.balance?.current ?? r.earned,
        earnedKnown: !!state.grades.length || !!rule?.balance,
        required: rule?.required,
        remaining: rule?.historyAvailable ? rule.remaining : null,
        after: rule?.historyAvailable ? rule.after : null,
        needsReview: r.needsReview || rule?.needsBalance,
        source: rule?.source ?? rule?.evidence?.sources?.[0],
      };
    }) : [], [view, state, byCode, stageId, goal]);
  const originalGrade = historySelection && state.grades.find((g) => gradeKey(g) === historySelection);
  async function selectGrade(index) {
    const displayed = state.grades[index];
    let key = gradeKey(displayed);
    if (state.grades.filter((g) => gradeKey(g) === key).length > 1) {
      const recordId = crypto.randomUUID();
      const saved = await mutate((s) => {
        if (JSON.stringify(s.grades[index]) !== JSON.stringify(displayed))
          throw Error("この履修記録が更新されました。もう一度開いてください。");
        s.grades[index].recordId = recordId;
      });
      if (!saved) return;
      key = recordId;
    }
    setHistorySelection(key);
  }
  const selectedStage = stages.find((s) => s.id === stageId);
  return (
    <section className="page-content">
      <div className="profile-strip">
        <BookOpen size={23} />
        <div>
          <strong>{state.profile.faculty || "所属を設定"}</strong>
          <small>
            {state.profile.faculty
              ? [state.profile.program, state.profile.handbook ? state.profile.handbook + "年度の便覧" : "適用便覧未設定"]
                  .filter(Boolean)
                  .join(" · ")
              : "学部・適用便覧を選ぶと、必要単位を確認できます。"}
          </small>
        </div>
        <Button
          label="所属を設定"
          size="sm"
          variant="secondary"
          icon={<SlidersHorizontal size={15} />}
          onClick={() => setDialog("profile")}
        />
      </div>
      <div className="requirement-tools">
        <Segments
          label="単位の見方"
          value={view}
          change={setView}
          options={[
            ["rules", "進級・卒業要件"],
            ["fields", "シラバスの分野"],
            ["history", "修得履歴"],
          ]}
        />
        <Button
          icon={<FileUp size={15} />}
          label="成績を取り込む"
          size="sm"
          variant="secondary"
          onClick={() => requestImport({ kind: "grades" })}
        />
      </div>
      {view === "rules" && (
        <>
          <div className="split">
            <h2>単位の内訳</h2>
            <Segments
              label="照合する要件"
              value={goal}
              change={setGoal}
              options={[
                ["progress", "進級まで"],
                ["graduation", "卒業まで"],
              ]}
            />
          </div>
          {stages.length > 1 && (
            <Select label="照合する学年・履修条件" value={stageId} change={setStage}
              options={stages.map((s) => [s.id, s.label])} />
          )}
          {rows.length > 0 && (
            <p className="stage-summary">
              <strong>{selectedStage?.label || (goal === "graduation" ? "卒業要件" : "進級要件")}</strong>
              <span>現在　{statusLabel[stageStatus(rows)]}</span>
              <span>履修後　{statusLabel[stageStatus(rows, true)]}</span>
            </p>
          )}
          {info && <p className="hint">{info.note}</p>}
          {!state.grades.length && !state.balances.length && (
            <p className="notice">
              成績未取込。修得済みの授業か、確認表の区分別単位を入力すると現在の残りが表示されます。
            </p>
          )}
          {rows.length > 0 && (
            <div className="ledger">
              <div className="ledger-row ledger-head">
                <span>科目区分</span>
                <span>必要</span>
                <span>修得済</span>
                <span>今の残り</span>
                <span>履修後の残り</span>
              </div>
              {rows
                .filter((r) => !r.key.startsWith("field-"))
                .map((r) => {
                  return (
                    <div
                      className="ledger-row"
                      key={r.key}
                      ref={r.key === returnKey ? returnRow : undefined}
                      role="group"
                      aria-label={r.label}
                      tabIndex={-1}
                    >
                      <div>
                        <strong>{r.label}</strong>
                        <small>
                          {r.kind}
                          {r.needsBalance ? " · 要確認" : ""}
                        </small>
                      </div>
                      <span>{r.unit === "condition" && (r.required == null || r.required === 1) ? "条件確認" : rowValue(r.required, r.unit, false, r.required)}</span>
                      <span>{r.historyAvailable ? rowValue(r.current, r.unit, false, r.required) : "—"}</span>
                      <span>{r.historyAvailable ? rowValue(r.remaining, r.unit, true, r.required) : "—"}</span>
                      <div className="ledger-forecast">
                        <b>{r.historyAvailable ? rowValue(r.after, r.unit, true, r.required) : "—"}</b>
                        {r.searchable && r.after !== 0 && (
                            <ActionLink
                              onClick={() =>
                                search({ requirement: r.key, label: r.label, stageId, goal })
                              }
                            >
                              授業を探す <ArrowRight size={12} />
                            </ActionLink>
                          )}
                      </div>
                      <RequirementEvidence {...r.evidence} balance={r.balance} unit={r.unit} note={r.note} reason={r.reason} />
                    </div>
                  );
                })}
            </div>
          )}
          {!rows.length && (
            <p className="hint">
              {info
                ? "この課程・段階の単位内訳は要確認です。"
                : "所属を設定して、進級・卒業要件を表示してください。"}
            </p>
          )}
          {info && (
            <>
              <div className="actions">
              <Button
                label="確認表の内訳を入力"
                variant="secondary"
                size="sm"
                icon={<Plus size={14} />}
                onClick={() => setDialog("balance")}
              />
              <Button
                label="区分別の単位を取り込む"
                size="sm" variant="secondary" icon={<FileUp size={14} />}
                onClick={() => requestImport({ kind: "balances" })}
              />
              </div>
              <p className="hint">
                残りは照合できた単位からの見込みです。指定科目、在学年数、認定単位は所属の規程で確認してください。
              </p>
              <div className="sources">
                {sourceLinks(info).map((s) => (
                  <External key={s.url} href={s.url}>
                    {s.title || "大学の規程"}
                  </External>
                ))}
              </div>
            </>
          )}
        </>
      )}
      {view === "fields" && (
        <>
          <h2>分野／Academic Field</h2>
          <p className="hint">
            シラバスに記載された分野ごとの内訳です。複数分野の授業は各分野で表示します。
          </p>
          {info && (
            <Button
              label="分野の必要単位を入力"
              size="sm"
              variant="secondary"
              onClick={() => setDialog("balance")}
            />
          )}
          <AcademicFields
            rows={fieldRows}
            fieldNames={catalog.fields}
            catalogYear={catalog.year}
            returnField={returnKey?.startsWith("field-") ? returnKey.slice(6) : undefined}
            onSearch={({ field, requirement, label }) => search({ field, requirement, label, stageId, goal })}
            onReview={() => setView("history")}
          />
        </>
      )}
      {view === "history" && (
        <>
          <div className="split">
            <h2>修得履歴</h2>
            <Button label="修得科目を入力" size="sm" variant="secondary" onClick={() => requestImport({ kind: "grades", manual: true })} />
          </div>
          {!grades.length ? (
            <p className="hint">
              成績確認表を取り込むと、これまでに修得した授業が並びます。
            </p>
          ) : (
            <ul className="result-list">
              {grades.map((g, i) => (
                <li key={i}>
                  <div>
                    <strong>{g.title}</strong>
                    <small>
                      {g.code}　{g.year}　{g.grade}
                    </small>
                  </div>
                  <div className="history-actions">
                    <span>{g.credits}単位{g.counts === false ? " · 算入対象外" : ""}</span>
                    <ActionLink onClick={() => selectGrade(i)}>
                      {g.matchedCourse ? "シラバスの対応を確認" : "要確認 · シラバスを照合"}
                    </ActionLink>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
      {originalGrade && (
        <Modal title="履修年度のシラバス" close={() => setHistorySelection(null)}>
          <HistoricalMatchPanel grade={originalGrade} catalog={catalog} onConfirm={(match) =>
            mutate((s) => {
              const matches = s.grades.filter((g) => gradeKey(g) === historySelection);
              if (matches.length !== 1 || JSON.stringify(matches[0].matchedCourse ?? null) !==
                  JSON.stringify(originalGrade.matchedCourse ?? null))
                throw Error("この履修記録の対応が変わりました。もう一度開いて確認してください。");
              Object.assign(matches[0], { matchedCourse: match, matchStatus: "confirmed" });
            })
          } />
        </Modal>
      )}
      {dialog === "profile" && (
        <ProfileSettings
          {...{ state, mutate, handbooks }} facultyNames={Object.keys(FACULTIES)}
          close={() => setDialog("")}
        />
      )}

      {dialog === "balance" && (
        <Balance
          state={state}
          goal={goal}
          stageId={stageId || goal}
          rows={rows.filter((r) => r.unit === "credits" && !r.key.startsWith("field-"))}
          fields={catalog.fields}
          mutate={mutate}
          close={() => setDialog("")}
        />
      )}
    </section>
  );
}
