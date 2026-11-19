import React, { useMemo, useState } from "react";
import { BottomSheet } from "@astryxdesign/core/BottomSheet";
import {
  ArrowRight,
  BookOpen,
  CalendarDays,
  ChevronRight,
  Clock3,
  Plus,
  Search,
} from "lucide-react";
import { ProgressBar } from "@astryxdesign/core/ProgressBar";
import {
  DAYS,
  GAKUJO,
  activeCourses,
  chooseCourse,
  conflicts,
  hasUnscheduled,
  listCandidates,
  semesterCredits,
  slotsFor,
  termsFor,
} from "./study.mjs";
import {
  ActionLink,
  Button,
  CourseLine,
  External,
  Modal,
  Segments,
  slotTitle,
} from "./ui.jsx";

import { requirementRows, satisfiesFilter } from "./requirements.mjs";

export function Timetable({
  state,
  byCode,
  catalog,
  term,
  setTerm,
  slot,
  setSlot,
  mutate,
  search,
  requirements,
  openCourse,
  reopenSlot,
}) {
  const [replacement, setReplacement] = useState(null);
  const [extended, setExtended] = useState(false);
  const [sheet, setSheet] = useState(
    () => reopenSlot && window.matchMedia("(max-width: 920px)").matches,
  );
  const maps = useMemo(() => {
    const offered = new Map(),
      inList = new Map(),
      planned = new Map(),
      denied = new Map();
    const saved = new Set(state.lists.flatMap((l) => l.codes));
    const active = activeCourses(state, byCode),
      chosen = new Set(active.map((c) => c.code));
    const push = (map, key, c) => {
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(c);
    };
    for (const course of catalog.courses) {
      if (!termsFor(course).includes(term)) continue;
      const when = new Set(slotsFor(course));
      if (hasUnscheduled(course)) when.add("他");
      for (const key of when) {
        push(offered, key, course);
        if (saved.has(course.code)) push(inList, key, course);
        if (chosen.has(course.code)) push(planned, key, course);
        if (
          state.status[course.code] === "不許可" &&
          state.plan.includes(course.code)
        )
          push(denied, key, course);
      }
    }
    return { offered, inList, planned, denied, active };
  }, [catalog, byCode, state, term]);
  const cap = semesterCredits(
    maps.active,
    term,
    state.profile,
    state.capOverrides,
  );
  const sem = term <= 2 ? "第1学期" : "第2学期";
  const candidates = listCandidates(state, byCode, term, slot);
  const selected = maps.planned.get(slot) ?? [];
  const impact = useMemo(() => {
    if (!selected.length || (!state.grades.length && !state.balances.length))
      return [];
    return ["progress", "graduation"].flatMap((goal) => {
      const rows = requirementRows(state, byCode, maps.active, goal);
      const applicable = rows.filter(
        (r) =>
          !r.needsBalance &&
          r.future > r.current &&
          selected.some((c) => satisfiesFilter(c, r.key, state.profile)),
      );
      const row =
        applicable.find((r) => !["区分計", "合計"].includes(r.kind)) ??
        applicable[0];
      return row
        ? [{ goal: goal === "progress" ? "進級・履修条件" : "卒業", row }]
        : [];
    });
  }, [state, maps, slot, byCode]);
  const extras = [
    ...maps.planned.keys(),
    ...maps.denied.keys(),
    ...maps.inList.keys(),
    slot,
  ].filter((k) => k !== "他");
  const days = extended
    ? DAYS
    : DAYS.slice(0, Math.max(5, ...extras.map((k) => DAYS.indexOf(k[0]) + 1)));
  const periods = extended
    ? 7
    : Math.max(5, ...extras.map((k) => Number(k.slice(1))));
  const showSlot = (key) => {
    setSlot(key);
    setSheet(window.matchMedia("(max-width: 920px)").matches);
  };
  const apply = async (course, replace = false) => {
    const reviewed = new Set(
      conflicts(course, state, byCode).map(({ course: c }) => c.code),
    );
    if (
      await mutate((s) => {
        if (
          replace &&
          conflicts(course, s, byCode).some(
            ({ course: c }) => !reviewed.has(c.code),
          )
        )
          throw Error(
            "時間割が更新されました。重なる授業をもう一度確認してください。",
          );
        chooseCourse(s, course, byCode, replace);
      })
    ) {
      setReplacement(null);
      setSheet(false);
    }
  };
  function pick(course) {
    if (conflicts(course, state, byCode).length) setReplacement(course);
    else void apply(course);
  }
  const card = (key) => {
    const entries = maps.planned.get(key) ?? [],
      options = maps.inList.get(key)?.length ?? 0,
      count = maps.offered.get(key)?.length ?? 0;
    return (
      <button
        type="button"
        key={key}
        aria-label={slotTitle(key) + "の候補"}
        aria-pressed={key === slot}
        className={
          "cell" +
          (slot === key ? " current" : "") +
          (entries.length ? " booked" : "") +
          (options ? " saved" : "")
        }
        onClick={() => showSlot(key)}
      >
        {entries.length ? (
          <>
            <strong>{entries.map((c) => c.title).join("・")}</strong>
            <small>
              {entries
                .map((c) => state.status[c.code] ?? "履修予定")
                .join("・")}
            </small>
          </>
        ) : maps.denied.has(key) ? (
          <>
            <strong>{maps.denied.get(key)[0].title}</strong>
            <small>不許可</small>
          </>
        ) : options ? (
          <>
            <strong>候補 {options}件</strong>
            <small>{count}件開講</small>
          </>
        ) : (
          <>
            <span className="cell-plus" aria-hidden="true">
              <Plus size={15} />
            </span>
            <small>{count ? count + "件開講" : "—"}</small>
          </>
        )}
      </button>
    );
  };

  return (
    <div className="planner-layout">
      <section className="calendar-pane">
        <div className="table-tools">
          <Segments
            label="表示ターム"
            value={term}
            change={(v) => setTerm(Number(v))}
            options={[1, 2, 3, 4].map((t) => [t, "第" + t + "ターム"])}
          />
        </div>
        <div className="table-scroll">
          <div
            className="week"
            role="group"
            aria-label="週間時間割"
            style={{ "--days": days.length }}
          >
            <div className="axis axis-corner">時限</div>
            {days.map((d) => (
              <div key={d} className="axis day">
                {d}
              </div>
            ))}
            {Array.from({ length: periods }, (_, i) => (
              <React.Fragment key={i}>
                <div className="axis hour">
                  {i + 1}
                  <span>限</span>
                </div>
                {days.map((d) => card(d + (i + 1)))}
              </React.Fragment>
            ))}
          </div>
        </div>
        <div className="calendar-foot">
          <button
            type="button"
            className={"irregular" + (slot === "他" ? " picked" : "")}
            onClick={() => showSlot("他")}
          >
            <Clock3 size={15} />
            集中・時限未定
            {maps.inList.get("他")?.length
              ? "　候補 " + maps.inList.get("他").length + "件"
              : ""}
            <ChevronRight size={14} />
          </button>
          <ActionLink onClick={() => setExtended(!extended)}>
            {extended ? "平日・5限まで" : "土日・6限以降"}
          </ActionLink>
        </div>
        <section className="cap-strip">
          <div className="cap-icon">
            <BookOpen size={19} />
          </div>
          <div className="cap-body">
            <div className="split">
              <strong>{sem}のCAP</strong>
              <b>
                {cap.included}
                <small> / {cap.limit ?? "未設定"} 単位</small>
              </b>
            </div>
            {cap.limit > 0 && (
              <ProgressBar
                value={Math.min(cap.included, cap.limit)}
                max={cap.limit}
                label="CAP算入見込み"
                isLabelHidden
              />
            )}
            <div className="split">
              <small>
                登録予定の算入見込み
                {cap.excluded ? " · 対象外 " + cap.excluded + "単位" : ""}
                {cap.unconfirmed.length
                  ? " · 要確認 " + cap.unconfirmed.length + "科目"
                  : ""}
                {cap.limit != null && cap.included > cap.limit
                  ? " · 上限超過"
                  : ""}
              </small>
              <ActionLink onClick={requirements}>
                単位・要件へ <ArrowRight size={13} />
              </ActionLink>
            </div>
          </div>
        </section>
        {impact.length > 0 && (
          <div className="slot-impact">
            <strong>このコマの授業を修得した場合</strong>
            {impact.map(({ goal, row }) => (
              <div key={goal}>
                <span>
                  {goal} · {row.label}
                </span>
                <b>あと{row.after}単位</b>
              </div>
            ))}
          </div>
        )}
      </section>
      <aside
        className="inspector desktop-inspector"
        aria-label="選んだコマの授業"
      >
        {renderInspector()}
      </aside>
      {sheet && (
        <BottomSheet
          isOpen
          onOpenChange={setSheet}
          label={slotTitle(slot) + "の授業"}
        >
          <div className="sheet-inspector">
            <div className="sheet-close">
              <ActionLink onClick={() => setSheet(false)}>閉じる</ActionLink>
            </div>
            {renderInspector()}
          </div>
        </BottomSheet>
      )}
      {renderReplacement()}
    </div>
  );
  function renderInspector() {
    return (
      <>
        <div className="inspector-head">
          <CalendarDays size={17} />
          <span>第{term}ターム</span>
        </div>
        <h2>{slotTitle(slot)}</h2>
        {selected.map((c) => (
          <div className="selected-course" key={c.code}>
            <span className="state-dot">
              {state.status[c.code] ?? "履修予定"}
            </span>
            <CourseLine course={c} />
            <small>{c.code}</small>
            <External href={GAKUJO}>学務で申請</External>
            <ActionLink onClick={() => openCourse(c)}>
              詳細・登録状況 <ChevronRight size={13} />
            </ActionLink>
          </div>
        ))}
        {(maps.denied.get(slot) ?? []).map((c) => (
          <div className="selected-course" key={c.code}>
            <span className="error">不許可</span>
            <ActionLink onClick={() => openCourse(c)}>{c.title}</ActionLink>
          </div>
        ))}
        <div className="section-label">
          <h3>リスト内の候補</h3>
          <span>{candidates.length}件</span>
        </div>
        {candidates.length === 0 ? (
          <p className="hint">
            このコマの授業をリストに追加すると、ここで選べます。
          </p>
        ) : (
          <ul className="rows">
            {candidates.map(({ course, lists }) => (
              <li key={course.code}>
                <ActionLink onClick={() => openCourse(course)}>
                  {course.title}
                </ActionLink>
                <small>
                  {lists.join("・")} · {course.credits ?? "?"}単位
                </small>
                {conflicts(course, state, byCode).map(
                  ({ course: other, slots }) => (
                    <small className="conflict" key={other.code}>
                      {slots.map(slotTitle).join("・")}で「{other.title}」と重複
                    </small>
                  ),
                )}
                {!selected.some((c) => c.code === course.code) && (
                  <Button
                    label={
                      state.status[course.code] === "不許可"
                        ? "不許可"
                        : "この授業を選ぶ"
                    }
                    isDisabled={state.status[course.code] === "不許可"}
                    size="sm"
                    variant="secondary"
                    onClick={() => pick(course)}
                  />
                )}
              </li>
            ))}
          </ul>
        )}
        <Button
          variant="primary"
          label="このコマの授業を探す"
          icon={<Search size={16} />}
          onClick={() => search({ slot, term })}
        />
        {!candidates.length && (
          <div className="offered">
            <div className="section-label">
              <h3>このコマの開講科目</h3>
              <span>{maps.offered.get(slot)?.length ?? 0}件</span>
            </div>
            {(maps.offered.get(slot) ?? []).slice(0, 3).map((c) => (
              <button
                key={c.code}
                className="preview-course"
                onClick={() => openCourse(c)}
              >
                <span>{c.title}</span>
                <ChevronRight size={14} />
              </button>
            ))}
          </div>
        )}
      </>
    );
  }
  function renderReplacement() {
    return (
      replacement && (
        <Modal title="重なる授業を確認" close={() => setReplacement(null)}>
          <CourseLine course={replacement} />
          <p>次の授業と時限が重なります。</p>
          <ul className="rows">
            {conflicts(replacement, state, byCode).map(({ course, slots }) => (
              <li key={course.code}>
                <strong>{course.title}</strong>
                <small>
                  {course.period} · {slots.join("、")} ·{" "}
                  {state.status[course.code] ?? "履修予定"}
                </small>
              </li>
            ))}
          </ul>
          <div className="actions">
            <Button
              label="戻る"
              variant="secondary"
              onClick={() => setReplacement(null)}
            />
            <Button
              label="入れ替える"
              variant="primary"
              onClick={() => apply(replacement, true)}
              isDisabled={conflicts(replacement, state, byCode).some(
                ({ course }) =>
                  ["許可", "申請中"].includes(state.status[course.code]),
              )}
            />
          </div>
        </Modal>
      )
    );
  }
}
