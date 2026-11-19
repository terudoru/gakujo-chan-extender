import {
  act,
  category,
  combined,
  condition,
  contribution,
  credits,
  generalCategories,
  named,
  norm,
  recognition,
  residency,
  source,
  stage,
  stageApproval,
  subtotal,
} from "./rules.mjs";
import { packageCodes } from "./package-codes.mjs";
import { creationAllocation } from "./creation-allocation.mjs";
import { syllabusSection } from "./catalog-sections.mjs";

const site = "https://create.niigata-u.ac.jp/";
const archive = "wp-content/uploads/";
const creationAct = source("創生学部規程・施行日と経過措置", act(110000592));
const books = {
  2017: [archive + "2021/04/4e2995ad7eff834b9ce85c4eaae5ae94-1.pdf", 18, 19, 8, 12],
  2018: [archive + "2022/08/f40a47f79747319f968981e7f1719538.pdf", 1, 2, 0, 0],
  2019: [archive + "2021/04/4e2995ad7eff834b9ce85c4eaae5ae94-1.pdf", 18, 19, 8, 12],
  2020: [archive + "2021/04/4e2995ad7eff834b9ce85c4eaae5ae94.pdf", 17, 18, 9, 11],
  2021: [archive + "2021/03/b745a80bdecf3d49a7463fa891895cd7.pdf", 27, 28, 10, 14],
  2022: [archive + "2022/03/e2a9b2af23d3ba96284a4abd52018013.pdf", 27, 28, 10, 14],
  2023: [archive + "2023/03/6d326046005747021cc21db9c954fc9b.pdf", 11, 12, 21, 23],
  2024: [archive + "2024/04/4e2995ad7eff834b9ce85c4eaae5ae94.pdf", 11, 12, 21, 23],
  2025: [archive + "2025/04/071ad28f4208d0425beea195396432df.pdf", 14, 15, 23, 26],
  2026: ["public/brochers/R8_ccshandbook.pdf", 14, 15, 23, 26],
};
const packageUrl = {
  2025: site + archive + "2025/04/67fe6aa5da2844a3bef5677360fa95d2.pdf",
  2026: site + "public/brochers/R8_package.pdf",
};
function packageNames(year) {
  const current = Object.keys(packageCodes[2026]).filter((name) => {
    if (name === "社会文化学") return year >= 2020;
    if (name === "歴史文化学") return year <= 2019;
    if (name === "知能情報システム") return year < 2025;
    if (name === "情報社会デザイン科学") return year >= 2025;
    return true;
  });
  return year <= 2019 ? [...current, "社会・地域文化学"] : current;
}
export const creationBooks = Object.entries(books).map(([year, [url]]) => ({
  faculty: "創生学部",
  year,
  title: year === "2017" ? "2017年施行 創生学部規程（改正前の便覧収録）" : year + "年度 創生学部学生便覧",
  url: site + url,
  programs: [
    ...(Number(year) >= 2025 ? ["創生学修コース", "DX共創コース"] : ["創生学修課程"]),
    ...packageNames(+year).map((n) => (+year >= 2025 ? "創生学修コース" : "創生学修課程") + "（" + n + "）"),
  ],
}));
// The free-elective table includes other faculties' courses in the listed syllabus categories.
const anyGeneral = (c) => {
  if (c.department === "0B") return false;
  if (!c.category || !c.department) return null;
  return generalCategories.includes(c.category);
};
const own = (n, u) => named(n, "0B|84", u);
const allHalf = [
  "Academic Listening & Speaking",
  "Academic Reading I",
  "Academic Writing I",
  "Oral Communication",
  "Academic Writing II",
  "Academic Reading II",
];
const oneUnit = ["Research Writing", "Academic Communication Skills", "Presentation Skills"];
function skillRow(dx, src, year) {
  const ds = named(["A", "B", "C"].map((v) => "データサイエンス実践" + v), "0B", 2);
  const half = allHalf.map((v) => own("P.A.C.E.(" + v + ")", 0.5));
  const full = oneUnit.map((v) => {
    const match = own("P.A.C.E.(" + v + ")", 1);
    return (c) => {
      const result = match(c);
      if (result !== true || year >= 2020 || v === "Presentation Skills") return result;
      return c.year ? Number(c.year) >= 2020 : null;
    };
  });
  const pace = combined(...half, ...full);
  return credits(
    "skill",
    "データサイエンス" + (dx ? "" : "／P.A.C.E.") + "の選択",
    4,
    dx ? ds : combined(ds, pace),
    src,
    {
      kind: "選択必修",
      evaluate: ({ courses }) => {
        const selected = (checks) =>
          checks.flatMap((test) => {
            const c = courses.find((c) => test(c) === true);
            return c ? [contribution(c, c.credits)] : [];
          });
        const data = selected(["A", "B", "C"].map((v) => own("データサイエンス実践" + v, 2)));
        const basics = selected(half), advanced = selected(full);
        // Six prescribed half-credit courses and at least one additional credit form the P.A.C.E. route.
        const english = basics.length === 6 ? [...basics, ...advanced.slice(0, 1)] : basics;
        const sum = (a) => a.reduce((s, c) => s + c.applied, 0);
        const contributions = !dx && sum(english) > sum(data.slice(0, 2)) ? english : data.slice(0, 2);
        return { value: sum(contributions), contributions };
      },
      note: dx
        ? "データサイエンス実践A～Cのうち4単位。"
        : "同一の系列で4単位。P.A.C.E.では指定の0.5単位科目をすべて履修します。" +
          (year < 2020 ? "2020年4月の在学者は改正附則で追加された2科目も履修できます。" : ""),
    },
  );
}
const through2024 = new Set([
  "250H1003",
  "250H1004",
  "253H1005",
  "254H1006",
  "250H1002",
  "251E6001",
  "251E6002",
  "260H1003",
  "260H1004",
  "263H1005",
  "264H1006",
  "260H1002",
  "261E6001",
  "261E6002",
]);
const from2018 = new Set(["252G7067", "252G7065", "261G7066", "262G7065"]);
const from2022 = new Set(["250S6540", "260S6540"]);
function packageMatcher(selected, type, admission) {
  return (c) => {
    if (c.department === "0B") return false;
    const code = String(c.code ?? "").toUpperCase(), yr = Number(code.slice(0, 2)) + 2000;
    if (!code || !packageCodes[yr] || !selected) return null;
    if (c.year && Number(c.year) !== yr) return null;
    if (
      (through2024.has(code) && admission >= 2025) || (from2018.has(code) && admission < 2018) ||
      (from2022.has(code) && admission < 2022)
    ) return false;
    const item = packageCodes[yr][selected];
    if (!item) return null;
    const exact = item[type].split(" ").includes(code);
    if (exact) return true;
    return false;
  };
}
function graduationTiming(c, p) {
  const term = String(c.period ?? "") + " " + String(c.semester ?? "");
  if (!/[春夏](期|季)?休[業暇]/.test(term)) return true;
  if (!p.graduationMonth || !p.graduationYear || !c.year) return null;
  const month = Number(p.graduationMonth), yr = Number(p.graduationYear);
  return !((month === 3 && yr === Number(c.year) + 1 && /春/.test(term)) ||
    (month === 9 && yr === Number(c.year) && /夏/.test(term)));
}
export function creation(p) {
  const year = Number(p.handbook), record = books[year];
  if (!record) return null;
  const modern = year >= 2025, early = year <= 2020;
  const program = norm(p.program);
  const dx = modern && program.includes("dx共創");
  const determined = !modern || dx || program.includes("創生学修");
  const names = packageNames(year);
  const selected = dx
    ? "情報社会デザイン科学"
    : names.find((n) => p.package === n || program.endsWith("(" + norm(n) + ")") || program === norm(n));
  const url = site + record[0], page = (title, num) => source(title, url + "#page=" + num);
  const progress = page("4年次進級基準", record[1]), grad = page("卒業要件", record[2]);
  const subjects = year === 2018
    ? source("改正前の創生学部規程・科目表", site + books[2019][0] + "#page=9")
    : page("科目区分・指定科目", record[3]);
  const capSrc = year <= 2018
    ? source("平成30年施行の創生学部履修細則第3条", site + books[2019][0] + "#page=12")
    : page("履修登録単位数の上限", record[4]);
  const pkg = source(
    selected ? selected + " 領域学修科目表（2026年度開講分）" : "令和8年度領域学修科目パッケージ案内",
    packageUrl[2026] + "#page=" + (packageCodes[2026][selected]?.page ?? 5),
  );
  const base = packageMatcher(selected, "foundation", year), advance = packageMatcher(selected, "advanced", year);
  const domain = combined(base, advance);
  const introTarget = modern ? 14 : early ? 17 : 16;
  const basicNames = modern
    ? ["デジタルスキルリテラシー", "データサイエンス概説"]
    : early
    ? ["情報処理・データ分析"]
    : ["情報処理・データ分析", "データサイエンス概説", "国際理解リテラシー"];
  const intro = modern
    ? [["課題解決リテラシー", 2], ["スタディスキルズ", 2], ["アソシエーションゼミⅠ", 2], ["アソシエーションゼミⅡ", 2]]
    : [
      ...(early ? [["創生学修入門", 1]] : []),
      ["リフレクションデザインⅠ", 2],
      [["スタディスキルズ", "スタディスキルズ（大学学習法）"], 2],
      ["リテラシー基礎", 2],
      ["基礎ゼミⅠ", 2],
      ["基礎ゼミⅡ", 2],
    ];
  if (determined) {
    intro.push([dx ? "DXスタディーズ" : ["フィールドスタディーズ", "フィールドスタディーズ（学外学修）"], 6]);
  }
  const group = (k, label, arr) =>
    arr.map(([name, num]) =>
      credits(k + "-" + norm([name].flat()[0]), [name].flat()[0], num, own(name, num), subjects)
    );
  const introRows = group("intro", "導入", intro);
  const basics = [
    credits("english", "英語", early ? 4 : 2, category("英語"), subjects),
    ...group("basic", "基礎", basicNames.map((n) => [n, 2])),
  ];
  const foreign = credits("foreign", "初修外国語", 2, category("初修外国語"), subjects);
  const foundation = credits("field-foundation", "領域基礎科目", determined ? (dx ? 26 : 20) : null, base, pkg, {
    kind: "領域学修",
  });
  const expanded = credits("field-advanced", "領域科目（領域基礎の超過分を含む）", 20, domain, pkg, {
    kind: "領域学修",
  });
  const fieldIntro = modern ? "領域学修入門" : "リフレクションデザインⅡ";
  const overviews = ["経済科学", "理学", "人文学", "法学", "工学", "農学"].map((n, i) =>
    "領域概説" + "ABCDEF"[i] + "(" + n + ")"
  );
  overviews.push("領域概説A(経済学)");
  const overview = credits("domain-overview", "指定された領域概説から4単位", 4, own(overviews, 2), subjects, {
    kind: "選択必修",
  });
  const domainRequired = dx || !determined ? [] : [...group("domain", "領域", [[fieldIntro, 2]]), overview];
  const fixedPbl = group("pbl", "PBL", [
    [modern ? "アソシエーションゼミⅢ" : "基礎ゼミⅢ", 2],
    [modern ? "アソシエーションゼミⅣ" : "基礎ゼミⅣ", 2],
    ["プロジェクトゼミⅠ", 2],
    ["プロジェクトゼミⅡ", 2],
    ["ソリューションラボⅠ", 4],
    ["ソリューションラボⅡ", 4],
  ]);
  const literacy = modern
    ? (dx
      ? group(
        "literacy",
        "リテラシー",
        ["データ利活用実践", "IoT&データ計測基礎", "AI・統計科学実践Ⅰ", "AI・統計科学実践Ⅱ"].map((n) => [n, 2]),
      )
      : determined
      ? [["人文社会・教育科学", ["人文科学", "法学", "経済学"]], ["自然科学", ["理学", "工学", "農学"]]].map((
        [n, sub],
      ) =>
        credits(
          "literacy-" + n,
          "リテラシー・スキル涵養（" + n + "）",
          4,
          (c) => {
            if (c.category !== n) return c.category ? false : null;
            const section = syllabusSection(c);
            if (section && !sub.includes(section)) return false;
            const inPackage = domain(c);
            if (inPackage === true) return false;
            return section && inPackage === false ? true : null;
          },
          subjects,
          { kind: "選択必修" },
        )
      )
      : [])
    : [
      credits(
        "literacy",
        "リテラシー応用A～Eから8単位",
        8,
        own("ABCDE".split("").map((n) => "リテラシー応用" + n), 2),
        subjects,
        { kind: "選択必修" },
      ),
    ];
  const skill = skillRow(dx || !determined, subjects, year);
  const freeNames = modern ? ["データサイエンス概説演習"] : [
    "フィールドスタディーズコーディネート",
    "地域・国際交流A",
    "地域・国際交流B",
    ...(!early ? ["データサイエンス概説演習"] : []),
  ];
  const extra = combined(
    anyGeneral,
    own(freeNames),
    domain,
    overview.match,
    ...fixedPbl.map((r) => r.match),
    ...literacy.map((r) => r.match),
    skill.match,
  );
  const summary = determined
    ? group(
      "final",
      "総括",
      modern
        ? [[dx ? "DX共創総括" : "創生学修総括", 2]]
        : [["リフレクションデザインⅢ", 1], ["リフレクションデザインⅣ", 1]],
    )
    : [];
  const common = (clinicalGoal) => {
    const isGrad = clinicalGoal === "graduation",
      src = isGrad ? grad : progress,
      prefix = isGrad ? "卒業" : "4年次進級";
    const poolUnit = modern ? 44 : early ? 41 : 40;
    const parts = [...introRows, ...basics, ...domainRequired];
    if (isGrad) {
      parts.push(
        foreign,
        ...(early ? group("basic", "基礎", [["データサイエンス基礎", 2]]) : []),
        foundation,
        expanded,
        ...fixedPbl,
        ...literacy,
        skill,
        ...summary,
        credits("free", "自由科目", modern ? 28 : early ? 23 : 24, extra, src, { kind: "選択" }),
      );
    } else {
      parts.push(
        credits("field-pool", "領域基礎・領域科目", determined ? (dx ? 26 : 20) : null, domain, pkg),
        credits(
          "remaining-pool",
          "基礎②・リテラシーコア・自由科目等",
          poolUnit,
          combined(extra, foreign.match, ...(early ? [own("データサイエンス基礎", 2)] : [])),
          src,
          { kind: "選択" },
        ),
      );
    }
    const guard = (m) => (c, profile) => {
      if (norm(c.title) === "ベーシック数学ゼミ") return false;
      if (isGrad && year >= 2023) {
        const allowed = graduationTiming(c, profile ?? p);
        if (allowed !== true) return allowed;
      }
      return m(c, profile);
    };
    const guarded = parts.map((r) => ({ ...r, match: guard(r.match) }));
    const allocate = creationAllocation(guarded);
    const rows = guarded.map((r) => ({
      ...r,
      evaluate: ({ courses, profile }) => allocate(courses, profile ?? p).get(r.key),
    }));
    const introSum = subtotal(
      "intro",
      "導入・転換教育科目",
      introTarget,
      guarded.filter((r) => r.key.startsWith("intro-")),
      src,
    );
    const total = credits(
      "total",
      prefix + "単位の合計",
      isGrad ? 126 : 90,
      combined(...rows.map((r) => r.match)),
      src,
      {
        kind: "合計",
        evaluate: ({ courses, profile }) => allocate(courses, profile ?? p).get("total"),
      },
    );
    const result = [total, introSum, ...rows, residency("residency", "創生学部の在学期間", isGrad ? 48 : 36, src)];
    if (!determined) {
      result.push(
        condition(
          "program",
          "コース別の指定科目",
          "創生学修コース・DX共創コースのどちらに所属するか創生学部学務係で確認してください。",
          src,
        ),
      );
    }
    if (!selected) {
      result.push(
        condition(
          "package",
          "本人に配属された領域学修科目パッケージ",
          "所属パッケージを選択し、年度別案内と創生学部学務係の配属結果を照合してください。",
          pkg,
        ),
      );
    }
    if (selected === "社会・地域文化学") {
      result.push(
        condition(
          "old-package",
          "社会・地域文化学の旧科目表",
          "令和8年度案内では令和4年度に選択者が全員卒業したため旧表を掲載していません。所属当時の領域科目と読替を創生学部学務係で照合してください。",
          pkg,
        ),
      );
    }
    if (isGrad) result.push(stageApproval("創生学部学務係", grad), ...recognition(p, "創生学部学務係", creationAct));
    return stage(isGrad ? "graduation" : "year-4", isGrad ? "卒業" : "4年次進級", clinicalGoal, result, [
      src,
      subjects,
      pkg,
    ]);
  };
  return {
    title: year + "年度 創生学部" + (determined && modern ? (dx ? " DX共創コース" : " 創生学修コース") : ""),
    sources: [progress, grad, subjects, creationAct, pkg, source("2025年度領域学修科目表", packageUrl[2025])],
    stages: [common("progress"), common("graduation")],
    cap: {
      limit: 24,
      source: capSrc,
      classify(c) {
        if (
          [c.period, c.semester, c.schedule].some((s) => String(s ?? "").includes("集中")) ||
          norm(c.title) === "ベーシック数学ゼミ"
        ) return "exclude";
        if (year < 2024 && c.minorIntro === true) return "exclude";
        const relevant = combined(
          extra,
          ...introRows.map((r) => r.match),
          ...basics.map((r) => r.match),
          ...summary.map((r) => r.match),
          ...domainRequired.map((r) => r.match),
        )(c);
        return relevant === true && (c.period || c.semester || c.schedule) ? "include" : "unknown";
      },
      note: "各学期24単位。集中講義" + (year < 2024 ? "と副専攻プログラムの指定入門科目" : "") + "を除きます。",
    },
    note:
      "領域は配属結果と履修年度の科目表で照合します。規程で特に指定された読替・教授会の個別認定は創生学部学務係に確認してください。",
  };
}
