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
} from "./extract.js";

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
const maxSemesters = 4;

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
function semesterUrl(raw: string, base: string) {
  const clean = raw.trim().replace(/&amp;/g, "&");
  const url = parse(clean, base);
  const params = url?.searchParams;
  if (
    !url || !params ||
    !Array.from(params.keys()).every((k) =>
      /^(_flowExecutionKey|_flowId|_eventId|gakkiKbnCode|nendo|locale)$/.test(k) && params.getAll(k).length === 1,
    ) ||
    params.get("_eventId") !== "search" ||
    !/^[0-9]+$/.test(params.get("gakkiKbnCode") || "") ||
    (params.has("nendo") && !/^(19|20)\d{2}$/.test(params.get("nendo") || "")) ||
    (params.has("_flowId") && params.get("_flowId") !== "RSW0001000-flow") ||
    (params.has("_flowExecutionKey") && !/^e\d+s\d+$/.test(params.get("_flowExecutionKey") || "")) ||
    (!params.has("_flowId") && !params.has("_flowExecutionKey"))
  )
    return null;
  return url.pathname + url.search;
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

function get(path: string): { doc: Document; href: string } | null {
  const xhr = new XMLHttpRequest();
  xhr.open("GET", path, false);
  try { xhr.send(null); } catch { return null; }
  if (xhr.status < 200 || xhr.status >= 300) return null;
  if (xhr.responseText.length > maxPageLength) return null;
  const doc = new DOMParser().parseFromString(xhr.responseText, "text/html");
  // A sign-in form in any fetched page means the session has ended: abort all.
  if (doc.querySelector('input[type="password"],input[name="ninshoCode"]'))
    throw sessionExpired;
  const href = xhr.responseURL || new URL(path, location.href).href;
  if (!parse(href, location.href)) return null;
  return { doc, href };
}

function fetchInquiries() {
  if (window !== window.top || location.origin !== origin) return null;
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
  const pages: Page[] = [];
  const grades = discover(docs, names.grades) || gradesFallback;
  if (grades) {
    const page = get(grades);
    if (page) pages.push({ source: "grades", ...page });
  }
  const first = get(discover(docs, names.registration) || registrationFallback);
  if (first) {
    pages.push({ source: "registration", ...first });
    const seen = new Set<string>();
    for (const link of Array.from(first.doc.querySelectorAll("a[href]"))) {
      const path = semesterUrl(link.getAttribute("href") || "", first.href);
      if (!path || seen.has(path) || seen.size >= maxSemesters) continue;
      seen.add(path);
      const page = get(path);
      if (page) pages.push({ source: "registration", ...page });
    }
  }

  const packets: Partial<Record<Kind, Packet>> = {};
  const registration: Table[] = [];
  const tableKeys = new Set<string>();
  const years = new Set<string>();
  let yearless = false;
  for (const page of pages) {
    const { pageKinds, packet } = extractor(staticView(page.href));
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
  if (registration.length && withinBounds(registration))
    packets.registration = {
      v: 1,
      kind: "registration",
      tables: registration,
      ...(years.size === 1 && !yearless ? { year: Array.from(years)[0] } : {}),
    };
  // Read the student inquiry only when the portal advertises the read-only flow.
  // The official admission-year fact can be separate from the affiliation table.
  const studentPath = discover(docs, studentInquiryName);
  const studentPage = studentPath ? get(studentPath) : null;
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
  return { v: 1, packets: ordered };
}

function run() {
  try {
    return fetchInquiries();
  } catch {
    return null;
  }
}
__mbgEntryResult = JSON.stringify(run());
