import React, { useEffect, useState } from "react";
import { contentIdentity, loadSyllabusContent } from "./load.mjs";

function Content({ year, department, code, title, showSource }) {
  const [result, setResult] = useState(undefined);
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    let current = true;
    loadSyllabusContent({ year, department, code }).then(
      (data) => { if (current) setResult(data); },
      () => { if (current) setError(true); },
    );
    return () => { current = false; };
  }, [year, department, code, attempt]);

  if (error) return <p role="status">比較用データを読み込めませんでした。{" "}
    <button type="button" onClick={() => { setError(false); setAttempt((a) => a + 1); }}>再読み込み</button></p>;
  if (result === undefined) return <p role="status">授業内容を読み込み中…</p>;
  if (!result) return <p className="hint">この授業の比較用データは未収録です。</p>;

  const { record, sourceUrl } = result;
  const rows = [
    ["キーワード", record.keywords?.join("、")],
    ["授業計画の例", record.topics?.join(" ／ ")],
    ["授業で使う言語", record.language],
    ["実施方法", record.mode],
    ["遠隔授業の方式", record.remote?.join("・")],
    ["成績評価の配点", record.weights?.map(([method, percent]) => `${method} ${percent}`).join(" ／ ")],
    ["成績評価の方法（記載例）", record.methods?.join("・")],
  ].filter(([, value]) => value);
  return <section className="syllabus-content" aria-label={`${title || code}の授業内容`}>
    {rows.length > 0 ? <dl>{rows.map(([label, value]) =>
      <React.Fragment key={label}><dt>{label}</dt><dd>{value}</dd></React.Fragment>)}</dl> :
      <p className="hint">この授業の比較項目は未収録です。詳細は公式シラバスで確認できます。</p>}
    {showSource && <a href={sourceUrl} target="_blank" rel="noopener noreferrer" aria-label={`${title || code}の公式シラバス`}>
      公式シラバス</a>}
  </section>;
}

export function SyllabusContent({ course, year = course?.year, showSource = true }) {
  const identity = contentIdentity(course, year);
  if (!identity) return <p className="hint">この年度・開講番号の比較用データは未収録です。</p>;
  return <Content key={`${identity.year}/${identity.department}/${identity.code}`} {...identity} title={course.title} showSource={showSource} />;
}

export default SyllabusContent;
