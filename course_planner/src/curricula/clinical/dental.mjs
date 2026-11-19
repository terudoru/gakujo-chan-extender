import {
  act,
  category,
  combined,
  contribution,
  credits,
  decision,
  generalCategories,
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
import { scienceRows } from "./medicine.mjs";
import { dentistry2025, oral2025 } from "./subject-tables.mjs";
import { syllabusSection } from "./catalog-sections.mjs";

export const dentalAct = source("新潟大学歯学部規程・附則", act(110000514));
export const oldDental = "https://www.niigata-u.ac.jp/wp-content/uploads/2025/09/r8gishiho_kihon.pdf";
const standard = source("歯学部規程第8条 進級", act(110000514, "#at8"));
const clinical = source(
  "歯学科の診療参加型臨床実習・開始条件",
  "https://www.dent.niigata-u.ac.jp/faculty/dentistry/curriculum/",
);
const exam = source("歯学部専門科目試験規程第3条", act(110000519, "#at3"));
const degree = source("歯学部規程第10・11条", act(110000514, "#at10"));
export const historicalDental = source(
  "歯学部の2016年度入学者からの教育課程・必修PBL科目",
  "https://www.niigata-u.ac.jp/wp-content/uploads/2020/08/R2_genkyo_kyoiku_07.pdf",
);
function dentalGeneral(oral, old, src) {
  const part = (k, l, n, m, y = 1) => ({ ...credits(k, l, n, m, src, { exclusive: "dental-general" }), year: y });
  const subject = (n, u) => named(n, "84", u);
  const rows = [
    part("english", "英語", 2, subcategory("英語", "英語")),
    part("foreign", "初修外国語", 2, category("初修外国語")),
    part("study", "歯学スタディ・スキルズ", 2, subject("歯学スタディ・スキルズ", 2)),
    part("data", "データサイエンス総論Ⅰ", 1, subject("データサイエンス総論Ⅰ", 1)),
  ];
  if (oral) {
    rows.push(
      part("sport", "体育実技", 1, subcategory("健康・スポーツ", "体育実技", /^健康スポーツ科学実習/)),
      part(
        "science",
        "自然系共通専門基礎（物理学・化学・生物学）",
        4,
        combined(...scienceRows(src, 2).slice(1).map((r) => r.match)),
      ),
      part("psychology", "心理学", 2, subcategory("人文社会・教育科学", "心理学", /^心理学$/)),
      part("sociology", "社会学", 2, subcategory("人文社会・教育科学", "社会学", /^社会学$/)),
      part("social-rest", "人文社会・教育科学の残り", 4, category("人文社会・教育科学")),
      ...["Ⅰ", "Ⅱ"].map((n) => part("intro-" + n, "医学序説" + n, 2, subject("医学序説" + n, 2))),
    );
  } else {
    rows.push(
      ...scienceRows(src, 2).map((r) => ({ ...r, year: 1, exclusive: "dental-general" })),
      part("study-2", "歯学スタディ・スキルズⅡ", 2, subject("歯学スタディ・スキルズⅡ", 2), 2),
      part("pbl", "PBL入門", 1, subject("PBL入門", 1), 3),
    );
    if (old) rows.push(part("general-seminar", "教養を考える", 2, subject("教養を考える", 2)));
  }
  const generalChoice = category(...generalCategories);
  rows.push(part("choice", "教養教育科目の自由選択", oral ? 6 : old ? 20 : 22, (c) => {
    if (c.category === "留学生基本科目" && !syllabusSection(c)) return null;
    if (c.category === "留学生基本科目" && ["日本語", "日本事情"].includes(syllabusSection(c))) return false;
    return generalChoice(c);
  }));
  return rows;
}
export function scienceBreadth(src) {
  const options = scienceRows(src, 2).slice(1);
  return {
    ...credits("science-breadth", "物理学・化学・生物学のうち2区分", 2, combined(...options.map((r) => r.match)), src),
    unit: "courses",
    evaluate: ({ courses }) => {
      const contributions = [];
      let unknown = false;
      for (const opt of options) {
        const c = courses.find((c) => opt.match(c) === true && c.credits > 0);
        if (c) contributions.push(contribution(c, 1));
        else if (courses.some((c) => opt.match(c) == null)) unknown = true;
      }
      return {
        value: contributions.length,
        contributions,
        ...(unknown && contributions.length < 2
          ? { unknown: "自然系共通専門基礎の細区分を歯学部学務係で確認してください。" }
          : {}),
      };
    },
  };
}
export function dental(p) {
  const oral = p.faculty === "歯学部口腔生命福祉学科", y = Number(p.handbook), old = y < 2025;
  if (!Number.isInteger(y) || y < 2021 || y > 2026) return null;
  const src = source(
    old ? "改正前の教育課程・卒業要件" : "歯学部規程・教養教育科目",
    old ? oldDental + "#page=" + (oral ? 64 : 53) : act(110000514, oral ? "#bt2" : "#bt1"),
  );
  const prof = source(
    old ? "改正前の教育課程・専門の年次配当" : "歯学部規程・専門科目の年次別配当",
    old ? oldDental + "#page=" + (oral ? 63 : 51) : act(110000514, oral ? "#bt4" : "#bt3"),
  );
  const gen = dentalGeneral(oral, old, src);
  const table = oral ? oral2025 : dentistry2025;
  const family = oral ? /^\d{3}DA/i : /^\d{3}DS/i;
  const major = table.filter((r) => !r[3]).map(([n, units, year]) => ({
    ...credits(
      "dent-" + norm(n),
      n,
      units,
      named(n === "口腔と全身との関わり" ? [n, "口腔と全身とのかかわり"] : n, "08", units, family),
      prof,
    ),
    year,
  }));
  if (oral) {
    const choice = table.filter((r) => r[2] === 4 && r[3]).map(([n]) => n);
    major.push({
      ...credits("oral-choice", "4年次の指定5科目から選択", 2, named(choice, "08", 2, family), prof, {
        kind: "選択必修",
      }),
      year: 4,
    });
  }
  const attendance = decision(
    "attendance",
    "専門科目試験の受験資格",
    "講義は授業時間の3分の2、実習は4分の3以上の出席が必要です。担当教員・歯学部学務係で出席を確認してください。",
    exam,
  );
  const stages = [];
  for (let year = 1; year < (oral ? 4 : 6); year++) {
    const parts = gen.filter((r) => r.year === year), units = major.filter((r) => r.year === year);
    const rows = [];
    if (parts.length) {
      rows.push(
        subtotal("general", "当該年次の指定教養科目", parts.reduce((a, r) => a + r.required, 0), parts, src),
        ...parts,
      );
    }
    if (oral && year === 1) rows.push(scienceBreadth(src));
    rows.push(
      subtotal("major", "当該年次の指定専門科目", units.reduce((a, r) => a + r.required, 0), units, prof),
      ...units,
      attendance,
    );
    stages.push(stage("year-" + (year + 1), (year + 1) + "年次進級", "progress", rows, [standard, src, prof]));
  }
  if (!oral) {
    stages.push(stage("clinical-practice", "5年次・診療参加型臨床実習の開始", "progress", [
      ...major.filter((r) => r.year === 5 && r.label !== "臨床実習I"),
      decision(
        "prior-terms",
        "5年次前期までの全指定科目の修了",
        "第1～4年次と第5年次前期の必修科目の修得を歯学部学務係の記録で確認してください。",
        clinical,
      ),
      ...["CBT", "OSCE"].map((n) =>
        decision(
          "pre-clinical-" + n,
          "臨床実習前共用試験 " + n,
          "歯学部学務係で" + n + "の合格結果を確認してください。",
          clinical,
        )
      ),
      attendance,
    ], [clinical, prof]));
  }
  const genTotal = subtotal("general", "教養教育科目", oral ? 30 : 40, gen, src);
  const majorTotal = subtotal("major", "専門教育科目", oral ? 120 : 152, major, prof);
  stages.push(stage("graduation", "卒業", "graduation", [
    subtotal("total", "卒業単位の合計", oral ? 150 : 192, [genTotal, majorTotal], src, { kind: "合計" }),
    genTotal,
    ...gen,
    ...(oral ? [scienceBreadth(src)] : []),
    majorTotal,
    ...major,
    residency("residency", "学科での在学期間", oral ? 48 : 72, degree),
    attendance,
    stageApproval("歯学部学務係", degree),
    ...recognition(p, "歯学部学務係", degree),
  ], [degree, src, prof]));
  return {
    title: y + "年度 " + p.faculty,
    sources: [dentalAct, src, prof, exam],
    stages,
    note:
      "留学生等の日本語・日本事情による振替、再試験、教授会が認める年次配当や進級の特例は歯学部学務係の個別判定です。",
  };
}
