import React, { useEffect, useRef, useState } from "react";
import { External } from "../ui.jsx";
import { confirmHistoricalMatch, dentalSource, departments, economicsTable, resolveHistoricalGrade,
  searchSource, validYear } from "./identity.mjs";
import { readPublicSyllabusHtml, reviewPublicRecord } from "./manual.mjs";
import { loadHistoricalIndex, revalidateGradeMatch } from "./packs.mjs";

function Evidence({ course, catalog }) {
  const names = course.fieldSource === searchSource || (String(catalog?.year) === course.year &&
    !["saved-syllabus", "manual-record"].includes(course.sourceKind)) ? catalog?.fields : null;
  return <div className="course-line">
    <strong>{course.title}</strong>
    <span>{[course.year + "年度", departments[course.department], course.code, course.term || course.period || course.semester,
      course.section, course.schedule, course.credits != null ? course.credits + "単位" : ""].filter(Boolean).join(" · ")}</span>
    <span>分野　{course.fields.map((id) => [id, names?.[id]].filter(Boolean).join(" ")).join("、") || "資料に記載なし・要確認"}</span>
    {course.category && <span>科目区分　{course.category}</span>}
    {course.sourceKind === "public-index" && <small>出典は個別ページのない公式検索結果です。大学の検索でこの年度と開講番号を指定して確認できます。</small>}
    <External href={course.sourceUrl}>{({
      "faculty-index": "歯学部の年度別科目一覧", "public-index": "大学の公式シラバス検索",
      "manual-record": "本人が照合した公式資料のページ", "saved-syllabus": "保存したシラバスの公開元",
    })[course.sourceKind] ?? "この年度の公式シラバス"}</External>
    {course.fieldSource && course.fieldSource !== course.sourceUrl &&
      <External href={course.fieldSource}>{course.fieldSource === searchSource ? "分野の出典（大学の年度別・分野別検索）" : "分野の出典"}</External>}
    {course.categorySource && <External href={course.categorySource}>科目区分の出典（授業科目開設一覧）</External>}
    {course.creditSource && <External href={course.creditSource}>単位数の出典（授業科目開設一覧）</External>}
    {course.aliasSource && <External href={course.aliasSource}>経済学部生の科目読替表</External>}
  </div>;
}

const messages = {
  "missing-year": "成績確認表の履修年度を入力してください。",
  unavailable: "この年度の全学索引はありません。履修当時の資料で照合できます。",
  "not-found": "この年度の索引に一致する候補がありません。履修当時の資料を確認してください。",
  mismatch: "履修年度・開講所属・開講番号・科目名の組合せが一致しません。",
  conflict: "成績の学期・クラス・科目番号・単位数と、授業の開講情報が一致しません。履修当時の資料を確認してください。",
  ambiguous: "同じ科目名の授業があります。開講所属・開講番号・時限を確認して選んでください。",
  alias: "経済学部生の読替表に別の科目名が載っています。履修した授業を確認してください。",
  review: "学期・クラス・単位数を含め、年度別の掲載情報を成績確認表と照合してください。",
  exact: "履修年度と科目の情報が一致しました。",
};

function ManualSource({ grade, year, index, preview }) {
  const [mode, setMode] = useState("html"), [url, setUrl] = useState(""), [error, setError] = useState("");
  const [file, setFile] = useState(null);
  const generation = useRef(0);
  useEffect(() => () => { generation.current++; }, []);
  const invalidate = () => { generation.current++; setError(""); preview(null); };
  async function read(event) {
    event.preventDefault();
    const sequence = ++generation.current;
    const form = new FormData(event.currentTarget);
    try {
      if (!validYear(year)) throw Error("履修年度を確認してください。");
      const scoped = { ...grade, year };
      let match;
      if (mode === "html") {
        if (!file || file.size > 2 * 1024 * 1024) throw Error("2 MB以内の公開シラバスHTMLを選んでください。");
        match = readPublicSyllabusHtml(await file.text(), url, scoped, document, file.name);
      } else {
        match = reviewPublicRecord({ ...Object.fromEntries(form), year }, scoped);
      }
      if (sequence === generation.current) { setError(""); preview(confirmHistoricalMatch(scoped, match, index)); }
    } catch (err) {
      if (sequence === generation.current) { setError(err.message); preview(null); }
    }
  }
  return <details><summary>履修当時の資料から確認する</summary>
    <form onSubmit={read} onChange={invalidate}>
      <label>資料の形式<select aria-label="資料の形式" value={mode} onChange={(e) => setMode(e.target.value)}>
        <option value="html">保存した公開シラバス（HTML）</option>
        <option value="pdf">公式PDFの科目記載を転記</option>
      </select></label>
      {mode === "html" ? <>
        <label>元の公式シラバスURL<input type="url" value={url} onChange={(e) => setUrl(e.target.value)} /></label>
        <label>公開シラバスのHTML<input type="file" accept=".html,.htm" onChange={(e) => setFile(e.target.files?.[0] ?? null)} /></label>
      </> : <>
        <p className="hint">資料にある開講年度が{year || "履修した年度"}年度であることを確認し、該当する授業の記載を転記してください。分野や科目区分の記載がない欄は空欄にしてください。</p>
        <label>該当ページの公式PDF URL<input name="sourceUrl" type="url" required placeholder="https://…pdf#page=12" /></label>
        <label>資料にある開講所属<select name="department" aria-label="資料にある開講所属" required defaultValue=""><option value="">選択してください</option>
          {Object.entries(departments).map(([id, name]) => <option key={id} value={id}>{name}</option>)}</select></label>
        <label>資料にある科目名<input name="title" required maxLength={300} /></label>
        <label>開講番号<input name="code" maxLength={25} /></label>
        <label>資料にある開講学期・ターム<input name="period" maxLength={80} /></label>
        <label>資料にあるクラス<input name="section" maxLength={80} /></label>
        {grade.courseId && <label>資料にある科目番号<input name="courseId" maxLength={80} /></label>}
        <label>資料にある単位数<input name="credits" inputMode="decimal" maxLength={10} /></label>
        <label>分野番号（複数は読点区切り）<input name="fields" maxLength={80} /></label>
        <label>科目区分<input name="category" maxLength={100} /></label>
      </>}
      <button type="submit">資料の記載を照合</button>
      {error && <p role="alert" className="error">{error}</p>}
    </form>
  </details>;
}

