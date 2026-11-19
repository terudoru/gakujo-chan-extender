import test from "node:test";
import assert from "node:assert/strict";
import {
  buildCandidateMeetings,
  countCandidateOverlaps,
  formatOverlapTerms,
  overlapsForCourse,
} from "../src/components/candidate-overlaps.mjs";

const SYNTHETIC = [
  {
    code: "261S0001",
    title: "サンプル線形代数A",
    semester: "第1学期",
    period: "第1ターム",
    schedule: "月1, 月2",
  },
  {
    code: "261S0002",
    title: "サンプル英語演習",
    semester: "第1学期",
    period: "第1ターム",
    schedule: "月2, 木2",
  },
  {
    code: "262S0003",
    title: "サンプル線形代数B",
    semester: "第1学期",
    period: "第2ターム",
    schedule: "月2",
  },
  {
    code: "260S0004",
    title: "サンプル通期演習",
    semester: "第1学期",
    period: "第1,2ターム",
    schedule: "月2, 木2",
  },
  {
    code: "261S0005",
    title: "サンプル集中講義A",
    semester: "第1学期",
    period: "集中",
    schedule: "他",
  },
  {
    code: "261S0006",
    title: "サンプル集中講義B",
    semester: "第1学期",
    period: "第1ターム",
    schedule: "未定",
  },
  {
    code: "261S0007",
    title: "サンプル混在科目",
    semester: "第1学期",
    period: "第1ターム",
    schedule: "木2, 他",
  },
];

const byCode = new Map(SYNTHETIC.map((c) => [c.code, c]));

test("same weekday/period in different terms never overlaps", () => {
  const lists = [
    { id: "mine", name: "履修候補", codes: ["261S0001", "262S0003"] },
  ];
  const index = buildCandidateMeetings(lists, byCode);
  assert.equal(countCandidateOverlaps(byCode.get("261S0001"), index), 0);
  assert.deepEqual(overlapsForCourse(byCode.get("261S0001"), index), []);
  assert.equal(countCandidateOverlaps(byCode.get("262S0003"), index), 0);
});

test("multi-meeting offerings detect overlap on other meetings and deduplicate multi-term/multi-slot matches", () => {
  const lists = [
    {
      id: "mine",
      name: "履修候補",
      codes: ["261S0001", "261S0002", "260S0004", "262S0003"],
    },
  ];
  const index = buildCandidateMeetings(lists, byCode);

  // 261S0002 (term 1: 月2, 木2) overlaps 261S0001 (term 1: 月1, 月2) on 月2
  // and 260S0004 (terms 1,2: 月2, 木2) on term 1 月2 & 木2 — each appearing ONCE!
  const overlaps = overlapsForCourse(byCode.get("261S0002"), index);
  assert.equal(countCandidateOverlaps(byCode.get("261S0002"), index), 2);
  assert.deepEqual(
    overlaps.map((o) => o.course.code),
    ["260S0004", "261S0001"],
  );
  assert.deepEqual(overlaps[0].terms, [1]);
  assert.deepEqual(overlaps[0].slots, ["月2", "木2"]);
  assert.deepEqual(overlaps[1].terms, [1]);
  assert.deepEqual(overlaps[1].slots, ["月2"]);

  // 260S0004 (terms 1,2: 月2, 木2) overlaps 261S0001 (t1 月2), 261S0002 (t1 月2,木2), and 262S0003 (t2 月2)
  const spanOverlaps = overlapsForCourse(byCode.get("260S0004"), index);
  assert.deepEqual(
    spanOverlaps.map((o) => ({
      code: o.course.code,
      terms: o.terms,
      slots: o.slots,
    })),
    [
      { code: "261S0001", terms: [1], slots: ["月2"] },
      { code: "261S0002", terms: [1], slots: ["月2", "木2"] },
      { code: "262S0003", terms: [2], slots: ["月2"] },
    ],
  );
  assert.equal(formatOverlapTerms([1, 2]), "第1・2ターム");
});

test("duplicate list membership across personal and copied lists merges list names without duplicating offerings", () => {
  const lists = [
    { id: "mine", name: "履修候補", codes: ["261S0001", "261S0002", "261S0002"] },
    { id: "copy", name: "履修候補（コピー）", codes: ["261S0002", "261S0001"] },
    { id: "dup", name: "履修候補", codes: ["261S0002"] },
  ];
  const index = buildCandidateMeetings(lists, byCode);

  const overlaps = overlapsForCourse(byCode.get("261S0001"), index);
  assert.equal(overlaps.length, 1);
  assert.equal(overlaps[0].course.code, "261S0002");
  assert.deepEqual(overlaps[0].lists, ["履修候補", "履修候補（コピー）"]);
  assert.equal(countCandidateOverlaps(byCode.get("261S0001"), index), 1);
});

test("intensive and unknown slots are never confirmed overlaps, while confirmed slots in mixed schedules still match", () => {
  const lists = [
    {
      id: "mine",
      name: "履修候補",
      codes: ["261S0005", "261S0006", "261S0007", "261S0002", "261MISSING"],
    },
  ];
  const index = buildCandidateMeetings(lists, byCode);

  assert.equal(countCandidateOverlaps(byCode.get("261S0005"), index), 0);
  assert.deepEqual(overlapsForCourse(byCode.get("261S0005"), index), []);
  assert.equal(countCandidateOverlaps(byCode.get("261S0006"), index), 0);
  assert.deepEqual(overlapsForCourse(byCode.get("261S0006"), index), []);

  // 261S0007 ("木2, 他") overlaps 261S0002 ("月2, 木2") ONLY on 木2, never with 261S0005/261S0006
  const mixed = overlapsForCourse(byCode.get("261S0007"), index);
  assert.equal(mixed.length, 1);
  assert.equal(mixed[0].course.code, "261S0002");
  assert.deepEqual(mixed[0].slots, ["木2"]);
});

test("index stays linear in meetings without materializing a pairwise N^2 graph", () => {
  const syntheticMany = new Map();
  const codes = [];
  for (let i = 0; i < 600; i++) {
    const code = `261M${String(i).padStart(4, "0")}`;
    codes.push(code);
    syntheticMany.set(code, {
      code,
      title: `大量候補${i}`,
      semester: "第1学期",
      period: "第1ターム",
      schedule: "月1",
    });
  }
  const index = buildCandidateMeetings(
    [{ id: "all", name: "大量リスト", codes }],
    syntheticMany,
  );
  // Only 1 bucket ("1:月1") with 600 entries instead of 600*599 pairwise edges
  assert.equal(index.byMeeting.size, 1);
  assert.equal(index.byMeeting.get("1:月1").length, 600);
  assert.equal(countCandidateOverlaps(syntheticMany.get(codes[0]), index), 599);
});
