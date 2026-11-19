import { condition, credits, named, recognition, source, stage } from "./clinical/rules.mjs";
import { medicalAct, medicine, medicineSources } from "./clinical/medicine.mjs";
import { health, healthGuide, healthPrograms } from "./clinical/health.mjs";
import { healthArchive } from "./clinical/health-history.mjs";
import { dental, dentalAct, historicalDental, oldDental } from "./clinical/dental.mjs";
import { historicalOral, oralArchive } from "./clinical/oral-history.mjs";
import { creation, creationBooks } from "./clinical/creation.mjs";
import { listing2026 } from "./clinical/catalog-sections.mjs";

const faculties = {
  医学部医学科: [medicine, medicalAct, "医学科学務係"],
  医学部保健学科: [health, healthGuide, "保健学科学務係"],
  歯学部歯学科: [dental, dentalAct, "歯学部学務係"],
  歯学部口腔生命福祉学科: [(p) => dental(p) ?? historicalOral(p), dentalAct, "歯学部学務係"],
  創生学部: [
    creation,
    source("創生学部の入学年度別学生便覧", "https://create.niigata-u.ac.jp/students/"),
    "創生学部学務係",
  ],
};
const capSource = source(
  "新潟大学の学科別履修単位登録上限の公表表（88頁）",
  "https://www.niigata-u.ac.jp/wp-content/uploads/2026/08/uni_syugakushien2026.pdf#page=88",
);
const assessment2014 = source(
  "平成26年度 大学機関別認証評価・必要単位修得数",
  "https://www.niigata-u.ac.jp/wp-content/uploads/2016/03/H26ninsyo1-jiko.pdf#page=60",
);
const priorTotals = {
  2019: source(
    "令和元年度公表の学科別卒業単位数",
    "https://www.niigata-u.ac.jp/wp-content/uploads/2019/09/uni_syugakushien.pdf#page=52",
  ),
  2020: source(
    "令和2年度公表の学科別卒業単位数",
    "https://www.niigata-u.ac.jp/wp-content/uploads/2020/09/uni_syugakushien2020.pdf#page=86",
  ),
};
function editions(first, last, faculty, getSource, programs) {
  return Array.from({ length: last - first + 1 }, (_, i) => {
    const y = first + i;
    return { faculty, year: String(y), ...getSource(y), ...(programs ? { programs } : {}) };
  });
}
export const handbooks = [
  ...creationBooks,
  ...editions(2017, 2026, "医学部医学科", medicineSources),
  ...editions(2022, 2026, "医学部保健学科", () => healthGuide, healthPrograms),
  ...editions(
    2019,
    2021,
    "医学部保健学科",
    (y) => source("令和4年度時間割に掲載された旧課程の専攻別科目", healthArchive(y, 0).src.url.split("#")[0]),
    healthPrograms,
  ),
  ...editions(2014, 2014, "医学部保健学科", () => assessment2014, healthPrograms),
  ...["歯学部歯学科", "歯学部口腔生命福祉学科"].flatMap((faculty) =>
    editions(
      2021,
      2026,
      faculty,
      (y) =>
        y >= 2025
          ? dentalAct
          : source("改正前の教育課程・卒業要件", oldDental + "#page=" + (faculty === "歯学部歯学科" ? 53 : 64)),
    )
  ),
  ...editions(2008, 2014, "歯学部口腔生命福祉学科", oralArchive),
  ...editions(2009, 2014, "歯学部歯学科", () => assessment2014),
  ...editions(2019, 2020, "歯学部口腔生命福祉学科", (y) => priorTotals[y]),
  ...editions(2016, 2020, "歯学部歯学科", () => historicalDental),
];
function archiveProfile(p, src, office) {
  const status = (section) => p.handbook + "年度入学者に適用された" + section + "を" + office + "で確認してください。";
  const oldPbl = p.faculty === "歯学部歯学科" && Number(p.handbook) >= 2016 && Number(p.handbook) <= 2020;
  const year = Number(p.handbook);
  const dentistry = p.faculty === "歯学部歯学科";
  const oral = p.faculty === "歯学部口腔生命福祉学科";
  const historicSplit = dentistry && year >= 2009 && year <= 2014;
  const totals = historicSplit
    ? 202
    : (dentistry || oral) && priorTotals[year]
    ? (dentistry ? (year === 2019 ? 195 : 191) : (year === 2019 ? 147 : 145))
    : null;
  const numbers = historicSplit ? assessment2014 : priorTotals[year];
  const evidence = [src, ...(oldPbl ? [historicalDental] : []), ...(totals ? [numbers] : [])];
  const stages = [stage("advancement", "進級", "progress", [
    condition("year-table", "当時の進級条件と指定科目の年次配当", status("年次別の必修配当と進級判定"), src),
  ], evidence)];
  if (oldPbl) {
    for (
      const [year, courses] of [[3, ["PBL入門", "人体のしくみ"]], [4, ["生涯にわたる歯と咬合"]], [5, [
        "口腔と全身との関わり",
      ]]]
    ) {
      stages.push(
        stage(
          "pbl-" + year,
          year + "年次の必修PBL科目",
          "progress",
          courses.map((label, index) => ({
            key: "pbl-" + index,
            label,
            kind: "必修",
            required: 1,
            unit: "courses",
            source: historicalDental,
            match: label === "PBL入門" ? named(label, "84") : named(label, "08", undefined, /^\d{3}DS/i),
          })),
          evidence,
        ),
      );
    }
  }
  stages.push(stage("graduation", "卒業", "graduation", [
    historicSplit
      ? credits("general", "教養教育科目", 45, () => null, numbers, { unknown: status("教養科目の別表") })
      : condition("general", "当時の教養科目の区分と必要単位", status("教養科目の別表"), src),
    historicSplit
      ? credits("major", "専門教育科目", 157, () => null, numbers, { unknown: status("専門科目の別表と読替") })
      : condition("major", "当時の専門必修・選択と必要単位", status("専門科目の別表と読替"), src),
    totals
      ? credits("total", "当時の公表表による卒業単位数", totals, () => null, numbers, {
        unknown: status("科目区分と個別認定"),
      })
      : condition("total", "卒業に必要な単位", status("経過措置を含む卒業要件"), src),
    ...recognition(p, office, src),
  ], evidence));
  return { title: p.handbook + "年度 " + p.faculty, stages, sources: evidence };
}
export default function resolve(profile) {
  if (!Object.hasOwn(faculties, profile?.faculty)) return null;
  const [resolveFaculty, src, office] = faculties[profile.faculty];
  const selected = resolveFaculty(profile) ?? archiveProfile(profile, src, office);
  const descriptor = { ...selected, sources: [...selected.sources, listing2026] };
  if (descriptor.cap || profile.faculty === "創生学部") return descriptor;
  return {
    ...descriptor,
    cap: {
      limit: null,
      source: capSource,
      classify: () => "unknown",
      note: "大学の公表表ではこの学科の登録上限は空欄です。当該年度・履修区分の上限と対象科目を" + office +
        "で確認してください。",
    },
  };
}
