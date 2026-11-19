import test from "node:test";
import assert from "node:assert/strict";
import {
  applyPlannerImport,
  reviewPlannerImport,
} from "../src/imports/review.mjs";
import { installPlannerImportListener } from "../src/imports/native.mjs";
import { delimitedRows } from "../src/transcript.mjs";
import { pdfPageRows } from "../src/imports/pdf-rows.mjs";
import { initialState } from "../src/study.mjs";

const code = "261G7011",
  code2 = "261G7012",
  title = "例示科目Ａ";
const byCode = new Map(
  [code, code2].map((c) => [
    c,
    {
      code: c,
      title,
      year: "2026",
      credits: 1,
      fields: ["70"],
      category: "教育",
      department: "84",
    },
  ]),
);
const profile = {
  faculty: "例学部",
  handbook: "2025",
  program: "例専攻",
  entry: "編入",
  curriculum: "2",
};
const targets = [
  { key: "english", label: "英語", required: 4, kind: "必修" },
  { key: "major", label: "学部共通基礎", required: 8 },
];
const options = {
  byCode,
  catalogYear: 2026,
  profile,
  goal: "progress",
  stage: "4年次",
  requirementRows: targets,
};
const packet = (kind, rows, heading = "") => ({
  v: 1,
  kind,
  tables: [{ heading, rows }],
});
const review = (kind, rows, heading) =>
  reviewPlannerImport(packet(kind, rows, heading), options);
const state = () => ({ ...initialState(), profile });
const select = (r) => r.rows.filter((x) => x.value).map(({ id }) => ({ id }));
const head = [
  "開講番号",
  "科目名",
  "修得単位",
  "評語",
  "年度",
  "クラス",
  "科目ID",
];
const success = [code, title, "1", "優", "2026", "", ""];
test("column names, not dates, scores, body text or table order, establish earned grades", () => {
  const rows = [
    success,
    head,
    success,
    [code, title, "1", "85", "2026", "", ""],
    [code, title, "", "良", "2026", "", ""],
    [code2, title, "1", "不可", "2026", "", ""],
    [...head, "単位数"],
    [...success, "100"],
    ["学籍番号", "氏名"],
  ];
  const r = review("grades", rows);
  assert.equal(select(r).length, 1);
  assert.equal(r.rows.filter((x) => x.skipped).length, 1);
  assert.equal(r.rows.find((x) => x.value).value.matchedCourse.year, "2026");
  assert.equal(r.rows.find((x) => x.value).value.fields[0], "70");
  assert.equal(r.rows[0].value, undefined);
  assert.equal(
    review("grades", [
      ["科目名", "点数", "単位数"],
      [title, "90", "1"],
    ]).rows.some((r) => r.value),
    false,
  );
});

test("contradictory pass and fail for one offering cannot create earned credit", () => {
  const r = review("grades", [
    head,
    success,
    [code, title, "1", "不可", "2026", "", ""],
  ]);
  assert.equal(select(r).length, 0);
  assert.match(r.rows[0].reason, /修得と未修得/);
});

test("an export without the original duplicate mark cannot restore excluded credits", () => {
  const marked = review(
    "grades",
    [head, [code, title, "＊1", "優", "2026", "", ""]],
    "成績確認表",
  );
  const plain = review("grades", [head, success]);
  const s = state();
  applyPlannerImport(s, marked, select(marked));
  applyPlannerImport(s, plain, select(plain));
  assert.equal(s.grades.length, 1);
  assert.equal(s.grades[0].duplicate, true);
  assert.equal(s.grades[0].counts, false);
});

test("compatible PDF and native columns retain a stable import identifier", () => {
  const s = state();
  const minimal = review("grades", [head.slice(0, 5), success.slice(0, 5)]);
  applyPlannerImport(s, minimal, select(minimal));
  const id = s.grades[0].importId;
  const extra = review("grades", [
    head,
    [code, title, "1", "優", "2026", "A", "C1"],
  ]);
  applyPlannerImport(s, extra, select(extra));
  applyPlannerImport(s, minimal, select(minimal));
  assert.equal(s.grades.length, 1);
  assert.equal(s.grades[0].importId, id);
  assert.equal(s.grades[0].courseId, "C1");
  assert.equal(s.grades[0].section, "A");
});

