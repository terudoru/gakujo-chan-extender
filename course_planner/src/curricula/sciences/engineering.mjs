import {
  norm,
  name,
  urlPage,
  row,
  check,
  months,
  stage,
  isThirdTransfer,
  irregular,
  categories,
  category,
  type,
  night,
  capped,
  transferRow,
  programFor,
} from "./common.mjs";
import {
  engineeringTables,
  engineeringCourses,
} from "./engineering-tables.mjs";
import { engineeringPackages } from "./engineering-packages.mjs";
import { engineeringCap, teachingTableSources } from "./engineering-cap.mjs";
import { legacyPackages } from "./engineering-legacy-packages.mjs";
import { semester2026 } from "./science-tables.mjs";

export const engineeringPrograms = [
  "機械システム工学",
  "社会基盤工学",
  "電子情報通信",
  "知能情報システム",
  "化学システム工学",
  "材料科学",
  "建築学",
  "人間支援感性科学",
  "協創経営",
];
const fields = [
  "力学",
  "力学",
  "情報電子",
  "情報電子",
  "化学材料",
  "化学材料",
  "建築",
  "融合領域",
  "融合領域",
];
const firstYear = [
  "総合工学概論",
  "総合技術科学演習",
  "技術者の心がまえ",
  "知的財産概論",
  "情報セキュリティ概論",
].map(norm);
const dTitles = [
  "リメディアル演習",
  "工学力リーダー育成演習I",
  "工学力リーダー育成演習II",
  "工場実習",
  "工場見学",
  "特別講義",
  "海外英語研修",
  "国際研修",
].map(norm);
const packages = [
  "先端融合材料",
  "先進未来システム",
  "次世代社会文化環境システムデザイン",
  "エネルギー・環境",
].map((n) => n + "パッケージ");
const fusionClasses = new Set(
  [
    "人間支援感性科学概論",
    "協創経営概論",
    "ビジネス統計学",
    "アントレプレナーシップⅠ",
    "キャリアデザイン・インターンシップⅠ",
    "コンピュータ基礎",
    "プログラミング基礎Ⅰ",
    "プログラミング基礎Ⅱ",
  ].map(norm),
);
const isFusion = (c, y) =>
  fusionClasses.has(name(c)) ||
  (y <= 2020 && name(c) === "芸術コミュニケーション概論");
