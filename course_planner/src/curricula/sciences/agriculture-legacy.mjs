import {
  norm,
  name,
  type,
  category,
  night,
  stage,
  months,
  row,
  check,
  transferRow,
  programFor,
} from "./common.mjs";
import { agriculturePrograms } from "./agriculture.mjs";
import { legacyAgricultureCourses } from "./agriculture-legacy-tables.mjs";

const uni = "https://www.niigata-u.ac.jp/wp-content/uploads/";
export const agricultureLaw = {
  title: "農学部規程・附則（令和4年施行と令和3年度への適用）",
  url: "https://public1.legalcrud.com/niigata_univ/act/110000544.html",
};
export const agricultureReport = (y) =>
  uni + (y === 2020 ? "2021/04/r2agr_ac.pdf" : "2020/04/r1agr_ac.pdf");
const generalGroups = [
  ["study", "大学学習法", 2],
  ["english", "英語", 4],
  ["foreign", "初修外国語", 4],
  ["sport", "健康・スポーツ", 1],
  ["data", "情報リテラシー", 2],
  ["social", "人文社会・教育科学・新潟大学個性化科目", 10],
  ["science", "自然系共通専門基礎・自然科学・医歯学", 10],
];
const sectionNames = [
  "入門科目",
  "主題科目",
  "専門基礎科目",
  "専門科目",
  "就業力育成科目",
  "グローバル科目",
  "卒業論文",
];
const generalCategories = [
  ["大学学習法"],
  ["英語"],
  ["初修外国語"],
  ["健康・スポーツ"],
  ["情報リテラシー"],
  ["人文社会・教育科学", "新潟大学個性化科目"],
  ["自然系共通専門基礎", "自然科学", "医歯学"],
];
const capNote =
  "公開の履行状況報告書には学期24単位とあります。GPAによる特例・混合形態の算入は入学年度の農学部学務係の取扱いを確認してください。";
const scopeSource = {
  title: "農学部の入学年度別履修の手引・学務係",
  url: "https://www.agr.niigata-u.ac.jp/students",
};
const research = () =>
  stage("thesis", "卒業論文の履修", [
    check(
      "thesis-eligibility",
      "研究室配属と卒業論文の履修資格",
      "学年・プログラムごとの配属時の修得単位と指定実習を、入学時の履修の手引と指導予定教員の記録で確認してください。",
      scopeSource,
    ),
  ]);

