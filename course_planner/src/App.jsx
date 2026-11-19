import React, { useCallback, useEffect, useMemo, useState } from "react";
import { Heading } from "@astryxdesign/core/Heading";
import { SideNav, SideNavItem } from "@astryxdesign/core/SideNav";
import {
  ArrowUpRight,
  BookMarked,
  CalendarDays,
  ChevronRight,
  CloudSync,
  GraduationCap,
  LibraryBig,
  Search,
  X,
} from "lucide-react";
import { GAKUJO, activeCourses, initialState, readShare, spansSemesters, termsFor } from "./study.mjs";
import { SemesterCreditSplit } from "./components/SemesterCreditSplit.jsx";
import { changeLocal, loadLocal, STORAGE_KEY } from "./storage.mjs";
import { Timetable } from "./Timetable.jsx";
import { Discovery } from "./Discovery.jsx";
import { Lists, SharedList } from "./Lists.jsx";
import { Requirements } from "./Requirements.jsx";
import { availableStages, handbooks, requirementRows, selectedStage, shortageFilter } from "./requirements.mjs";
import { matchHistoricalGrades, revalidateGradeMatch } from "./archive/packs.mjs";
import { CandidateOverlaps } from "./components/CandidateOverlaps.jsx";
import { buildCandidateMeetings } from "./components/candidate-overlaps.mjs";
import { SyllabusFacts } from "./components/SyllabusFacts.jsx";
import { PlannerImportPanel } from "./imports/PlannerImportPanel.jsx";
import { installPlannerImportListener } from "./imports/native.mjs";
import { SyncPanel } from "./sync/SyncPanel.jsx";
import {
  AddCourse,
  Button,
  ListPicker,
  Modal,
  PlannerError,
  Select,
} from "./ui.jsx";

