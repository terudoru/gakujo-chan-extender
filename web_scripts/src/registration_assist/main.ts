export {};

type Config = {
  command: "inspect" | "semester" | "add" | "search" | "highlight" | "back" | "clear";
  href: string;
  documentId?: number;
  year?: number;
  semester?: number;
  slot?: string;
  code?: string;
  ticket?: string;
};
type RegistrationWindow = Window & {
  MbgRegistrationChoice?: { postMessage(message: string): void };
  mbgRegistrationHighlight?: { ticket: string; clear(): void };
};
declare const __mbgConfig: Config;

const origin = "https://gakujo.iess.niigata-u.ac.jp";
const heading = "履修登録・登録状況照会";
const codePattern = /^\d{3}[A-Z][A-Z0-9]{4,5}$/;
const weekdays = ["月", "火", "水", "木", "金", "土"];
const documentId = performance.timeOrigin;

function visible(element: Element): boolean {
  if (!element.getClientRects().length ||
      element.closest('[hidden],[inert],[aria-hidden="true"]')) return false;
  for (let parent: Element | null = element; parent; parent = parent.parentElement) {
    const style = getComputedStyle(parent);
    if (style.visibility !== "visible" || style.opacity === "0") return false;
  }
  return true;
}

function label(element: Element): string {
  return (element instanceof HTMLInputElement ? element.value : (element as HTMLElement).innerText || "")
    .normalize("NFKC").replace(/\s+/g, " ").trim();
}

function unique<T>(items: T[]): T | undefined {
  return items.length === 1 ? items[0] : undefined;
}

function controls(scope: ParentNode, text: string, linksOnly = false): HTMLElement[] {
  const selector = linksOnly ? "a" : 'a,button,input[type="submit"],input[type="button"]';
  return Array.from(scope.querySelectorAll<HTMLElement>(selector)).filter((element) =>
    visible(element) && label(element) === text &&
    !element.closest(':disabled,[aria-disabled="true"]'));
}

function portalUrl(url: URL) {
  return url.origin === origin && !url.username && !url.password &&
    /^\/campusweb\/(?:[^/]+\/)*campussquare\.do(?:;jsessionid=[^/;]+)?$/.test(url.pathname);
}

type NavigationLabel = "追加" | "第1学期" | "第2学期" | "検索開始" | "戻る";

function canNavigate(element: HTMLElement | undefined, name: NavigationLabel): element is HTMLElement {
  if (!element || !element.isConnected || !visible(element) || label(element) !== name) return false;
  if (element instanceof HTMLAnchorElement) {
    if (element.hasAttribute("download") || (element.target && element.target !== "_self")) return false;
    const href = element.getAttribute("href")?.trim() || "";
    if (href && !href.startsWith("#") && !/^javascript:void\(0\);?$/i.test(href) &&
        !portalUrl(new URL(href, location.href))) return false;
  } else if (element instanceof HTMLButtonElement || element instanceof HTMLInputElement) {
    const form = element.form;
    if (form) {
      const target = element.getAttribute("formtarget") ?? form.target;
      const action = element.getAttribute("formaction") || form.action;
      if ((target && target !== "_self") || !portalUrl(new URL(action, location.href))) return false;
    }
  }
  return true;
}

// Every programmatic click passes through this closed label allowlist.
function navigate(element: HTMLElement | undefined, name: NavigationLabel) {
  if (!canNavigate(element, name)) return false;
  element.click();
  return true;
}

function rows(table: HTMLTableElement) {
  return Array.from(table.rows).filter((row) => visible(row) &&
    Array.from(row.cells).every((cell) => visible(cell) && cell.rowSpan === 1 && cell.colSpan === 1));
}

function season(text: string): number | undefined {
  if (text === "第1学期") return 1;
  if (text === "第2学期") return 2;
  return undefined;
}

