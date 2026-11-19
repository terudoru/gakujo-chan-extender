import React, { useEffect, useMemo, useState } from "react";
import { Heading } from "@astryxdesign/core/Heading";
import { SideNav, SideNavItem } from "@astryxdesign/core/SideNav";
import {
  ArrowUpRight,
  BookMarked,
  CalendarDays,
  ChevronRight,
  GraduationCap,
  LibraryBig,
  Search,
  X,
} from "lucide-react";
import { GAKUJO, STATUS, initialState, readShare } from "./study.mjs";
import { changeLocal, loadLocal, STORAGE_KEY } from "./storage.mjs";
import { Timetable } from "./Timetable.jsx";
import { Discovery } from "./Discovery.jsx";
import { Lists, SharedList } from "./Lists.jsx";
import { Requirements } from "./Requirements.jsx";
import {
  AddCourse,
  Button,
  CourseLine,
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
];
const descriptions = {
  search: "新潟大学の開講科目",
  lists: "保存した授業",
  credits: "修得単位と履修後の見込み",
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
  const [sharing, setSharing] = useState(() => shareFromURL(catalog.year));
  const byCode = useMemo(
    () => new Map(catalog.courses.map((c) => [c.code, c])),
    [catalog],
  );
  const list = state.lists.find((l) => l.id === listId) ?? state.lists[0];
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
                  {...{
                    state,
                    byCode,
                    catalog,
                    term,
                    setTerm,
                    slot,
                    setSlot,
                    mutate,
                    search,
                    reopenSlot,
                  }}
                  requirements={() => navigate("credits")}
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
                />
              )}
              {page === "lists" && (
                <Lists
                  {...{ state, byCode, mutate }}
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
                  {...{ state, catalog, byCode, mutate, search }}
                  goal={creditGoal}
                  setGoal={setCreditGoal}
                  view={creditView}
                  setView={setCreditView}
                />
              )}
            </>
          )}
        </main>
        {course && (
          <Modal title="授業の詳細" close={() => setCourse(null)}>
            <CourseLine course={course} fields={catalog.fields} details />
            <div className="detail-line">
              <span>開設一覧の科目区分</span>
              <strong>{course.category || "要確認"}</strong>
            </div>
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
                <Select
                  label="学務で確認した登録状況"
                  value={status ?? "履修予定"}
                  options={STATUS}
                  change={(value) =>
                    mutate((s) => {
                      s.status[course.code] = value;
                    })
                  }
                />
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
      </div>
    </PlannerError.Provider>
  );
}