export const engineeringOptions = [
  ...engineeringPrograms.map((n) => n + "プログラム"),
  ...["応用化学", "化学工学"].map((n) => "化学システム工学（" + n + "コース）"),
  ...packages.map((n) => "協創経営（" + n + "）"),
];
function homeField(p, index) {
  const explicit = fields.find((f) =>
    norm(p.program).includes(norm(f + "分野")),
  );
  return explicit || fields[index];
}
function generalKey(c, y, field, internationalStudent) {
  if (!type(c)) return null;
  if (night(c) || c.counts === false || c.graduationExcluded) return false;
  const t = name(c),
    cat = category(c);
  if (type(c) !== "G") return type(c) === "T" ? false : null;
  if (cat === "自然系共通専門基礎") {
    const target = norm(semester2026[c.code]?.[2]);
    if (
      target.includes("工学部を除く") ||
      /工学部[,、][^(){}]+を除く/.test(target)
    )
      return false;
    const restricted = target.match(/工学部\(([^)]+)\)を除く/);
    if (restricted && (!field || restricted[1].includes(field)))
      return field ? false : null;
    const designated = target.match(/^工学部\(([^)]+)\)$/);
    if (designated && (!field || !designated[1].includes(field))) return null;
  }
  if (y >= 2023 && t === "データサイエンス総論i") return false;
  if (
    cat === "大学学習法" ||
    t.startsWith("エンジニアのためのデータサイエンス入門")
  ) {
    const stem =
      cat === "大学学習法"
        ? "工学リテラシー入門"
        : "エンジニアのためのデータサイエンス入門";
    if (!t.startsWith(stem)) return false;
    if (!field || !fields.some((f) => t.includes(norm(f + "分野"))))
      return null;
    if (!t.includes(norm(field + "分野"))) return false;
    return cat === "大学学習法" ? "study" : y >= 2023 ? "data" : null;
  }
  if (y >= 2021 && /^英語基礎[lr]$/.test(t)) return "human";
  if (!cat) return null;
  if (cat === "英語") return "english";
  if (cat === "初修外国語") return "foreign";
  if (cat === "健康・スポーツ" && t === "健康スポーツ科学実習i") return "sport";
  if (cat === "人文社会・教育科学") return "human";
  if (cat === "新潟大学個性化科目") return "socialPool";
  if (y >= 2021 && y <= 2022 && t === "データサイエンス総論i") return "data";
  if (["自然科学", "自然系共通専門基礎", "情報リテラシー"].includes(cat))
    return "sciencePool";
  if (cat === "留学生基本科目")
    return internationalStudent === true || c.internationalStudent === true
      ? "choice"
      : null;
  return categories.includes(cat) ? "choice" : null;
}
function generalRows(y, field, grad, source, internationalStudent) {
  const data = y <= 2020 ? 0 : y <= 2022 ? 1 : 2;
  const defs = [
    ["study", "所属分野の工学リテラシー入門", 2],
    ["english", "英語", y <= 2020 ? 4 : 2],
    ["foreign", "初修外国語", 2],
    ["sport", "健康スポーツ科学実習Ⅰ", 1],
    [
      "data",
      y <= 2022
        ? "データサイエンス総論Ⅰ"
        : "所属分野のエンジニアのためのデータサイエンス入門",
      data,
    ],
    ["human", "人文社会・教育科学", 4],
    ["sciencePool", "情報リテラシー・自然系共通専門基礎・自然科学", 10],
    ["socialPool", "人文社会・教育科学・新潟大学個性化科目", 2],
    ["choice", "教養系選択", (grad ? 11 : 7) + (data === 1 ? 1 : 0)],
  ];
  return defs
    .filter(([, , n]) => n > 0)
    .map(([key, label, n], i) =>
      row(
        key,
        label,
        key === "choice" ? "選択" : key.endsWith("Pool") ? "選択必修" : "必修",
        n,
        (c) => {
          const k = generalKey(c, y, field, internationalStudent);
          if (k == null || k === false) return k;
          return (
            key === "choice" ||
            key === k ||
            (key === "socialPool" && k === "human")
          );
        },
        source,
        { exclusive: "engineering-general" },
      ),
    );
}
function courseMap(y, prog, pack) {
  const index = new Map();
  const selected = new Map();
  const legacy = new Map();
  if (prog === 8 && y <= 2021)
    for (const [lo, hi, i, names] of legacyPackages)
      if (lo <= y && y <= hi)
        for (const n of names) {
          if (!legacy.has(norm(n))) legacy.set(norm(n), []);
          legacy.get(norm(n)).push(i);
        }
  for (const [lo, hi, i, kind, names] of engineeringPackages)
    if (prog === 8 && lo <= y && y <= hi && packages[i] === pack)
      for (const n of names) selected.set(norm(n), kind);
  for (const [start, end, program, group, mark, titles] of engineeringCourses) {
    if (y < start || y > end) continue;
    for (const title of titles) {
      const prefix = title.match(/^[●○■□]+/)?.[0] ?? "";
      const n = norm(title.slice(prefix.length)),
        entries = index.get(n) ?? [];
      entries.push({ program, group, mark: mark + prefix });
      index.set(n, entries);
    }
  }
  return (c) => {
    if (!type(c)) return null;
    if (night(c) || c.graduationExcluded) return false;
    if (c.engineeringGroup === "E") return { group: "E" };
    if (type(c) !== "T") return false;
    const t = name(c);
    if (dTitles.includes(t)) return { group: "D" };
    if (prog === 8 && y <= 2021 && isFusion(c, y))
      return { group: "B", legacy: legacy.get(t) };
    if (selected.has(t))
      return {
        group: "B",
        mark: selected.get(t) === "lab" ? "■" : "",
        packageKind: selected.get(t),
      };
    if (legacy.has(t)) return { group: "B", legacy: legacy.get(t) };
    if (prog === 8 && y >= 2022 && t === "社会システム工学演習")
      return { group: "B", mark: "■" };
    const reference = index.get(t);
    if (!reference) return null;
    const local = reference.filter((r) => r.program === prog);
    const taughtFor = engineeringPrograms.indexOf(
      programFor({ program: c.program }, engineeringPrograms),
    );
    if (
      taughtFor >= 0 &&
      prog >= 0 &&
      taughtFor !== prog &&
      !local.some((r) => r.group.startsWith("base"))
    )
      return { group: "C" };
    if (
      !c.program &&
      prog >= 0 &&
      reference.some((r) => r.program !== prog) &&
      local.some((r) => !r.group.startsWith("base")) &&
      /^(卒業研究|卒業研修)/.test(t)
    )
      return null;
    // Named class, course and laboratory variants must agree on classification.
    if (
      local.length &&
      local.every((r) => r.group === local[0].group && r.mark === local[0].mark)
    )
      return local[0];
    if (
      prog >= 0 &&
      !local.length &&
      reference.every((r) =>
        ["baseA", "baseB", "A", "B", "C"].includes(r.group),
      )
    )
      return { group: "C" };
    if (prog < 0 && reference.every((r) => r.group === reference[0].group))
      return reference[0];
    return null;
  };
}
export function engineering(book, p) {
  const y = Number(book.year),
    idx = engineeringPrograms.indexOf(programFor(p, engineeringPrograms)),
    field = homeField(p, idx);
  const pack = packages.find((t) => p.program?.includes(t) || p.package === t);
  const tables = engineeringTables[y],
    groups = courseMap(y, idx, pack);
  const third = isThirdTransfer(p),
    unspecified = irregular(p) && !third;
  const ref = (n, t) => urlPage(book, n, t),
    capSource = ref(tables.cap, "履修登録の上限"),
    guide = ref(tables.general, "工学部規程別表第1・教養系");
  const exclusions = ref(tables.english, "英語基礎と教養系科目の取扱い");
  const classify = (c, level) => {
    if (type(c) && c.engineeringGroup === "E") return "E";
    if (y <= 2023 && type(c) === "Q") return false;
    const g = generalKey(c, y, field, p.internationalStudent);
    if (typeof g === "string") return "general";
    if (type(c) !== "T") return g;
    const m = groups(c);
    if (m == null || m === false) return m;
    if (m.group === "D" && (level === 4 || (level === 2 && y >= 2023)))
      return false;
    return m.group;
  };
  function total(key, label, minimum, level, source) {
    const bucket = (c) => {
      const k = classify(c, level);
      if (k == null || k === false) return k;
      if (
        (key === "major" && k === "general") ||
        (key === "general" && k !== "general")
      )
        return false;
      return k;
    };
    return row(
      key,
      label,
      "区分計",
      minimum,
      (c) => {
        const k = bucket(c);
        return k == null ? null : k !== false;
      },
      source,
      { evaluate: capped(bucket, level === 4 ? { E: 6 } : {}) },
    );
  }
  const stages = [];
  if (!third) {
    const source = ref(tables.article, "工学部規程細則第10条・第2年次");
    stages.push(
      stage("year2", "2年次進級", [
        months(12, source),
        total("total", "教養系・学部専門系", 32, 2, source),
        row(
          "engineering-first-five",
          "指定5科目から",
          "指定",
          4,
          (c) =>
            type(c) ? type(c) === "T" && firstYear.includes(name(c)) : null,
          source,
        ),
      ]),
    );
  }
  for (const grad of [false, true]) {
    const level = grad ? 0 : 4,
      source = ref(
        tables.page + (grad ? 1 : 0),
        grad ? "別表第2・卒業資格基準" : "別表第1・4年次進級基準",
      );
    const relaxed = third && !grad,
      min = tables[grad ? "graduation" : "progress"][idx];
    const rows = [
      months(grad ? 48 : 36, source),
      total(
        "total",
        "教養系・学部専門系の合計",
        grad ? 124 : 104,
        level,
        source,
      ),
      total("general", "教養系", grad ? 36 : relaxed ? 28 : 32, level, source),
      total(
        "major",
        "学部専門系",
        grad ? 82 : relaxed ? 62 : 66,
        level,
        source,
      ),
    ];
    if (!relaxed && !(unspecified && !grad))
      rows.push(...generalRows(y, field, grad, guide, p.internationalStudent));
    if (unspecified && !grad) {
      rows.splice(
        2,
        2,
        check(
          "transfer-criteria",
          "入学区分に応じた教養・専門の最低単位",
          "3年次編入は教養28・専門62。編入年次と認定期間を工学部学務係で確認してください。",
          source,
        ),
      );
    }
    if (min && !(unspecified && !grad)) {
      const listRef = ref(
        tables.page + 3 + idx * 3,
        "所属プログラムの専門基礎・専門応用標準課程表",
      );
      const marks = (c, wanted) => {
        const a = groups(c);
        if (a == null || a === false) return a;
        return wanted.includes(a.group);
      };
      const defs = [
        ["baseA", "専門基礎 A", ["baseA"]],
        ["baseB", "専門基礎 B", ["baseB"]],
        ["A", "専門応用 A", ["A"]],
        ["B", "専門応用 B（専門基礎 Bの超過分を含む）", ["B", "baseB"]],
        [
          "pool",
          grad ? "専門応用 B・C・D・E" : "専門応用 B・C・E",
          grad ? ["B", "baseB", "C", "D", "E"] : ["B", "baseB", "C", "E"],
        ],
      ];
      for (const [i, [key, label, wanted]] of defs.entries()) {
        if (!min[i] || (relaxed && !["baseA", "A"].includes(key))) continue;
        rows.push(
          row(
            "eng-" + key,
            label,
            "専門",
            min[i],
            (c) => marks(c, wanted),
            listRef,
            { exclusive: "engineering-major" },
          ),
        );
        if (key === "pool" && !grad) {
          // Validate the E subcap independently of the engine's exclusive credit allocation.
          const subtotal = (c) => {
            const m = groups(c);
            return m == null
              ? null
              : m && wanted.includes(m.group)
                ? m.group
                : false;
          };
          rows.push(
            row(
              "eng-flexible",
              "専門基礎B・専門応用B/C/Eの合計（Eは6単位まで）",
              "内訳",
              min[1] + min[3] + min[4],
              (c) => marks(c, wanted),
              source,
              { evaluate: capped(subtotal, { E: 6 }) },
            ),
          );
        }
      }
      if (idx === 4 && (!relaxed || tables.chemical)) {
        const track = ["応用化学", "化学工学"].find(
          (t) => p.program.includes(t) || p.track === t,
        );
        if (!track)
          rows.push(
            check(
              "chem-track",
              "コース指定の実験・講義",
              "応用化学・化学工学の配属コースを指定し、標準課程表の記号を確認してください。",
              listRef,
            ),
          );
        else
          for (const [i, m] of (track === "応用化学"
            ? ["●", "○"]
            : ["■", "□"]
          ).entries()) {
            if (relaxed && i === 1) continue;
            const n = (y >= 2025 ? [4, 6] : [12, 32])[i];
            rows.push(
              row(
                "chem-" + m,
                track + "コース " + m + "B",
                "内数",
                n,
                (c) => {
                  const v = groups(c);
                  return v == null ? null : (v.mark?.includes(m) ?? false);
                },
                ref(tables.page + 16, "化学システム工学・コース別B単位の注"),
              ),
            );
          }
      }
      if (idx === 8) {
        if (!grad && tables.fusion && !relaxed)
          rows.push(
            row(
              "eng-fusion",
              "融合領域分野の専門応用 B",
              "内数",
              12,
              (c) =>
                type(c)
                  ? type(c) === "T" &&
                    !night(c) &&
                    !c.graduationExcluded &&
                    isFusion(c, y)
                  : null,
              ref(
                y === 2021 ? 18 : y === 2020 ? 30 : 31,
                "工学部規程別表第2・融合領域分野",
              ),
            ),
          );
        if (grad) {
          const packageRow = row(
            "eng-package",
            y <= 2021
              ? "一つの主専攻の指定科目"
              : "配属時に選択したパッケージの講義",
            "内数",
            tables.package,
            (c) => {
              if (!type(c)) return null;
              if (type(c) !== "T") return false;
              if (y < 2022) return !!groups(c)?.legacy;
              if (!pack) return null;
              return groups(c)?.packageKind === "lecture";
            },
            source,
            {
              note: "科目群の内訳は当該年度の工学部規程別表第3に記載されています。",
            },
          );
          if (y <= 2021)
            packageRow.evaluate = (args) => {
              const choices = engineeringPrograms.slice(0, 7).map((_, i) =>
                capped((c) => {
                  const m = groups(c);
                  return m == null
                    ? null
                    : m.legacy?.includes(i)
                      ? "selected"
                      : false;
                })(args),
              );
              return choices.sort((a, b) => b.value - a.value)[0];
            };
          rows.push(packageRow);
          if (y >= 2022) {
            for (const [m, n] of [
              ["■", 6],
              ["●", 4],
              ["○", 2],
            ])
              rows.push(
                row(
                  "management-" + m,
                  "協創経営 " + m + "B",
                  "内数",
                  n,
                  (c) => {
                    const v = groups(c);
                    if (v == null) return null;
                    if (v.mark === m) return true;
                    return !pack && m === "■" && type(c) === "T" ? null : false;
                  },
                  listRef,
                ),
              );
          }
        }
      }
    } else if (!min)
      rows.push(
        check(
          "program",
          "専門基礎・専門応用の指定科目",
          "工学部の学位プログラムを選んでください。",
          source,
        ),
      );
    rows.push(...transferRow(p, source, "工学部"));
    stages.push(
      stage(grad ? "graduation" : "year4", grad ? "卒業" : "4年次進級", rows),
    );
  }
  return {
    title: book.title,
    sources: [book, guide, exclusions, ...teachingTableSources(book)],
    stages,
    cap: {
      limit: 28,
      source: capSource,
      classify: (c) => engineeringCap(c, y),
      note:
        `集中講義、単位互換、休業中の特別開講、教員免許状の別表${y < 2019 ? "2" : "1"}で指定された教職科目、リメディアル演習を除きます。` +
        (y === 2018
          ? "教職のハンドブックと別表2で科目名が異なる場合は、CAPへの算入を工学部学務係に確認してください。"
          : ""),
    },
  };
}