test("old or missing year and mismatched course/section cannot acquire current catalog fields", () => {
  const r = review("grades", [
    head,
    [code, title, "1", "優", "2024", "", ""],
    [code, title, "1", "良", "", "", ""],
    [code, "別科目", "1", "可", "2026", "", ""],
    [code, title, "1", "良", "2026", "別組", "別ID"],
  ]);
  assert.equal(select(r).length, 4);
  for (const { value } of r.rows) {
    assert.deepEqual(value.fields, []);
    assert.equal(value.matchedCourse, undefined);
  }
  const explicit = packet("grades", [head.slice(0, 4), success.slice(0, 4)]);
  explicit.year = "2026";
  assert.equal(
    reviewPlannerImport(explicit, options).rows[0].value.year,
    "2026",
  );
});

test("reimport preserves a confirmed historic mapping, original offering identity and other sections/years", () => {
  const r = review("grades", [
    head,
    [code, title, "1", "良", "2024", "A", "C001"],
    [code, title, "1", "良", "2024", "B", "C002"],
    success,
  ]);
  const s = state();
  applyPlannerImport(s, r, select(r));
  const original = {
    year: "2024",
    code: "241G0001",
    title: "過去の科目",
    fields: ["50"],
    department: "84",
    category: "旧区分",
    sourceUrl: "https://example.org/",
    confirmed: true,
  };
  s.grades[0].matchedCourse = original;
  applyPlannerImport(s, r, select(r));
  assert.equal(s.grades.length, 3);
  assert.deepEqual(s.grades[0].matchedCourse, original);
  assert.deepEqual(s.grades[0].fields, ["50"]);
  assert.deepEqual(
    s.grades.slice(0, 2).map((g) => [g.section, g.courseId]),
    [
      ["A", "C001"],
      ["B", "C002"],
    ],
  );
  assert.equal(s.grades[0].code, code);
});

test("ambiguous identical name-only histories survive separately and are never double counted", () => {
  const rows = [
    ["科目名", "単位数", "評価", "年度"],
    [title, "1", "可", "2024"],
    [title, "1", "可", "2024"],
  ];
  const r = review("grades", rows);
  assert.notEqual(r.rows[0].value.importId, r.rows[1].value.importId);
  const s = state();
  applyPlannerImport(s, r, select(r));
  applyPlannerImport(s, r, select(r));
  assert.equal(s.grades.length, 2);
  assert.ok(s.grades.every((g) => g.identityUncertain && g.counts === false));
  const single = review("grades", rows.slice(0, 2));
  applyPlannerImport(s, single, select(single));
  assert.equal(s.grades.length, 2);
});

test("official credit star and documented duplicates are excluded, alternative titles remain auditable", () => {
  const cols = ["科目名", "単位数", "評価", "年度", "読替科目名", "重複"];
  const r = review("grades", [
    ["成績確認表"],
    cols,
    ["新科目", "＊２", "良", "2024", "旧科目", ""],
    ["別科目", "2", "可", "2024", "", "重複"],
    ["任意科目", "2", "良", "2024", "旧科目", ""],
  ]);
  const s = state();
  const picks = select(r);
  picks[2].excludeDuplicate = true;
  applyPlannerImport(s, r, picks);
  applyPlannerImport(s, r, select(r));
  assert.equal(s.grades.length, 3);
  assert.ok(s.grades.every((g) => !g.counts && g.duplicate));
  assert.equal(s.grades[0].alternativeTitle, "旧科目");
  const unlabelled = review("grades", [
    cols,
    ["新科目", "＊2", "優", "2024", "", ""],
  ]);
  assert.equal(unlabelled.rows[0].value.counts, false);
  assert.equal(unlabelled.rows[0].value.duplicate, false);
});

test("recognition carries only an institutional allocation and never invents an academic field", () => {
  const r = review("grades", [
    ["科目名", "単位", "成績", "認定区分"],
    ["例A", "2", "認定", "英語"],
    ["例B", "2", "認定", ""],
  ]);
  assert.equal(r.rows[0].value.allocationKey, "english");
  assert.equal(r.rows[0].value.allocationScope.entry, "編入");
  assert.equal(r.rows[1].value.recognized, true);
  assert.equal(r.rows[1].value.allocationKey, undefined);
  assert.match(r.rows[1].reason, /算入先/);
  assert.deepEqual(r.rows[0].value.fields, []);
});

test("previously recorded alternative titles require a separate reviewed counting decision", () => {
  const prior = {
    year: "2022",
    title: "旧科目",
    credits: 2,
    grade: "可",
    counts: true,
  };
  const p = packet("grades", [
    ["科目名", "単位数", "評価", "年度", "読替科目名"],
    ["新科目", "2", "可", "2024", "旧科目"],
  ]);
  const r = reviewPlannerImport(p, { ...options, grades: [prior] });
  assert.equal(r.rows[0].value.possibleDuplicate, true);
  const s = state();
  s.grades.push(prior);
  applyPlannerImport(s, r, select(r));
  assert.deepEqual(
    s.grades.map((g) => g.counts),
    [true, false],
  );
  applyPlannerImport(s, r, [{ id: r.rows[0].id, confirmDistinct: true }]);
  assert.deepEqual(
    s.grades.map((g) => g.counts),
    [true, true],
  );
  applyPlannerImport(s, r, select(r));
  assert.deepEqual(
    s.grades.map((g) => g.counts),
    [true, true],
  );
});

