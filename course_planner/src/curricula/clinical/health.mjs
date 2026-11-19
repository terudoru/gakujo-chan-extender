import {
  act,
  assessmentInApril,
  category,
  combined,
  condition,
  credits,
  decision,
  isSpecial,
  named,
  norm,
  recognition,
  residency,
  source,
  stage,
  stageApproval,
  subtotal,
  unknownCredits,
  wholeNumber,
} from "./rules.mjs";
import { medicalAct } from "./medicine.mjs";
import { laboratory, nursing, radiology } from "./subject-tables.mjs";
import { healthArchive } from "./health-history.mjs";

export const healthGuide = source(
  "保健学科 進級要件・卒業要件（編入生の適用年度を含む）",
  "https://www.clg.niigata-u.ac.jp/ug/requirements.html",
);
const table = source("医学部規程別表第5 専攻別専門科目", act(110000476, "#bt5"));
const schedule = source("保健学科の各年度・学年別時間割", "https://www.clg.niigata-u.ac.jp/ug/classcalendar.html");
const education = "https://www.niigata-u.ac.jp/wp-content/uploads/2025/09/r8gishiho_kihon.pdf";
const recognitionSrc = source("医学部規程第9条の2", act(110000476, "#at9.2"));
const nursingTransfer = source(
  "令和6年度以降の第3年次編入と保健師・助産師国家試験の受験資格",
  "https://www.clg.niigata-u.ac.jp/news/202207081700.html",
);
export const healthPrograms = ["看護学専攻", "放射線技術科学専攻", "検査技術科学専攻"];
const sections = ["基礎必修", "基礎選択", "専門必修", "専門選択"];
const counts = [[15, 6, 74, 3], [12, 5, 79, 2], [10, 8, 73, 7]];
const entries = [nursing, radiology, laboratory];
const families = [/^\d{3}M[85]1/i, /^\d{3}M[85]3/i, /^\d{3}M[85]5/i];
const baseFamily = /^\d{3}M[85]0/i;
const pool = category(
  "情報リテラシー",
  "新潟大学個性化科目",
  "自然系共通専門基礎",
  "自然科学",
  "人文社会・教育科学",
  "医歯学",
);
const excluded = (c) => c.category === "教職に関する科目" || c.subcategory === "教職に関する科目";
const generalParts = [["english", "英語", 3], ["foreign", "初修外国語", 2], ["sports", "健康・スポーツ", 1], [
  "study",
  "大学学習法",
  2,
]]
  .map(([k, label, n]) => credits(k, label, n, category(label), healthGuide));
