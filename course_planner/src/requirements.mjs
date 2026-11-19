import sources from "./rule-sources.json" with { type: "json" };
import { normalize } from "./study.mjs";

export const FACULTIES = {
  人文学部: {
    unit: "01",
    graduation: 124,
    progress: 54,
    stage: "3年次進級",
    general: 41,
    major: 60,
    sources: ["human-3", "human-grad"],
    note: "在学2年以上。人文初年次演習、同じ初修外国語、入門講義の指定単位を便覧で照合してください。",
  },
  教育学部: {
    unit: "03",
    graduation: 131,
    progress: 95,
    stage: "卒業研究の履修",
    general: 17,
    major: 114,
    sources: ["ed-thesis", "ed-total", "ed-general"],
    note: "卒業研究は在学3年以上。日本国憲法、教育実習、専修ごとの指定科目も確認してください。",
  },
  法学部: {
    unit: "04",
    graduation: 124,
    progress: 60,
    stage: "4年次D類の登録",
    sources: ["law-study", "law-grad"],
    note: "C類の修得と、3年次終了時のA類全科目などが条件です。編入などの特例は便覧で確認してください。",
  },
  経済科学部: {
    unit: "0C",
    graduation: 124,
    progress: 90,
    stage: "4年次進級",
    sources: ["econ-year", "econ-grad", "econ-site"],
    note: "4年次進級には3年次の在学1年以上・学部在学3年以上が必要です。外国語・教養の内訳はプログラム別です。",
  },
  "経済学部（旧課程）": {
    unit: "05",
    sources: ["econ-site"],
    note: "本人に適用される年度の便覧と科目読替表を確認してください。",
  },
  理学部: {
    unit: "06",
    graduation: 124,
    general: 21,
    major: 84,
    sources: ["sci-year", "sci-correct", "sci-guide"],
    note: "3年次・4年次の進級条件は所属プログラムの履修ガイドで確認してください。",
  },
  医学部医学科: {
    unit: "07",
    graduation: 219,
    general: 43,
    major: 176,
    sources: ["med", "med-gen", "med-prof"],
    note: "卒業には6年以上の在学が必要です。進級は学年別の指定科目で判定されます。",
  },
  医学部保健学科: {
    unit: "07",
    graduation: 124,
    general: 26,
    major: 98,
    sources: ["health", "med-health"],
    note: "4年次進級は3年次までの必修科目、在学期間と教授会の確認が必要です。3年次編入には特例があります。",
  },
  歯学部歯学科: {
    unit: "08",
    graduation: 192,
    general: 40,
    major: 152,
    sources: ["dent", "dent-g", "dent-p"],
    note: "在学期間6年以上。各学年の指定科目と臨床実習の履修条件を照合してください。",
  },
  歯学部口腔生命福祉学科: {
    unit: "08",
    graduation: 150,
    general: 30,
    major: 120,
    sources: ["dent", "oral-g", "oral-p"],
    note: "各学年に配当された指定科目の修得を照合してください。",
  },
  工学部: {
    unit: "09",
    graduation: 124,
    progress: 104,
    stage: "4年次進級",
    general: 36,
    major: 82,
    sources: ["eng-4", "eng-grad", "eng-edu"],
    note: "4年次進級には在学3年以上。専門の指定科目・所属分野・個別認定は学生必携で確認してください。",
  },
  農学部: {
    unit: "0A",
    graduation: 124,
    general: 34,
    major: 85,
    sources: ["agr-grad", "agr-thesis"],
    note: "卒業論文の履修条件はプログラム別です。分野の指定科目と在学期間も確認してください。",
  },
  創生学部: {
    unit: "0B",
    graduation: 126,
    progress: 90,
    stage: "4年次進級",
    sources: ["create-4", "create-grad"],
    note: "在学3年以上。領域学修の内訳はコース別です。ベーシック数学ゼミは進級・卒業単位に算入されません。",
  },
};
export function facultyInfo(profile) {
  const info = FACULTIES[profile.faculty];
  if (!info) return null;
  if (profile.entry === "編入・転部・再入学")
    return {
      unit: info.unit,
      verified: false,
      sources: info.sources,
      note: "編入・転部・再入学の認定単位と適用条件を確認し、本人の確認表の内訳を入力してください。",
    };
  if (String(profile.handbook) === "2026" && info.graduation)
    return { ...info, verified: true };
  if (profile.faculty === "創生学部" && String(profile.handbook) === "2018")
    return {
      unit: info.unit,
      progress: 90,
      stage: "4年次進級",
      sources: ["create-2018"],
      verified: true,
      note: "導入・転換教育17単位を含む旧課程です。卒業要件も適用便覧で確認してください。",
    };
  return {
    unit: info.unit,
    verified: false,
    sources: info.sources.includes("econ-site") ? ["econ-site"] : [],
    note: "この年度・所属の要件は要確認です。本人に適用される便覧・履修科目確認表と照合してください。",
  };
}
const sourceTitles = {
  "eng-4": "4年次進級基準",
  "eng-grad": "卒業資格基準",
  "eng-edu": "教養系の別表",
  "sci-guide": "年度別履修ガイド",
  "econ-site": "年度別学生便覧",
  "eng-cap": "CAPの規定",
  "agr-cap": "CAPの規定",
};
export function sourceLinks(info) {
  return (info?.sources ?? []).map((key, i) => ({
    url: sources[key],
    title:
      sourceTitles[key] ??
      ["進級・履修の規程", "卒業要件の規程", "科目の内訳"][i],
  }));
}
export function gradeCourses(state, byCode) {
  return state.grades.map((g) => {
    const match = g.code && byCode.get(g.code);
    return {
      ...(match ?? {}),
      ...g,
      code: g.code ?? "",
      fields: g.fields ?? match?.fields ?? [],
      category: g.category || match?.category || "",
      department: g.department || match?.department || "",
    };
  });
}
const engineeringRows = [
  ["study", "大学学習法", "必修", 2, 2],
  ["english", "英語", "必修", 2, 2],
  ["foreign", "初修外国語", "必修", 2, 2],
  ["sport", "健康スポーツ科学実習Ⅰ", "必修", 1, 1],
  ["data", "情報リテラシー指定科目", "必修", 2, 2],
  ["human", "人文社会・教育科学", "必修", 4, 4],
  [
    "sciencePool",
    "情報リテラシー・自然系共通専門基礎・自然科学",
    "選択必修",
    10,
    10,
  ],
  ["socialPool", "人文社会・教育科学・新潟大学個性化科目", "選択必修", 2, 2],
  ["choice", "教養系選択", "選択", 7, 11],
];
function engMatches(c, profile) {
  const n = normalize(c.title),
    cat = c.category;
  if (c.department !== "84" || /リメディアル|データサイエンス総論i$/.test(n))
    return [];
  if (cat === "大学学習法")
    return n.includes("工学リテラシー入門") &&
      profile.program &&
      n.includes(normalize(profile.program))
      ? ["study"]
      : [];
  if (cat === "英語") return ["english", "choice"];
  if (cat === "初修外国語") return ["foreign", "choice"];
  if (cat === "健康・スポーツ")
    return /^健康スポーツ科学実習i(?!i)/.test(n)
      ? ["sport", "choice"]
      : ["choice"];
  if (cat === "人文社会・教育科学") return ["human", "socialPool", "choice"];
  if (cat === "新潟大学個性化科目") return ["socialPool", "choice"];
  if (
    cat === "情報リテラシー" &&
    n.includes("エンジニアのためのデータサイエンス入門")
  ) {
    return profile.program && n.includes(normalize(profile.program))
      ? ["data"]
      : [];
  }
  if (["情報リテラシー", "自然系共通専門基礎", "自然科学"].includes(cat))
    return ["sciencePool", "choice"];
  return [];
}
export function satisfiesFilter(course, key, profile) {
  if (key === "total") return true;
  if (key === "major")
    return course.department === FACULTIES[profile.faculty]?.unit;
  if (key === "general") return course.department === "84";
  if (key.startsWith("field-")) return course.fields?.includes(key.slice(6));
  return engMatches(course, profile).includes(key);
}
function allocate(courses, profile, goalIndex, baseline = {}) {
  const assigned = Object.fromEntries(
    engineeringRows.map((row) => [row[0], baseline[row[0]] ?? 0]),
  );
  for (const c of courses) {
    let left = c.credits ?? 0;
    for (const key of engMatches(c, profile)) {
      const row = engineeringRows.find((r) => r[0] === key);
      const used = Math.min(left, Math.max(0, row[goalIndex] - assigned[key]));
      assigned[key] += used;
      left -= used;
    }
  }
  return assigned;
}
export function requirementRows(state, byCode, planned, goal = "graduation") {
  const info = facultyInfo(state.profile);
  const official = state.balances.filter(
    (b) =>
      b.faculty === state.profile.faculty &&
      b.handbook === state.profile.handbook &&
      (b.program ?? "") === state.profile.program &&
      b.goal === goal,
  );
  const grades = gradeCourses(state, byCode);
  const earnedCodes = new Set(grades.map((g) => g.code).filter(Boolean));
  const upcoming = planned.filter((c) => !earnedCodes.has(c.code));
  const earned = grades.filter(
    (c) =>
      c.counts !== false &&
      !(
        state.profile.faculty === "創生学部" &&
        normalize(c.title) === "ベーシック数学ゼミ"
      ),
  );
  const projected = upcoming.filter(
    (c) =>
      !(
        state.profile.faculty === "創生学部" &&
        normalize(c.title) === "ベーシック数学ゼミ"
      ),
  );
  const rows = [];
  const sum = (arr, filter) =>
    arr.filter(filter).reduce((s, c) => s + (c.credits ?? 0), 0);
  const row = (key, label, kind, required, current, future) => ({
    key,
    label,
    kind,
    required,
    current,
    future,
    remaining: Math.max(0, required - current),
    after: Math.max(0, required - future),
  });
  const total = goal === "graduation" ? info?.graduation : info?.progress;
  if (total)
    rows.push(
      row(
        "total",
        goal === "graduation" ? "卒業単位の合計" : info.stage + "の単位合計",
        "合計",
        total,
        sum(earned, () => true),
        sum([...earned, ...projected], () => true),
      ),
    );
  if (info?.verified) {
    for (const [key, label, required] of [
      [
        "general",
        "教養系の単位",
        goal === "graduation"
          ? info.general
          : state.profile.faculty === "工学部"
            ? 32
            : 0,
      ],
      [
        "major",
        "専門系の単位",
        goal === "graduation"
          ? info.major
          : state.profile.faculty === "工学部"
            ? 66
            : 0,
      ],
    ]) {
      if (!required) continue;
      const match = (c) => satisfiesFilter(c, key, state.profile);
      rows.push(
        row(
          key,
          label,
          "区分計",
          required,
          sum(earned, match),
          sum([...earned, ...projected], match),
        ),
      );
    }
    if (state.profile.faculty === "教育学部" && goal === "graduation") {
      rows.push({
        ...row("ed-required", "教養教育の必修", "必修", 13, 0, 0),
        needsBalance: true,
      });
      rows.push({
        ...row("ed-elective", "教養教育の選択必修", "選択必修", 4, 0, 0),
        needsBalance: true,
      });
    }
    if (state.profile.faculty === "工学部") {
      const ix = goal === "graduation" ? 4 : 3,
        a = allocate(earned, state.profile, ix);
      for (const balance of official)
        if (Object.hasOwn(a, balance.key)) a[balance.key] = balance.current;
      const b = allocate(projected, state.profile, ix, a);
      for (const [index, definition] of engineeringRows.entries()) {
        const [key, label, kind] = definition;
        rows.push(
          row(key, label, kind, engineeringRows[index][ix], a[key], b[key]),
        );
      }
    }
  }
  // The university's category subtotal already includes recognized and earned courses.
  for (const b of official) {
    const previous = rows.find((r) => r.key === b.key);
    const increase = previous ? previous.future - previous.current : 0;
    const result = {
      ...row(
        b.key,
        b.label,
        b.kind,
        b.required,
        b.current,
        b.current + increase,
      ),
      needsBalance: false,
    };
    if (previous) Object.assign(previous, result);
    else rows.push(result);
  }
  return rows;
}
