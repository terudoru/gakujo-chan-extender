import React from "react";
import { Search } from "lucide-react";
import { Button, External } from "../ui.jsx";
import { safeExternalURL } from "./profile-settings.mjs";
import "./planner-forms.css";

function fieldHeading(field, fieldNames) {
  if (field === "?") return "分野要確認";
  const name = fieldNames?.[field];
  return name ? `${field} ${name}` : String(field ?? "");
}

function resolveSource(source) {
  if (!source) return null;
  if (typeof source === "string") {
    const url = safeExternalURL(source);
    return url ? { url, title: "根拠資料" } : null;
  }
  if (typeof source === "object") {
    const url = safeExternalURL(source.url);
    return url ? { url, title: source.title || "根拠資料" } : null;
  }
  return null;
}

function isFiniteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

export function AcademicFields({
  rows = [],
  fieldNames = {},
  onSearch,
  onReview,
}) {
  if (!rows.length) {
    return (
      <p className="empty">
        授業を時間割に入れるか成績を取り込むと、分野別の単位が表示されます。
      </p>
    );
  }

  return (
    <div className="af-list">
      {rows.map((row) => {
        const label = fieldHeading(row.field, fieldNames);
        const earned = isFiniteNumber(row.earned) ? row.earned : 0;
        const planned = isFiniteNumber(row.planned) ? row.planned : 0;
        const forecast = earned + planned;
        const hasRequired = isFiniteNumber(row.required);
        const hasRemaining = isFiniteNumber(row.remaining);
        const hasAfter = isFiniteNumber(row.after);
        const hasRequirementInfo = hasRequired || hasRemaining || hasAfter;
        const isUnknown = row.field === "?";
        const needsReview = Boolean(row.needsReview) || isUnknown;
        const isUnmet =
          !isUnknown &&
          ((hasRemaining && row.remaining > 0) || (hasAfter && row.after > 0));
        const source = resolveSource(row.source);
        const courses = Array.isArray(row.courses) ? row.courses : [];
        const summaryParts = [];
        if (hasRequired) summaryParts.push(`必要 ${row.required}`);
        if (hasRemaining) summaryParts.push(`現在の残り ${row.remaining}`);
        if (hasAfter) summaryParts.push(`履修後の残り ${row.after}`);
        const showSearch = isUnmet && typeof onSearch === "function";
        const showReview = needsReview && typeof onReview === "function";

        return (
          <details className="field-row af-row" key={String(row.field)}>
            <summary className="af-summary">
              <div className="af-heading">
                <strong>{label}</strong>
                {needsReview && (
                  <span className="af-badge af-badge-warn">要確認</span>
                )}
              </div>
              <div className="af-metrics">
                <span>
                  修得 {earned} · 履修後 {forecast} 単位
                </span>
                {summaryParts.length > 0 && (
                  <span className="af-req-summary">
                    {summaryParts.join(" · ")} 単位
                  </span>
                )}
              </div>
            </summary>
            <div className="af-body">
              {hasRequirementInfo && (
                <dl className="af-stats">
                  {hasRequired && (
                    <div>
                      <dt>必要単位</dt>
                      <dd>{row.required}単位</dd>
                    </div>
                  )}
                  {hasRemaining && (
                    <div>
                      <dt>現在の残り</dt>
                      <dd>{row.remaining}単位</dd>
                    </div>
                  )}
                  {hasAfter && (
                    <div>
                      <dt>履修後の残り</dt>
                      <dd>{row.after}単位</dd>
                    </div>
                  )}
                </dl>
              )}
              {source && (
                <div className="af-source">
                  <External href={source.url}>{source.title}</External>
                </div>
              )}
              {courses.length > 0 ? (
                <ul className="rows af-courses">
                  {courses.map((entry, index) => {
                    const course = entry?.course ?? {};
                    const column = entry?.column;
                    const yearText = course.year
                      ? `${course.year}年度`
                      : "年度未記載";
                    const creditText =
                      course.credits != null
                        ? `${course.credits}単位`
                        : "単位要確認";
                    const statusText =
                      column === "earned" ? "修得済み" : "履修予定";
                    return (
                      <li key={course.code ? `${course.code}-${index}` : index}>
                        <strong>{course.title || "科目名要確認"}</strong>
                        <small>
                          {[course.code, yearText, statusText, creditText]
                            .filter(Boolean)
                            .join(" · ")}
                        </small>
                      </li>
                    );
                  })}
                </ul>
              ) : (
                <p className="hint">この分野に該当する授業はまだありません。</p>
              )}
              {(showSearch || showReview) && (
                <div className="actions af-actions">
                  {showSearch && (
                    <Button
                      size="sm"
                      variant="secondary"
                      icon={<Search size={14} />}
                      label="この分野の授業を探す"
                      onClick={() =>
                        onSearch({
                          field: row.field,
                          requirement: `field-${row.field}`,
                          label,
                          row,
                        })
                      }
                    />
                  )}
                  {showReview && (
                    <Button
                      size="sm"
                      variant="secondary"
                      label={isUnknown ? "分野を確認する" : "要確認の項目を確認"}
                      onClick={() => onReview(row)}
                    />
                  )}
                </div>
              )}
            </div>
          </details>
        );
      })}
    </div>
  );
}
