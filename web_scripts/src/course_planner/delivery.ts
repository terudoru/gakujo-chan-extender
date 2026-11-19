export {};
declare const __mbgConfig: {
  origin: string;
  path: string;
  attempt: string;
  packet?: unknown;
  phase: "bind" | "probe" | "deliver";
};
type PlannerDocument = Document & {
  __mbgPlannerDelivery?: { attempt: string; sent: boolean };
};

function delivery() {
  const { origin, path, attempt, phase } = __mbgConfig;
  if (
    window !== window.top ||
    location.origin !== origin ||
    location.pathname !== path ||
    location.search ||
    location.hash ||
    new URL(location.href).username ||
    new URL(location.href).password
  )
    return "wrong-document";
  const doc: PlannerDocument = document;
  if (phase === "bind" && !doc.__mbgPlannerDelivery)
    doc.__mbgPlannerDelivery = { attempt, sent: false };
  const state = doc.__mbgPlannerDelivery;
  if (state?.attempt !== attempt) return "wrong-document";
  if (state.sent) return "sent";
  if (phase === "bind") return "bound";
  let ready = false;
  const onReady = () => {
    ready = true;
  };
  window.addEventListener("mbg:planner-ready", onReady);
  try {
    window.dispatchEvent(new Event("mbg:planner-probe"));
  } finally {
    window.removeEventListener("mbg:planner-ready", onReady);
  }
  if (!ready) return "waiting";
  if (phase === "probe") return "ready";
  state.sent = true;
  window.dispatchEvent(
    new CustomEvent("mbg:planner-import", { detail: __mbgConfig.packet }),
  );
  return "sent";
}
__mbgEntryResult = delivery();
