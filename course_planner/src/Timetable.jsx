import React, { useMemo, useState } from "react";
import { BottomSheet } from "@astryxdesign/core/BottomSheet";
import {
  ArrowRight,
  BookOpen,
  CalendarDays,
  ChevronRight,
  Clock3,
  FileUp,
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

import { availableStages, slotRequirements } from "./requirements.mjs";
import { fieldProgress } from "./field-progress.mjs";
import { CandidateOverlaps } from "./components/CandidateOverlaps.jsx";

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
  candidateIndex,
  fieldSelector,
  importRegistration,
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
      registrationNotes = new Map();
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
          !chosen.has(course.code) &&
          ["不許可", "要確認"].includes(state.status[course.code])
        )
          push(registrationNotes, key, course);
      }
    }
    return { offered, inList, planned, registrationNotes, active };
  }, [catalog, byCode, state, term]);
  const cap = semesterCredits(
    maps.active,
    term,
    state.profile,
    state.capOverrides,
    state.semesters,
  );
  const sem = term <= 2 ? "第1学期" : "第2学期";
  const candidates = listCandidates(state, byCode, term, slot);
  const selected = maps.planned.get(slot) ?? [];
  const fieldForecast = useMemo(() => {
    const courseFieldsHere = new Set(
      (maps.planned.get(slot) ?? []).flatMap((c) =>
        c.fields?.length ? c.fields : ["?"],
      ),
    );
    if (!courseFieldsHere.size) return [];
    return fieldProgress(state, byCode, maps.active, fieldSelector)
      .filter((row) => courseFieldsHere.has(row.field));
  }, [state, byCode, maps, slot, fieldSelector]);
  const impact = useMemo(() => {
    const chosen = maps.planned.get(slot);
    if (!chosen?.length || (!state.grades.length && !state.balances.length)) return [];
    return slotRequirements(state, byCode, maps.active, chosen);
  }, [state, maps, slot, byCode]);
  const stageNames = useMemo(
    () => new Map(availableStages(state.profile, "progress").map((stage) => [stage.id, stage.label ?? stage.title])),
    [state.profile],
  );
  const extras = [
    ...maps.planned.keys(),
    ...maps.registrationNotes.keys(),
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
      notes = maps.registrationNotes.get(key) ?? [],
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
        {entries.length || notes.length ? (
          [...entries, ...notes].map((c) => (
            <span className="cell-course" key={c.code}>
              <strong>{c.title}</strong>
              <small>{c.code} · {state.status[c.code] ?? "履修予定"}</small>
            </span>
          ))
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
          <Button
            size="sm" variant="secondary" label="登録状況を取り込む"
            icon={<FileUp size={15} />} onClick={importRegistration}
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
              <strong>{sem}{state.profile.faculty ? "のCAP" : "の登録予定"}</strong>
              <b>
                {state.profile.faculty ? cap.included : cap.scheduled}
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
                {state.profile.faculty ? "CAP算入見込み" : "所属を設定するとCAPを確認できます"}
                {cap.excluded ? " · 対象外 " + cap.excluded + "単位" : ""}
                {cap.unconfirmed.length
                  ? " · 要確認 " + cap.unconfirmed.length + "科目"
                  : ""}
                {cap.limit != null && cap.included > cap.limit
                  ? " · 上限超過"
                  : ""}
              </small>
              <ActionLink onClick={() => requirements()}>
                単位・要件へ <ArrowRight size={13} />
              </ActionLink>
            </div>
            {state.profile.faculty && (cap.note || cap.source?.url || cap.unconfirmed.length > 0) && (
              <details className="cap-rules">
                <summary>算入の根拠と要確認の授業</summary>
                {cap.note && <p>{cap.note}</p>}
                {cap.source?.url && <External href={cap.source.url}>{cap.source.title || "CAPの規定"}</External>}
                {cap.unconfirmed.map((c) => <div key={c.code}>
                  <ActionLink onClick={() => openCourse(c)}>{c.title}（{c.code}）</ActionLink>
                </div>)}
              </details>
            )}
          </div>
        </section>
        {renderForecast()}
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
            {renderInspector(true)}
          </div>
        </BottomSheet>
      )}
      {renderReplacement()}
    </div>
  );
  function renderForecast() {
    if (!fieldForecast.length && !impact.length) return null;
    return (
      <section className="slot-impact" aria-label="選択したコマの修得見込み">
        <strong>分野別の修得見込み</strong>
        <dl>
          {fieldForecast.map((r) => (
            <div key={r.field}>
              <dt>{r.field === "?" ? "分野要確認" : r.field + " " + catalog.fields[r.field]}</dt>
              <dd>
                {r.conflicted ? "確認表の修得単位が一致しません"
                  : r.needsReview ? `確認できた分 ${r.forecast}単位（ほか要確認）`
                  : r.earnedKnown
                    ? `修得 ${r.earned} → 履修後 ${r.forecast}単位`
                    : `履修予定 ${r.planned}単位`}
              </dd>
            </div>
          ))}
        </dl>
        {impact.length > 0 && (
          <details>
            <summary>このコマで減る進級・卒業要件の残り</summary>
            <dl>
              {impact.map((row) => (
                <div key={row.stageId + "/" + row.key}>
                  <dt>
                    <ActionLink onClick={() => requirements(row)}>
                      {row.goal === "progress" ? "進級・履修条件" : "卒業"} · {row.label}
                    </ActionLink>
                    {row.goal === "progress" && <small>{stageNames.get(row.stageId)}</small>}
                  </dt>
                  <dd>{row.previousAfter} → {row.after}{row.unit === "courses" ? "科目" : row.unit === "months" ? "か月" : "単位"}</dd>
                </div>
              ))}
            </dl>
          </details>
        )}
      </section>
    );
  }
  function renderInspector(showForecast = false) {
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
        {(maps.registrationNotes.get(slot) ?? []).map((c) => (
          <div className="selected-course" key={c.code}>
            <span className="error">{state.status[c.code]}</span>
            <ActionLink onClick={() => openCourse(c)}>{c.title}</ActionLink>
          </div>
        ))}
        {showForecast && renderForecast()}
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
                <CandidateOverlaps course={course} index={candidateIndex} onOpenCourse={openCourse} />
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
                  {course.period} · {slots.map(slotTitle).join("、")} ·{" "}
                  {state.status[course.code] ?? "履修予定"}
                </small>
              </li>
            ))}
          </ul>
          <div className="actions">
            <Button
              label="今の予定を残す"
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
