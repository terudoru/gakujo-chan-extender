import React from "react";
import { Button } from "@astryxdesign/core/Button";
import { ArrowUpRight, Search } from "lucide-react";

const detailsStyle = {
  marginTop: "6px",
  textAlign: "start",
  color: "var(--color-text-primary, var(--ink, #242420))",
  fontFamily: "var(--font-family-body)",
};

const summaryStyle = {
  fontSize: "var(--text-supporting-size, 12px)",
  lineHeight: "var(--text-supporting-leading, 1.6)",
  color: "var(--color-text-secondary, var(--soft, #5f605a))",
  fontWeight: 550,
  cursor: "pointer",
  width: "fit-content",
};

const bodyStyle = {
  display: "grid",
  gap: "10px",
  marginTop: "8px",
  paddingInlineStart: "10px",
  borderInlineStart: "2px solid var(--color-border, var(--rule, #d7d8d2))",
  minWidth: 0,
};

const sectionStyle = {
  display: "grid",
  gap: "4px",
  minWidth: 0,
};

const headingStyle = {
  fontSize: "var(--text-supporting-size, 12px)",
  lineHeight: "var(--text-supporting-leading, 1.5)",
  color: "var(--color-text-secondary, var(--soft, #5f605a))",
  fontWeight: 600,
};

const listStyle = {
  margin: 0,
};

const itemStyle = {
  padding: "6px 0",
  gap: "2px",
};

const titleStyle = {
  fontSize: "var(--font-size-sm, 13px)",
  fontWeight: 600,
  color: "var(--color-text-primary, var(--ink, #242420))",
  overflowWrap: "anywhere",
};

const metaStyle = {
  fontSize: "var(--text-supporting-size, 12px)",
  color: "var(--color-text-secondary, var(--soft, #5f605a))",
  overflowWrap: "anywhere",
};

const emptyStyle = {
  margin: 0,
  fontSize: "var(--text-supporting-size, 12px)",
  color: "var(--color-text-secondary, var(--soft, #5f605a))",
};

const sourcesStyle = {
  padding: "2px 0",
  gap: "6px 14px",
};

const actionStyle = {
  paddingTop: "2px",
};

function hasValue(value) {
  return value !== undefined && value !== null && String(value).trim() !== "";
}

function safeHttpUrl(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  try {
    const parsed = new URL(trimmed);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return null;
    }
    return parsed.href;
  } catch {
    return null;
  }
}

function formatUnits(applied, credits) {
  const hasApplied = hasValue(applied);
  const hasCredits = hasValue(credits);
  if (hasApplied && hasCredits) {
    if (String(applied) === String(credits)) {
      return `算入 ${applied}単位`;
    }
    return `算入 ${applied}単位（科目 ${credits}単位）`;
  }
  if (hasApplied) return `算入 ${applied}単位`;
  if (hasCredits) return `${credits}単位`;
  return "";
}

function EvidenceGroup({ heading, rows }) {
  return (
    <div style={sectionStyle}>
      <strong style={headingStyle}>{heading}</strong>
      {rows.length > 0 ? (
        <ul className="rows" style={listStyle}>
          {rows.map((row, index) => {
            const hasTitle = hasValue(row.title);
            const title = hasTitle
              ? String(row.title)
              : hasValue(row.code)
                ? String(row.code)
                : "名称未設定";
            const meta = [
              hasTitle && hasValue(row.code) ? String(row.code) : "",
              hasValue(row.year) ? String(row.year) : "",
              formatUnits(row.applied, row.credits),
            ]
              .filter(Boolean)
              .join(" · ");
            const reason =
              typeof row.reason === "string" ? row.reason.trim() : "";
            return (
              <li
                key={`${row.code ?? ""}-${row.year ?? ""}-${title}-${index}`}
                style={itemStyle}
              >
                <span style={titleStyle}>{title}</span>
                {meta && <small style={metaStyle}>{meta}</small>}
                {reason && <small style={metaStyle}>{reason}</small>}
              </li>
            );
          })}
        </ul>
      ) : (
        <p style={emptyStyle}>該当する授業はありません</p>
      )}
    </div>
  );
}

export function RequirementEvidence({
  earned = [],
  planned = [],
  unknown = [],
  sources = [],
  balance,
  onSearch,
} = {}) {
  const toRows = (list) =>
    Array.isArray(list)
      ? list.filter((row) => row && typeof row === "object")
      : [];
  const earnedRows = toRows(earned);
  const plannedRows = toRows(planned);
  const unknownRows = toRows(unknown);
  const validSources = (Array.isArray(sources) ? sources : [])
    .map((source) => {
      if (!source || typeof source !== "object") return null;
      const url = safeHttpUrl(source.url);
      if (!url) return null;
      const title =
        typeof source.title === "string" && source.title.trim()
          ? source.title.trim()
          : "公式規程";
      return { title, url };
    })
    .filter(Boolean);

  return (
    <details style={detailsStyle}>
      <summary style={summaryStyle}>根拠・内訳</summary>
      <div style={bodyStyle}>
        {balance && (
          <div style={sectionStyle}>
            <strong style={headingStyle}>確認表の修得済み</strong>
            <span>{balance.current}単位</span>
          </div>
        )}
        {(!balance || earnedRows.length > 0) && (
          <EvidenceGroup
            heading={balance ? "照合できた修得科目" : "修得済み"}
            rows={earnedRows}
          />
        )}
        <EvidenceGroup heading="履修予定" rows={plannedRows} />
        {unknownRows.length > 0 && (
          <EvidenceGroup heading="要確認" rows={unknownRows} />
        )}
        {validSources.length > 0 && (
          <div style={sectionStyle}>
            <strong style={headingStyle}>公式規程・出典</strong>
            <div className="sources" style={sourcesStyle}>
              {validSources.map((source, index) => (
                <a
                  key={`${source.url}-${index}`}
                  className="external"
                  href={source.url}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {source.title}
                  <ArrowUpRight size={14} aria-hidden="true" />
                </a>
              ))}
            </div>
          </div>
        )}
        {typeof onSearch === "function" && (
          <div style={actionStyle}>
            <Button
              size="sm"
              variant="secondary"
              icon={<Search size={14} aria-hidden="true" />}
              label="不足を埋める授業を探す"
              onClick={() => onSearch()}
            />
          </div>
        )}
      </div>
    </details>
  );
}
