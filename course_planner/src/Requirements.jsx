import React, { useState } from "react";
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
  facultyInfo,
  gradeCourses,
  requirementRows,
  sourceLinks,
} from "./requirements.mjs";
import { activeCourses, courseFields, normalize, validCode } from "./study.mjs";
import { mergeGrades, reviewGradeRows } from "./transcript.mjs";
import {
  ActionLink,
  Button,
  External,
  Modal,
  Segments,
  Select,
} from "./ui.jsx";

function Profile({ state, mutate, close }) {
  const [p, set] = useState({ ...state.profile }),
    update = (key, value) => set({ ...p, [key]: value });
  const standard = p.entry ?? "1年次入学";
  return (
    <Modal title="所属・適用便覧" close={close}>
      <Select
        label="学部・学科"
        value={p.faculty}
        options={Object.keys(FACULTIES)}
        change={(v) => update("faculty", v)}
      />
      <TextInput
        label="プログラム・分野"
        placeholder="例　融合領域分野"
        value={p.program}
        onChange={(v) => update("program", v)}
      />
      <Select
        label="入学区分"
        value={standard}
        change={(v) => update("entry", v)}
        options={["1年次入学", "編入・転部・再入学"]}
      />
      <div className="pair">
        <TextInput
          label="入学年度"
          value={p.admitted}
          onChange={(v) =>
            set({
              ...p,
              admitted: v,
              handbook: p.admitted === p.handbook ? v : p.handbook,
            })
          }
        />
        <TextInput
          label="適用便覧の年度"
          value={p.handbook}
          onChange={(v) => update("handbook", v)}
        />
      </div>
      <div className="pair">
        <TextInput
          label="個別のCAP上限"
          value={p.cap}
          placeholder="単位"
          onChange={(v) => update("cap", v)}
        />
        <TextInput
          label="前学期GPA"
          value={p.gpa}
          onChange={(v) => update("gpa", v)}
        />
      </div>
      <Button
        label="設定を保存"
        variant="primary"
        onClick={async () => {
          if (
            await mutate((s) => {
              if (
                !p.faculty ||
                ![p.handbook, p.admitted].every((y) => /^\d{4}$/.test(y))
              )
                throw Error("学部と4桁の年度を入力してください。");
              if (
                (p.cap !== "" &&
                  (!Number.isFinite(Number(p.cap)) || Number(p.cap) <= 0)) ||
                (p.gpa !== "" &&
                  (!Number.isFinite(Number(p.gpa)) ||
                    Number(p.gpa) < 0 ||
                    Number(p.gpa) > 4))
              )
                throw Error("CAP上限またはGPAを確認してください。");
              s.profile = { ...p, entry: standard };
            })
          )
            close();
        }}
      />
    </Modal>
  );
}

