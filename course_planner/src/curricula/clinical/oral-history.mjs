import {
  category,
  combined,
  credits,
  decision,
  named,
  recognition,
  residency,
  source,
  stage,
  stageApproval,
  subcategory,
  subtotal,
} from "./rules.mjs";
import { dentalAct, scienceBreadth } from "./dental.mjs";

const root = "https://www.niigata-u.ac.jp/wp-content/uploads/2016/03/";
export function oralArchive(year) {
  return year === 2008
    ? source("平成20年度 口腔生命福祉学科の教育課程", root + "h20ishigakusogo_m_gaiyo.pdf#page=9")
    : source(
      "平成22年度公開・平成21年改正後の口腔生命福祉学科の教育課程",
      root + "h22ishigakusogo_d_kihon.pdf#page=13",
    );
}
const mandatory = [
  [["早期臨床実習ⅠB", 2]],
  [
    ["早期臨床実習ⅡB", 1],
    ["臨床歯学演習", 1],
    ["歯科衛生士概論", 1],
    ["医療倫理", 1],
    ["人体のしくみ", 8],
    ["疾病とその病態", 2],
    ["口腔の科学", 6],
    ["歯科臨床概論", 2],
    ["歯科衛生学Ⅰ", 8],
    ["歯科衛生学実習Ⅰ", 3],
    ["栄養学", 2],
    ["社会調査法", 2],
    ["衛生学・公衆衛生学", 2],
    ["歯科診療補助Ⅰ", 2],
    ["臨床歯科学Ⅰ", 1],
  ],
  [
    ["歯科衛生学実習Ⅱ", 3],
    ["歯科衛生学実習Ⅲ", 2],
    ["歯科診療補助Ⅱ", 4],
    ["高齢者・障害者歯科学", 2],
    ["臨床歯科学Ⅱ", 1],
    ["臨床歯科学Ⅲ", 1],
    ["歯科衛生士臨床実習Ⅰ", 4],
    ["社会福祉原論Ⅰ", 2],
    ["社会福祉援助技術論Ⅰ", 2],
    ["社会福祉援助技術論Ⅱ", 2],
    ["地域福祉論", 2],
    ["社会保障論", 2],
    ["高齢者福祉論Ⅰ", 4],
    ["障害者福祉論Ⅰ", 2],
    ["児童福祉論Ⅰ", 2],
    ["公的扶助論", 2],
    ["権利擁護と成年後見", 1],
    ["社会福祉援助技術演習Ⅰ", 4],
    ["社会福祉現場実習指導Ⅰ", 2],
  ],
  [
    ["臨床歯科学Ⅳ", 1],
    ["保健医療制度", 2],
    ["歯科衛生士臨床実習Ⅱ", 14],
    ["訪問歯科診療", 1],
    ["社会福祉行政", 1],
    ["社会福祉経営", 1],
    ["社会福祉援助技術演習Ⅱ", 1],
    ["社会福祉現場実習指導Ⅱ", 1],
    ["社会福祉現場実習", 4],
  ],
];
const old08 = [
  [["早期臨床実習ⅠB", 2]],
  [
    ["人体の構造と機能", 4],
    ["臨床歯学演習", 1],
    ["口腔の科学", 6],
    ["疾病とその病態", 2],
    ["医療倫理", 1],
    ["歯科衛生士概論", 1],
    ["歯科予防処置Ⅰ", 4],
    ["衛生学・公衆衛生学", 2],
    ["歯科臨床概論", 2],
    ["歯科診療補助Ⅰ", 2],
    ["早期臨床実習ⅡB", 1],
    ["咀嚼嚥下の科学", 4],
    ["栄養指導・栄養学", 4],
    ["保健指導Ⅰ", 3],
    ["口腔衛生学・歯科統計学Ⅰ", 2],
    ["臨床歯科学Ⅰ", 1],
  ],
  [
    ["歯科診療補助Ⅱ", 4],
    ["歯科予防処置Ⅱ", 4],
    ["高齢者・障害者歯科学", 2],
    ["歯科衛生士臨床実習Ⅰ", 4],
    ["介護概論", 2],
    ["保健指導Ⅱ", 1],
    ["社会福祉原論Ⅰ", 2],
    ["老人福祉論Ⅰ", 2],
    ["障害者福祉論Ⅰ", 2],
    ["児童福祉論Ⅰ", 2],
    ["社会保障論", 2],
    ["公的扶助論", 2],
    ["臨床歯科学Ⅱ", 2],
    ["社会福祉援助技術論", 4],
    ["社会福祉援助技術演習", 4],
    ["社会福祉援助技術現場実習指導", 2],
  ],
  [["訪問歯科診療", 1], ["歯科衛生士臨床実習Ⅱ", 14], ["口腔衛生学・歯科統計学Ⅱ", 2], ["社会保険と医療制度", 2], [
    "臨床歯科学Ⅲ",
    1,
  ], ["社会福祉援助技術現場実習", 4]],
];
export function historicalOral(p) {
  const y = Number(p.handbook);
  if (!Number.isInteger(y) || y < 2008 || y > 2014) return null;
  const src = oralArchive(y), old = y === 2008;
  const table = source("口腔生命福祉学科の指定専門科目と配当", src.url.replace(/page=\d+$/, "page=" + (old ? 8 : 12)));
  const g = (key, label, units, match) => credits(key, label, units, match, src, { exclusive: "oral-history-general" });
  const general = [
    g("english", "英語", 6, category("英語")),
    g("sport", "体育実技", 1, subcategory("健康・スポーツ", "体育実技", /^健康スポーツ科学実習/)),
    g("study", "歯学スタディスキルズ", 2, named(["歯学スタディスキルズ", "歯学スタディ・スキルズ"], "84", 2)),
    g(
      "science",
      "物理学・化学・生物学",
      4,
      combined(...["物理学", "化学", "生物学"].map((n) => subcategory("自然系共通専門基礎", n))),
    ),
    g("psychology", "心理学", 2, subcategory("人文社会・教育科学", "心理学")),
    g(
      "law-social",
      "法学または社会学",
      2,
      combined(...["法学", "社会学"].map((n) => subcategory("人文社会・教育科学", n))),
    ),
    g("social-rest", "人文社会・教育科学の残り", 4, category("人文社会・教育科学")),
    ...["Ⅰ", "Ⅱ"].map((n) => g("intro-" + n, "医学序説" + n, 2, named("医学序説" + n, "84", 2))),
    g("choice", "専門教育・日本語・日本事情を除く選択科目", 6, (c) => {
      if (c.department !== "84") return c.department ? false : null;
      if (!c.category || (c.category === "留学生基本科目" && !c.subcategory)) return null;
      return !["日本語", "日本事情"].includes(c.subcategory);
    }),
  ];
  const prof = (old ? old08 : mandatory).flatMap((items, index) =>
    items.map(([label, n]) => ({
      ...credits("oral-" + label, label, n, named(label, "08", n, /^\d{3}DA/i), table),
      year: index + 1,
    }))
  );
  const choices = old
    ? ["社会福祉原論Ⅱ", "老人福祉論Ⅱ", "障害者福祉論Ⅱ", "児童福祉論Ⅱ", "保健指導Ⅲ", "歯科予防処置Ⅲ"]
    : ["社会福祉原論Ⅱ", "高齢者福祉論Ⅱ", "障害者福祉論Ⅱ", "児童福祉論Ⅱ", "歯科衛生学Ⅱ"];
  prof.push(credits("oral-choice", "4年次選択科目", 2, named(choices, "08", 2, /^\d{3}DA/i), table));
  const majorUnits = old ? 109 : 116;
  const major = subtotal("major", "専門教育科目", majorUnits, prof, table);
  const gen = subtotal("general", "教養教育科目", 31, general, src);
  const stages = [1, 2, 3].map((n) =>
    stage("year-" + (n + 1), (n + 1) + "年次進級", "progress", [
      ...prof.filter((r) => r.year === n),
      decision(
        "promotion",
        "当時の進級判定",
        "年次配当の修了記録と当時の進級条件を歯学部学務係で照合してください。",
        dentalAct,
      ),
    ], [table, dentalAct])
  );
  stages.push(stage("graduation", "卒業", "graduation", [
    subtotal("total", "卒業単位の合計", 31 + majorUnits, [gen, major], src),
    gen,
    ...general,
    scienceBreadth(src),
    major,
    ...prof,
    residency("residency", "在学期間", 48, dentalAct),
    stageApproval("歯学部学務係", dentalAct),
    ...recognition(p, "歯学部学務係", dentalAct),
  ], [src, table, dentalAct]));
  return { title: y + "年度 歯学部口腔生命福祉学科", sources: [src, table, dentalAct], stages };
}
