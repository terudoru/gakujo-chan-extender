import React from "react";
import { syllabusURL } from "../study.mjs";
import { External } from "../ui.jsx";
import {
  departmentLabel,
  formatAcademicFields,
  formatCourseType,
  formatMeetingSlots,
  formatOfferingTerm,
} from "./discovery-search.mjs";
import "./planner-forms.css";

export function SyllabusFacts({
  course,
  fields = {},
  year = 2026,
  departmentNames,
  compact = false,
  showTitle = true,
}) {
  if (!course) return null;
  const officialUrl = syllabusURL(course, year);
  const creditsLabel =
    course.credits != null ? `${course.credits}単位` : "要確認";
  return (
    <div className="sf-card">
      {showTitle && <h3 className="sf-title">{course.title}</h3>}
      <dl className={"sf-grid" + (compact ? " sf-compact" : "")}>
        <div className="sf-item">
          <dt>開講番号</dt>
          <dd>{course.code || "要確認"}</dd>
        </div>
        <div className="sf-item">
          <dt>開講ターム</dt>
          <dd>{formatOfferingTerm(course)}</dd>
        </div>
        <div className="sf-item sf-item-wide">
          <dt>曜日・時限</dt>
          <dd>{formatMeetingSlots(course)}</dd>
        </div>
        <div className="sf-item">
          <dt>担当教員</dt>
          <dd>{course.teacher || "要確認"}</dd>
        </div>
        <div className="sf-item">
          <dt>単位数</dt>
          <dd>{creditsLabel}</dd>
        </div>
        <div className="sf-item">
          <dt>開講部局</dt>
          <dd>{departmentLabel(course.department, departmentNames)}</dd>
        </div>
        <div className="sf-item">
          <dt>科目区分</dt>
          <dd>{course.category || "要確認"}</dd>
        </div>
        <div className="sf-item sf-item-wide">
          <dt>分野／Academic Field</dt>
          <dd>{formatAcademicFields(course, fields)}</dd>
        </div>
        <div className="sf-item">
          <dt>授業形態</dt>
          <dd>{formatCourseType(course)}</dd>
        </div>
      </dl>
      {officialUrl ? (
        <div className="sf-link-row">
          <External href={officialUrl}>公式シラバス</External>
          <small>大学の公開シラバスを別タブで開きます</small>
        </div>
      ) : (
        <p className="sf-missing">公式シラバスのURLは要確認です。</p>
      )}
    </div>
  );
}
