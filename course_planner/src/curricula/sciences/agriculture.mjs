import {
  name,
  norm,
  row,
  check,
  decision,
  stage,
  months,
  type,
  night,
  categories,
  category,
  intensive,
  urlPage,
  isThirdTransfer,
  transferRow,
  programFor,
  record,
} from "./common.mjs";
import {
  agricultureTables,
  agricultureCourses,
  agricultureCommon,
} from "./agriculture-tables.mjs";

export const agriculturePrograms = [
  "応用生命科学",
  "食品科学",
  "生物資源科学",
  "流域環境学",
  "フィールド科学人材育成",
];
const subfields = ["食料・資源経済学", "植物資源科学", "動物資源科学"];
export const agricultureOptions = [
  ...agriculturePrograms.map((n) => n + "プログラム"),
  ...subfields.map((n) => "生物資源科学（" + n + "分野）"),
];
const short = ["応", "食", "生", "流", "フィ"];
const excluded = ["職業指導(農)", "基礎物理学", "基礎化学", "基礎生物学"].map(
  norm,
);
const labels = {
  intro: "共通基礎・入門必修",
  theme: "共通基礎・主題選択必修",
  global: "グローバル・科学英語演習",
  thesis: "卒業論文Ⅰ・Ⅱ",
  baseRequired: "専門基礎・必修",
  baseChoice: "専門基礎・選択必修",
  specialRequired: "専門・必修",
  specialChoice: "専門・選択必修",
  fieldChoice: "専門・実地見学・実験実習等",
  visitChoice: "専門・実地見学または調理実習",
  jointChoice: "専門基礎・専門共通の選択必修",
  free: "専門系の残りの選択",
};
function baseTitle(c) {
  return name(c).replace(/\((応|食|生|流|フィ)\)$/, "");
}
function classifyGeneral(c, p) {
  if (!type(c)) return null;
  if (night(c) || excluded.includes(name(c)) || c.graduationExcluded)
    return false;
  if (type(c) !== "G") return false;
  const t = name(c),
    cat = category(c);
  if (cat === "大学学習法")
    return /^スタディ[・･]スキルズai{1,2}$/.test(t) ? "study" : false;
  if (/^英語基礎[lr]$/.test(t)) return "social";
  if (cat === "英語") return "english";
  if (cat === "初修外国語") return "foreign";
  if (cat === "情報リテラシー") return "data";
  if (cat === "健康・スポーツ") return "sport";
  if (["人文社会・教育科学", "新潟大学個性化科目"].includes(cat))
    return "social";
  if (["自然系共通専門基礎", "自然科学", "医歯学"].includes(cat))
    return "science";
  if (cat === "留学生基本科目") return p.internationalStudent ? "choice" : null;
  return categories.includes(cat) ? "choice" : null;
}
function labField(c) {
  if (category(c) !== "自然系共通専門基礎") return false;
  for (const sub of ["生物学", "化学"])
    if (c.subcategory === sub || name(c).startsWith(sub + "基礎")) return sub;
  return c.subcategory || /^(数学|解析学|統計学|物理学|地学)/.test(name(c))
    ? false
    : null;
}
function cap(c, y) {
  if (
    intensive(c) ||
    c.failedRetake === true ||
    c.teacherTraining === true ||
    excluded.includes(name(c)) ||
    (y >= 2024 && category(c) === "留学生基本科目") ||
    (y <= 2023 && (type(c) === "Q" || c.shortStayJapanese === true)) ||
    c.capExcluded === true
  )
    return "exclude";
  const forms = String(c.format ?? "")
    .split(/[・、,/／]/)
    .map(norm)
    .filter(Boolean);
  if (!forms.length) return "unknown";
  const exempt = forms.filter((s) =>
    ["実習", "実技", "演習", "実験"].includes(s),
  );
  if (exempt.length === forms.length) return "exclude";
  if (exempt.length || !forms.every((s) => s === "講義")) return "unknown";
  return "include";
}
export function agriculture(book, p) {
  const y = +book.year,
    b = agricultureTables[y],
    prog = agriculturePrograms.indexOf(programFor(p, agriculturePrograms));
  const ref = (pg, title) => urlPage(book, pg, title),
    generalRef = ref(b.page, "農学部規程別表第2・卒業の最低単位");
  const detail = ref(
      b.page - 5 + Math.max(0, prog),
      "農学部規程別表第1・プログラム別科目",
    ),
    th = ref(
      b.thesis + (prog < 2 ? 0 : prog === 2 ? 1 : 2),
      "卒業論文の履修条件",
    );
  const all = new Set(),
    own = new Map();
  function add(n, k) {
    const t = norm(n);
    all.add(t);
    if (!own.has(t)) own.set(t, new Set());
    own.get(t).add(k);
  }
  for (const [k, ns] of Object.entries(agricultureCommon))
    for (const n of ns) add(n, k);
  add("地域交流サテライト実習", "free");
  add("技術コミュニケーション入門", "free");
  for (const [lo, hi, i, k, ns] of agricultureCourses)
    if (lo <= y && y <= hi)
      for (const n of ns) {
        if (i === prog) add(n, k);
        else all.add(norm(n));
      }
  function major(c) {
    if (!type(c)) return null;
    const t = baseTitle(c);
    if (excluded.includes(t) || c.graduationExcluded || night(c)) return false;
    if (type(c) !== "A") return type(c) === "G" ? false : null;
    if (!all.has(t)) return null;
    const restriction = name(c).match(/\((応|食|生|流|フィ)\)$/)?.[1];
    if (restriction && restriction !== short[prog]) return null;
    return true;
  }
  const g = (c) => classifyGeneral(c, p);
  const eligible = (c) => {
    const m = major(c),
      k = g(c);
    return m === true || typeof k === "string"
      ? true
      : m == null || k == null
        ? null
        : false;
  };
  const has = (k) => (c) => {
    const m = major(c);
    return m === true
      ? k === "free"
        ? !own.get(baseTitle(c))?.has("thesis")
        : (own.get(baseTitle(c))?.has(k) ?? false)
      : m;
  };
  const general = (c) => {
    const k = g(c);
    return k == null ? null : !!k;
  };
  const credit = (key, label, n, fn, s = generalRef, options = {}) =>
    row(key, label, "単位", n, fn, s, options);
  const generalDefs = [
    ["study", "大学学習法", 2],
    ["english", "英語", 2],
    ["foreign", "初修外国語", 4],
    ["sport", "健康・スポーツ", 1],
    ["data", "情報リテラシー", 3],
    ["social", "人文社会・教育科学・新潟大学個性化科目", 10],
    ["science", "自然系共通専門基礎・自然科学・医歯学", 10],
    ["choice", "教養系の選択", 2],
  ];
  const generalRows = generalDefs.map(([k, l, n]) =>
    credit(
      k,
      l,
      n,
      (c) => (g(c) == null ? null : k === "choice" ? general(c) : g(c) === k),
      generalRef,
      { exclusive: "ag-general" },
    ),
  );
  const ds = (c) =>
    g(c) == null
      ? null
      : g(c) === "data" && name(c) === "データサイエンス総論i";
  const grad = [
    months(48, generalRef),
    credit("total", "卒業に算入できる単位", 124, eligible),
    credit("general", "教養系", 34, general),
    credit("major", "専門系", 85, major),
    ...generalRows,
    credit("ag-ds", "データサイエンス総論Ⅰ", 1, ds),
  ];
  if (prog === 0 || prog === 1) {
    grad.push(
      credit("ag-natural", "理系10単位のうち自然系共通専門基礎", 6, (c) =>
        g(c) == null
          ? null
          : g(c) === "science" && category(c) === "自然系共通専門基礎",
      ),
    );
    for (const sub of ["化学", "生物学"])
      grad.push(
        credit("ag-" + sub, sub + "の専門基礎", 2, (c) =>
          g(c) == null || labField(c) == null
            ? null
            : g(c) === "science" && labField(c) === sub,
        ),
      );
  }
  const minimum = {
    intro: 5,
    theme: 6,
    global: 2,
    thesis: 6,
    ...b.minimum[prog],
  };
  for (const [k, n] of Object.entries(minimum))
    grad.push(
      credit("ag-" + k, labels[k], n, has(k), detail, {
        exclusive: "ag-major",
      }),
    );
  if (prog < 0)
    grad.push(
      check(
        "program",
        "専門科目のプログラム別内訳",
        "配属された農学部のプログラムを選択してください。",
        detail,
      ),
    );
  const flags = transferRow(p, detail, "農学部");
  grad.push(...flags);
  const thesis = [months(36, th)];
  const stages = [];
  if (prog === 0 || prog === 1) {
    const ex = prog === 0 ? "応用生命科学" : "食品科学";
    const labs = [...own.keys()].filter(
      (n) => own.get(n).has("baseRequired") && n.includes("実験"),
    );
    const requiresLabs = () =>
      labs.map((t) =>
        credit(
          "lab-" + t,
          t,
          2,
          (c) => (major(c) === true ? baseTitle(c) === t : major(c)),
          detail,
        ),
      );
    const deferredLabs = isThirdTransfer(p) && y >= 2024;
    if (!deferredLabs || prog === 0)
      stages.push(
        stage("research-guidance", "卒業論文の事前指導", [
          credit(
            "total",
            prog === 0 ? "2年次第2学期終了時" : "3年次第1学期終了時",
            prog === 0 ? 62 : 80,
            eligible,
            th,
          ),
          ...(!deferredLabs ? requiresLabs() : []),
          ...(prog === 1
            ? [
                credit(
                  "food-intro",
                  "食品科学概論",
                  1,
                  (c) =>
                    type(c)
                      ? type(c) === "A" && baseTitle(c) === "食品科学概論"
                      : null,
                  th,
                ),
              ]
            : []),
        ]),
      );
    thesis.push(
      decision(
        "guidance",
        "卒業論文の事前指導",
        "卒業論文指導予定教員に受講記録を確認してください。",
        th,
      ),
    );
    if (deferredLabs && prog === 0) thesis.push(...requiresLabs());
    thesis.push(
      row(
        "thesis-deficit",
        "卒論と" + ex + "演習Ⅰ・Ⅱを除く不足が10単位以内",
        "条件",
        1,
        undefined,
        th,
        {
          unit: "condition",
          evaluate: ({ courses }) => {
            const applicable = courses.filter(
              (c) =>
                eligible(c) === true &&
                !own.get(baseTitle(c))?.has("thesis") &&
                !baseTitle(c).startsWith(ex + "演習"),
            );
            const sum = (arr) =>
              arr.reduce((n, c) => n + Number(c.credits ?? 0), 0);
            const gap = (n, arr) => Math.max(0, n - sum(arr));
            const generalDeficit = generalDefs
              .filter(([k]) => k !== "choice")
              .reduce((n, [k, , v]) => {
                let gapValue = gap(
                  v,
                  applicable.filter((c) => g(c) === k),
                );
                if (k === "data")
                  gapValue = Math.max(gapValue, gap(1, applicable.filter(ds)));
                if (k === "science") {
                  const pool = applicable.filter(
                    (c) =>
                      g(c) === "science" &&
                      category(c) === "自然系共通専門基礎",
                  );
                  gapValue = Math.max(
                    gapValue,
                    gap(6, pool),
                    ["化学", "生物学"].reduce(
                      (v, f) =>
                        v +
                        gap(
                          2,
                          pool.filter((c) => labField(c) === f),
                        ),
                      0,
                    ),
                  );
                }
                return n + gapValue;
              }, 0);
            const majorDeficit = Object.entries(minimum)
              .filter(([k]) => !["free", "thesis"].includes(k))
              .reduce(
                (n, [k, v]) =>
                  n +
                  gap(
                    k === "specialRequired" ? v - 4 : v,
                    applicable.filter(has(k)),
                  ),
                0,
              );
            const languagePenalty =
              prog === 0
                ? gap(
                    2,
                    applicable.filter((c) => g(c) === "english"),
                  ) +
                  gap(
                    4,
                    applicable.filter((c) => g(c) === "foreign"),
                  )
                : 0;
            const missing =
              Math.max(
                gap(114, applicable),
                Math.max(gap(34, applicable.filter(general)), generalDeficit) +
                  Math.max(
                    gap(
                      75,
                      applicable.filter((c) => major(c) === true),
                    ),
                    majorDeficit,
                  ),
              ) + languagePenalty;
            return {
              value: missing <= 10 ? 1 : 0,
              contributions: applicable.map((c) => record(c, c.credits)),
              ...(courses.some((c) => eligible(c) == null) && {
                unknown:
                  "算入区分が未確定の科目を農学部学務係で確認してください。",
              }),
            };
          },
          note:
            prog === 0
              ? "不足する語学1単位は2単位分として計算します。"
              : "卒業論文6単位と指定演習4単位を除いて照合します。",
        },
      ),
    );
  } else if (prog === 2) {
    if (!isThirdTransfer(p))
      stages.push(
        stage(
          "field-assignment",
          "生物資源科学の分野分属（2年次第1学期終了時）",
          [credit("total", "教養・専門の合計", 46, eligible, th)],
        ),
      );
    const subject = (t) => (c) =>
      major(c) === true ? baseTitle(c) === norm(t) : major(c);
    thesis.push(
      credit("total", "3年次終了時の教養・専門", 106, eligible, th),
      credit("ag-science-english", "科学英語演習", 2, has("global"), th),
      credit(
        "ag-required-11",
        "卒論・生物資源科学演習以外の必修13単位から",
        11,
        (c) =>
          major(c) === true
            ? ["intro", "global", "baseRequired"].some((k) => has(k)(c))
            : major(c),
        th,
      ),
    );
    const i = subfields.findIndex(
      (f) => (p.program || "").includes(f) || p.track === f,
    );
    if (i < 0)
      thesis.push(
        check(
          "research-field",
          "分野別指定科目",
          "食料・資源経済学、植物資源科学、動物資源科学の配属分野を確認してください。",
          th,
        ),
      );
    else {
      const names = [
        "農業経済学演習",
        "植物生産学実験実習",
        "動物生産学実験実習",
      ];
      const required = [..."ⅠⅡⅢⅣ"]
        .map((n) => names[i] + n)
        .concat(
          i === 0 && y >= 2025
            ? ["農業経営学", "農産物流通論"]
            : i === 2
              ? ["牧場実習"]
              : [],
        );
      for (const t of required)
        thesis.push(
          row("ag-field-" + t, t, "指定科目", 1, subject(t), th, {
            unit: "courses",
          }),
        );
      if (i === 0 && y < 2025) {
        const list = [
          y === 2022 ? "環境保全型農業論" : "農業農村開発論",
          "国際フードシステム論",
          "農産物流通論",
        ];
        thesis.push(
          row(
            "ag-economics-choice",
            list.join("・") + "から2科目",
            "指定科目",
            2,
            (c) => (major(c) === true ? list.includes(baseTitle(c)) : major(c)),
            th,
            { unit: "courses" },
          ),
        );
      }
      if (i === 1)
        thesis.push(
          row(
            "ag-plant-three",
            "果樹・蔬菜園芸学、作物学、植物育種学、植物病理学から3科目",
            "指定科目",
            3,
            (c) =>
              major(c) === true
                ? [
                    "果樹・蔬菜園芸学",
                    "作物学",
                    "植物育種学",
                    "植物病理学",
                  ].includes(baseTitle(c))
                : major(c),
            th,
            { unit: "courses" },
          ),
        );
    }
  } else if (prog >= 3)
    thesis.push(
      credit("general", "教養教育に関する科目", 27, general, th),
      credit(
        "ag-languages",
        "英語・初修外国語",
        4,
        (c) => (g(c) == null ? null : ["english", "foreign"].includes(g(c))),
        th,
      ),
      credit("major", "専門教育に関する科目", 68, major, th),
      credit("total", "教養・専門の合計", 100, eligible, th),
    );
  else
    thesis.push(
      check(
        "research-program",
        "プログラム別の卒業論文履修条件",
        "農学部の配属プログラムを選択してください。",
        th,
      ),
    );
  stages.push(
    stage("thesis", "卒業論文の履修", [...thesis, ...flags]),
    stage("graduation", "卒業", grad),
  );
  const gpa = Number(p.gpa),
    valid =
      p.gpa != null &&
      p.gpa !== "" &&
      Number.isFinite(gpa) &&
      gpa >= 0 &&
      gpa <= 5;
  return {
    title: book.title,
    sources: [book, detail, th],
    stages,
    cap: {
      limit: valid && gpa >= 3.5 ? 28 : 24,
      source: ref(b.cap, "学期のCAPと除外科目"),
      classify: (c) => cap(c, y),
      note: "原則24単位。前学期GPAが3.5以上なら28単位。講義を併記した授業・再履修の事情は学務係に確認してください。",
    },
  };
}
