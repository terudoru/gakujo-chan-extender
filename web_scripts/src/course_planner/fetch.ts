import {
  extractor,
  liveView,
  names,
  normalized,
  origin,
  staticView,
  studentInquiryName,
  withinBounds,
  type Kind,
  type Packet,
  type Table,
  type TimetableSnapshot,
} from "./extract.js";

declare const __mbgConfig: { attempt: string };

// Reads the inquiry pages in the background so the student need not open
// them. It only issues same-origin GET requests that start an inquiry flow,
// plus the registration page's own semester tabs; it never submits a form,
// clicks, or navigates the displayed page.

type Source = "grades" | "registration";
type Page = { source: Source; doc: Document; href: string };

const order: Kind[] = ["profile", "grades", "balances", "registration"];
// Already requested in production by calendar_registration_page_fetch.
const registrationFallback =
  "/campusweb/campussquare.do?_flowId=RSW0001000-flow";
// The 単位修得状況照会 portlet flow.
const gradesFallback =
  "/campusweb/campussquare.do?_flowId=SIW0001300-flow";
const maxPageLength = 4 * 1024 * 1024;
const requestTimeout = 8000;
const captureTimeout = 60000;
const balancePdfLimit = 2 * 1024 * 1024;
type Term = Pick<TimetableSnapshot, "year" | "semester">;
type Target = { path: string; year?: string; semester: Term["semester"] };

type CaptureBridge = {
  take(attempt: string): string | null;
  cancel(attempt?: string): void;
};
const host = window as Window & { __mbgPlannerFetch?: CaptureBridge };

function servlet(url: URL) {
  return /^\/campusweb\/campussquare\.do(?:;jsessionid=[^/;]*)?$/i.test(
    url.pathname,
  );
}
function parse(raw: string, base: string) {
  try {
    const url = new URL(raw.trim(), base);
    return url.origin === origin && !url.username && !url.password && servlet(url)
      ? url
      : null;
  } catch {
    return null;
  }
}
/** A request that starts an inquiry flow and carries no event. */
function inquiryUrl(raw: string, base: string) {
  const url = parse(raw.replace(/&amp;/g, "&"), base);
  if (!url) return null;
  const keys = Array.from(url.searchParams.keys());
  const flows = url.searchParams.getAll("_flowId");
  if (
    keys.some((k) => /^_eventId/i.test(k) || /^_flowExecutionKey$/i.test(k)) ||
    flows.length !== 1 ||
    !/^[A-Za-z0-9_-]+-flow$/.test(flows[0])
  )
    return null;
  return { path: url.pathname + url.search, flow: flows[0] };
}
/** The registration page's semester tab, as calendar_registration_page_fetch reads it. */
function semesterTarget(raw: string, base: string, year?: string): Target | null {
  const clean = raw.trim().replace(/&amp;/g, "&");
  const url = parse(clean, base);
  const params = url?.searchParams;
  const semester = params?.get("gakkiKbnCode");
  if (
    !url || !params ||
    !Array.from(params.keys()).every((k) =>
      /^(_flowExecutionKey|_flowId|_eventId|gakkiKbnCode|nendo|locale)$/.test(k) && params.getAll(k).length === 1,
    ) ||
    params.get("_eventId") !== "search" ||
    (semester !== "1" && semester !== "2") ||
    (params.has("nendo") && !/^(19|20)\d{2}$/.test(params.get("nendo") || "")) ||
    (params.has("_flowId") && params.get("_flowId") !== "RSW0001000-flow") ||
    (params.has("_flowExecutionKey") && !/^e\d+s\d+$/.test(params.get("_flowExecutionKey") || "")) ||
    (!params.has("_flowId") && !params.has("_flowExecutionKey"))
  )
    return null;
  return {path: url.pathname + url.search, year: params.get("nendo") || year,
    semester: semester === "1" ? "first" : "second"};
}