const departmentPool = credits("general-pool", "情報・自然科学・人文社会等の選択枠", 18, pool, healthGuide, {
  kind: "選択必修",
  note: "情報リテラシー1単位、自然系共通専門基礎4単位以上を含む。医学部規程別表第5の専門科目を除く。",
});
function requiredSubject([name, units, group, assignedYear], index) {
  const family = group.startsWith("基礎") ? baseFamily : families[index];
  const matches = named(name, "07", units, family);
  return credits(
    "health-" + group + "-" + norm(name),
    name,
    units,
    (c) => {
      if (excluded(c)) return false;
      return matches(c);
    },
    table,
    { kind: group.endsWith("必修") ? "必修" : "選択", assignedYear },
  );
}
export function health(p) {
  const y = Number(p.handbook);
  const mixedEntry = p.entry === "編入・転部・再入学";
  const explicitGrade = /([1-4])年次編入|編入.*?([1-4])年次/.exec(norm(p.entry).replace("三", "3"));
  const transfer = !mixedEntry && /編入/.test(p.entry ?? "");
  const grade = wholeNumber(explicitGrade?.[1] ?? explicitGrade?.[2] ?? p.entryGrade);
  const entryGrade = transfer && grade >= 1 && grade <= 4 ? grade : null;
  const transfer3 = entryGrade === 3;
  const unknownExemption = mixedEntry || (transfer && entryGrade == null);
  const matriculation = wholeNumber(p.admitted);
  const grid = y >= 2022 && y <= 2026 && (!(transfer || mixedEntry) || matriculation >= 2024);
  if (!(y >= 2004 && y <= 2026)) return null;
  const index = healthPrograms.findIndex((n) =>
    norm(p.program) === norm(n) || norm(p.program) === norm(n.replace("専攻", ""))
  );
  const old = !isSpecial(p) && healthArchive(y, index);
  const poolGeneral = [...generalParts, departmentPool].map((r) => ({
    ...r,
    match: (c) => excluded(c) ? false : r.match(c),
  }));
  const gen = subtotal("general", "教養教育科目", 26, poolGeneral, healthGuide);
  const subjects = index < 0 ? [] : entries[index];
  const yearSource = source("保健学科の専攻別教育課程・配当年次", education + "#page=" + ([39, 40, 41][index] ?? 39));
  const groups = grid && index >= 0
    ? sections.map((group, i) => {
      const rows = subjects.filter((r) => r[2] === group).map((r) => requiredSubject(r, index));
      const label = group.replace("基礎", "専門基礎科目・").replace(/^専門(必修|選択)$/, "専門教育科目・$1");
      return {
        group,
        rows,
        summary: group.endsWith("必修")
          ? subtotal("health-" + group, label, counts[index][i], rows, healthGuide)
          : credits(
            "health-" + group,
            label,
            counts[index][i],
            combined(...rows.map((r) => r.match)),
            healthGuide,
            { kind: "区分計", allocationKeys: rows.map((r) => r.key) },
          ),
      };
    })
    : [];
  const majorMatch = groups.length
    ? combined(...groups.map((g) => g.summary.match))
    : (c) => excluded(c) || c.department === "84" ? false : old ? old.match(c) : null;
  const major = groups.length
    ? subtotal("major", "専門教育科目・専門基礎科目", 98, groups.map((g) => g.summary), healthGuide)
    : credits("major", "専門教育科目・専門基礎科目", 98, majorMatch, healthGuide, { kind: "区分計" });
  const stages = [];
  for (let year = 1; year <= 3; year++) {
    if (entryGrade != null && year < entryGrade) continue;
    const duration = residency("year-months", "第" + year + "年次での在学期間", 12, healthGuide, year);
    const rows = [duration, {
      key: "assessment-month",
      label: "4月の進級判定",
      kind: "判定時期",
      unit: "condition",
      required: 1,
      source: healthGuide,
      profileValue: assessmentInApril,
      note: "進級を判定する日付を入力してください。",
    }];
    if (year < 3 && unknownExemption) {
      rows.push(
        condition(
          "entry-grade",
          "この進級判定の適用年次",
          "編入時の年次を確認し、本人に適用される進級判定を選んでください。",
          healthGuide,
        ),
      );
    }
    if (year === 3) {
      if (!transfer3) {
        const explanation = unknownExemption
          ? "3年次編入の場合はこの必修条件が免除されます。入学区分と編入時の年次を保健学科学務係に確認してください。"
          : "専攻別時間割と成績確認表で、3年次までに開講する専門基礎・専門教育の必修全科目を保健学科学務係と照合してください。";
        if (!unknownExemption && groups.length) {
          for (const g of groups.filter((g) => g.group.endsWith("必修"))) {
            const leaves = g.rows.filter((r) => r.assignedYear <= 3);
            rows.push(
              subtotal(
                "through-year3-" + g.group,
                "3年次までの" + g.summary.label,
                leaves.reduce((n, r) => n + r.required, 0),
                leaves,
                yearSource,
              ),
              ...leaves.map((r) => ({ ...r, source: yearSource })),
            );
          }
        } else {
          rows.push(
            decision(
              "required-through-year3",
              "3年次までに開講する専門の必修全科目または編入による免除",
              explanation,
              unknownExemption ? healthGuide : schedule,
            ),
          );
        }
      }
      rows.push(
        decision(
          "faculty-review",
          "教授会の進級判定",
          "保健学科学務係で教授会を経た4月の進級判定を確認してください。",
          healthGuide,
        ),
      );
    }
    stages.push(stage("year-" + (year + 1), (year + 1) + "年次進級（4月）", "progress", rows, [healthGuide, schedule]));
  }
  const grad = [];
  if (grid) {
    grad.push(
      gen,
      ...poolGeneral,
      credits("information", "選択枠のうち情報リテラシー", 1, category("情報リテラシー"), healthGuide),
      credits("science", "選択枠のうち自然系共通専門基礎", 4, category("自然系共通専門基礎"), healthGuide),
      major,
    );
    if (index < 0) {
      grad.push(
        condition("program", "専攻別の専門必修・選択", "保健学科の3専攻から本人の専攻を選んでください。", healthGuide),
      );
    }
    for (const g of groups) {
      grad.push(g.summary);
      if (g.group.endsWith("必修")) grad.push(...g.rows);
    }
    if (y < 2026) {
      grad.push(
        decision(
          "historical-subjects",
          "当時の必修科目・単位数",
          "専攻別の必要単位数は年度別卒業要件表に基づきます。改正で配当・単位が変わった科目は入学年度の別表第5と照合してください。",
          healthGuide,
        ),
      );
    }
  } else if (y === 2014 && !isSpecial(p)) {
    const assessment = source(
      "平成26年度認証評価・保健学科の必要単位修得数",
      "https://www.niigata-u.ac.jp/wp-content/uploads/2016/03/H26ninsyo1-jiko.pdf#page=60",
    );
    grad.push(
      credits("general", "教養教育科目", 31, () => null, assessment, {
        unknown: "平成26年度の教養科目別配分を保健学科学務係で照合してください。",
      }),
      credits("major", "専門基礎・専門教育科目", 93, () => null, assessment, {
        unknown: "専門基礎17～20単位、専門教育73～76単位の専攻別指定と科目の読替を保健学科学務係で確認してください。",
      }),
    );
  } else {
    grad.push(
      unknownCredits(
        "general",
        "教養科目の区分と単位",
        "この入学区分・年度の別表第2を保健学科学務係で確認してください。",
        healthGuide,
      ),
      unknownCredits(
        "major",
        "専攻別の専門必修・選択と単位",
        "2022年度以降の表は編入学生には2024年度入学から適用されます。当時の別表第4・第5を保健学科学務係で照合してください。",
        healthGuide,
      ),
    );
  }
  if (old) stages.push(old.studyStage);
  const total = subtotal(
    "total",
    "卒業単位の合計",
    124,
    grad.filter((r) => ["general", "major"].includes(r.key)),
    healthGuide,
    { kind: "合計" },
  );
  grad.unshift({ ...total, match: (c, p) => excluded(c) ? false : total.match(c, p) });
  grad.push(
    residency("residency", "保健学科の在学期間", 48, medicalAct),
    stageApproval("保健学科学務係", medicalAct),
    ...recognition(p, "保健学科学務係", recognitionSrc),
  );
  if (isSpecial(p) && /編入/.test(p.entry)) {
    grad.push(
      decision(
        "transfer-limits",
        "編入生の在学年限・休学期間",
        "保健学科学務係で教授会が本人について認定した在学年限と休学期間を確認してください。",
        recognitionSrc,
      ),
    );
  }
  stages.push(stage("graduation", "卒業", "graduation", grad, [healthGuide, table]));
  const nursingAdmission = transfer3 && index === 0 && matriculation >= 2024;
  return {
    title: y + "年度 医学部保健学科" + (healthPrograms[index] ?? ""),
    sources: [healthGuide, medicalAct, yearSource, schedule, ...(nursingAdmission ? [nursingTransfer] : [])],
    stages,
    note: "教職に関する科目を卒業単位から除きます。" +
      (nursingAdmission
        ? "令和6年度以降の看護学専攻第3年次編入では、保健師・助産師国家試験の受験資格を取得できません。"
        : index === 0
        ? "保健師・助産師の資格課程は、入学区分と適用年度に応じて学務係で確認してください。"
        : ""),
  };
}
