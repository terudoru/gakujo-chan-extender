import {
  act,
  category,
  combined,
  condition,
  credits,
  named,
  norm,
  recognition,
  residency,
  source,
  stage,
  stageApproval,
  subcategory,
  subtotal,
} from "./rules.mjs";
import { medicine2022, medicine2026 } from "./subject-tables.mjs";

export const medicalAct = source("新潟大学医学部規程・附則", act(110000476));
const older =
  "https://www.med.niigata-u.ac.jp/pme/medical-education-center/wp-content/themes/niigata-u-pme/img/igakubu_kitei.pdf";
const annual23 = "https://www.niigata-u.ac.jp/wp-content/uploads/2022/11/r5igaku_syushi.pdf";
const annual21 = "https://www.niigata-u.ac.jp/wp-content/uploads/2021/04/r3igaku_syushi.pdf";
const annual20 = "https://www.niigata-u.ac.jp/wp-content/uploads/2020/04/r2igaku_syushi.pdf";
const oldSeries = (name, url) => source(name + "・医学部規程別表第3", url + "#page=5");
const current = source("医学科の専門科目・別表第3", act(110000476, "#bt3"));
const degree = source("医学部規程第9条・第9条の2", act(110000476, "#at9"));
const advancement = source("医学部規程第7条・学年末の進級判定", act(110000476, "#at7"));
const practice = source("医学科臨床実習Ⅰ・学習の条件", annual23 + "#page=86");
const clinicalExams = source(
  "医学教育センター 共用試験・臨床実習後評価",
  "https://www.med.niigata-u.ac.jp/pme/business/index.html",
);
const old24 = source("令和6年施行 医学部規程別表第3", older + "#page=4");
const study24 = source("医学科履修基準・出席と考査", older + "#page=6");
const old22 = oldSeries("令和5年度設置届出", annual23);
const old21 = oldSeries("令和3年度設置届出", annual21);
const old19 = oldSeries("令和2年度設置届出（改正前の別表）", annual20);
const medicine2024 = [
  ...medicine2026.filter((r) => r[2] <= 2).map(([n, c, y]) => [n === "基礎臨床統合Ⅰ" ? "基礎臨床統合" : n, c, y]),
  ["薬物による生体調節", 2, 3],
  ["アドバンス基礎医学", 1.5, 3],
  ["早期地域医療体験実習(EME)Ⅲ", 1, 3],
  ...medicine2022.filter(([n, , y]) => y === 3 && !["基礎薬理", "臓器別講義・演習Ⅰ"].includes(n)),
  ["臓器別講義・演習Ⅰ", 15, 3],
  ...medicine2022.filter(([, , y]) => y >= 4),
  ["多職種連携", 0.5, 4],
];
const medFamily = /^\d{3}M1/i;
const excluded = [
  "実践医学英語演習",
  "夏期臨床・基礎医学",
  "新潟大学における医学研究に基盤をおいた最新医療の演習",
  ...["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"].map((n) => "自己主導型臨床実習" + n),
].map(norm);
export function medicineSources(y) {
  if (y === 2026) return current;
  if ([2024, 2025].includes(y)) return old24;
  if ([2022, 2023].includes(y)) return old22;
  if ([2020, 2021].includes(y)) return old21;
  if ([2017, 2018, 2019].includes(y)) return old19;
  return null;
}
export function scienceRows(src, minimum) {
  return [["数学・統計学", 2, /^(?:数学|統計学|微分積分学|線形代数学)/], ["物理学", minimum, /^物理学/], [
    "化学",
    minimum,
    /^化学/,
  ], ["生物学", minimum, /^生物学/]].map(([name, num, test]) =>
    credits("science-" + name, name, num, subcategory("自然系共通専門基礎", name, test), src)
  );
}
function medGeneral(src) {
  const g = (k, label, num, test) => credits(k, label, num, test, src, { exclusive: "medical-general" });
  return [
    g("english", "英語", 2, subcategory("英語", "英語")),
    g("foreign", "初修外国語", 6, category("初修外国語")),
    g("sport", "体育実技", 1, subcategory("健康・スポーツ", "体育実技", /^健康スポーツ科学実習/)),
    ...["Ⅰ", "Ⅱ"].map((n) => g("data-" + n, "データサイエンス総論" + n, 1, named("データサイエンス総論" + n, "84", 1))),
    ...scienceRows(src, 4).map((r) => ({ ...r, exclusive: "medical-general" })),
    g("experiment", "自然科学基礎実験", 2, named("自然科学基礎実験", "84", 2)),
    g("intro", "医学序説Ⅰ", 2, named("医学序説Ⅰ", "84", 2)),
    g(
      "choice",
      "自由選択",
      14,
      category(
        "英語",
        "初修外国語",
        "健康・スポーツ",
        "情報リテラシー",
        "自然系共通専門基礎",
        "自然科学",
        "医歯学",
        "人文社会・教育科学",
        "新潟大学個性化科目",
      ),
    ),
  ];
}
export function medicine(p) {
  const y = Number(p.handbook), src = medicineSources(y);
  if (!src) return null;
  const generalSrc = y >= 2026
    ? source("医学科の教養科目・別表第1", act(110000476, "#bt1"))
    : y >= 2024
    ? source("医学科の教養科目・令和6年施行別表第1", older + "#page=3")
    : y >= 2022
    ? source("医学教育プログラム 教養の履修方法", annual23 + "#page=16")
    : y >= 2020
    ? source(
      "令和2年度公表・医学科の卒業単位数",
      "https://www.niigata-u.ac.jp/wp-content/uploads/2020/09/uni_syugakushien2020.pdf#page=86",
    )
    : source(
      "令和元年度公表・医学科の卒業単位数",
      "https://www.niigata-u.ac.jp/wp-content/uploads/2019/09/uni_syugakushien.pdf#page=52",
    );
  const subjects = y === 2026
    ? medicine2026
    : y >= 2024
    ? medicine2024
    : y >= 2020
    ? medicine2022
    : medicine2022.filter(([n]) => !["医学英語Ⅰ", "医学英語Ⅱ"].includes(n));
  const major = subjects.map(([name, num, year]) => ({
    ...credits("med-" + norm(name), name, num, named(name, "07", num, medFamily), src),
    year,
  }));
  const legacyFixed = [
    ...["Ⅰ", "Ⅱ"].map((n) => ["実践コミュニケーション英語" + n, 1, 7]),
    ["健康スポーツ科学実習Ⅰ", 1, 10],
    ["データサイエンス総論Ⅰ", 1, 10],
    ["データサイエンス総論Ⅱ", 1, 10],
    ["統計学基礎１", 1, 11],
    ["統計学基礎２", 1, 11],
    ["物理学基礎ＣⅠ", 2, 11],
    ["物理学基礎ＣⅡ", 2, 11],
    ["化学基礎Ａ", 2, 11],
    ["化学基礎Ｂ", 2, 11],
    ["生物学基礎Ａ", 2, 11],
    ["生物学基礎Ｂ", 2, 11],
    ["自然科学基礎実験", 2, 11],
    ["医学序説Ⅰ", 2, 12],
  ];
  const general = y >= 2024 ? medGeneral(generalSrc) : [];
  const historicGeneral = y >= 2022 && y < 2024
    ? legacyFixed.map(([name, units, page]) =>
      credits(
        "general-" + norm(name),
        name,
        units,
        named(name, "84", units),
        source("医学教育プログラム・教養科目表", annual23 + "#page=" + page),
      )
    )
    : [];
  const generalCheck = condition(
    "general-designation",
    "教養科目の区分・指定科目",
    "当該年度の医学部規程別表第1で、英語・初修外国語・自然系共通専門基礎等の配分と読替を医学科学務係に確認してください。",
    generalSrc,
  );
  const majorSum = (rows) =>
    subtotal("major", "当該年次の指定専門科目", rows.reduce((s, r) => s + r.required, 0), rows, src);
  const majorRow = { ...majorSum(major), label: "専門必修科目" };
  const genMatch = general.length ? combined(...general.map((r) => r.match)) : (c, p) => {
    if (c.department && c.department !== "84") return false;
    return historicGeneral.some((r) => r.match(c, p) === true) ? true : null;
  };
  const gen = general.length
    ? subtotal("general", "教養教育科目", 43, general, generalSrc)
    : credits("general", "教養教育科目", y >= 2020 ? 43 : 45, genMatch, generalSrc, { unknown: generalCheck.unknown });
  const totalMatch = combined(genMatch, majorRow.match);
  const attend = condition(
    "attendance",
    "専門科目の出席・考査",
    "医学科学務係で考査の受験資格と成績を確認してください。出席が授業時間の3分の2に達しない場合は受験資格を失うことがあります。",
    study24,
  );
  const stages = [];
  for (let year = 1; year <= 5; year++) {
    const rows = major.filter((r) => r.year === year);
    stages.push(stage("year-" + (year + 1), (year + 1) + "年次進級", "progress", [
      ...(year === 1 ? [gen, ...general, ...historicGeneral, ...(!general.length ? [generalCheck] : [])] : []),
      majorSum(rows),
      ...rows,
      ...(y >= 2024 ? [attend] : []),
    ], [advancement, src]));
  }
  stages.push(
    stage(
      "clinical-practice",
      "診療参加型臨床実習の開始",
      "progress",
      ["CBT", "OSCE"].map((n) =>
        condition(
          "clinical-" + n,
          "臨床実習前共用試験 " + n,
          "医学科学務係で" + n + "の合格結果を確認してください。",
          practice,
        )
      ),
      [practice, clinicalExams],
    ),
  );
  const total = general.length
    ? subtotal("total", "卒業単位の合計", 43 + majorRow.required, [...general, ...major], src, { kind: "合計" })
    : credits(
      "total",
      "卒業単位の合計",
      gen.required == null ? null : gen.required + majorRow.required,
      (c, p) => excluded.includes(norm(c.title)) ? false : totalMatch(c, p),
      src,
      { kind: "合計", ...(gen.required == null ? { unknown: generalCheck.unknown } : {}) },
    );
  const gradRows = [
    total,
    gen,
    ...general,
    ...historicGeneral,
    ...(!general.length ? [generalCheck] : []),
    majorRow,
    ...major,
    residency("residency", "医学科の在学期間", 72, degree),
    stageApproval("医学科学務係", degree),
    ...recognition(p, "医学科学務係", degree),
  ];
  if (y >= 2024) gradRows.push(attend);
  if (y >= 2017) {
    gradRows.push(
      condition(
        "clinical-exam",
        "卒業時の臨床能力評価",
        "医学科学務係で卒業時臨床実習後OSCEの合格と適用される評価方法を確認してください。",
        clinicalExams,
      ),
    );
  }
  if (/編入/.test(p.entry ?? "")) {
    gradRows.push(
      condition(
        "transfer-limits",
        "編入学の場合の在学年限・休学期間",
        "医学科学務係で編入認定と在学年限を照合してください。2年次は最長3年、2～4年次通算6年、5～6年次通算4年です。休学期間にも年次別の上限があります。",
        degree,
      ),
    );
  }
  if (y < 2024) {
    gradRows.push(
      condition(
        "transition-2024",
        "2024年改正後の専門科目を履修した場合",
        "施行時の在学者が改正別表第3の科目を算入できる場合があります。対応科目と認定単位を医学科学務係に確認してください。",
        medicalAct,
      ),
    );
  }
  stages.push(stage("graduation", "卒業", "graduation", gradRows, [degree, src, generalSrc]));
  return {
    title: y + "年度 医学部医学科",
    sources: [medicalAct, src, generalSrc],
    stages,
    note: (y < 2022
      ? "教養の単位数は同じ規程期間に大学が公表した卒業総単位数から専門別表の合計を引いた値です。当時の教養科目別の配分と読替は医学科学務係で照合してください。"
      : "") + "外国人留学生等の日本語・日本事情の代替、再試験、個別の既修得認定は医学科学務係の判定によります。",
  };
}
