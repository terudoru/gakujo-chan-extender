import {
  norm,
  name,
  type,
  category,
  night,
  row,
  check,
  months,
  stage,
  urlPage,
  programFor,
  irregular,
  isThirdTransfer,
  intensive,
  record,
  transferRow,
  courseYear,
} from "./common.mjs";
import { scienceCourses, semester2026 } from "./science-tables.mjs";
import { scienceEquivalences } from "./science-equivalences.mjs";
import { scienceChoices } from "./science-choices.mjs";
import { departmentCourses, departmentMinima } from "./science-departments.mjs";
import { semester2021 } from "./science-archive.mjs";

export const sciencePrograms = [
  "数学",
  "物理学",
  "化学",
  "生物学",
  "地質科学",
  "自然環境科学",
  "フィールド科学人材育成",
];
export const scienceOptions = sciencePrograms.flatMap((p, i) =>
  i < 5 ? [p + "（専門力）", p + "（総合力）"] : [p + "プログラム"],
);
const site = "https://www.sc.niigata-u.ac.jp/sc/edu/";
const programGuide = {
  title: "年度別履修ガイド・プログラム相談員（学内認証）",
  url: site + "rishu_guide.html",
};
const semesterGuide = {
  title: "理学部の学期別開講科目・対象プログラム",
  url: site + "subject/index.html",
};
const readAcross = {
  title: "開講年度・入学年度別の読み替え対応表",
  url: site + "yomikae.html",
};
const guidance = {
  title: "2023～2026年度の学期別・編入生ガイダンス",
  url: site + "guidance.html",
};
const archive = [
  {
    title: "2021年度理学部・第1学期の開講番号と授業名",
    url: "https://www.niigata-u.ac.jp/wp-content/uploads/2021/03/210310_05.pdf",
  },
  {
    title: "2021年度理学部・第2学期の開講番号と授業名",
    url: "https://www.niigata-u.ac.jp/wp-content/uploads/2021/09/210910_05.pdf",
  },
];
const commonCategories = [
  "大学学習法",
  "英語",
  "初修外国語",
  "健康・スポーツ",
  "情報リテラシー",
  "新潟大学個性化科目",
  "人文社会・教育科学",
  "自然科学",
  "医歯学",
];
const cohorts = {
  2005: 16,
  2006: 16,
  2007: 16,
  2008: 16,
  2009: 16,
  2010: 16,
  2011: 17,
  2012: 17,
  2013: 17,
  2014: 17,
  2015: 17,
  2016: 16,
  2017: 18,
  2018: 20,
  2019: 20,
  2020: 20,
  2021: 21,
  2022: 21,
  2023: 22,
  2024: 22,
  2025: 23,
  2026: 24,
};
const sciNorm = (n) =>
  norm(n).replace(
    /^(?:分野|数学(?=数学基礎演習)|(?:物理学|化学|生物学|地学)(?=(?:物理学|化学|生物学|地学)基礎実習))/,
    "",
  );
