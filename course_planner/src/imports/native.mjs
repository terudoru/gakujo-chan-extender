import { validatePacket } from "./tables.mjs";

// Mount once at the App root, before announcing readiness to the native host.
export function installPlannerImportListener(
  onPacket,
  onError = () => {},
  target = window,
) {
  // The v1 host has no delivery ID. Suppress identical retried deliveries in
  // the current handshake, while permitting a later intentional re-import.
  const recent = new Map();
  const ready = () => target.dispatchEvent(new Event("mbg:planner-ready"));
  const receive = ({ detail }) => {
    try {
      validatePacket(detail);
      const packet = {
        v: 1,
        kind: detail.kind,
        tables: detail.tables.map(({ heading, rows }) => ({
          heading,
          rows: rows.map((r) => [...r]),
        })),
        ...(detail.year ? { year: detail.year } : {}),
      };
      const now = Date.now();
      for (const [key, time] of recent)
        if (now - time > 5000) recent.delete(key);
      const key = JSON.stringify(packet);
      if (recent.has(key)) return;
      if (recent.size >= 4) recent.delete(recent.keys().next().value);
      recent.set(key, now);
      onPacket(packet);
    } catch (error) {
      onError(error);
    }
  };
  target.addEventListener("mbg:planner-import", receive);
  target.addEventListener("mbg:planner-probe", ready);
  ready();
  return () => {
    target.removeEventListener("mbg:planner-import", receive);
    target.removeEventListener("mbg:planner-probe", ready);
    recent.clear();
  };
}
