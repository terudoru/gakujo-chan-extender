import React, { useDeferredValue, useMemo, useState } from "react";
import { TextInput } from "@astryxdesign/core/TextInput";
import { ArrowLeft, ChevronDown, Search } from "lucide-react";
import {
  conflicts,
  hasUnscheduled,
  normalize,
  slotsFor,
  termsFor,
} from "./study.mjs";
import { satisfiesFilter } from "./requirements.mjs";
import {
  ActionLink,
  AddCourse,
  Button,
  ListPicker,
  Select,
  slotTitle,
} from "./ui.jsx";

export function Discovery({
  catalog,
  state,
  byCode,
  context,
  returnTo,
  openCourse,
  list,
  setListId,
  mutate,
}) {
  const [query, setQuery] = useState(""),
    [term, setTerm] = useState(context.term ? String(context.term) : "all");
  const [field, setField] = useState("all"),
    [free, setFree] = useState(false),
    [limit, setLimit] = useState(30);
  const deferred = useDeferredValue(query);
  const matches = useMemo(() => {
    const words = deferred.trim().split(/\s+/).map(normalize).filter(Boolean);
    const results = catalog.courses.filter(
      (c) =>
        (term === "all" || termsFor(c).includes(Number(term))) &&
        (!context.slot ||
          (context.slot === "他"
            ? hasUnscheduled(c)
            : slotsFor(c).includes(context.slot))) &&
        (!context.requirement ||
          satisfiesFilter(c, context.requirement, state.profile)) &&
        (field === "all" || c.fields.includes(field)) &&
        (!free || !conflicts(c, state, byCode).length) &&
        (!words.length ||
          words.every((w) =>
            normalize(
              [
                c.title,
                c.teacher,
                c.code,
                c.category,
                c.period,
                c.schedule,
                ...c.fields.map((f) => catalog.fields[f]),
              ].join(" "),
            ).includes(w),
          )),
    );
    if (!context.requirement || free) return results;
    const available = [],
      overlapping = [];
    for (const c of results)
      (conflicts(c, state, byCode).length ? overlapping : available).push(c);
    return [...available, ...overlapping];
  }, [catalog, term, context, deferred, field, free, state, byCode]);
  const back = context.slot
    ? "時間割に戻る"
    : context.requirement
      ? "単位・要件に戻る"
      : null;
  return (
    <section className="page-content">
      {back && (
        <ActionLink onClick={returnTo}>
          <ArrowLeft size={15} />
          {back}
        </ActionLink>
      )}
      {(context.slot || context.requirement) && (
        <h2 className="context-title">
          {context.slot ? slotTitle(context.slot) : context.label}
        </h2>
      )}
      <div className="search-field">
        <TextInput
          type="search"
          label="授業を検索"
          isLabelHidden
          placeholder="授業名・担当教員・科目コードで検索"
          startIcon={<Search size={17} />}
          value={query}
          onChange={(v) => {
            setQuery(v);
            setLimit(30);
          }}
        />
      </div>
      <div className="filters">
        <Select
          label="開講ターム"
          value={term}
          change={(v) => {
            setTerm(v);
            setLimit(30);
          }}
          options={[
            ["all", "全ターム"],
            ...[1, 2, 3, 4].map((t) => [String(t), "第" + t + "ターム"]),
          ]}
        />
        <Select
          label="シラバスの分野"
          value={field}
          change={(v) => {
            setField(v);
            setLimit(30);
          }}
          options={[
            ["all", "すべての分野"],
            ...Object.entries(catalog.fields).map(([id, name]) => [
              id,
              id + " " + name,
            ]),
          ]}
        />
        <ListPicker lists={state.lists} id={list?.id} setId={setListId} />
        <label className="check">
          <input
            type="checkbox"
            checked={free}
            onChange={(e) => setFree(e.target.checked)}
          />
          重ならない授業
        </label>
      </div>
      <div className="result-caption">
        {matches.length.toLocaleString("ja-JP")}件の授業
      </div>
      <ul className="result-list">
        {matches.slice(0, limit).map((c) => (
          <li key={c.code}>
            <div>
              <button className="title-link" onClick={() => openCourse(c)}>
                {c.title}
              </button>
              <small>
                {c.code}　{c.teacher}
              </small>
              <span>
                {c.period} · {c.schedule} · {c.credits ?? "要確認"}単位
              </span>
            </div>
            <AddCourse
              course={c}
              list={list}
              mutate={mutate}
              onAdded={context.slot ? returnTo : undefined}
            />
          </li>
        ))}
      </ul>
      {!matches.length && (
        <p className="hint">
          この条件の授業はありません。タームや検索語を変更してください。
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
    </section>
  );
}