function scannedMinima(y, i) {
  if (i < 0 || i > 5 || y > 2011) return undefined;
  const base = i === 5 ? (y <= 2008 ? 22 : 20) : 16;
  const split = [
    y <= 2007 ? [23, 0, 41] : [30, 2, 32],
    [46, 12, 6],
    [42, 4, 18],
    [12, "12又は16", "40又は36"],
    [53, 0, 11],
    y <= 2008 ? [14, 0, 44] : [24, 12, 24],
  ][i];
  return [base, 80 - base, ...(y === 2005 ? [] : split)];
}
function equivalentMap(y) {
  const byCode = new Map();
  for (const [
    from,
    to,
    codes,
    target,
    credits,
    permission,
  ] of scienceEquivalences)
    if (from <= y && y <= to)
      for (const code of codes)
        byCode.set(code, { target: sciNorm(target), credits, permission });
  return byCode;
}
function semesterAllowed(n, y) {
  const yearLabel = norm(n);
  const ranges = [...yearLabel.matchAll(/r(\d+)(以前|以降)入学者/g)];
  if (ranges.length !== 1) return true;
  const [, r, dir] = ranges[0],
    cut = 2018 + Number(r);
  return dir === "以前" ? y <= cut : y >= cut;
}
function discipline(n) {
  if (typeof n !== "string") return null;
  if (/^(解析学基礎|数学基礎|統計学基礎)/.test(n)) return "数学・統計学";
  return (
    ["物理学", "化学", "生物学", "地学"].find((f) => n.startsWith(f)) ?? null
  );
}
function scienceProfile(p, book) {
  const y = +book.year,
    old = y <= 2016,
    program = programFor(
      p,
      [...sciencePrograms].sort((a, b) => b.length - a.length),
    );
  const index = sciencePrograms.indexOf(program),
    track = norm(p.program).includes("総合力")
      ? 1
      : norm(p.program).includes("専門力")
        ? 0
        : null;
  const first = y <= 2022 ? 9 : y <= 2024 ? 10 : y === 2025 ? 11 : 12;
  const reference = new Map(),
    eq = equivalentMap(y);
  const oldNames = new Map();
  for (const [from, to, i, group, credits, names] of departmentCourses)
    if (from <= y && y <= to) {
      for (const title of names) {
        const n = sciNorm(title);
        if (i === index)
          reference.set(n, {
            title,
            group,
            credits,
            page: (y === 2016 ? 8 : 9) + i,
          });
        if (!oldNames.has(n)) oldNames.set(n, new Set());
        oldNames.get(n).add(i);
      }
    }
  for (const [from, to, offset, flags, credits, names] of scienceCourses)
    if (from <= y && y <= to)
      for (const n of names) {
        const key = sciNorm(n),
          prior = reference.get(key);
        const merged = prior
          ? Array.from(flags, (f, i) => (f === "-" ? prior.flags[i] : f)).join(
              "",
            )
          : flags;
        reference.set(key, {
          title: n,
          flags: merged,
          credits: Number(credits),
          page: first + offset,
        });
      }
  function identity(c) {
    if (!type(c)) return null;
    const a = eq.get(c.code),
      listing = semester2026[c.code];
    if (a) {
      if (
        a.permission &&
        !(
          c.registrationApproved ||
          c.permitted ||
          ["秀", "優", "良", "可", "合格", "認定"].includes(c.grade)
        )
      )
        return null;
      if (Number(c.credits) !== a.credits) return null;
      return a.target;
    }
    if (listing && !semesterAllowed(listing[1], y)) return false;
    const historical = semester2021[c.code];
    if (historical) {
      const official = sciNorm(historical[0]);
      if (c.title && sciNorm(c.title) !== official) return null;
      return official;
    }
    return sciNorm(c.title);
  }
  function membership(c) {
    const n = identity(c);
    if (n == null || n === false) return n;
    if (
      night(c) ||
      c.graduationExcluded ||
      n === "臨海実習ii" ||
      c.socialEducationOfficer ||
      (c.curatorCourse && type(c) !== "G")
    )
      return false;
    if (c.teacherTraining || /^数学科教育法i{1,3}$|^数学科教育法iv$/.test(n)) {
      return index === 0 && /^数学科教育法(?:i|ii|iii|iv)$/.test(n)
        ? "major"
        : false;
    }
    const cat = category(c),
      t = type(c),
      listing = semester2026[c.code],
      r = reference.get(n);
    if (t === "Q" && y >= 2017 && y <= 2023) return false;
    if (old) {
      if (t === "S" && courseYear(c) > 2016 && !c.recognitionApproved)
        return null;
      if (t === "G" && cat === "大学学習法" && index >= 0 && y >= 2012) {
        const designated = [
          "数学",
          "現代物理学への招待",
          "化学学習法",
          "生命科学への招待",
          "地質科学学習法",
          "環境科学スタディ・スキルズ",
        ][index];
        return n.includes(designated) ? "major" : null;
      }
      if (t === "S" && r) return "major";
      if (
        t === "S" &&
        index >= 0 &&
        oldNames.has(n) &&
        !oldNames.get(n).has(index)
      )
        return "general";
      if (t === "G" && cat === "自然系共通専門基礎") {
        if (
          y >= 2012 &&
          ((index === 1 &&
            /^(物理学基礎(?:bi|bii|ci|cii)|物理学入門)$/.test(n)) ||
            (index === 2 && n === "化学基礎c"))
        )
          return false;
        if (
          y >= 2012 &&
          ((index === 1 && /^物理学基礎ai{1,2}$/.test(n)) ||
            (index === 2 && /^化学基礎[ab]$/.test(n)))
        )
          return "major";
        if (
          y >= 2012 &&
          /^(数学基礎[ab]|統計学基礎|物理学基礎(?:[abc]i{1,2}|d)|化学基礎[abc]|生物学基礎[abc]|地学基礎[abc])$/.test(
            n,
          ) &&
          courseYear(c) <= 2016
        )
          return "major";
        return null;
      }
      if (t === "G" && commonCategories.includes(cat) && cat !== "大学学習法")
        return "general";
      return null;
    }
    if (t === "G" && cat === "自然系共通専門基礎") {
      if (listing && /理学部を除く|工学部のみ|工学部対象/.test(listing[2]))
        return false;
      if (listing && !/理学部|自然系学部/.test(listing[2])) return null;
      return r || (y === 2017 && discipline(n)) ? "major" : null;
    }
    if (n === "理学スタディ・スキルズ" && (t === "S" || t === "G"))
      return "major";
    if (r && (t === "S" || (listing && ["A", "T", "G"].includes(t)))) {
      if (r.flags === "△".repeat(12)) return false;
      if (index >= 0) {
        const pos = index < 5 ? 2 * index : index + 5;
        const marks =
          index < 5 && track == null
            ? r.flags.slice(pos, pos + 2)
            : r.flags[pos + (track ?? 0)];
        if (marks.includes("△")) return /^△+$/.test(marks) ? false : null;
      }
      return "major";
    }
    if (t === "S") return reference.size ? (listing ? null : false) : null;
    if (t === "G" && commonCategories.includes(cat))
      return cat === "大学学習法" && y < 2022 ? false : "general";
    return null;
  }
  return {
    y,
    old,
    index,
    track,
    program,
    first,
    reference,
    identity,
    membership,
  };
}
function creditEvaluation(sc, select, { fieldCap = false } = {}) {
  return ({ courses }) => {
    const remaining = new Map(),
      contributions = [];
    let unclear = false;
    const add = (c, bucket, limit = Infinity) => {
      if (!Number.isFinite(c.credits)) {
        unclear = true;
        return;
      }
      const used = remaining.get(bucket) ?? 0,
        add = Math.min(c.credits, Math.max(0, limit - used));
      if (add > 0) {
        remaining.set(bucket, used + add);
        contributions.push(record(c, add));
      }
    };
    const pairs = new Map();
    for (const c of [...courses].sort((a, b) =>
      String(a.code).localeCompare(String(b.code)),
    )) {
      const ok = select(c);
      if (ok == null) {
        unclear = true;
        continue;
      }
      if (!ok) continue;
      const n = sc.identity(c);
      if (
        sc.y >= 2018 &&
        /^(健康スポーツ科学実習i(?:a|b)?|健康スポーツ科学講義[ab]?)$/.test(n)
      ) {
        const k = n.includes("実習") ? "体育実技" : "体育講義";
        if (!pairs.has(k)) pairs.set(k, []);
        pairs.get(k).push(c);
        continue;
      }
      let bucket = n,
        limit = sc.reference.get(n)?.credits ?? Infinity;
      if (sc.y >= 2017 && /^物理学基礎[ab]i{1,2}$/.test(n)) {
        bucket = n.replace(/[ab]/, "");
        limit = 2;
      }
      if (sc.y >= 2026 && ["科学・技術と社会", "科学と社会"].includes(n)) {
        bucket = "科学と社会";
        limit = 2;
        if (c.duplicateApproved) {
          bucket = c.code;
          limit = c.credits;
        }
      }
      if (/^理学基礎演習$|アクティブ・ラーニング$/.test(n)) limit = 2;
      if (fieldCap) {
        const group = discipline(n);
        if (!group) {
          unclear = true;
          continue;
        }
        const fieldUsed = remaining.get("field-" + group) ?? 0,
          old = contributions.length;
        add(
          c,
          bucket,
          Math.min(
            limit,
            (remaining.get(bucket) ?? 0) + Math.max(0, 6 - fieldUsed),
          ),
        );
        if (contributions.length > old)
          remaining.set(
            "field-" + group,
            fieldUsed + contributions.at(-1).applied,
          );
      } else add(c, bucket, limit);
    }
    for (const [bucket, cs] of pairs) {
      const practical = bucket === "体育実技",
        max = practical ? 1 : 2;
      const whole = cs.find((c) => !/[ab]$/.test(name(c)));
      if (whole) {
        add(whole, bucket, max);
        continue;
      }
      const left = cs.filter((c) => name(c).endsWith("a")),
        right = cs.filter((c) => name(c).endsWith("b"));
      const pair = left
        .flatMap((a) => right.map((b) => [a, b]))
        .find(
          ([a, b]) =>
            !practical ||
            sc.y < 2019 ||
            (a.teacher && b.teacher && norm(a.teacher) !== norm(b.teacher)),
        );
      if (pair) for (const c of pair) add(c, bucket, max);
      else if (left.length && right.length && cs.some((c) => !c.teacher))
        unclear = true;
    }
    return {
      value: contributions.reduce((s, c) => s + c.applied, 0),
      contributions,
      ...(unclear && {
        unknown:
          "科目の所属区分、読替・組合せまたは教員を理学部学務係に確認してください。",
      }),
    };
  };
}
export function science(book, p) {
  const sc = scienceProfile(p, book),
    { y, old, index, track } = sc,
    page = cohorts[y];
  const ref = urlPage(book, page, "理学部履修の手引・別表の履修方法"),
    capRef = urlPage(
      book,
      page + (y === 2015 || y === 2016 ? 2 : 1),
      "履修科目数の上限",
    ),
    reg = urlPage(book, old ? 4 : sc.first, "理学部規程・別表"),
    progRef = urlPage(book, page + (y === 2017 ? 1 : 2), "各年次の進級");
  const corrected = [2025, 2026].includes(y)
    ? {
        title:
          y === 2026
            ? "履修の手引21頁の訂正・重複履修"
            : "別表第2（地質科学）の訂正",
        url: site + "rishu_tebiki/tebiki" + y + "_mod1.pdf",
      }
    : ref;
  const matchCategory = (c, key) => {
    const m = sc.membership(c);
    return m == null ? null : key === "total" ? !!m : m === key;
  };
  const count = (key, l, n, test, source = ref, opts = {}) =>
    row(key, l, "単位", n, test, source, {
      evaluate: creditEvaluation(sc, test, opts),
    });
  const named = (ns) => {
    const names = new Set(ns.map(norm));
    return (c) => {
      const n = sc.identity(c);
      return n == null
        ? null
        : names.has(n)
          ? matchCategory(c, "major")
          : false;
    };
  };
  const rows = [
    months(48, ref),
    ...[
      ["total", "卒業単位の合計", 124],
      ["general", "教養教育に関する科目", old ? 25 : 21],
      ["major", "専門教育に関する科目", old ? 82 : 84],
    ].map(([k, l, n]) => count(k, l, n, (c) => matchCategory(c, k))),
  ];
  if (old) {
    const legacy =
      departmentMinima[y]?.[sc.program + "科"] ?? scannedMinima(y, index);
    const source = urlPage(
      book,
      y === 2016 || y <= 2010 ? 6 : 7,
      "改組前の学科別単位・別表第1",
    );
    const generalIn =
      (...keys) =>
      (c) =>
        keys.includes(category(c))
          ? matchCategory(c, "general")
          : type(c)
            ? false
            : null;
    rows.push(
      count("english", "英語", 2, generalIn("英語"), source),
      count("foreign", "初修外国語", 2, generalIn("初修外国語"), source),
      count(
        "old-languages",
        "英語・初修外国語の合計",
        8,
        generalIn("英語", "初修外国語"),
        source,
      ),
      count(
        "old-sport",
        "体育実技",
        1,
        (c) =>
          category(c) === "健康・スポーツ" &&
          (c.subcategory === "体育実技" || name(c).includes("実習"))
            ? matchCategory(c, "general")
            : type(c)
              ? false
              : null,
        source,
      ),
    );
    if (index >= 0) {
      const social = index === 4 ? 12 : index === 5 && y >= 2009 ? 4 : 8;
      rows.push(
        count(
          "old-social",
          "人文社会・教育科学",
          social,
          generalIn("人文社会・教育科学"),
          source,
        ),
      );
      if (index === 0 && y >= 2008)
        rows.push(
          count(
            "old-data",
            "情報リテラシー",
            2,
            generalIn("情報リテラシー"),
            source,
          ),
        );
    }
    rows.push(
      row(
        "study",
        "所属学科が指定する大学学習法",
        "必修",
        2,
        (c) => {
          if (!type(c)) return null;
          if (category(c) !== "大学学習法") return false;
          if (y < 2012 || index < 0) return null;
          const n = sc.identity(c);
          const designated = [
            "数学",
            "現代物理学への招待",
            "化学学習法",
            "生命科学への招待",
            "地質科学学習法",
            "環境科学スタディ・スキルズ",
          ][index];
          return n === false
            ? false
            : typeof n === "string" && n.includes(designated)
              ? true
              : null;
        },
        ref,
      ),
    );
    if (legacy) {
      rows.push(
        count(
          "old-foundation",
          "自然系共通専門基礎",
          Number(legacy[0]),
          (c) =>
            category(c) === "自然系共通専門基礎"
              ? matchCategory(c, "major")
              : type(c)
                ? false
                : null,
          source,
        ),
      );
      rows.push(
        count(
          "old-special",
          "自然科学の学科専門科目",
          Number(legacy[1]),
          (c) =>
            sc.reference.has(sc.identity(c))
              ? matchCategory(c, "major")
              : type(c) !== "S"
                ? false
                : null,
          source,
        ),
      );
      for (const [j, group] of [
        "必修科目",
        "選択必修科目",
        "選択科目",
      ].entries()) {
        if (!legacy[j + 2]) continue;
        if (!/^\d+$/.test(legacy[j + 2])) {
          rows.push(
            check(
              "old-" + group,
              "学科専門・" + group + " " + legacy[j + 2] + "単位",
              "課題研究の選択により必要単位が変わります。学科の履修ガイドと照合してください。",
              source,
            ),
          );
          continue;
        }
        rows.push(
          count(
            "old-" + group,
            "学科専門・" + group,
            Number(legacy[j + 2]),
            (c) =>
              sc.reference.has(sc.identity(c))
                ? sc.reference.get(sc.identity(c)).group === group &&
                  matchCategory(c, "major")
                : type(c) === "S" || !type(c)
                  ? null
                  : false,
            source,
          ),
        );
      }
      for (const [n, r] of sc.reference)
        if (r.group === "必修科目")
          rows.push(
            count(
              "old-required-" + n,
              r.title,
              r.credits,
              named([n]),
              urlPage(book, r.page, "別表第2・所属学科の必修科目"),
            ),
          );
    }
    if (y >= 2012 && index === 4)
      rows.push(
        count(
          "old-geo-math",
          "数学基礎A・Bまたは統計学基礎",
          2,
          named(["数学基礎A", "数学基礎B", "統計学基礎"]),
          ref,
        ),
      );
    if (y >= 2012 && index === 5) {
      const picks = [
        ["数学基礎A"],
        ["化学基礎A"],
        ["化学基礎B"],
        ["生物学基礎A"],
        ["生物学基礎B"],
        ["地学基礎A"],
        ["数学基礎B", "統計学基礎"],
        ["物理学基礎AI", "物理学基礎BI"],
        ["地学基礎B", "地学基礎C"],
        y < 2015
          ? ["物理学基礎D"]
          : ["物理学基礎AII", "物理学基礎BII", "物理学基礎D"],
      ];
      for (const ns of picks)
        rows.push(
          count(
            "old-natural-" + ns[0],
            ns.join("・"),
            2,
            named(ns),
            urlPage(book, page + 1, "自然環境科学科の学科別留意事項"),
          ),
        );
    }
    if (index === 1 || index === 2) {
      for (const n of index === 1
        ? ["物理学基礎AI", "物理学基礎AII"]
        : ["化学基礎A", "化学基礎B"]) {
        // Old handbooks differ on the names of mandatory physics and chemistry courses.
        if (y >= 2012)
          rows.push(
            count(
              "old-" + n,
              n,
              2,
              named([n]),
              urlPage(book, page + 1, "学科別の指定科目"),
            ),
          );
      }
    }
    rows.push(
      check(
        "old-designated",
        "学科別の専門・選択必修の内訳",
        "入学年度の別表第1・2と学科の履修ガイドで、所属学科・コースの指定科目を確認してください。",
        reg,
      ),
    );
  } else {
    rows.push(
      count(
        "study",
        "理学スタディ・スキルズ",
        2,
        named(["理学スタディ・スキルズ"]),
      ),
    );
    for (const [key, label] of [
      ["english", "英語"],
      ["foreign", "初修外国語"],
    ])
      rows.push(
        count(key, label, y <= 2020 && key === "english" ? 4 : 2, (c) =>
          matchCategory(c, "general") == null
            ? null
            : matchCategory(c, "general") && category(c) === label,
        ),
      );
    if (y <= 2020)
      rows.push(
        count(
          "sci-sport",
          "健康スポーツ科学実習Ⅰ（体育実技）",
          1,
          (c) =>
            matchCategory(c, "general") &&
            /^健康スポーツ科学実習i(?:a|b)?$/.test(name(c)),
        ),
      );
    if (y === 2026)
      rows.push(
        count(
          "sci-social",
          "新潟大学個性化科目・人文社会・教育科学",
          8,
          (c) =>
            matchCategory(c, "general") &&
            ["新潟大学個性化科目", "人文社会・教育科学"].includes(category(c)),
        ),
      );
    for (const n of y < 2021 ? [] : y === 2026 ? ["I", "II"] : ["I"]) {
      rows.push(
        count(
          "sci-data-" + n,
          "データサイエンス総論" + n,
          1,
          (c) =>
            sc.identity(c) == null
              ? null
              : sc.identity(c) === norm("データサイエンス総論" + n) &&
                type(c) === "G",
          corrected,
        ),
      );
    }
    const nat = (c) => {
      const m = matchCategory(c, "major");
      return m == null ? null : m && category(c) === "自然系共通専門基礎";
    };
    rows.push(
      count(
        "sci-foundation",
        "自然系共通専門基礎（原則1分野6単位以内）",
        12,
        nat,
        ref,
        { fieldCap: true },
      ),
    );
    const codeList = (c, part) => {
      const m = matchCategory(c, "major");
      if (m !== true) return m;
      const s = semester2026[c.code]?.[0];
      if (!s) return null;
      return s.includes(part);
    };
    rows.push(
      count("sci-basic", "理学部共通ベーシック科目", 8, (c) =>
        codeList(c, "basic"),
      ),
      count("sci-practical", "基礎実習・演習科目", 2, (c) => {
        const n = sc.identity(c);
        return n == null
          ? null
          : /(?:学基礎実習|数学基礎演習)/.test(n) && matchCategory(c, "major");
      }),
      count("sci-core", "理学部共通コア科目", 6, (c) => codeList(c, "core")),
    );
    const act = y >= 2022 ? "理学基礎演習" : "アクティブ・ラーニング";
    rows.push(
      count("sci-exercise", act, 2, (c) => {
        const n = sc.identity(c);
        return n == null
          ? null
          : typeof n === "string" &&
              n.endsWith(act) &&
              matchCategory(c, "major");
      }),
    );
    if (index >= 0) {
      const pos = index < 5 ? index * 2 : index + 5;
      if (y === 2026 && (track != null || index >= 5)) {
        const column = pos + (track ?? 0),
          table = urlPage(
            book,
            track === 1 || index === 6 ? 11 : 10,
            "別表第1・履修体系別の内訳",
          );
        if (track === 1 || index === 6)
          rows.push(
            row(
              "sci-practical-fields",
              "基礎実習科目を複数分野で修得",
              "条件",
              1,
              undefined,
              table,
              {
                unit: "condition",
                evaluate: ({ courses }) => {
                  const seen = new Map();
                  let unknown = false;
                  for (const c of courses) {
                    const n = sc.identity(c);
                    if (n == null) {
                      unknown = true;
                      continue;
                    }
                    const field =
                      typeof n === "string" &&
                      n.match(
                        /^(数学)基礎演習|^(物理学|化学|生物学|地学)基礎実習/,
                      );
                    if (!field) continue;
                    const m = matchCategory(c, "major");
                    if (m == null) {
                      unknown = true;
                      continue;
                    }
                    if (m && c.credits > 0 && !seen.has(field[1] || field[2]))
                      seen.set(field[1] || field[2], c);
                  }
                  return {
                    value: Number(seen.size >= 2),
                    contributions: [...seen.values()]
                      .slice(0, 2)
                      .map((c) => record(c, c.credits)),
                    ...(seen.size < 2 &&
                      unknown && {
                        unknown: "基礎実習科目の分野を確認してください。",
                      }),
                  };
                },
              },
            ),
          );
        const belongs = (c) => {
          const m = matchCategory(c, "major");
          if (m !== true) return m;
          const r = sc.reference.get(sc.identity(c));
          return r ? ["●", "○"].includes(r.flags[column]) : null;
        };
        const subject = (c, core, own) => {
          const m = matchCategory(c, "major");
          if (m !== true) return m;
          const sections = semester2026[c.code]?.[0];
          if (!sections) return null;
          if (
            core
              ? !sections.includes("core")
              : sections.includes("core") ||
                !/(?:^| )(?:math|phys|chem|bio|geo|env|fres|sonota)(?: |$)/.test(
                  sections,
                )
          )
            return false;
          const designated = belongs(c);
          return designated == null ? null : designated === own;
        };
        // These are inclusive minima within a category. They coexist with the individual compulsory courses.
        const core = [14, 14, 4, 4, 10, 8, 8, 8, 9, 9, 4, 6][column];
        const special = [14, 14, 40, 30, 44, 30, 25, 21, 44, 32, 16, 44][
          column
        ];
        rows.push(
          count(
            "sci-home-core",
            index === 6 ? "理学部共通コア" : "所属プログラムのコア科目",
            core,
            (c) => (index === 6 ? codeList(c, "core") : subject(c, true, true)),
            table,
          ),
        );
        rows.push(
          count(
            "sci-home-special",
            "所属プログラムの専門科目",
            special,
            (c) => subject(c, false, true),
            table,
          ),
        );
        if (index < 6)
          rows.push(
            count(
              "sci-other-core",
              "他プログラムのコア科目",
              track === 1 ? 4 : 2,
              (c) => subject(c, true, false),
              table,
            ),
          );
        const combined = (c, home) => {
          const decisions =
            home === null
              ? [
                  subject(c, true, true),
                  subject(c, true, false),
                  subject(c, false, true),
                  subject(c, false, false),
                ]
              : [subject(c, true, home), subject(c, false, home)];
          return decisions.includes(true)
            ? true
            : decisions.includes(null)
              ? null
              : false;
        };
        const home = [58, 48, 58, 40, 54, 38, 58, 43, 58, 48, 58, 60][column];
        rows.push(
          count(
            "sci-home-combined",
            "所属プログラムのコア・専門科目計",
            home,
            (c) => combined(c, true),
            table,
          ),
        );
        rows.push(
          count(
            "sci-special-combined",
            "コア・専門科目（他プログラムを含む）",
            60,
            (c) => combined(c, null),
            table,
          ),
        );
        if (track === 1)
          rows.push(
            count(
              "sci-other-combined",
              "他プログラムのコア・専門科目計",
              12,
              (c) => combined(c, false),
              table,
            ),
          );
        if (index === 5)
          rows.push(
            count(
              "sci-home-practical",
              "自然環境科学の基礎実習科目",
              4,
              (c) => {
                const n = sc.identity(c);
                return n == null
                  ? null
                  : /(?:学基礎実習|数学基礎演習)/.test(n) &&
                      matchCategory(c, "major");
              },
              table,
            ),
          );
        const fieldMinimum = [
          [4, 0, 0, 0, 0],
          [0, 0, 0, 0, 0],
          [0, 4, 0, 0, 0],
          [0, 4, 0, 0, 0],
          [0, 0, 4, 0, 0],
          [0, 0, 4, 0, 0],
          [2, 2, 2, 2, 2],
          [2, 2, 2, 2, 2],
          [2, 0, 0, 0, 6],
          [2, 0, 0, 0, 6],
          [2, 2, 2, 2, 2],
          [0, 0, 0, 0, 0],
        ][column];
        for (const [i, field] of [
          "数学・統計学",
          "物理学",
          "化学",
          "生物学",
          "地学",
        ].entries()) {
          if (fieldMinimum[i])
            rows.push(
              count(
                "sci-discipline-" + i,
                field + "の自然系共通専門基礎",
                fieldMinimum[i],
                (c) => {
                  const selected = nat(c);
                  return selected === true
                    ? discipline(sc.identity(c)) === field
                    : selected;
                },
                table,
              ),
            );
        }
      }
      const own = new Map();
      for (const [n, r] of sc.reference) {
        const flags = r.flags;
        const required =
          flags[pos + (track ?? 0)] === "●" &&
          (index >= 5 || track != null || flags[pos + 1] === "●");
        if (required && n !== "理学スタディ・スキルズ" && n !== "理学基礎演習")
          own.set(n, r);
      }
      for (const [n, r] of own)
        rows.push(
          count(
            "sci-required-" + n,
            r.title,
            r.credits,
            named([n]),
            urlPage(book, r.page, "別表第2・" + sc.program + "指定科目"),
          ),
        );
      const notes = urlPage(
        book,
        sc.first + 7,
        "別表第2備考・" + sc.program + "の指定科目群",
      );
      for (const [from, to, i, label, min, ns] of scienceChoices) {
        if (
          y < from ||
          y > to ||
          (index !== i && !(i === 35 && [3, 5].includes(index)))
        )
          continue;
        const correction =
          y === 2025 && index === 4 && label === "数学・統計学";
        const test = named(correction ? [...ns, "数学基礎B1"] : ns);
        const r = count(
          "sci-pool-" + label,
          label,
          min,
          test,
          correction ? corrected : notes,
        );
        if (index === 5 && y === 2026 && label === "指定実験・実習") {
          const cappedNames = [
            "自然環境科学実験B1",
            "自然環境科学実験B2",
            "環境生物学野外実習A",
            "環境生物学野外実習B",
          ].map(norm);
          const evaluate = r.evaluate;
          r.evaluate = (args) => {
            const res = evaluate(args);
            let remaining = 4;
            for (const c of res.contributions)
              if (cappedNames.includes(sc.identity(c))) {
                c.applied = Math.min(remaining, c.applied);
                remaining -= c.applied;
              }
            res.contributions = res.contributions.filter((c) => c.applied > 0);
            res.value = res.contributions.reduce((v, c) => v + c.applied, 0);
            return res;
          };
        }
        rows.push(r);
      }
      if (index === 1 && track === 1 && y >= 2018)
        for (const level of ["I", "II"]) {
          rows.push(
            count(
              "sci-physics-" + level,
              "物理学基礎 A" + level + "・B" + level + "の選択",
              2,
              named(["物理学基礎A" + level, "物理学基礎B" + level]),
              notes,
            ),
          );
        }
      if (index === 3 && y >= 2021) {
        const pairs = [
          "解析学基礎",
          "数学基礎A",
          "数学基礎B",
          "統計学基礎",
        ].map((stem) => [stem + "1", stem + "2"]);
        rows.push(
          row(
            "sci-math-pair",
            "同一系列の数学・統計学基礎1と2",
            "組合せ",
            2,
            named(pairs.flat()),
            notes,
            {
              evaluate: ({ courses }) => {
                const results = pairs.map((pair) =>
                  creditEvaluation(sc, named(pair))({ courses }),
                );
                return results.sort((a, b) => b.value - a.value)[0];
              },
            },
          ),
        );
      }
      if (index === 3 && track === 1 && y >= 2018) {
        const research = (level) => (c) => {
          const n = sc.identity(c);
          if (n == null) return null;
          if (n === "課題研究" + level + "(生物学)")
            return matchCategory(c, "major");
          if (n !== "課題研究" + level) return false;
          const program = semester2026[c.code]?.[0];
          return program
            ? program.split(" ").includes("bio") && matchCategory(c, "major")
            : null;
        };
        const a = research("i"),
          b = research("ii");
        rows.push(
          row(
            "sci-research-choice",
            "生物学の課題研究Ⅰ（8単位）またはⅡ（4単位）",
            "指定科目",
            1,
            (c) => {
              const x = a(c),
                z = b(c);
              return x === true || z === true
                ? true
                : x == null || z == null
                  ? null
                  : false;
            },
            notes,
            {
              unit: "condition",
              evaluate: ({ courses }) => {
                const x = creditEvaluation(sc, a)({ courses }),
                  z = creditEvaluation(sc, b)({ courses });
                const result = x.value >= 8 ? x : z;
                return {
                  value: x.value >= 8 || z.value >= 4 ? 1 : 0,
                  contributions: result.contributions,
                  unknown: x.unknown || z.unknown,
                };
              },
            },
          ),
        );
      }
      if (index < 5 && track == null)
        rows.push(
          check(
            "sci-track",
            "専門力・総合力の履修体系",
            "所属する履修体系を選ぶと、別表第2の該当欄で必修科目を照合できます。",
            reg,
          ),
        );
    }
    rows.push(
      check(
        "sci-limits",
        "複数区分にまたがる選択枠の充当",
        "所属プログラム・履修体系の別表第1で、必修や指定枠に使った単位を除いた選択枠の残りを理学部学務係の確認表と照合してください。",
        urlPage(book, sc.first - 2, "別表第1・プログラム別の修得単位"),
      ),
    );
  }
  rows.push(...transferRow(p, ref, "理学部"));
  const stages = [];
  if (old) {
    for (const n of [2, 3, 4])
      stages.push(
        stage("year" + n, n + "年次進級", [
          check(
            "old-progress-" + n,
            "所属学科の" + n + "年次進級条件",
            "所属学科が定める進級条件を当該年度の学科ガイド・学務係で確認してください。",
            progRef,
          ),
        ]),
      );
  } else {
    const timing =
      y < 2025
        ? []
        : [
            row(
              "progress-month",
              "進級時期（4月・10月）",
              "時期",
              1,
              undefined,
              progRef,
              {
                unit: "condition",
                profileValue: ({ assessmentDate }) => {
                  if (!/^\d{4}-\d{2}-\d{2}$/.test(assessmentDate ?? ""))
                    return null;
                  const d = new Date(assessmentDate + "T00:00:00Z");
                  return Number.isFinite(+d) &&
                    d.toISOString().slice(0, 10) === assessmentDate
                    ? Number([4, 10].includes(d.getUTCMonth() + 1))
                    : null;
                },
              },
            ),
          ];
    if (!isThirdTransfer(p))
      stages.push(
        stage("year2", "2年次進級", [months(12, progRef), ...timing]),
      );
    if (!isThirdTransfer(p))
      stages.push(
        stage("assignment", "学位プログラムの配属", [
          months(18, progRef),
          check(
            "selection",
            "志望プログラムの選択要件",
            "入学年度のプログラム選択条件と受入枠を、理学部の相談員に確認してください。",
            programGuide,
          ),
        ]),
      );
    for (const n of [3, 4]) {
      if (n === 3 && isThirdTransfer(p)) continue;
      stages.push(
        stage("year" + n, n + "年次進級", [
          months(12, progRef, n - 1),
          ...timing,
          ...(n === 3
            ? [
                check(
                  "selection",
                  "プログラムの選択要件",
                  "入学年度の履修ガイドで配属の判定を確認してください。",
                  programGuide,
                ),
              ]
            : []),
          check(
            "program-progress-" + n,
            (sc.program || "所属プログラム") + "の" + n + "年次進級条件",
            "学期別の開講表では進級の指定単位を確定できません。年度別履修ガイドを学内で確認するか、プログラム相談員に問い合わせてください。",
            programGuide,
          ),
        ]),
      );
    }
  }
  stages.push(stage("graduation", "卒業", rows));
  return {
    title: book.title,
    sources: [
      book,
      ...(corrected !== ref ? [corrected] : []),
      semesterGuide,
      readAcross,
      programGuide,
      guidance,
      ...(y <= 2021 ? archive : []),
    ],
    stages,
    cap: {
      limit: y < 2015 || irregular(p) ? null : 28,
      source: y < 2015 ? ref : capRef,
      classify: (c) => {
        if (isThirdTransfer(p)) return "exclude";
        if (y < 2015) return "unknown";
        if (intensive(c)) return "exclude";
        const m = sc.membership(c);
        return m == null ? "unknown" : m ? "include" : "exclude";
      },
      note: isThirdTransfer(p)
        ? "3年次編入生にはCAPを適用しません。"
        : y < 2015
          ? "この便覧で学期CAPの数値を確認できません。理学部学務係で確認してください。"
          : "学期28単位。集中講義・卒業要件外の科目を除き、個別の上限超過は申請・認定を確認してください。",
    },
  };
}