function frameDocuments(doc: Document, found: Document[], depth = 0) {
  let url: URL;
  try {
    url = new URL(doc.URL);
  } catch {
    return;
  }
  if (url.origin !== origin || !url.pathname.startsWith("/campusweb/")) return;
  found.push(doc);
  if (depth > 4) return;
  for (const frame of Array.from(
    doc.querySelectorAll<HTMLIFrameElement>("iframe,frame"),
  )) {
    try {
      if (frame.contentDocument)
        frameDocuments(frame.contentDocument, found, depth + 1);
    } catch {
      /* Other origins cannot offer the menu. */
    }
  }
}
function quoted(script: string) {
  const values: string[] = [];
  const pattern = /(['"])(.*?)\1/g;
  for (let match = pattern.exec(script); match; match = pattern.exec(script))
    values.push(match[2]);
  return values;
}
/** The menu link whose text names the inquiry, when it names exactly one flow. */
function discover(docs: Document[], title: string) {
  let found: string | null = null;
  const flows = new Set<string>();
  for (const doc of docs)
    for (const el of Array.from(
      doc.querySelectorAll<HTMLElement>(
        'a,button,input[type="button"],input[type="submit"],[onclick]',
      ),
    )) {
      const text =
        el.tagName === "INPUT" ? (el as HTMLInputElement).value : el.textContent;
      if (normalized(text).replace(/\s/g, "") !== title) continue;
      const href = el.getAttribute("href") || "";
      const candidates = [
        ...(/^javascript:/i.test(href.trim()) ? quoted(href) : [href]),
        ...quoted(el.getAttribute("onclick") || ""),
      ];
      for (const raw of candidates) {
        const target = raw.includes("campussquare.do")
          ? inquiryUrl(raw, doc.URL)
          : null;
        if (!target) continue;
        flows.add(target.flow);
        found = found || target.path;
      }
    }
  return flows.size === 1 ? found : null;
}

const sessionExpired = new Error("session-expired");

/** The university's named report may be exposed as a direct same-origin PDF. */
function advertisedBalancePdf(page: Omit<Page, "source">) {
  const candidates = new Set<string>();
  const {visible} = staticView(page.href);
  for (const link of Array.from(page.doc.querySelectorAll<HTMLAnchorElement>("a[href]"))) {
    if (!visible(link)) continue;
    const namesOnLink = [link.textContent, link.title, link.getAttribute("aria-label"),
      ...Array.from(link.querySelectorAll<HTMLImageElement>("img[alt]"), icon => icon.getAttribute("alt"))];
    if (!namesOnLink.some(value => normalized(value).replace(/\s/g, "") === names.balances)) continue;
    const href = link.getAttribute("href") || "";
    try {
      const url = new URL(href, page.href);
      if (url.origin === origin && !url.username && !url.password &&
          (/^\/campusweb\/.*\.pdf$/i.test(url.pathname) ||
            (servlet(url) && link.type.toLowerCase() === "application/pdf")))
        candidates.add(url.origin + url.pathname + url.search);
    } catch {
      /* Unreadable links cannot authorize a download. */
    }
  }
  return candidates.size === 1 ? candidates.values().next().value : undefined;
}

async function readBalancePdf(url: string, signal: AbortSignal, deadline: number) {
  const remaining = deadline - Date.now();
  if (signal.aborted || remaining <= 0) return null;
  const controller = new AbortController();
  const abort = () => controller.abort();
  signal.addEventListener("abort", abort, {once:true});
  const timeout = setTimeout(abort, Math.min(remaining, requestTimeout));
  try {
    const response = await fetch(url, {credentials:"same-origin", redirect:"error", signal:controller.signal});
    if (!response.ok || response.headers.get("Content-Type")?.split(";")[0]?.trim().toLowerCase() !== "application/pdf" ||
        Number(response.headers.get("Content-Length")) > balancePdfLimit || !response.body) return null;
    const reader = response.body.getReader();
    let length = 0;
    const chunks: Uint8Array[] = [];
    for (;;) {
      const {done, value} = await reader.read();
      if (done) break;
      if ((length += value.length) > balancePdfLimit) return null;
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    if (String.fromCharCode(...bytes.subarray(0, 5)) !== "%PDF-") return null;
    let binary = "";
    for (let start = 0; start < length; start += 16384)
      binary += String.fromCharCode(...bytes.subarray(start, start + 16384));
    return btoa(binary);
  } catch {
    return null;
  } finally {
    abort();
    clearTimeout(timeout);
    signal.removeEventListener("abort", abort);
  }
}

async function get(path: string, signal: AbortSignal, deadline: number) {
  const remaining = deadline - Date.now();
  if (signal.aborted || remaining <= 0) return null;
  const xhr = new XMLHttpRequest();
  const abort = () => xhr.abort();
  const loaded = await new Promise<boolean>((resolve) => {
    xhr.open("GET", path);
    xhr.timeout = Math.min(remaining, requestTimeout);
    xhr.onload = () => resolve(true);
    xhr.onerror = xhr.ontimeout = xhr.onabort = () => resolve(false);
    signal.addEventListener("abort", abort, {once:true});
    try { xhr.send(); } catch { resolve(false); }
  }).finally(() => signal.removeEventListener("abort", abort));
  if (!loaded || xhr.status < 200 || xhr.status >= 300 || xhr.responseText.length > maxPageLength)
    return null;
  const href = xhr.responseURL || new URL(path, location.href).href;
  if (new URL(href).origin !== origin) throw sessionExpired;
  const doc = new DOMParser().parseFromString(xhr.responseText, "text/html");
  // A sign-in form in any fetched page means the session has ended: abort all.
  if (doc.querySelector('input[type="password"],input[name="ninshoCode"]'))
    throw sessionExpired;
  return parse(href, location.href) ? {doc, href} : null;
}

const termKey = ({year, semester}: Pick<Target, "year" | "semester">) =>
  (year ?? "") + "/" + semester;

async function fetchInquiries(signal: AbortSignal) {
  const docs: Document[] = [];
  frameDocuments(document, docs);
  if (
    !docs.length ||
    docs.some((d) =>
      Array.from(
        d.querySelectorAll('input[type="password"],input[name="ninshoCode"]'),
      ).some((el) => liveView.visible(el)),
    )
  )
    return null;
  const deadline = Date.now() + captureTimeout;
  const read = (path: string) => get(path, signal, deadline);
  const pages: Page[] = [];
  const grades = await read(discover(docs, names.grades) || gradesFallback);
  if (grades) pages.push({ source: "grades", ...grades });
  // Read affiliation before entering the registration flow, whose links can share a flow key.
  const studentPath = discover(docs, studentInquiryName);
  const studentPage = studentPath ? await read(studentPath) : null;
  const first = await read(discover(docs, names.registration) || registrationFallback);
  const pending = new Map<string, Target>();
  const confirmed = new Set<string>();
  const attempted = new Map<string, Set<string>>();
  const unresolved = new Set<string>();
  function includeRegistration(page: Omit<Page, "source">, target?: Target) {
    const {registrationTerm, pageKinds} = extractor(staticView(page.href));
    const term = registrationTerm(page.doc);
    if (target && (!term || term.semester !== target.semester || (target.year && term.year !== target.year))) return false;
    if (!term && !pageKinds(page.doc).includes("registration")) return false;
    pages.push({ source: "registration", ...page });
    if (term) {
      const key = termKey(term);
      confirmed.add(key);
      unresolved.delete(key);
      pending.delete(key);
    }
    for (const link of Array.from(page.doc.querySelectorAll("a[href]"))) {
      const next = semesterTarget(link.getAttribute("href") || "", page.href, term?.year);
      if (!next) continue;
      const key = termKey(next);
      const seen = attempted.get(key);
      if (confirmed.has(key) || seen?.has(next.path) || (seen && seen.size >= 2)) continue;
      pending.set(key, next);
    }
    return true;
  }
  const rootRead = first && includeRegistration(first);
  const balanceUrl = first && rootRead ? advertisedBalancePdf(first) : undefined;
  // The registration flow's current report takes precedence over the archive.
  const balancePdf = balanceUrl ? await readBalancePdf(balanceUrl, signal, deadline) : null;
  for (const [key, next] of pending) {
    if (signal.aborted || Date.now() >= deadline) break;
    pending.delete(key);
    const seen = attempted.get(key) ?? new Set<string>();
    seen.add(next.path);
    attempted.set(key, seen);
    const page = await read(next.path);
    if (page && includeRegistration(page, next)) unresolved.delete(key);
    else unresolved.add(key);
  }

  const packets: Partial<Record<Kind, Packet>> = {};
  const registration: Table[] = [];
  const timetable = new Map<string, TimetableSnapshot | null>();
  const tableKeys = new Set<string>();
  const years = new Set<string>();
  let yearless = false;
  for (const page of pages) {
    const { pageKinds, packet, timetableSnapshot } = extractor(staticView(page.href));
    if (page.source === "registration") {
      const snapshot = timetableSnapshot(page.doc);
      if (snapshot) {
        const key = snapshot.year + snapshot.semester;
        const previous = timetable.get(key);
        if (previous === undefined) timetable.set(key, snapshot);
        else if (JSON.stringify(previous) !== JSON.stringify(snapshot)) timetable.set(key, null);
      }
    }
    for (const kind of pageKinds(page.doc)) {
      if (
        (kind === "grades" || kind === "registration") &&
        kind !== page.source
      )
        continue;
      if (kind !== "registration" && packets[kind]) continue;
      const found = packet(page.doc, kind);
      if (!found) continue;
      if (kind !== "registration") {
        packets[kind] = found;
        continue;
      }
      // Semester tabs repeat tables that do not depend on the semester.
      for (const table of found.tables) {
        const key = JSON.stringify(table);
        if (!tableKeys.has(key)) {
          tableKeys.add(key);
          registration.push(table);
        }
      }
      if (found.year) years.add(found.year);
      else yearless = true;
    }
  }
  const registrationFits = !registration.length || withinBounds(registration);
  if (registration.length && registrationFits)
    packets.registration = {
      v: 1,
      kind: "registration",
      tables: registration,
      ...(years.size === 1 && !yearless ? { year: Array.from(years)[0] } : {}),
    };
  // Read the student inquiry only when the portal advertises the read-only flow.
  // The official admission-year fact can be separate from the affiliation table.
  if (studentPage) {
    const read = extractor(staticView(studentPage.href));
    const student = read.packet(studentPage.doc, "profile");
    const previous = packets.profile;
    const profile = student || previous;
    const year = read.admissionYear(studentPage.doc);
    if (profile) {
      const {year: oldYear, ...base} = profile;
      packets.profile = year ? {...base, year} : base;
    }
  }
  const ordered: Partial<Record<Kind, Packet>> = {};
  for (const kind of order) if (packets[kind]) ordered[kind] = packets[kind];
  const gradePageRead = grades && extractor(staticView(grades.href)).pageKinds(grades.doc).includes("grades");
  const complete = !!gradePageRead && !!rootRead && (!studentPath || !!studentPage) && (!balanceUrl || !!balancePdf) &&
    registrationFits && pending.size === 0 && unresolved.size === 0 && ![...timetable.values()].includes(null);
  return {v:1, packets:ordered, timetable:[...timetable.values()].filter(value => value !== null), complete,
    ...(balancePdf && {balancePdf})};
}

function start() {
  if (window !== window.top || location.origin !== origin) return null;
  const {attempt} = __mbgConfig;
  host.__mbgPlannerFetch?.cancel();
  const controller = new AbortController();
  let result = "pending";
  const cancel = (owner?: string) => {
    if (owner !== undefined && owner !== attempt) return;
    delete host.__mbgPlannerFetch;
    controller.abort();
    window.removeEventListener("pagehide", leave);
  };
  const leave = () => cancel();
  window.addEventListener("pagehide", leave, {once:true});
  host.__mbgPlannerFetch = {
    take(owner) {
      if (owner !== attempt) return null;
      if (result !== "pending") cancel(attempt);
      return result;
    },
    cancel,
  };
  void fetchInquiries(controller.signal).then(
    (capture) => {
      result = JSON.stringify(capture);
      if (capture?.balancePdf && result.length > 7 * 1024 * 1024) {
        const {balancePdf, ...inquiries} = capture;
        result = JSON.stringify({...inquiries, complete:false});
      }
    },
    () => { result = "null"; },
  );
  return result;
}

__mbgEntryResult = start();