function Grades({ state, byCode, mutate, close }) {
  const [review, setReview] = useState(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const [title, setTitle] = useState(""),
    [units, setUnits] = useState(""),
    [year, setYear] = useState(""),
    [code, setCode] = useState("");
  async function read(file) {
    if (!file) return;
    setBusy(true);
    setError("");
    setReview(null);
    try {
      const { readGradeFile } = await import("./read-grade-file.js");
      setReview(reviewGradeRows(await readGradeFile(file), byCode));
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }
  function manual() {
    const course = byCode.get(code.trim().toUpperCase()),
      enteredTitle = title.trim() || course?.title;
    if (
      !enteredTitle ||
      !units.trim() ||
      !Number.isFinite(Number(units)) ||
      Number(units) <= 0 ||
      Number(units) > 99 ||
      (year && !/^\d{4}$/.test(year)) ||
      (code && !validCode(code.trim().toUpperCase()))
    ) {
      setError("授業名または科目コード、修得した単位数を確認してください。");
      return;
    }
    setReview({
      candidates: [
        {
          code: code.trim().toUpperCase(),
          title: enteredTitle,
          credits: Number(units),
          year,
          grade: "修得",
          fields: course?.fields ?? [],
          category: course?.category ?? "",
          department: course?.department ?? "",
        },
      ],
      missing: [],
    });
    setError("");
  }
  async function accept() {
    if (await mutate((s) => mergeGrades(s, review.candidates))) {
      setReview(null);
      close();
    }
  }
  return (
    <Modal title="修得済みの授業を取り込む" close={close}>
      <p>端末内で読み取ります。科目と単位数を確認してから保存してください。</p>
      <label className="input-label">
        成績確認表（PDF・CSV・TSV）
        <input
          type="file"
          accept=".pdf,.csv,.tsv"
          disabled={busy}
          onChange={(e) => read(e.target.files?.[0])}
        />
      </label>
      {busy && <p role="status">読み取り中…</p>}
      {review && (
        <>
          <strong>読み取れた授業　{review.candidates.length}件</strong>
          <ul className="rows grade-review">
            {review.candidates.map((g, i) => (
              <li key={i}>
                {g.title}
                <small>
                  {g.code}　{g.credits}単位　{g.grade}
                </small>
              </li>
            ))}
          </ul>
          {review.missing.length > 0 && (
            <p>
              要確認の行が{review.missing.length}
              件あります。確認できた授業だけを取り込みます。
            </p>
          )}
          {!review.candidates.length && (
            <p>
              科目・評価・単位を特定できませんでした。下の欄から修得科目を入力できます。
            </p>
          )}
          {review.candidates.length > 0 && (
            <Button
              label="確認した授業を取り込む"
              variant="primary"
              onClick={accept}
            />
          )}
        </>
      )}
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <details>
        <summary>1科目ずつ入力</summary>
        <div className="form-stack">
          <TextInput label="科目コード" value={code} onChange={setCode} />
          <TextInput label="授業名" value={title} onChange={setTitle} />
          <div className="pair">
            <TextInput label="修得単位" value={units} onChange={setUnits} />
            <TextInput label="修得年度" value={year} onChange={setYear} />
          </div>
          <Button label="入力内容を確認" variant="secondary" onClick={manual} />
        </div>
      </details>
    </Modal>
  );
}

function Balance({ state, goal, mutate, close, fields, rows }) {
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
          ...rows.map((r) => [r.key, r.label]),
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
              const b = {
                key: id,
                label: name,
                kind,
                required: Number(req),
                current: Number(current),
                faculty: state.profile.faculty,
                handbook: state.profile.handbook,
                program: state.profile.program,
                goal,
              };
              s.balances = s.balances.filter(
                (r) =>
                  !(
                    r.key === id &&
                    r.goal === goal &&
                    r.faculty === b.faculty &&
                    r.handbook === b.handbook &&
                    (r.program ?? "") === b.program
                  ),
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
export function Requirements({
  state, catalog, byCode, mutate, search, goal, setGoal, view, setView,
}) {
  const [dialog, setDialog] = useState("");
  const info = facultyInfo(state.profile),
    active = activeCourses(state, byCode),
    grades = gradeCourses(state, byCode);
  const earnedCodes = new Set(grades.map((g) => g.code).filter(Boolean));
  const fields = courseFields(
    grades,
    active.filter((c) => !earnedCodes.has(c.code)),
  );
  const rows = requirementRows(state, byCode, active, goal);
  const sums = new Map(
    rows
      .filter((r) => r.key.startsWith("field-"))
      .map((r) => [r.key.slice(6), r]),
  );
  const fieldRows = new Map(fields.map((r) => [r.field, r]));
  for (const f of sums.keys())
    if (!fieldRows.has(f))
      fieldRows.set(f, { field: f, earned: 0, planned: 0, courses: [] });
  return (
    <section className="page-content">
      <div className="profile-strip">
        <BookOpen size={23} />
        <div>
          <strong>{state.profile.faculty || "所属を設定"}</strong>
          <small>
            {state.profile.faculty
              ? [state.profile.program, state.profile.handbook + "年度の便覧"]
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
          onClick={() => setDialog("grades")}
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
                  const known =
                    !r.needsBalance &&
                    (!!grades.length ||
                      state.balances.some(
                        (b) =>
                          b.key === r.key &&
                          b.goal === goal &&
                          b.faculty === state.profile.faculty &&
                          b.handbook === state.profile.handbook &&
                          (b.program ?? "") === state.profile.program,
                      ));
                  return (
                    <div className="ledger-row" key={r.key}>
                      <div>
                        <strong>{r.label}</strong>
                        <small>
                          {r.kind}
                          {r.needsBalance ? " · 要確認" : ""}
                        </small>
                      </div>
                      <span>{r.required}</span>
                      <span>{known ? r.current : "—"}</span>
                      <span>{known ? r.remaining : "—"}</span>
                      <div>
                        <b>{known ? r.after : "—"}</b>
                        {!r.key.startsWith("manual-") &&
                          !r.key.startsWith("ed-") && (
                            <ActionLink
                              onClick={() =>
                                search({ requirement: r.key, label: r.label })
                              }
                            >
                              授業を探す <ArrowRight size={12} />
                            </ActionLink>
                          )}
                      </div>
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
              <Button
                label="確認表の内訳を入力"
                variant="secondary"
                size="sm"
                icon={<Plus size={14} />}
                onClick={() => setDialog("balance")}
              />
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
          {!fieldRows.size && (
            <p className="empty">
              授業を時間割に入れるか成績を取り込むと、分野別の単位が表示されます。
            </p>
          )}
          {[...fieldRows.values()].map((r) => {
            const b = sums.get(r.field);
            return (
              <details className="field-row" key={r.field}>
                <summary>
                  <strong>
                    {r.field === "?"
                      ? "分野要確認"
                      : r.field + " " + catalog.fields[r.field]}
                  </strong>
                  <span>
                    修得 {b?.current ?? r.earned} · 履修後{" "}
                    {(b?.current ?? r.earned) + r.planned} 単位
                  </span>
                </summary>
                {b && (
                  <p>
                    必要 {b.required} · 現在の残り {b.remaining} · 履修後の残り{" "}
                    {Math.max(0, b.remaining - r.planned)} 単位
                  </p>
                )}
                <ul className="rows">
                  {r.courses.map(({ course, column }, i) => (
                    <li key={i}>
                      {course.title}
                      <small>
                        {course.year}　
                        {column === "earned" ? "修得済み" : "履修予定"}　
                        {course.credits}単位
                      </small>
                    </li>
                  ))}
                </ul>
              </details>
            );
          })}
        </>
      )}
      {view === "history" && (
        <>
          <h2>修得履歴</h2>
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
                  <span>{g.credits}単位</span>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
      {dialog === "profile" && (
        <Profile state={state} mutate={mutate} close={() => setDialog("")} />
      )}
      {dialog === "grades" && (
        <Grades
          state={state}
          byCode={byCode}
          mutate={mutate}
          close={() => setDialog("")}
        />
      )}
      {dialog === "balance" && (
        <Balance
          state={state}
          goal={goal}
          rows={rows.filter((r) => !r.key.startsWith("field-"))}
          fields={catalog.fields}
          mutate={mutate}
          close={() => setDialog("")}
        />
      )}
    </section>
  );
}