function timetable(table: HTMLTableElement) {
  const all = rows(table);
  const header = unique(all.filter((row) => {
    const labels = Array.from(row.cells, label);
    return weekdays.every((day) => labels.filter((s) => s === day || s === day + "曜日").length === 1);
  }));
  if (!header) return null;
  const columns = Array.from(header.cells, label);
  const add: Record<string, HTMLAnchorElement> = {};
  const codes = new Set<string>();
  const periods = all.filter((row) => row.rowIndex > header.rowIndex &&
    row.cells.length === columns.length && /^(?:[1-7]限|HT)$/.test(label(row.cells[0])));
  if (!periods.length ||
      new Set(periods.map((row) => label(row.cells[0]))).size !== periods.length) return null;
  for (const row of periods) {
    const period = label(row.cells[0]).match(/^([1-7])限$/)?.[1];
    for (const day of weekdays) {
      const cell = row.cells[columns.findIndex((s) => s === day || s === day + "曜日")];
      for (const link of Array.from(cell.querySelectorAll('div.tblDivNml a[onclick*="CallDetail("]'))) {
        const code = label(link).match(/^\??\s*(\d{3}[A-Z][A-Z0-9]{4,5})(?:\s*\(T[\d,\s～~-]+\))?$/)?.[1];
        const detailCode = link.getAttribute("onclick")?.match(
          /\bCallDetail\(\s*'\d{4}'\s*,\s*'[A-Za-z0-9]+'\s*,\s*'(\d{3}[A-Z][A-Z0-9]{4,5})'/,
        )?.[1];
        if (code && code === detailCode && visible(link)) codes.add(code);
      }
      const link = unique(controls(cell, "追加", true));
      if (link instanceof HTMLAnchorElement && period) add[day + period] = link;
    }
  }
  const panel = table.closest('[role="tabpanel"]');
  const namedBy = panel?.getAttribute("aria-labelledby");
  const name = panel?.getAttribute("aria-label") ||
    (namedBy ? document.getElementById(namedBy)?.innerText : "") ||
    (table.caption ? label(table.caption) : "");
  return { semester: season(name?.trim() || ""), add, codes: Array.from(codes) };
}

function message(): string {
  const messages = Array.from(document.querySelectorAll('[role="alert"],[aria-live="assertive"]'))
    .filter(visible).map(label).filter((value) => value.length <= 140 &&
      !/https?:|[@<>]|学籍番号|在籍番号|学生番号|氏名|メールアドレス|電話番号|\b\d{2}[A-Za-z]\d{4}[A-Za-z]\b|\d{7,}/i.test(value) &&
      // Restrict to known message shapes with no interpolated free text.
      /^(?:履修登録期間外です|履修登録できません|履修登録できない科目です|既に登録されています|定員に達しています|時間割が重複しています|単位数の上限を超えています)[。.!]?$/.test(value));
  return unique(messages) || "";
}

function grid(tables: HTMLTableElement[]) {
  const selected = Array.from(document.querySelectorAll("th,td")).filter(
    (cell) => visible(cell) && label(cell) === "年度・学期" && cell.nextElementSibling &&
      visible(cell.nextElementSibling),
  ).map((cell) => label(cell.nextElementSibling!).match(/^(\d{4})年度\s*第([12])学期$/));
  const term = unique(selected);
  if (!term) return null;
  const semester = Number(term[2]);
  const timetables = tables.map(timetable).filter((table) => table !== null);
  if (timetables.length === 1 && timetables[0].semester === undefined) {
    timetables[0].semester = semester;
  }
  const current = unique(timetables.filter((t) => t.semester === semester));
  if (!current) return null;
  const slots: Record<string, string[]> = {};
  for (const t of timetables) {
    if (!t.semester || slots[t.semester]) return null;
    slots[t.semester] = Object.keys(t.add);
  }
  return {
    year: Number(term[1]), semester, current, slots,
    registered: Array.from(new Set(timetables.flatMap((t) => t.codes))),
  };
}

function field(form: HTMLFormElement, text: string, selector: string): Element | undefined {
  const labelled = Array.from(form.querySelectorAll("label")).filter((l) => visible(l) && label(l) === text)
    .map((l) => l.control).filter((el): el is HTMLElement => el !== null && el.matches(selector));
  const adjacent = Array.from(form.querySelectorAll("th,td")).filter(
    (cell) => visible(cell) && label(cell) === text && cell.nextElementSibling,
  ).flatMap((cell) => Array.from(cell.nextElementSibling!.querySelectorAll(selector)));
  return unique(Array.from(new Set([...labelled, ...adjacent])).filter((el) =>
    visible(el) && !el.matches(":disabled") &&
    (el as HTMLInputElement | HTMLSelectElement).form === form));
}

function run() {
  const config = __mbgConfig;
  const view = window as RegistrationWindow;
  const url = new URL(location.href);
  const flowIds = url.searchParams.getAll("_flowId");
  const flow = flowIds.length === 1 && flowIds[0] === "RSW0001000-flow";
  const execution = url.searchParams.getAll("_flowExecutionKey");
  if (window !== window.top || !portalUrl(url) || config.href !== url.href ||
      (config.command !== "inspect" && config.documentId !== documentId) ||
      (!flow && (flowIds.length || execution.length !== 1 || !/^e\d+s\d+$/.test(execution[0]))) ||
      Array.from(document.querySelectorAll('input[type="password"],input[name="ninshoCode"]')).some(visible)) {
    return null;
  }
  const headings = Array.from(document.querySelectorAll("h1,h2,h3,h4,caption,th,td,legend,.title,.pageTitle"))
    .filter((element) => visible(element) && !element.closest("nav,a,button,[role=menu]") &&
      !element.querySelector("table,th,td,a,button,input,select"))
    .map((element) => label(element).replace(/\s/g, ""));
  if (!headings.some((text) => text === heading || text === heading + "/条件入力" ||
      text === heading + "/検索結果")) return null;

  if (config.command === "clear") {
    if (view.mbgRegistrationHighlight?.ticket === config.ticket) {
      view.mbgRegistrationHighlight?.clear();
    }
    return null;
  }
  const tables = Array.from(document.querySelectorAll("table")).filter(visible);
  const results = tables.flatMap((table) => rows(table).filter((row) => {
    const names = Array.from(row.cells, label);
    return ["開講番号", "選択", "優先度", "科目名"].every((s) => names.filter((n) => n === s).length === 1);
  }).map((header) => ({ table, header })));
  const result = unique(results);
  const timetableGrid = grid(tables);
  if (results.length && timetableGrid) return null;
  if (timetableGrid) {
    const { year, semester, current, slots, registered } = timetableGrid;
    if (config.command === "inspect") {
      return { page: "grid", documentId, year, semester, slots, registered, message: message() };
    }
    if (config.year !== year || ![1, 2].includes(config.semester!)) return null;
    if (config.command === "semester" && config.semester !== semester) {
      const name = config.semester === 1 ? "第1学期" : "第2学期";
      return navigate(unique(controls(document, name)), name);
    }
    if (config.command === "add" && config.semester === semester &&
        config.slot && /^[月火水木金土][1-7]$/.test(config.slot) &&
        config.code && codePattern.test(config.code) && !registered.includes(config.code)) {
      return navigate(current.add[config.slot], "追加");
    }
    return null;
  }

  if (!config.code || !codePattern.test(config.code)) return null;
  if (result) {
    const { table, header } = result;
    const names = Array.from(header.cells, label);
    const codeColumn = names.indexOf("開講番号");
    const codeIn = (row: HTMLTableRowElement) => row.cells[codeColumn]?.innerText.trim();
    const matches = rows(table).filter((row) => row.rowIndex > header.rowIndex &&
      row.cells.length === names.length && codeIn(row) === config.code);
    const link = matches.length === 1 ? unique(controls(matches[0].cells[names.indexOf("選択")], "選択", true)) : undefined;
    if (config.command === "inspect") return { page: "results", documentId, count: matches.length, selectable: !!link };
    if (config.command === "back") return navigate(unique(controls(document, "戻る")), "戻る");
    if (config.command !== "highlight" || !link || !config.ticket) return null;
    const ticket = config.ticket;
    view.mbgRegistrationHighlight?.clear();
    const elements = [matches[0], link];
    const previous = elements.map((el) => el.style.outline);
    const onChoice = (event: MouseEvent) => {
      if (event.isTrusted && event.target instanceof Node && link.contains(event.target) &&
          visible(link) && label(link) === "選択" &&
          codeIn(matches[0]) === config.code) {
        view.MbgRegistrationChoice?.postMessage(ticket);
      }
    };
    view.mbgRegistrationHighlight = {
      ticket,
      clear() {
        elements.forEach((el, index) => { el.style.outline = previous[index]; });
        document.removeEventListener("click", onChoice, true);
        delete view.mbgRegistrationHighlight;
      },
    };
    document.addEventListener("click", onChoice, true);
    elements.forEach((el) => { el.style.outline = "3px solid #bf6000"; });
    link.scrollIntoView({ block: "center", inline: "nearest" });
    return true;
  }
  if (results.length) return null;

  const condition = unique(Array.from(document.forms).filter((form) =>
    controls(form, "検索開始").length === 1));
  if (!condition ||
      !headings.some((text) => text === "条件入力" || text === heading + "/条件入力")) return null;
  const input = field(condition, "開講番号", 'input[type="text"],input:not([type])');
  if (!(input instanceof HTMLInputElement) || input.readOnly) return null;
  if (config.command === "inspect") return { page: "condition", documentId };
  if (config.command === "back") return navigate(unique(controls(condition, "戻る")), "戻る");
  if (config.command !== "search") return null;
  const faculty = field(condition, "開講所属", "select");
  const weekday = field(condition, "曜日", "select");
  const period = field(condition, "時限", "select");
  const search = unique(controls(condition, "検索開始"));
  if (!(faculty instanceof HTMLSelectElement) || !(weekday instanceof HTMLSelectElement) ||
      !(period instanceof HTMLSelectElement) || !canNavigate(search, "検索開始") ||
      !config.slot ||
      ![config.slot[0], config.slot[0] + "曜日"].includes(weekday.selectedOptions[0]?.text.normalize("NFKC").trim()) ||
      ![config.slot[1], config.slot[1] + "限"].includes(period.selectedOptions[0]?.text.normalize("NFKC").trim())) return null;
  const option = unique(Array.from(faculty.options).filter((o) =>
    o.text.trim() === "指示なし" && !o.disabled && !o.closest("optgroup:disabled")));
  if (option) faculty.selectedIndex = option.index;
  input.value = config.code;
  return navigate(search, "検索開始");
}

__mbgEntryResult = JSON.stringify(run());
