// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/course_planner/delivery.ts
// Regenerate with: npm --prefix web_scripts run build

import 'dart:convert';

String coursePlannerDeliveryJs(Map<String, Object?> config) =>
    _coursePlannerDeliveryJsPrefix +
    jsonEncode(config) +
    _coursePlannerDeliveryJsSuffix;

const String _coursePlannerDeliveryJsPrefix = r'''(function(__mbgConfig) {
"use strict";
(() => {
  // web_scripts/src/course_planner/delivery.ts
  function delivery() {
    const { origin, path, attempt, phase } = __mbgConfig;
    if (window !== window.top || location.origin !== origin || location.pathname !== path || location.search || location.hash || new URL(location.href).username || new URL(location.href).password)
      return "wrong-document";
    const doc = document;
    if (phase === "bind" && !doc.__mbgPlannerDelivery)
      doc.__mbgPlannerDelivery = { attempt, sent: false };
    const state = doc.__mbgPlannerDelivery;
    if ((state == null ? void 0 : state.attempt) !== attempt) return "wrong-document";
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
      new CustomEvent("mbg:planner-import", { detail: __mbgConfig.packet })
    );
    return "sent";
  }
  __mbgEntryResult = delivery();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})(''';
const String _coursePlannerDeliveryJsSuffix = r''')
''';