export function legacyAgriculture(book, p) {
  const y = Number(book.year),
    i = agriculturePrograms.indexOf(programFor(p, agriculturePrograms));
  const evidence = {
    title: "農学部農学科・設置計画履行状況報告書の科目区分と卒業要件",
    url:
      agricultureReport(y) +
      "#page=" +
      ((y === 2020 ? [7, 16, 26, 36, 46] : [7, 14, 21, 28, 35])[
        Math.max(i, 0)
      ] +
        (y <= 2018 ? 2 : 0)),
  };
  const method = {
    title: "農学科設置資料・プログラム別履修方法",
    url:
      uni + "2016/03/agr_insp.pdf#page=" + [9, 11, 14, 17, 20][Math.max(i, 0)],
  };
  const flags = transferRow(p, agricultureLaw, "農学部");
  const credit = (key, label, v, match, source = evidence) =>
    row(key, label, "単位", v, match, source);
  const transition = (c) => {
    if (!type(c)) return null;
    if (
      type(c) !== "A" ||
      !["公開森林実習", "フィールド惑星科学概論"].includes(name(c))
    )
      return false;
    return p.enrolledApril2022 === true || c.recognitionApproved ? true : null;
  };
  const late = check(
    "transition-electives",
    "施行時在学生の選択科目への算入",
    "令和4年4月1日に在学していた場合、公開森林実習とフィールド惑星科学概論を選択科目に加えられます。農学部学務係で当時の在籍と履修を確認してください。",
    agricultureLaw,
  );
  if (y === 2021) {
    const rr = [
      check(
        "general",
        "教養教育の区分別最低単位",
        "令和3年度の別表第2を農学部学務係で確認してください。令和2年度以前は別課程です。",
        scopeSource,
      ),
      check(
        "total",
        "卒業資格・履修区分",
        "令和3年度入学時の別表とプログラム別履修表を農学部学務係で確認してください。",
        scopeSource,
      ),
    ];
    const rules =
      i === 2
        ? [
            ["専門基礎・必修", 6],
            ["専門・選択必修", 34],
          ]
        : i === 4
          ? [
              ["専門・必修", 6],
              ["専門・選択必修", 30],
            ]
          : [];
    for (const [label, minimum] of rules)
      rr.push(
        credit(
          "retro-" + label,
          label + "（令和3年度に遡及）",
          minimum,
          (c) => (type(c) === "A" || !type(c) ? null : false),
          agricultureLaw,
        ),
      );
    rr.push(late, ...flags);
    return {
      title: book.title,
      sources: [agricultureLaw, scopeSource],
      stages: [research(), stage("graduation", "卒業", rr)],
      cap: {
        limit: null,
        classify: () => "unknown",
        source: scopeSource,
        note: "令和3年度の登録上限とGPA特例を農学部学務係で確認してください。",
      },
    };
  }
  const listings = new Map();
  for (const [
    lo,
    hi,
    prog,
    section,
    mandatory,
    names,
  ] of legacyAgricultureCourses) {
    if (y < lo || y > hi) continue;
    for (const title of names)
      if (i === prog)
        listings.set(norm(title), { section, mandatory: !!mandatory });
  }
  const base = (c) => name(c).replace(/\((応|食|生|流|フィ)\)$/, "");
  const major = (c) => {
    if (!type(c)) return null;
    if (night(c) || c.graduationExcluded) return false;
    if (type(c) !== "A") return type(c) === "G" ? false : null;
    if (
      [
        "基礎物理学",
        "基礎化学",
        "基礎生物学",
        "基礎地学",
        "職業指導(農)",
      ].includes(base(c))
    )
      return false;
    const restriction = name(c).match(/\((応|食|生|流|フィ)\)$/)?.[1];
    if (restriction && restriction !== ["応", "食", "生", "流", "フィ"][i])
      return null;
    if (listings.has(base(c))) return true;
    if (transition(c) !== false) return transition(c);
    return null;
  };
  const group = (c) => {
    if (!type(c)) return null;
    if (night(c) || c.graduationExcluded) return false;
    if (type(c) !== "G") return type(c) === "A" ? false : null;
    const j = generalCategories.findIndex((s) => s.includes(category(c)));
    if (j === 0 && !name(c).startsWith("スタディ・スキルズa")) return null;
    if (j < 0) return null;
    return generalGroups[j][0];
  };
  const general = (c) => {
    const k = group(c);
    return k == null ? null : !!k;
  };
  const eligible = (c) => {
    const m = major(c),
      g = general(c);
    return m === true || g === true
      ? true
      : m == null || g == null
        ? null
        : false;
  };
  const match = (fn) => (c) => {
    const eligible = major(c);
    if (eligible !== true) return eligible;
    const a = listings.get(base(c));
    return a ? fn(a, c) : false;
  };
  const rr = [
    months(48, evidence),
    credit("total", "卒業に算入できる単位", 124, eligible),
    credit("general", "教養教育", 35, general),
    credit("major", "専門教育", 85, major),
  ];
  for (const [k, l, v] of generalGroups)
    rr.push(
      credit(
        k,
        l,
        v,
        (c) => (group(c) == null ? null : group(c) === k),
        method,
      ),
    );
  if (i >= 0) {
    for (const [s, v] of [
      [0, 5],
      [1, 6],
      [4, 1],
      [5, 2],
      [6, 6],
    ])
      rr.push(
        credit(
          "section-" + s,
          sectionNames[s],
          v,
          match((a) => a.section === s),
          method,
        ),
      );
    const [baseLecture, majorLecture, practice, mandatory] = [
      [20, 24, 16, 49],
      [28, 18, 15, 55],
      [16, 24, 14, 25],
      [16, 18, 16, 23],
      [10, 32, 17, 23],
    ][i];
    const form = (c) => {
      const f = norm(c.format);
      return f === "講義"
        ? "lecture"
        : /^(?:実験|実習|演習)(?:[・/、](?:実験|実習|演習))*$/.test(f)
          ? "practice"
          : null;
    };
    for (const [key, label, v, sections, wanted] of [
      ["base-lecture", "専門基礎の講義", baseLecture, [2], "lecture"],
      ["major-lecture", "専門の講義", majorLecture, [3], "lecture"],
      [
        "practice",
        "専門基礎・専門の演習と実験・実習",
        practice,
        [2, 3],
        "practice",
      ],
    ])
      rr.push(
        credit(
          key,
          label,
          v,
          match((a, c) =>
            sections.includes(a.section)
              ? form(c) == null
                ? null
                : form(c) === wanted
              : false,
          ),
          method,
        ),
      );
    rr.push(
      credit(
        "ag-mandatory",
        "専門教育の必修科目",
        mandatory,
        match((a) => a.mandatory),
      ),
    );
    rr.push(
      check(
        "ag-selective",
        "選択必修と選択の内訳",
        "履行状況報告書は選択必修と選択を一つの欄に掲載しています。設置資料の履修方法と入学時の農学部履修表で照合してください。",
        method,
      ),
    );
  } else
    rr.push(
      check(
        "program",
        "専門科目のプログラム別条件",
        "プログラムの配属先を選択してください。",
        evidence,
      ),
    );
  rr.push(...flags);
  return {
    title: book.title,
    sources: [evidence, method, agricultureLaw, scopeSource],
    stages: [research(), stage("graduation", "卒業", rr)],
    cap: {
      limit: 24,
      source: evidence,
      classify: (c) =>
        norm(c.format) === "講義" &&
        c.period !== "集中" &&
        !c.failedRetake &&
        !c.teacherTraining
          ? "include"
          : "unknown",
      note: capNote,
    },
  };
}
