import sources from "../rule-sources.json" with { type: "json" };
import { normalize } from "../course-facts.mjs";
import { quantity } from "./engine-evidence.mjs";

// Pre-pack catalog and rules for existing local snapshots and isolated builds.
// An installed pack always controls its own faculty and handbook years.
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
export function priorFacultyInfo(profile) {
  const info = FACULTIES[profile.faculty];
  if (!info) return null;
  if (profile.entry && profile.entry !== "1年次入学")
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
    url: typeof key === "string" ? sources[key] : key.url,
    title:
      key.title ??
      sourceTitles[key] ??
      ["進級・履修の規程", "卒業要件の規程", "科目の内訳"][i],
  }));
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

export function priorDescriptor(profile) {
  const info = priorFacultyInfo(profile);
  if (!info?.verified) return null;
  const links = sourceLinks(info);
  const engineering = profile.faculty === "工学部";
  function engineeringMatch(course, key) {
    const matches = engMatches(course, profile);
    if (matches.length) {
      if (key === "total" || key === "general") return true;
      return matches.includes(key);
    }
    if (
      course.department === "84" &&
      /リメディアル|データサイエンス総論i$/.test(normalize(course.title))
    )
      return false;
    return null;
  }
  const stages = [];
  for (const goal of ["progress", "graduation"]) {
    const grad = goal === "graduation",
      label = grad ? "卒業" : info.stage;
    const required = grad ? info.graduation : info.progress;
    if (!label && !required) continue;
    const rows = [];
    for (const [key, name, kind, minimum] of [
      ["total", label + "の単位合計", "合計", required],
      [
        "general",
        "教養系の単位",
        "区分計",
        grad ? info.general : engineering ? 32 : null,
      ],
      [
        "major",
        "専門系の単位",
        "区分計",
        grad ? info.major : engineering ? 66 : null,
      ],
    ]) {
      if (minimum == null) continue;
      rows.push({
        key,
        label: name,
        kind,
        required: minimum,
        match: engineering ? (c) => engineeringMatch(c, key) : () => null,
      });
    }
    if (engineering) {
      for (const [key, name, kind, progress, graduation] of engineeringRows) {
        rows.push({
          key,
          label: name,
          kind,
          required: grad ? graduation : progress,
          exclusive: "教養系",
          match: (c) => engineeringMatch(c, key),
          source: links[2],
        });
      }
    }
    if (grad && profile.faculty === "教育学部") {
      rows.push(
        {
          key: "ed-required",
          label: "教養教育の必修",
          kind: "必修",
          required: 13,
        },
        {
          key: "ed-elective",
          label: "教養教育の選択必修",
          kind: "選択必修",
          required: 4,
        },
      );
    }
    rows.push({
      key: "individual",
      label: "指定科目・在学期間の照合",
      kind: "確認事項",
      required: null,
      unit: "condition",
      unknown: info.note,
    });
    stages.push({ id: goal, label, goal, rows, sources: links });
  }
  return {
    title: profile.faculty + " " + profile.handbook + "年度",
    sources: links,
    stages,
    note: info.note,
    cap: priorCAP(profile),
  };
}

function priorCAP(profile) {
  if (String(profile.handbook) !== "2026") return;
  const engineering = profile.faculty === "工学部";
  if (!engineering && profile.faculty !== "農学部") return;
  const gpa = quantity(profile.gpa);
  return {
    limit: engineering
      ? 28
      : gpa === null || gpa > 5
        ? null
        : gpa >= 3.5
          ? 28
          : 24,
    source: sourceLinks({ sources: [engineering ? "eng-cap" : "agr-cap"] })[0],
    classify(c) {
      if (c.period === "集中" || c.category === "教職に関する科目")
        return "exclude";
      if (engineering) {
        if (
          c.title === "リメディアル演習" ||
          c.creditExchange ||
          c.vacationOffering
        )
          return "exclude";
      } else {
        if (c.category === "留学生基本科目" || c.failedRetake) return "exclude";
        const formats = (c.format ?? "").split("・");
        const exempt = (format) => ["演習", "実技", "実験"].includes(format);
        if (formats.every(exempt)) return "exclude";
        if (formats.some(exempt) || !c.format) return "unknown";
      }
      return c.code && c.category && c.period ? "include" : "unknown";
    },
  };
}