test("one selected ambiguous row cannot revoke an earlier explicitly reviewed record", () => {
  const rows = [
    ["科目名", "単位数", "評価", "年度"],
    ["同名", "2", "可", "2024"],
  ];
  const s = state();
  const single = review("grades", rows);
  applyPlannerImport(s, single, select(single));
  const repeated = review("grades", [...rows, rows[1]]);
  applyPlannerImport(s, repeated, [{ id: repeated.rows[1].id }]);
  assert.equal(s.grades[0].counts, true);
  assert.equal(s.grades[1].counts, false);
});

test("requirement totals must be reviewed for duplicate-free earned units", () => {
  const r = reviewPlannerImport(
    packet("balances", [
      ["区分", "既修得単位"],
      ["卒業単位の合計", "12"],
    ]),
    {
      ...options,
      requirementRows: [
        { key: "total", label: "卒業単位の合計", required: 124 },
      ],
    },
  );
  const s = state();
  assert.throws(() => applyPlannerImport(s, r, select(r)), /重複単位/);
  applyPlannerImport(s, r, [{ id: r.rows[0].id, confirmTotal: true }]);
  assert.equal(s.balances[0].duplicateFree, true);
});

test("registration uses exact row results or section labels, with omissions and conflicts kept local", () => {
  const packet = {
    v: 1,
    kind: "registration",
    tables: [
      {
        heading: "申請中の科目",
        rows: [
          ["開講番号", "科目名"],
          [code, title],
        ],
      },
      {
        heading: "不許可となった科目",
        rows: [
          ["開講番号", "科目名", "講義室", "開講期間", "単位数"],
          [code2 + " (T3,4)", title, "教室", "月1", "1.0単位"],
        ],
      },
    ],
  };
  const r = reviewPlannerImport(packet, options);
  assert.deepEqual(
    r.rows.map((x) => x.value.status),
    ["申請中", "不許可"],
  );
  const s = state();
  s.status[code] = "許可";
  applyPlannerImport(s, r, [{ id: r.rows[1].id }]);
  assert.deepEqual(s.status, { [code]: "許可", [code2]: "不許可" });
  assert.deepEqual(s.plan, [code2]);
  const unknown = review("registration", [
    ["開講番号", "登録状況"],
    [code2, ""],
    [code, "許可"],
    [code, "不許可"],
  ]);
  assert.deepEqual(
    unknown.rows.map((x) => x.value.status),
    ["要確認", "要確認", "要確認"],
  );
  applyPlannerImport(s, unknown, select(unknown));
  assert.equal(s.status[code2], "不許可");
  assert.equal(s.status[code], "許可");
  const disjoint = review("registration", [
    ["開講番号", "科目名"],
    [code, title],
  ]);
  const fresh = state();
  applyPlannerImport(fresh, disjoint, select(disjoint));
  assert.equal(fresh.status[code], "要確認");
  const mismatched = review("registration", [
    ["年度", "開講番号", "科目名", "許可状況"],
    ["2020", code, title, "許可"],
    ["2026", code, "別名", "許可"],
  ]);
  assert.equal(select(mismatched).length, 0);
});

test("registration does not carry a denial across another heading and header", () => {
  const r = review("registration", [
    ["不許可となった科目"],
    ["開講番号", "科目名"],
    [code, title],
    ["時間割"],
    ["開講番号", "科目名"],
    [code2, title],
  ]);
  assert.deepEqual(
    r.rows.map((v) => v.value.status),
    ["不許可", "要確認"],
  );
});

