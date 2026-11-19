import {
  norm,
  name,
  type,
  category,
  night,
  record,
  courseYear,
  stage,
  row,
  check,
  transferRow,
} from "./common.mjs";
import { formerEngineeringCourses } from "./engineering-equivalences.mjs";

export const formerDepartments = [
  "機械システム工学科",
  "電気電子工学科",
  "情報工学科",
  "福祉人間工学科",
  "化学システム工学科",
  "建設学科（社会基盤工学コース）",
  "建設学科（建築学コース）",
  "機能材料工学科",
];
const programs = [
  "機械システム工学",
  "電子情報通信",
  "知能情報システム",
  "人間支援感性科学",
  "化学システム工学",
  "社会基盤工学",
  "建築学",
  "材料科学",
];
const pages = [
  [2010, 2012, 2013, 2014, 2015, 2016],
  [2010, 2011, 2012, 2013, 2014, 2015, 2016],
  [2011, 2012, 2013, 2014, 2015, 2016],
  [2012, 2013, 2014, 2015, 2016],
  [2012, 2013, 2014, 2015, 2016],
  [2011, 2012, 2013, 2014, 2015, 2016],
  [2012, 2013, 2014, 2015, 2016],
  [2011, 2012, 2013, 2014, 2015, 2016],
];
export const engineeringTransition = {
  title: "工学部の旧課程読替表（旧サイト掲載資料）",
  url: "https://www.eng.niigata-u.ac.jp/old/topics/image2017/curriculum.pdf",
};
export const engineeringAssessment = {
  title: "工学部の現況分析・平成27年度、資料12・13",
  url: "https://www.niigata-u.ac.jp/wp-content/uploads/2016/07/H27_genkyo_kyoiku_08.pdf#page=9",
};
const source = {
  title: "工学部・学生必携と学務係",
  url: "https://www.eng.niigata-u.ac.jp/student/",
};
const facultyLaw = {
  title: "工学部規程・平成28年度以前の入学者に関する附則",
  url: "https://public1.legalcrud.com/niigata_univ/act/110000527.html",
};
const summary = [
  [6, 36, 20, 20],
  [10, 31, 33, 8],
  [10, 48, 18, 6],
  [10, 38, 28, 6],
  [10, 8, 50, 14],
  [10, 24, 36, 12],
  [4, 8, 46, 24],
  [24, 18, 36, 4],
];

