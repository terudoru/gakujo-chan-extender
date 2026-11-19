import {
  category,
  type,
  name,
  norm,
  night,
  row,
  check,
  stage,
  transferRow,
} from "./common.mjs";
import { agricultureLaw } from "./agriculture-legacy.mjs";
export const formerAgriculturePrograms = [
  "農業生産科学科",
  "応用生物化学科",
  "生産環境科学科",
  ...["生物生産情報工学", "地域環境工学", "森林管理科学", "生態環境科学"].map(
    (n) => "生産環境科学科（" + n + "コース）",
  ),
];
const oldReport = {
  title: "農学部・平成16～19年度現況調査、資料2-1-1",
  url: "https://www.niad.ac.jp/sub_hyouka/kokudai2010/no6_3_36_niigata_2010_6_2.pdf#page=150",
};
const newReport = {
  title: "農学部・平成22～27年度現況調査、資料12と卒業最低単位",
  url: "https://www.niigata-u.ac.jp/wp-content/uploads/2016/07/H27_genkyo_kyoiku_09.pdf#page=9",
};
const contact = {
  title: "農学部学務係・在学生の履修案内",
  url: "https://www.agr.niigata-u.ac.jp/students",
};
export function formerAgriculture(book, p) {
  const y = +book.year,
    report = y === 2007 ? oldReport : newReport;
  const isProduction = p.program?.includes("農業生産科学科"),
    isApplied = p.program?.includes("応用生物化学科"),
    isEnv = p.program?.includes("生産環境科学科");
  const changes = [
    [
      2011,
      ["アグリビジネス論", "食品産業論", "食品産業論演習"],
      y <= 2008 ? "教養" : "選択",
    ],
    [2012, ["トライアルインターンシップ"], "教養"],
    [2012, ["海外語学研修"], "選択"],
    [
      2013,
      [
        ...(isProduction ? ["作物生理生態学", "植物病原微生物学"] : []),
        "基礎農力",
        "応用農力",
      ],
      "選択",
    ],
    [
      2016,
      ["グローバル農力", "グローバル防災・復興学", "キャリアビジョン研修"],
      "選択",
    ],
  ];
  const rr = [];
  for (const [cut, names, k] of changes)
    if (y < cut)
      rr.push(
        check(
          "former-" + cut + k,
          names.join("・") + "の" + k + "区分への読替",
          cut +
            "年4月1日の在籍が必要です。農学部学務係で改正附則の対象者と認定区分を確認してください。",
          agricultureLaw,
        ),
      );
  const general = (c) =>
    !type(c)
      ? null
      : night(c) || c.graduationExcluded
        ? false
        : type(c) === "G" &&
            [
              "大学学習法",
              "英語",
              "初修外国語",
              "健康・スポーツ",
              "情報リテラシー",
              "自然系共通専門基礎",
              "自然科学",
              "医歯学",
              "新潟大学個性化科目",
              "人文社会・教育科学",
            ].includes(category(c)) &&
            (c.recognitionApproved || Number(c.code.slice(0, 2)) <= 16)
          ? true
          : null;
  if (y === 2007 || y === 2015)
    rr.unshift(
      row(
        "total",
        "卒業に算入できる単位",
        "単位",
        124,
        (c) => (general(c) === true ? true : null),
        report,
      ),
    );
  else
    rr.unshift(
      check(
        "total",
        "入学年度の卒業に必要な総単位",
        "当時の調査では124単位です。入学時の学科別規程と改正附則を農学部学務係で照合してください。",
        report,
      ),
    );
  if (y === 2007) {
    const credit = (k, l, v, fn) => rr.push(row(k, l, "単位", v, fn, report));
    const cat = (l) => (c) => (general(c) === true ? category(c) === l : null);
    credit("general", "教養教育", 40, general);
    credit("major", "専門教育", 80, (c) => (type(c) === "G" ? false : null));
    for (const [k, l, v] of [
      ["study", "大学学習法", 2],
      ["english", "英語", 4],
      ["foreign", "初修外国語", 4],
      ["sport", "健康・スポーツ", 1],
    ])
      credit(k, l, v, cat(l));
    if (isProduction || isApplied)
      credit("data", "情報リテラシー", 2, cat("情報リテラシー"));
    if (isProduction || isApplied || isEnv)
      credit(
        "natural",
        "自然系共通専門基礎・自然科学・医歯学",
        isProduction ? 10 : isApplied ? 14 : 16,
        (c) =>
          general(c) === true
            ? ["自然系共通専門基礎", "自然科学", "医歯学"].includes(category(c))
            : null,
      );
    if (isApplied)
      for (const l of ["化学", "生物学"])
        credit("natural-" + l, "自然系共通専門基礎の" + l, 4, (c) =>
          general(c) === true
            ? category(c) === "自然系共通専門基礎" && c.subcategory === l
            : null,
        );
    if (isProduction || isApplied || isEnv) {
      const idx = formerAgriculturePrograms.indexOf(p.program) - 3;
      const split = isProduction
        ? [16, 22]
        : isApplied
          ? [48, 22]
          : idx >= 0
            ? [
                [20, 42],
                [22, 48],
                [25, 39],
                [23, 39],
              ][idx]
            : null;
      if (split)
        for (const [index, text] of ["必修科目", "選択必修科目"].entries())
          credit("dept-" + index, text, split[index], (c) =>
            type(c) === "G" ? false : null,
          );
    }
  }
  rr.push(
    check(
      "program-table",
      "旧学科・コースの開講科目と区分",
      "手引で指定された科目名とコース区分を農学部学務係で照合してください。",
      contact,
    ),
    ...transferRow(p, agricultureLaw, "農学部"),
  );
  return {
    title: book.title,
    sources: [agricultureLaw, oldReport, newReport, contact],
    stages: [
      stage("thesis", "卒業論文の履修", [
        check(
          "research",
          "学科・コース別の卒論履修資格",
          "改組前の卒論研究の開講時期と履修の前提条件を農学部学務係に確認してください。",
          contact,
        ),
      ]),
      stage("graduation", "卒業", rr),
    ],
    cap: {
      limit: null,
      classify: () => "unknown",
      source: contact,
      note: "改組前の学科ごとの学期上限は入学時の手引で確認してください。",
    },
  };
}
