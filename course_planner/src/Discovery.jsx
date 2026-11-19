import React, { useDeferredValue, useMemo, useState } from "react";
import { TextInput } from "@astryxdesign/core/TextInput";
import {
  ArrowLeft,
  ChevronDown,
  Columns2,
  RotateCcw,
  Search,
  X,
} from "lucide-react";
import { DAYS, conflicts } from "./study.mjs";
import {
  ActionLink,
  AddCourse,
  Button,
  ListPicker,
  Select,
  slotTitle,
} from "./ui.jsx";
import { SyllabusFacts } from "./components/SyllabusFacts.jsx";
import {
  PERIOD_NUMBERS,
  departmentOptions,
  filterAndRankCourses,
  formatAcademicFields,
  formatMeetingSlots,
  formatOfferingTerm,
  initialFiltersFromContext,
} from "./components/discovery-search.mjs";
import "./components/planner-forms.css";

const MAX_COMPARE = 3;

export function Discovery({
  catalog,
  state,
  byCode,
  context = {},
  returnTo,
  openCourse,
  list,
  setListId,
  mutate,
  matchesRequirement,
  departmentNames,
}) {
  const initial = useMemo(() => initialFiltersFromContext(context), [context]);
  const [query, setQuery] = useState(initial.query);
  const [teacher, setTeacher] = useState(initial.teacher);
  const [term, setTerm] = useState(initial.term);
  const [department, setDepartment] = useState(initial.department);
  const [day, setDay] = useState(initial.day);
  const [periodSlot, setPeriodSlot] = useState(initial.periodSlot);
  const [field, setField] = useState(initial.field);
  const [free, setFree] = useState(initial.free);
  const [limit, setLimit] = useState(30);
  const [selectedCode, setSelectedCode] = useState(null);
  const [compareCodes, setCompareCodes] = useState([]);

  const deferredQuery = useDeferredValue(query);
  const deferredTeacher = useDeferredValue(teacher);
  const deptMap = departmentNames ?? catalog?.departments;

  const deptChoices = useMemo(
    () => [
      ["all", "すべての部局"],
      ...departmentOptions(catalog?.courses ?? [], deptMap),
    ],
    [catalog, deptMap],
  );
  const fieldChoices = useMemo(
    () => [
      ["all", "すべての分野"],
      ...Object.entries(catalog?.fields ?? {}).map(([id, name]) => [
        id,
        `${id} ${name}`,
      ]),
    ],
    [catalog],
  );
  const dayChoices = useMemo(
    () => [
      ["all", "すべての曜日"],
      ...DAYS.map((d) => [d, `${d}曜`]),
      ["他", "集中・時限未定"],
    ],
    [],
  );
  const periodChoices = useMemo(
    () => [
      ["all", "すべての時限"],
      ...PERIOD_NUMBERS.map((n) => [n, `${n}限`]),
    ],
    [],
  );

  const {
    courses: matches,
    hasRequirementContext,
    urlNotice,
  } = useMemo(
    () =>
      filterAndRankCourses({
        catalog,
        state,
        byCode,
        context,
        matchesRequirement,
        departmentNames: deptMap,
        filters: {
          query: deferredQuery,
          teacher: deferredTeacher,
          term,
          department,
          day,
          periodSlot,
          field,
          free,
        },
      }),
    [
      catalog,
      state,
      byCode,
      context,
      matchesRequirement,
      deptMap,
      deferredQuery,
      deferredTeacher,
      term,
      department,
      day,
      periodSlot,
      field,
      free,
    ],
  );

  const lookupCourse = (code) => {
    if (!code) return null;
    if (byCode?.has(code)) return byCode.get(code);
    return (catalog?.courses ?? []).find((c) => c.code === code) ?? null;
  };
  const selectedCourse = lookupCourse(selectedCode);
  const comparedCourses = useMemo(
    () => compareCodes.map(lookupCourse).filter(Boolean),
    [compareCodes, byCode, catalog],
  );

  const listsContaining = (code) =>
    (state?.lists ?? []).filter((l) => l.codes.includes(code));

  const toggleCompare = (code) => {
    setCompareCodes((prev) =>
      prev.includes(code)
        ? prev.filter((c) => c !== code)
        : [...prev.slice(-(MAX_COMPARE - 1)), code],
    );
  };

  async function removeFromList(code) {
    if (!list) return;
    await mutate((s) => {
      const target = s.lists.find((l) => l.id === list.id);
      if (!target) throw Error("追加先リストを選び直してください。");
      target.codes = target.codes.filter((k) => k !== code);
    });
  }

  const filtersChanged =
    query !== initial.query ||
    teacher !== initial.teacher ||
    term !== initial.term ||
    department !== initial.department ||
    day !== initial.day ||
    periodSlot !== initial.periodSlot ||
    field !== initial.field ||
    free !== initial.free;

  function resetFilters() {
    setQuery(initial.query);
    setTeacher(initial.teacher);
    setTerm(initial.term);
    setDepartment(initial.department);
    setDay(initial.day);
    setPeriodSlot(initial.periodSlot);
    setField(initial.field);
    setFree(initial.free);
    setLimit(30);
  }

  const back = context.slot
    ? "時間割に戻る"
    : hasRequirementContext || context.requirement || context.field
      ? "単位・要件に戻る"
      : null;

  const contextHeading = context.slot
    ? slotTitle(context.slot)
    : context.label ||
      (context.field && catalog?.fields?.[context.field]
        ? `${context.field} ${catalog.fields[context.field]}`
        : "");

  const renderConflictSummary = (course) => {
    const items = conflicts(course, state, byCode);
    if (!items.length) {
      return <p className="disc-status-note">現在の時間割と重複なし</p>;
    }
    return (
      <p className="disc-status-note disc-conflict">
        {items
          .map(
            ({ course: other, slots }) =>
              `${slots.map(slotTitle).join("・")}で「${other.title}」と重複`,
          )
          .join(" / ")}
      </p>
    );
  };

  const renderSavedLists = (course) => {
    const savedIn = listsContaining(course.code);
    if (!savedIn.length) return null;
    return (
      <p className="disc-status-note">
        保存先リスト：{savedIn.map((l) => l.name).join("・")}
      </p>
    );
  };

  return (
    <section className="page-content">
      {back && returnTo && (
        <ActionLink onClick={returnTo}>
          <ArrowLeft size={15} />
          {back}
        </ActionLink>
      )}
      {contextHeading && <h2 className="context-title">{contextHeading}</h2>}
      {hasRequirementContext && !free && (
        <p className="hint">
          現在の時間割と重ならない授業を優先して表示しています。
        </p>
      )}
      <div className="search-field">
        <TextInput
          type="search"
          label="授業を検索"
          isLabelHidden
          placeholder="授業名・担当教員・開講番号・公式シラバスURLで検索"
          startIcon={<Search size={17} />}
          value={query}
          onChange={(v) => {
            setQuery(v);
            setLimit(30);
          }}
        />
      </div>
      <div className="disc-filters">
        <div className="disc-filter-cell">
          <Select
            label="開講ターム"
            value={term}
            change={(v) => {
              setTerm(v);
              setLimit(30);
            }}
            options={[
              ["all", "全ターム"],
              ...[1, 2, 3, 4].map((t) => [String(t), `第${t}ターム`]),
            ]}
          />
        </div>
        <div className="disc-filter-cell">
          <Select
            label="開講部局"
            value={department}
            change={(v) => {
              setDepartment(v);
              setLimit(30);
            }}
            options={deptChoices}
          />
        </div>
        <div className="disc-filter-cell">
          <Select
            label="曜日"
            value={day}
            change={(v) => {
              setDay(v);
              if (v === "他") setPeriodSlot("all");
              setLimit(30);
            }}
            options={dayChoices}
          />
        </div>
        <div className="disc-filter-cell">
          <Select
            label="時限"
            value={periodSlot}
            change={(v) => {
              setPeriodSlot(v);
              if (v !== "all" && day === "他") setDay("all");
              setLimit(30);
            }}
            options={periodChoices}
          />
        </div>
        <div className="disc-filter-cell">
          <Select
            label="シラバスの分野"
            value={field}
            change={(v) => {
              setField(v);
              setLimit(30);
            }}
            options={fieldChoices}
          />
        </div>
        <div className="disc-filter-cell">
          <TextInput
            type="text"
            label="担当教員"
            placeholder="教員名で絞り込み"
            value={teacher}
            onChange={(v) => {
              setTeacher(v);
              setLimit(30);
            }}
          />
        </div>
        <div className="disc-filter-cell">
          <ListPicker lists={state.lists} id={list?.id} setId={setListId} />
        </div>
      </div>
      <div className="disc-filter-meta">
        <label className="check">
          <input
            type="checkbox"
            checked={free}
            onChange={(e) => {
              setFree(e.target.checked);
              setLimit(30);
            }}
          />
          重ならない授業
        </label>
        {filtersChanged && (
          <ActionLink onClick={resetFilters}>
            <RotateCcw size={13} />
            条件を戻す
          </ActionLink>
        )}
      </div>

      {urlNotice && (
        <p className="notice" role="status">
          {urlNotice}
        </p>
      )}

      {comparedCourses.length > 0 && (
        <section
          className="disc-compare-section"
          aria-label="比較中の授業"
        >
          <div className="disc-panel-head">
            <h3>比較中の授業（{comparedCourses.length}件）</h3>
            <ActionLink onClick={() => setCompareCodes([])}>
              <X size={13} />
              比較をクリア
            </ActionLink>
          </div>
          <div className="disc-compare-grid">
            {comparedCourses.map((c) => {
              const inActiveList = Boolean(list?.codes.includes(c.code));
              return (
                <article className="disc-compare-card" key={c.code}>
                  <SyllabusFacts
                    course={c}
                    fields={catalog.fields}
                    year={catalog.year}
                    departmentNames={deptMap}
                    compact
                  />
                  {renderConflictSummary(c)}
                  {renderSavedLists(c)}
                  <div className="disc-panel-actions">
                    <AddCourse
                      course={c}
                      list={list}
                      mutate={mutate}
                      onAdded={context.slot ? returnTo : undefined}
                    />
                    {inActiveList && (
                      <ActionLink onClick={() => removeFromList(c.code)}>
                        リストから外す
                      </ActionLink>
                    )}
                    <ActionLink onClick={() => toggleCompare(c.code)}>
                      比較から外す
                    </ActionLink>
                  </div>
                </article>
              );
            })}
          </div>
        </section>
      )}

      <div
        className={"disc-layout" + (selectedCourse ? " disc-has-panel" : "")}
      >
        <div className="disc-results-col">
          <div className="result-caption">
            {matches.length.toLocaleString("ja-JP")}件の授業
          </div>
          <ul className="result-list">
            {matches.slice(0, limit).map((c) => {
              const isSelected = selectedCode === c.code;
              const isCompared = compareCodes.includes(c.code);
              const courseConflicts = conflicts(c, state, byCode);
              return (
                <li
                  key={c.code}
                  className={
                    "disc-row" + (isSelected ? " disc-row-selected" : "")
                  }
                >
                  <div className="disc-row-main">
                    <button
                      type="button"
                      className="title-link"
                      aria-current={isSelected ? "true" : undefined}
                      onClick={() => setSelectedCode(c.code)}
                    >
                      {c.title}
                    </button>
                    <small>
                      {c.code}　{c.teacher || "担当未定"}
                    </small>
                    <span className="disc-meta-tags">
                      <span>{formatOfferingTerm(c)}</span>
                      <span>{formatMeetingSlots(c)}</span>
                      <span>{c.credits ?? "要確認"}単位</span>
                      <span>{formatAcademicFields(c, catalog.fields)}</span>
                    </span>
                    {courseConflicts.length > 0 && (
                      <small className="disc-status-note disc-conflict">
                        {courseConflicts
                          .map(
                            ({ course: other, slots }) =>
                              `${slots.map(slotTitle).join("・")}で「${other.title}」と重複`,
                          )
                          .join(" / ")}
                      </small>
                    )}
                  </div>
                  <div className="disc-row-actions">
                    <Button
                      size="sm"
                      variant={isCompared ? "primary" : "ghost"}
                      icon={<Columns2 size={14} />}
                      label={isCompared ? "比較中" : "比較"}
                      onClick={() => toggleCompare(c.code)}
                    />
                    <AddCourse
                      course={c}
                      list={list}
                      mutate={mutate}
                      onAdded={context.slot ? returnTo : undefined}
                    />
                  </div>
                </li>
              );
            })}
          </ul>
          {!matches.length && !urlNotice && (
            <p className="hint">
              この条件の授業はありません。タームや検索語、絞り込み条件を変更してください。
            </p>
          )}
          {matches.length > limit && (
            <Button
              label="さらに30件表示"
              icon={<ChevronDown size={15} />}
              variant="secondary"
              onClick={() => setLimit(limit + 30)}
            />
          )}
        </div>

        {selectedCourse && (
          <aside className="disc-panel" aria-label="選択中の授業の詳細">
            <div className="disc-panel-head">
              <h3>シラバス情報</h3>
              <ActionLink onClick={() => setSelectedCode(null)}>
                <X size={13} />
                閉じる
              </ActionLink>
            </div>
            <SyllabusFacts
              course={selectedCourse}
              fields={catalog.fields}
              year={catalog.year}
              departmentNames={deptMap}
            />
            {renderConflictSummary(selectedCourse)}
            {renderSavedLists(selectedCourse)}
            <div className="disc-panel-actions">
              <AddCourse
                course={selectedCourse}
                list={list}
                mutate={mutate}
                onAdded={context.slot ? returnTo : undefined}
              />
              {list?.codes.includes(selectedCourse.code) && (
                <ActionLink
                  onClick={() => removeFromList(selectedCourse.code)}
                >
                  リストから外す
                </ActionLink>
              )}
              <Button
                size="sm"
                variant="secondary"
                icon={<Columns2 size={14} />}
                label={
                  compareCodes.includes(selectedCourse.code)
                    ? "比較から外す"
                    : "比較に追加"
                }
                onClick={() => toggleCompare(selectedCourse.code)}
              />
              {typeof openCourse === "function" && (
                <ActionLink onClick={() => openCourse(selectedCourse)}>
                  登録状況・CAP設定
                </ActionLink>
              )}
            </div>
          </aside>
        )}
      </div>
    </section>
  );
}