export function legacyEngineering(book, p) {
  const y = +book.year,
    i = formerDepartments.findIndex(
      (d) => p.program && norm(p.program).includes(norm(d)),
    );
  const local = i >= 0 && pages[i].includes(y);
  const page = local
    ? 4 +
      2 *
        (pages.slice(0, i).reduce((s, a) => s + a.length, 0) +
          pages[i].indexOf(y))
    : 1;
  const rules = {
    title:
      engineeringTransition.title +
      "・" +
      (p.program || "学科別") +
      " " +
      y +
      "年度",
    url: engineeringTransition.url + "#page=" + page,
  };
  const entries = [];
  if (local)
    for (const [
      lo,
      hi,
      dept,
      group,
      credits,
      items,
    ] of formerEngineeringCourses) {
      if (dept !== i || y < lo || y > hi) continue;
      for (const item of items) {
        const [title, mapped] =
          typeof item === "string" ? [item, [[item, credits, 0]]] : item;
        entries.push({
          title: norm(title),
          label: title,
          credits,
          group,
          parts: mapped.map(([n, v, first]) => ({
            title: norm(n),
            credits: v,
            first,
          })),
        });
      }
    }
  const valid = (c) => type(c) === "T" && !night(c) && !c.graduationExcluded;
  function honors(e, c) {
    if (!valid(c)) return false;
    const n = name(c),
      v = Number(c.credits),
      year = courseYear(c);
    if (
      n === e.title &&
      v === e.credits &&
      (year <= 2016 || c.oldCurriculum === true)
    )
      return "old";
    for (const part of e.parts) {
      const [t, restriction] = part.title.split("(");
      if (
        (n !== part.title && n !== t) ||
        v !== part.credits ||
        (part.first && year < part.first)
      )
        continue;
      if (
        restriction &&
        n !== part.title &&
        !restriction.startsWith("工学科共通") &&
        !norm(c.program || c.field).includes(restriction.replace(/\)$/, ""))
      )
        continue;
      if (
        c.program &&
        !norm(c.program).includes(programs[i]) &&
        !(i === 3 && norm(c.program).includes("知能情報システム")) &&
        !restriction
      )
        continue;
      if (
        part.title === e.title &&
        !part.first &&
        c.program == null &&
        /^(卒業研究|卒業研修)$/.test(t) &&
        year > 2016
      )
        return null;
      return part.title;
    }
    return false;
  }
  const fulfill = (e, courses) => {
    const candidates = courses.map((c) => [c, honors(e, c)]);
    const original = candidates.find(([, v]) => v === "old");
    if (original) return [original[0]];
    if (!e.parts.length) return [];
    const result = e.parts.map(
      (v) => candidates.find(([, part]) => part === v.title)?.[0],
    );
    return result.every(Boolean) && new Set(result).size === result.length
      ? result
      : [];
  };
  const uncertain = (c) =>
    !type(c) || (type(c) === "T" && !entries.some((e) => honors(e, c)));
  function tally(selected) {
    return ({ courses }) => {
      const used = new Set(),
        contributions = [];
      let ambiguous = false;
      for (const e of selected) {
        const parts = fulfill(e, courses);
        if (!parts.length) continue;
        if (parts.some((c) => used.has(c))) {
          ambiguous = true;
          continue;
        }
        for (const c of parts) {
          used.add(c);
          contributions.push(record(c, c.credits, "旧課程 " + e.label));
        }
      }
      return {
        value: contributions.reduce((v, c) => v + c.applied, 0),
        contributions,
        ...((ambiguous || courses.some(uncertain)) && {
          unknown:
            "旧課程の学科指定・授業名・単位数または個別の読替認定を確認してください。",
        }),
      };
    };
  }
  const match = (selected) => (c) =>
    !type(c)
      ? null
      : selected.some((e) => honors(e, c))
        ? true
        : valid(c) && uncertain(c)
          ? null
          : false;
  const credit = (key, label, v, selected, s = rules) =>
    row(key, label, "単位", v, match(selected), s, {
      evaluate: tally(selected),
    });
  const rr = [];
  if (y === 2015 && i >= 0) {
    // This university evaluation identifies the rules then in use, including the two construction courses.
    const gen = (c) => {
      if (!type(c)) return null;
      if (night(c) || c.graduationExcluded) return false;
      if (type(c) !== "G") return type(c) === "T" ? false : null;
      return [
        "英語",
        "初修外国語",
        "健康・スポーツ",
        "情報リテラシー",
        "人文社会・教育科学",
        "新潟大学個性化科目",
        "自然科学",
        "医歯学",
      ].includes(category(c))
        ? true
        : null;
    };
    rr.push(
      row(
        "total",
        "卒業資格（資料12・13）",
        "単位",
        124,
        (c) => (gen(c) === true ? true : match(entries)(c)),
        engineeringAssessment,
        {
          evaluate: ({ courses }) => {
            const res = tally(entries)({ courses });
            for (const c of courses.filter((v) => gen(v) === true))
              if (c.credits > 0) {
                res.value += c.credits;
                res.contributions.push(record(c, c.credits));
              }
            return res;
          },
        },
      ),
      row("general", "教養系", "単位", 42, gen, engineeringAssessment),
      credit("major", "学部専門系", 82, entries, engineeringAssessment),
    );
    for (const [k, l, j, g] of [
      ["baseB", "専門基礎 B", 0, [0]],
      ["A", "専門 A", 1, [1]],
      ["B", "専門 B", 2, [2]],
      ["pool", "専門 B・C・D・E（B最低数を含む）", 3, [2, 3, 4, 5]],
    ])
      rr.push(
        credit(
          "eng-" + k,
          l,
          summary[i][j] + (j === 3 ? summary[i][2] : 0),
          entries.filter((e) => g.includes(e.group)),
          engineeringAssessment,
        ),
      );
    rr.push(
      check(
        "general-split",
        "教養系の選択必修・選択への充当",
        "資料12の区分別必要数と学部専門系に指定された教養科目を、入学時の工学部別表第1・2で確認してください。",
        engineeringAssessment,
      ),
    );
  } else {
    rr.push(
      check(
        "total",
        "卒業単位と学科ごとの最低単位",
        "旧課程の年度別読替表は科目区分を示します。卒業の最低数は当該年度の学生必携の別表第1・2を工学部学務係で確認してください。",
        source,
      ),
    );
  }
  for (const e of entries.filter((e) => e.group === 1)) {
    const r = credit("old-required-" + e.title, e.label, e.credits, [e]);
    if (!rr.some((a) => a.key === r.key)) rr.push(r);
  }
  if (!local)
    rr.push(
      check(
        "transition-list",
        "学科別の旧科目と代替科目",
        "公開の読替表に選択年度と学科の組合せがない場合は旧学生必携と学務係の個別認定で照合してください。",
        rules,
      ),
    );
  rr.push(...transferRow(p, facultyLaw, "工学部"));
  return {
    title: book.title,
    sources: [rules, engineeringAssessment, facultyLaw, source],
    note: "旧課程の同一科目・読替は、対象学科と単位数を照合します。2科目を組み合わせる読替は両方の修得が必要です。旧サイトの原本は現在リンク切れのため、変更後の取扱いは工学部学務係で確認してください。",
    stages: [
      stage("year4", "4年次進級・卒業研修の着手", [
        check(
          "old-progress",
          "旧学科の進級と卒業研修基準",
          "入学年度の工学部規程細則で4年次の必要単位を工学部学務係に確認してください。",
          facultyLaw,
        ),
      ]),
      stage("graduation", "卒業", rr),
    ],
    cap: {
      limit: null,
      source,
      classify: () => "unknown",
      note: "旧学科の学期別登録上限は入学時の学生必携で照合してください。",
    },
  };
}
