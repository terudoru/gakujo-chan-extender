import { extractor, liveView, names, origin, type Kind } from "./extract.js";

declare const __mbgConfig: { attempt: string; kind?: Kind; timetable?: boolean };
type SourceDocument = Document & {
  __mbgPlannerSource?: {
    attempt: string;
    href: string;
    tables: HTMLTableElement[];
  };
};

const { visible, pageKinds, academicTables, packet, timetableSnapshot } = extractor(liveView);

function sourceDocuments(doc: SourceDocument, found: SourceDocument[]) {
  if (
    new URL(doc.URL).origin !== origin ||
    !new URL(doc.URL).pathname.startsWith("/campusweb/")
  )
    return;
  found.push(doc);
  for (const frame of Array.from(
    doc.querySelectorAll<HTMLIFrameElement>("iframe,frame"),
  )) {
    try {
      if (visible(frame) && frame.contentDocument)
        sourceDocuments(frame.contentDocument, found);
    } catch {
      /* Other origins cannot own this capture. */
    }
  }
}
function capture() {
  if (window !== window.top || location.origin !== origin) return null;
  const docs: SourceDocument[] = [];
  sourceDocuments(document, docs);
  if (
    docs.some((d) =>
      Array.from(
        d.querySelectorAll('input[type="password"],input[name="ninshoCode"]'),
      ).some(visible),
    )
  )
    return null;
  const { attempt, kind } = __mbgConfig;
  const sources = docs.map((doc) => ({ doc, kinds: pageKinds(doc) }));
  if (!kind) {
    const offered = (Object.keys(names) as Kind[]).filter(
      (k) => sources.filter((s) => s.kinds.includes(k)).length === 1,
    );
    for (const s of sources)
      if (s.kinds.some((k) => offered.includes(k))) {
        const tables = s.kinds.reduce<HTMLTableElement[]>(
          (all, k) => all.concat(academicTables(s.doc, k)),
          [],
        );
        s.doc.__mbgPlannerSource = { attempt, href: s.doc.URL, tables };
      }
    return offered;
  }
  const matches = sources.filter((s) => s.kinds.includes(kind));
  if (matches.length !== 1) return null;
  const doc = matches[0].doc;
  const owner = doc.__mbgPlannerSource;
  const current = academicTables(doc, kind);
  if (
    !owner ||
    owner.attempt !== attempt ||
    owner.href !== doc.URL ||
    current.some((t) => !owner.tables.includes(t)) ||
    owner.tables.some((t) => !t.isConnected)
  )
    return null;
  return __mbgConfig.timetable ? (kind === "registration" ? timetableSnapshot(doc) : null) : packet(doc, kind, current);
}
__mbgEntryResult = JSON.stringify(capture());