function Match({ grade, catalog, onConfirm }) {
  const saved = revalidateGradeMatch(grade, catalog);
  const [year, setYear] = useState(String(grade.year || saved?.year || ""));
  const [result, setResult] = useState(null), [choice, setChoice] = useState(""), [manual, setManual] = useState(null);
  const [error, setError] = useState(""), [saving, setSaving] = useState(false), [attempt, retry] = useState(0);
  const [done, setDone] = useState(null), [review, setReview] = useState(false);
  useEffect(() => {
    if (done) return;
    let current = true;
    setResult(null); setChoice(""); setManual(null); setError("");
    loadHistoricalIndex(year, catalog).then((index) => {
      if (current) setResult({ ...resolveHistoricalGrade(grade, index, { year, review }), year, index });
    }).catch(() => {
      if (!current) return;
      if (!review && saved) setResult({ status: "confirmed", match: saved, year });
      else setError("年度別索引を読み込めませんでした。再読み込みするか、保存した資料で確認してください。");
    });
    return () => { current = false; };
  }, [grade, catalog, year, attempt, done, review]);
  const active = result?.year === year ? result : null;
  const confirmed = done || (!review && active?.status === "confirmed" ? active.match : null);
  const candidate = manual || active?.candidates[choice] || active?.match;
  async function save() {
    if (!candidate || saving) return;
    setSaving(true); setError("");
    try {
      const verified = confirmHistoricalMatch({ ...grade, year }, candidate, active?.index);
      if ((await onConfirm(verified)) === false) throw Error("保存できませんでした。もう一度確認してください。");
      setDone(verified);
    } catch (e) { setError(e.message); }
    finally { setSaving(false); }
  }
  if (confirmed) return <div>
    <p>照合済み</p><Evidence course={confirmed} catalog={catalog} />
    <button type="button" onClick={() => { setReview(true); setResult(null); setDone(null); }}>対応する授業を選び直す</button>
  </div>;
  return <section aria-label="履修年度のシラバス照合">
    <p><strong>{grade.title}</strong>　{[grade.code, grade.term, grade.section,
      grade.credits != null ? grade.credits + "単位" : ""].filter(Boolean).join(" · ")}</p>
    {grade.year ? <p>履修年度　{grade.year}年度</p> :
      <label>履修年度<input inputMode="numeric" maxLength={4} value={year} onChange={(e) => {
        setManual(null); setChoice(""); setYear(e.target.value.normalize("NFKC"));
      }} /></label>}
    {active && <p role="status">{messages[active.status]}</p>}
    {active?.status === "alias" && <External href={economicsTable}>経済学部生の科目読替表</External>}
    {active && active.candidates.length > 0 && !active.match && <label>履修した授業
      <select aria-label="履修した授業" value={choice} onChange={(e) => { setManual(null); setChoice(e.target.value); }}>
        <option value="">選択してください</option>
        {active.candidates.map((c, i) => <option key={i} value={String(i)}>
          {[c.title, departments[c.department], c.code, c.term || c.period || c.semester, c.section, c.schedule,
            c.credits != null ? c.credits + "単位" : ""].filter(Boolean).join(" · ")}
        </option>)}
      </select></label>}
    {validYear(year) && (active || error) && <ManualSource key={year} grade={grade} year={year} index={active?.index} preview={setManual} />}
    {Number(year) >= 1999 && Number(year) <= 2005 && <External href={dentalSource + "#p1-syl" + year}>歯学部の年度別目次</External>}
    {candidate && <><Evidence course={candidate} catalog={catalog} />
      <button type="button" disabled={saving} onClick={save}>この授業との対応を保存</button></>}
    {error && <p role="alert" className="error">{error} <button type="button" onClick={() => retry((n) => n + 1)}>再読み込み</button></p>}
  </section>;
}

// Mount for the selected ORIGINAL grade row. onConfirm receives only its bounded matchedCourse record.
export function HistoricalMatchPanel(props) {
  const g = props.grade;
  return <Match key={JSON.stringify([g.id, g.recordId, g.year, g.code, g.title, g.department,
    g.offeringDepartment, g.offeringFaculty, g.term, g.period, g.semester, g.section, g.courseId, g.credits,
    g.matchedCourse])} {...props} />;
}
export default HistoricalMatchPanel;
