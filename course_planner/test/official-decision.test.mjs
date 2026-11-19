import test from "node:test";
import assert from "node:assert/strict";
import { decisionRecords, decisionScope, saveDecision } from "../src/official-decision.mjs";
import { initialState } from "../src/study.mjs";

const condition = { key: "faculty-decision", label: "教授会の判定", kind: "確認", unit: "condition",
  required: 1, officialDecision: true };

test("documented decisions keep pending, negative and positive results distinct across dates and stages", () => {
  const state = initialState();
  Object.assign(state.profile, { faculty: "医学部医学科", handbook: "2026", assessmentDate: "2027-04-01" });
  const a = decisionScope(state.profile, "progress", "year-2");
  assert.deepEqual(decisionRecords(state.balances, a, condition.key), []);
  saveDecision(state, condition, a, [], 0);
  assert.equal(state.balances[0].current, 0);
  const earlier = structuredClone(state.balances);
  const b = decisionScope(state.profile, "progress", "clinical-practice");
  saveDecision(state, condition, b, [], 1);
  assert.deepEqual(decisionRecords(state.balances, a, condition.key), earlier);
  state.profile.assessmentDate = "2028-04-01";
  const c = decisionScope(state.profile, "progress", "year-2");
  assert.deepEqual(decisionRecords(state.balances, c, condition.key), []);
  assert.throws(() => saveDecision(state, condition, a, earlier, 1));
  saveDecision(state, condition, c, [], 1);
  assert.throws(() => saveDecision(state, condition, c, [], 0));
  saveDecision(state, condition, c, decisionRecords(state.balances, c, condition.key), null);
  assert.equal(state.balances.length, 2);
  assert.throws(() => saveDecision(state, { ...condition, officialDecision: false }, c, [], 1));
});