test("day and night earned credits stay distinct from registered credits and omitted categories", () => {
  const r = review("balances", [
    ["区分", "履修単位", "既修得単位", "備考"],
    ["昼間", "夜間", "昼間", "夜間"],
    ["英語", "99", "50", "2.0", "0.5", ""],
    ["不明区分", "0", "0", "3", "0", ""],
  ]);
  assert.equal(r.rows[0].value.current, 2.5);
  assert.equal(r.rows[0].targetKey, "english");
  assert.equal(r.rows[1].targetKey, "");
  const s = state();
  applyPlannerImport(s, r, [{ id: r.rows[0].id }]);
  applyPlannerImport(s, r, [{ id: r.rows[0].id }]);
  assert.equal(s.balances.length, 1);
  assert.deepEqual(
    [
      s.balances[0].current,
      s.balances[0].required,
      s.balances[0].entry,
      s.balances[0].stage,
    ],
    [2.5, 4, "編入", "4年次"],
  );
  assert.throws(() => applyPlannerImport(s, r, select(r)), /要件/);
  assert.throws(
    () =>
      applyPlannerImport(s, r, [
        { id: r.rows[0].id },
        { id: r.rows[1].id, targetKey: "english" },
      ]),
    /複数/,
  );
  assert.equal(s.balances.length, 1);
  applyPlannerImport(s, r, [{ id: r.rows[1].id, targetKey: "major" }]);
  assert.equal(s.balances.length, 2);
  const switched = { ...s, profile: { ...profile, program: "別" } };
  assert.throws(
    () => applyPlannerImport(switched, r, [{ id: r.rows[0].id }]),
    /変わりました/,
  );
});

test("PDF font runs, empty columns and the right-hand statement grid keep their column positions", () => {
  const t = (str, x, y, width = 9) => ({
    str,
    transform: [1, 0, 0, 1, x, y],
    height: 10,
    width,
  });
  const separate = [..."科目名"].map((c, i) => t(c, 80 + i * 10, 100));
  const pdf = pdfPageRows(
    [
      t("開講番号", 10, 100, 40),
      ...separate,
      t("単位数", 230, 100, 30),
      t("評価", 320, 100, 20),
      t("例", 80, 85),
      t("題", 90, 85),
      t("0.5", 230, 85, 15),
      t("優", 320, 85),
      t("科", 80, 65),
      t("⽬", 90, 65),
      t("Ⅰ", 100, 65),
      t("1", 230, 65),
      t("可", 320, 65),
    ],
    "grades",
  );
  assert.deepEqual(pdf[1], ["", "例題", "0.5", "優"]);
  assert.deepEqual(pdf[2], ["", "科目Ⅰ", "1", "可"]);
  const balance = pdfPageRows(
    [
      t("区分", 212, 104, 20),
      t("履修単位", 266, 110, 36),
      t("既修得単位", 330, 110, 44),
      ...[260, 292, 324, 356].map((x, i) =>
        t(i % 2 ? "夜間" : "昼間", x, 97, 16),
      ),
      t("他の表", 20, 82, 40),
      t("英語", 183, 82, 20),
      ...["98", "10", "2", "0.5"].map((v, i) => t(v, 263 + 32 * i, 82, 10)),
    ],
    "balances",
  );
  assert.equal(
    review("balances", balance).rows.find((r) => r.value)?.value.current,
    2.5,
  );
});

test("review is side-effect free, packet sizes are bounded, text quoting and headings are preserved", () => {
  assert.deepEqual(
    delimitedRows('成績確認表\r\n開講番号\t科目名\r\n100\t"理論,\n入門"'),
    [["成績確認表"], ["開講番号", "科目名"], ["100", "理論,\n入門"]],
  );
  assert.throws(() => delimitedRows('"a'), /引用符/);
  assert.throws(
    () => reviewPlannerImport({ v: 2, kind: "grades", tables: [] }),
    /形式/,
  );
  assert.throws(() => review("grades", [Array(150).fill("x")]), /サイズ/);
  const s = state();
  const r = review("grades", [head, success]);
  assert.throws(() => applyPlannerImport(s, r, []));
  assert.throws(() => applyPlannerImport(s, r, [{ id: "invalid" }]));
  assert.equal(s.grades.length, 0);
});

test("native listener is ready only after installation, deduplicates copies, and removes both listeners", () => {
  const bus = new EventTarget(),
    got = [],
    errors = [];
  const p = packet("grades", [head, success]);
  const emit = () =>
    bus.dispatchEvent(
      new CustomEvent("mbg:planner-import", { detail: structuredClone(p) }),
    );
  let ready = 0;
  bus.addEventListener("mbg:planner-ready", () => {
    ready++;
    emit();
  });
  const off = installPlannerImportListener(
    (p) => got.push(p),
    (e) => errors.push(e),
    bus,
  );
  bus.dispatchEvent(new Event("mbg:planner-probe"));
  emit();
  bus.dispatchEvent(
    new CustomEvent("mbg:planner-import", { detail: { v: 0 } }),
  );
  assert.equal(ready, 2);
  assert.equal(got.length, 1);
  assert.equal(errors.length, 1);
  assert.deepEqual(got[0], p);
  off();
  emit();
  bus.dispatchEvent(new Event("mbg:planner-probe"));
  assert.equal(ready, 2);
  assert.equal(got.length, 1);
});
