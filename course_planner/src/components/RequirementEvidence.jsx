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

const balanceStyle = {
  display: "grid",
  gap: "2px",
  padding: "6px 8px",
  borderRadius: "var(--radius-inner, 6px)",
  background: "var(--color-background-muted, var(--wash, #f6f6f3))",
  border: "1px solid var(--color-border, var(--rule, #d7d8d2))",
  minWidth: 0,
};

const balanceValueStyle = {
  fontSize: "var(--font-size-sm, 13px)",
  fontWeight: 600,
  color: "var(--color-text-primary, var(--ink, #242420))",
  fontVariantNumeric: "tabular-nums",
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

const noteStyle = {
  margin: 0,
  fontSize: "var(--text-supporting-size, 12px)",
  lineHeight: "var(--text-supporting-leading, 1.6)",
  color: "var(--color-text-primary, var(--ink, #242420))",
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

function formatQuantity(value, unit) {
  switch (unit) {
    case "courses":
      return `${value}科目`;
    case "months":
      return `${value}か月`;
    case "condition":
      return `条件 ${value}`;
    case "credits":
    default:
      return `${value}単位`;
  }
}

function formatUnits(applied, credits, unit) {
  const hasApplied = hasValue(applied);
  const hasCredits = hasValue(credits);
  if (hasApplied && hasCredits) {
    if (unit === "credits" && String(applied) === String(credits)) {
      return `算入 ${formatQuantity(applied, unit)}`;
    }
    return `算入 ${formatQuantity(applied, unit)}（科目 ${credits}単位）`;
  }
  if (hasApplied) return `算入 ${formatQuantity(applied, unit)}`;
  if (hasCredits) return `${credits}単位`;
  return "";
}

function formatCoveredUnits(applied, credits, unit) {
  const hasApplied = hasValue(applied);
  const hasCredits = hasValue(credits);
  if (hasApplied && hasCredits) {
    if (unit === "credits" && String(applied) === String(credits)) {
      return `確認表に含む ${formatQuantity(applied, unit)}`;
    }
    return `確認表に含む ${formatQuantity(applied, unit)}（科目 ${credits}単位）`;
  }
  if (hasApplied) return `確認表に含む ${formatQuantity(applied, unit)}`;
  if (hasCredits) return `${credits}単位`;
  return "";
}

function formatTransition(before, after, unit) {
  return `算入 ${formatQuantity(before, unit)} → ${formatQuantity(after, unit)}`;
}

function resolveCode(row) {
  if (hasValue(row?.code)) return String(row.code);
  if (hasValue(row?.matchedCode)) return String(row.matchedCode);
  return "";
}

function baseCourseIdentityKey(row) {
  if (hasValue(row.recordId)) {
    return `record:${row.sourceId ?? ""}/${row.recordId}`;
  }
  const code = resolveCode(row);
  return code
    ? `offering:${row.year ?? ""}/${code}/${row.title ?? ""}`
    : `title:${row.year ?? ""}/${row.title ?? ""}`;
}

function courseIdentityKey(row, counts) {
  const base = baseCourseIdentityKey(row);
  const seen = counts.get(base) ?? 0;
  counts.set(base, seen + 1);
  return `${base}#${seen}`;
}

function dedupeCoveredRows(coveredRows, earnedRows) {
  const seen = new Set(earnedRows.map(baseCourseIdentityKey));
  const unique = [];
  for (const row of coveredRows) {
    const key = baseCourseIdentityKey(row);
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(row);
  }
  return unique;
}

function diffProjectedEarned(earnedRows, projectedEarned) {
  if (!Array.isArray(projectedEarned)) return [];
  const projectedRows = projectedEarned.filter(
    (row) => row && typeof row === "object",
  );
  const earnedCounts = new Map();
  const projectedCounts = new Map();
  const earnedMap = new Map();
  const projectedMap = new Map();

  for (const row of earnedRows) {
    earnedMap.set(courseIdentityKey(row, earnedCounts), row);
  }
  for (const row of projectedRows) {
    projectedMap.set(courseIdentityKey(row, projectedCounts), row);
  }

  const changes = [];
  for (const [key, earnedRow] of earnedMap) {
    const projectedRow = projectedMap.get(key);
    const before = hasValue(earnedRow.applied) ? earnedRow.applied : 0;
    const after =
      projectedRow && hasValue(projectedRow.applied) ? projectedRow.applied : 0;
    if (String(before) !== String(after)) {
      const merged = projectedRow
        ? {
            ...earnedRow,
            ...projectedRow,
            sourceUrl: projectedRow.sourceUrl ?? earnedRow.sourceUrl,
          }
        : earnedRow;
      changes.push({ key, row: merged, before, after });
    }
  }
  for (const [key, projectedRow] of projectedMap) {
    if (earnedMap.has(key)) continue;
    const after = hasValue(projectedRow.applied) ? projectedRow.applied : 0;
    if (String(after) !== "0") {
      changes.push({ key, row: projectedRow, before: 0, after });
    }
  }
  return changes;
}

function EvidenceItem({ row, unitText }) {
  const code = resolveCode(row);
  const hasTitle = hasValue(row.title);
  const title = hasTitle ? String(row.title) : code || "名称未設定";
  const meta = [
    hasTitle && code ? code : "",
    hasValue(row.year) ? String(row.year) : "",
    unitText,
  ]
    .filter(Boolean)
    .join(" · ");
  const rowReason = typeof row.reason === "string" ? row.reason.trim() : "";
  const rowNote = typeof row.note === "string" ? row.note.trim() : "";
  const syllabusHref = safeHttpUrl(row.sourceUrl);

  return (
    <li style={itemStyle}>
      <span style={titleStyle}>{title}</span>
      {meta && <small style={metaStyle}>{meta}</small>}
      {rowReason && <small style={metaStyle}>{rowReason}</small>}
      {rowNote && rowNote !== rowReason && (
        <small style={metaStyle}>{rowNote}</small>
      )}
      {syllabusHref && (
        <a
          className="external"
          href={syllabusHref}
          target="_blank"
          rel="noopener noreferrer"
        >
          公式シラバス
          <ArrowUpRight size={13} aria-hidden="true" />
        </a>
      )}
    </li>
  );
}

function EvidenceGroup({ heading, rows, unit, formatRowUnits = formatUnits }) {
  return (
    <div style={sectionStyle}>
      <strong style={headingStyle}>{heading}</strong>
      {rows.length > 0 ? (
        <ul className="rows" style={listStyle}>
          {rows.map((row, index) => (
            <EvidenceItem
              key={`${resolveCode(row)}-${row.year ?? ""}-${row.title ?? ""}-${index}`}
              row={row}
              unitText={formatRowUnits(row.applied, row.credits, unit)}
            />
          ))}
        </ul>
      ) : (
        <p style={emptyStyle}>該当する授業はありません</p>
      )}
    </div>
  );
}

export function RequirementEvidence({
  earned = [],
  covered = [],
  planned = [],
  projectedEarned,
  unknown = [],
  sources = [],
  balance,
  unit,
  reason,
  note,
  onSearch,
} = {}) {
  const toRows = (list) =>
    Array.isArray(list)
      ? list.filter((row) => row && typeof row === "object")
      : [];
  const earnedRows = toRows(earned);
  const coveredRows = dedupeCoveredRows(toRows(covered), earnedRows);
  const plannedRows = toRows(planned);
  const unknownRows = toRows(unknown);
  const effectiveUnit = hasValue(unit)
    ? String(unit)
    : hasValue(balance?.unit)
      ? String(balance.unit)
      : "credits";
  const isCourseUnit =
    effectiveUnit === "credits" || effectiveUnit === "courses";

  const hasConfirmedBalance = Boolean(
    balance &&
      typeof balance === "object" &&
      balance.confirmed !== false &&
      hasValue(balance.current),
  );
  const balanceHeading = isCourseUnit ? "確認表の修得済み" : "確認表の記録";
  const coveredHeading = isCourseUnit
    ? "確認表の修得済みに含まれる科目"
    : "確認表の記録に含まれる科目";
  const balanceNote =
    typeof balance?.reason === "string" && balance.reason.trim()
      ? balance.reason.trim()
      : typeof balance?.note === "string" && balance.note.trim()
        ? balance.note.trim()
        : "";

  const ruleReason = typeof reason === "string" ? reason.trim() : "";
  const ruleNote = typeof note === "string" ? note.trim() : "";
  const projectedChanges = diffProjectedEarned(earnedRows, projectedEarned);

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

  const hasCourseRows =
    earnedRows.length > 0 ||
    coveredRows.length > 0 ||
    plannedRows.length > 0 ||
    unknownRows.length > 0 ||
    projectedChanges.length > 0;
  const hasRuleContext =
    hasConfirmedBalance ||
    Boolean(ruleReason) ||
    Boolean(ruleNote) ||
    validSources.length > 0;

  const showPlainEmptyGroups =
    isCourseUnit && !hasConfirmedBalance && !hasCourseRows && !hasRuleContext;
  const showEarnedGroup =
    earnedRows.length > 0 ||
    (isCourseUnit && !hasConfirmedBalance && plannedRows.length > 0) ||
    showPlainEmptyGroups;
  const showPlannedGroup =
    plannedRows.length > 0 ||
    (isCourseUnit && !hasConfirmedBalance && earnedRows.length > 0) ||
    showPlainEmptyGroups;
  const showNonCoursePlaceholder =
    !isCourseUnit && !hasCourseRows && !hasRuleContext;

  return (
    <details style={detailsStyle}>
      <summary style={summaryStyle}>根拠・内訳</summary>
      <div style={bodyStyle}>
        {hasConfirmedBalance && (
          <div style={balanceStyle}>
            <strong style={headingStyle}>{balanceHeading}</strong>
            <span style={balanceValueStyle}>
              {formatQuantity(balance.current, effectiveUnit)}
            </span>
            {balanceNote && <small style={metaStyle}>{balanceNote}</small>}
          </div>
        )}
        {coveredRows.length > 0 && (
          <EvidenceGroup
            heading={coveredHeading}
            rows={coveredRows}
            unit={effectiveUnit}
            formatRowUnits={formatCoveredUnits}
          />
        )}
        {ruleReason && (
          <div style={sectionStyle}>
            <strong style={headingStyle}>確認事項</strong>
            <p style={noteStyle}>{ruleReason}</p>
          </div>
        )}
        {ruleNote && ruleNote !== ruleReason && (
          <div style={sectionStyle}>
            <strong style={headingStyle}>注記</strong>
            <p style={noteStyle}>{ruleNote}</p>
          </div>
        )}
        {showEarnedGroup && (
          <EvidenceGroup
            heading={hasConfirmedBalance ? "照合できた修得科目" : "修得済み"}
            rows={earnedRows}
            unit={effectiveUnit}
          />
        )}
        {showPlannedGroup && (
          <EvidenceGroup
            heading="履修予定"
            rows={plannedRows}
            unit={effectiveUnit}
          />
        )}
        {projectedChanges.length > 0 && (
          <div style={sectionStyle}>
            <strong style={headingStyle}>
              履修予定に伴う修得済みの算入変更
            </strong>
            <ul className="rows" style={listStyle}>
              {projectedChanges.map(({ key, row, before, after }) => (
                <EvidenceItem
                  key={key}
                  row={row}
                  unitText={formatTransition(before, after, effectiveUnit)}
                />
              ))}
            </ul>
          </div>
        )}
        {unknownRows.length > 0 && (
          <EvidenceGroup
            heading="要確認"
            rows={unknownRows}
            unit={effectiveUnit}
          />
        )}
        {showNonCoursePlaceholder && (
          <p style={emptyStyle}>科目以外の条件に基づく項目です</p>
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