const pages = [
  ["week", "時間割", CalendarDays],
  ["search", "授業を探す", Search],
  ["lists", "候補リスト", BookMarked],
  ["credits", "単位・要件", GraduationCap],
  ["sync", "同期", CloudSync],
];
const descriptions = {
  search: "新潟大学の開講科目",
  lists: "保存した授業",
  credits: "修得単位と履修後の見込み",
  sync: "利用する端末と同期項目",
};
function init() {
  try {
    return { state: loadLocal() };
  } catch (e) {
    return { state: initialState(), error: e.message };
  }
}
function shareFromURL(year) {
  try {
    return { data: readShare(location.hash, year) };
  } catch (e) {
    return { error: e.message };
  }
}
export function App({ catalog }) {
  const [initial] = useState(init),
    [state, setState] = useState(initial.state),
    [error, setError] = useState(initial.error ?? "");
  const [page, setPage] = useState("week"),
    [term, setTerm] = useState(1),
    [slot, setSlot] = useState("月1");
  const [context, setContext] = useState({}),
    [listId, setListId] = useState("mine"),
    [course, setCourse] = useState(null);
  const [reopenSlot, setReopenSlot] = useState(false);
  const [creditGoal, setCreditGoal] = useState("graduation");
  const [creditView, setCreditView] = useState("rules");
  const [selectedStages, setSelectedStages] = useState({});
  const [imports, setImports] = useState([]);
  const pendingImport = imports[0];
  const [sharing, setSharing] = useState(() => shareFromURL(catalog.year));
  const byCode = useMemo(
    () => new Map(catalog.courses.map((c) => [c.code, c])),
    [catalog],
  );
  const checkedGrades = useMemo(() => state.grades.map((grade) => {
    if (!grade.matchedCourse?.confirmed) return grade;
    const match = revalidateGradeMatch(grade, catalog);
    return { ...grade, matchedCourse: match, fields: match?.fields ?? [], category: match?.category ?? "",
      matchStatus: match ? "confirmed" : "unresolved" };
  }), [state.grades, catalog]);
  const assessment = useMemo(() => ({ ...state, grades: checkedGrades }), [state, checkedGrades]);
  const list = state.lists.find((l) => l.id === listId) ?? state.lists[0];
  const stages = useMemo(() => availableStages(state.profile, creditGoal), [state.profile, creditGoal]);
  function stageScopeFor(goal) {
    const { faculty, handbook, admitted, program, entry, department, field, individual, curriculum } = state.profile;
    return JSON.stringify([faculty, handbook, admitted, program, entry, department, field, individual, curriculum, goal]);
  }
  const stageScope = stageScopeFor(creditGoal);
  const chosenStage = selectedStages[stageScope];
  const selector = stages.some((stage) => stage.id === chosenStage) ? chosenStage : creditGoal;
  const planned = useMemo(() => activeCourses(state, byCode), [state.plan, state.status, byCode]);
  const candidateIndex = useMemo(
    () => buildCandidateMeetings(state.lists, byCode),
    [state.lists, byCode],
  );
  const rows = useMemo(
    () => page === "credits" || pendingImport
      ? requirementRows(assessment, byCode, planned, selector)
      : [],
    [assessment, byCode, planned, page, selector, pendingImport],
  );
  const defaultStage = useMemo(() => selectedStage(state.profile, selector), [state.profile, selector]);
  const stageId = rows[0]?.stageId ?? defaultStage?.id ?? "";
  const matchesRequirement = useMemo(() => {
    if (page !== "search" || !context.requirement) return undefined;
    return shortageFilter(assessment, byCode, planned, context);
  }, [assessment, byCode, planned, page, context]);
  const prepareGrades = useCallback(
    (incoming, previous) => matchHistoricalGrades(incoming, catalog, previous),
    [catalog],
  );
  const importTargets = useMemo(() => {
    if (!pendingImport) return [];
    const known = new Set(rows.map((r) => r.key));
    return [...rows.filter((row) => row.unit === "credits"), ...Object.entries(catalog.fields)
      .filter(([id]) => !known.has("field-" + id))
      .map(([id, name]) => ({
        key: "field-" + id, label: "分野 " + id + " " + name, kind: "分野", required: null,
      }))];
  }, [catalog.fields, rows, pendingImport]);
  function requestImport(source) {
    const item = { ...source, id: crypto.randomUUID() };
    setImports((queue) => [...queue, item]);
  }
  useEffect(() => installPlannerImportListener(
    (packet) => requestImport({ packet }),
    (err) => setError(err.message),
  ), []);
  useEffect(() => {
    function fromSyllabus() {
      const match = /^#course=(\d{4})-(\d{3}[A-Z][A-Z0-9]{4,5})$/.exec(
        location.hash,
      );
      if (!match) return;
      if (Number(match[1]) === catalog.year && byCode.has(match[2]))
        setCourse(byCode.get(match[2]));
      else setError("この年度・科目の開講情報は要確認です。");
    }
    fromSyllabus();
    window.addEventListener("hashchange", fromSyllabus);
    return () => window.removeEventListener("hashchange", fromSyllabus);
  }, [catalog, byCode]);
  useEffect(() => {
    const reload = (e) => {
      if (e.key !== STORAGE_KEY && e.key !== null) return;
      try {
        setState(loadLocal());
      } catch (e) {
        setError(e.message);
      }
    };
    const hash = () => setSharing(shareFromURL(catalog.year));
    window.addEventListener("storage", reload);
    window.addEventListener("hashchange", hash);
    return () => {
      window.removeEventListener("storage", reload);
      window.removeEventListener("hashchange", hash);
    };
  }, [catalog.year]);
  async function mutate(update) {
    try {
      setState(await changeLocal(update));
      setError("");
      return true;
    } catch (e) {
      setError(e.message ?? "端末に保存できませんでした。");
      return false;
    }
  }
  function leaveShare() {
    history.replaceState(null, "", location.pathname + location.search);
    setSharing({});
  }
  function navigate(to) {
    leaveShare();
    setCourse(null);
    setContext({});
    setReopenSlot(false);
    setPage(to);
    window.scrollTo(0, 0);
  }
  function returnFromSearch() {
    const fromSlot = !!context.slot;
    navigate(context.requirement ? "credits" : "week");
    if (context.requirement) setContext({ requirement: context.requirement });
    setReopenSlot(fromSlot);
  }
  function search(filter = {}) {
    setContext(filter);
    setPage("search");
    window.scrollTo(0, 0);
  }
  async function copy() {
    const id = crypto.randomUUID();
    if (
      await mutate((s) => {
        let name = sharing.data.name;
        const names = new Set(s.lists.map((item) => item.name));
        for (let i = 1; names.has(name); i++) {
          const suffix = i === 1 ? "（コピー）" : "（コピー " + i + "）";
          name =
            [...sharing.data.name].slice(0, 80 - [...suffix].length).join("") +
            suffix;
        }
        s.lists.push({ id, name, codes: [...sharing.data.codes] });
      })
    ) {
      leaveShare();
      setListId(id);
      setPage("lists");
    }
  }
  const current = pages.find((p) => p[0] === page);
  const status = course && state.status[course.code];

  return (
    <PlannerError.Provider value={error}>
      <div className="workspace">
        <a className="skip" href="#planner-main">
          本文へ移動
        </a>
        <aside className="sidebar">
          <div className="brand">
            <span className="brand-symbol">
              <LibraryBig size={23} strokeWidth={1.7} />
            </span>
            <div>
              <b>履修プランナー</b>
              <span>More Better Gakujo</span>
            </div>
          </div>
          <div className="desktop-nav">
            <SideNav aria-label="プランナーのメニュー" className="nav-items">
              {pages.map(([id, name, Icon]) => (
                <SideNavItem
                  key={id}
                  label={name}
                  icon={<Icon size={18} />}
                  isSelected={!sharing.data && id === page}
                  onClick={() => navigate(id)}
                />
              ))}
            </SideNav>
          </div>
          <nav className="mobile-nav" aria-label="プランナーのメニュー">
            {pages.map(([id, name, Icon]) => (
              <button
                key={id}
                aria-current={!sharing.data && id === page ? "page" : undefined}
                onClick={() => navigate(id)}
              >
                <Icon size={14} />
                {name}
              </button>
            ))}
          </nav>
          <div className="rail-foot">
            <BookMarked size={17} />
            <a
              className="external"
              href={catalog.listing}
              target="_blank"
              rel="noreferrer"
            >
              大学の開設一覧 <ArrowUpRight size={13} />
            </a>
          </div>
        </aside>
        <main id="planner-main" className="work-main">
          <header className="topline">
            <span>
              新潟大学 <ChevronRight size={13} /> 学部履修
            </span>
            <a href={GAKUJO} target="_blank" rel="noopener noreferrer">
              学務で申請 <ArrowUpRight size={14} />
            </a>
          </header>
          {(error || sharing.error) && (
            <div role="alert" className="error-bar">
              <span>{error || sharing.error}</span>
              <button
                aria-label="メッセージを閉じる"
                onClick={() => {
                  setError("");
                  if (sharing.error) leaveShare();
                }}
              >
                <X size={15} />
              </button>
            </div>
          )}
          {sharing.data ? (
            <SharedList
              list={sharing.data}
              byCode={byCode}
              copy={copy}
              dismiss={() => navigate("week")}
            />
          ) : (
            <>
              <div className="page-head">
                <div className="meta-line">
                  {catalog.year}年度
                  {page === "week"
                    ? "　/　" + (term <= 2 ? "第1学期" : "第2学期")
                    : ""}
                </div>
                <div className="split">
                  <Heading level={1}>{current[1]}</Heading>
                  {page === "week" && (
                    <Button
                      label="授業を探す"
                      icon={<Search size={16} />}
                      variant="secondary"
                      onClick={() => search()}
                    />
                  )}
                </div>
                {page === "week" ? (
                  <p>コマを選んで、その時限の授業を比較できます。</p>
                ) : (
                  <p>
                    {descriptions[page]}
                    {page === "search"
                      ? "　" +
                        catalog.courses.length.toLocaleString("ja-JP") +
                        "件"
                      : ""}
                  </p>
                )}
              </div>
              {page === "week" && (
                <Timetable
                  state={assessment}
                  {...{
                    byCode,
                    catalog,
                    term,
                    setTerm,
                    slot,
                    setSlot,
                    mutate,
                    search,
                    reopenSlot,
                    candidateIndex,
                  }}
                  requirements={(row) => {
                    navigate("credits");
                    if (!row) return;
                    setCreditView("rules");
                    setCreditGoal(row.goal);
                    setSelectedStages((old) => ({ ...old, [stageScopeFor(row.goal)]: row.stageId }));
                    setContext({ requirement: row.key });
                  }}
                  fieldSelector={selector}
                  importRegistration={() => requestImport({ kind: "registration" })}
                  openCourse={setCourse}
                />
              )}
              {page === "search" && (
                <Discovery
                  key={JSON.stringify(context)}
                  {...{
                    catalog,
                    state,
                    byCode,
                    context,
                    list,
                    setListId,
                    mutate,
                  }}
                  openCourse={setCourse}
                  returnTo={returnFromSearch}
                  matchesRequirement={matchesRequirement}
                />
              )}
              {page === "lists" && (
                <Lists
                  {...{ state, byCode, mutate, candidateIndex }}
                  base={location.href}
                  year={catalog.year}
                  activeId={list.id}
                  setId={setListId}
                  openCourse={setCourse}
                  search={() => search()}
                />
              )}
              {page === "credits" && (
                <Requirements
                  {...{ state, assessment, catalog, byCode, mutate, search, rows, requestImport }}
                  {...{ stages, stageId, handbooks }}
                  setStage={(id) => setSelectedStages((old) => ({ ...old, [stageScope]: id }))}
                  returnKey={context.requirement}
                  goal={creditGoal}
                  setGoal={setCreditGoal}
                  view={creditView}
                  setView={setCreditView}
                />
              )}
            </>
          )}
          <SyncPanel
            state={state}
            setState={setState}
            catalog={catalog}
            visible={!sharing.data && page === "sync"}
          />
        </main>
        {course && (
          <Modal title="授業の詳細" close={() => setCourse(null)}>
            <SyllabusFacts course={course} fields={catalog.fields} year={catalog.year} />
            <CandidateOverlaps course={course} index={candidateIndex} onOpenCourse={setCourse} />
            <ListPicker lists={state.lists} id={list.id} setId={setListId} />
            <AddCourse
              course={course}
              list={list}
              mutate={mutate}
              onAdded={
                page === "search" && context.slot ? returnFromSearch : undefined
              }
            />
            {(state.plan.includes(course.code) || status) && (
              <>
                <hr />
                <div className="detail-line">
                  <span>登録状況</span>
                  <strong>{status ?? "履修予定"}</strong>
                </div>
                <Select
                  label="CAPの扱い"
                  value={state.capOverrides[course.code] ?? "便覧に従う"}
                  options={["便覧に従う", "除外", "算入"]}
                  change={(v) =>
                    mutate((s) => {
                      if (v === "便覧に従う")
                        delete s.capOverrides[course.code];
                      else s.capOverrides[course.code] = v;
                    })
                  }
                />
                {spansSemesters(termsFor(course)) && (
                  <SemesterCreditSplit course={course} split={state.semesters[course.code]}
                    onSave={(split, original) => mutate((s) => {
                      const latest = s.semesters[course.code];
                      if (latest?.first !== original?.first || latest?.second !== original?.second)
                        throw Error("この授業の学期別単位が更新されました。授業の詳細を開き直して確認してください。");
                      if (split === null) delete s.semesters[course.code];
                      else s.semesters[course.code] = split;
                    })} />
                )}
                {state.plan.includes(course.code) &&
                  !["許可", "申請中"].includes(status) && (
                    <Button
                      label="時間割から外す"
                      variant="secondary"
                      onClick={async () => {
                        if (
                          await mutate((s) => {
                            if (
                              ["許可", "申請中"].includes(s.status[course.code])
                            )
                              throw Error("学務の登録状況を確認してください。");
                            s.plan = s.plan.filter((k) => k !== course.code);
                          })
                        )
                          setCourse(null);
                      }}
                    />
                  )}
              </>
            )}
          </Modal>
        )}
        {pendingImport && (
          <PlannerImportPanel
            key={pendingImport.id}
            {...pendingImport}
            {...{ state, byCode, mutate }}
            catalogYear={catalog.year}
            goal={creditGoal}
            stage={stageId}
            prepareGrades={prepareGrades}
            requirementRows={importTargets}
            onClose={() => setImports((queue) => queue.filter((item) => item.id !== pendingImport.id))}
          />
        )}
      </div>
    </PlannerError.Provider>
  );
}
