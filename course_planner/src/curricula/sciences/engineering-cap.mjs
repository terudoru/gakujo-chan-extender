import { intensive, name, norm, type, urlPage } from "./common.mjs";

// PDF pages of the teaching-license table named in each handbook's CAP rule.
const teachingTablePage = {
  2017: 76,
  2018: 76,
  2019: 76,
  2020: 75,
  2021: 69,
  2022: 73,
  2023: 73,
  2024: 73,
  2025: 75,
  2026: 75,
};

export const teachingTableSources = (book) => [
  urlPage(
    book,
    teachingTablePage[book.year],
    `履修登録の上限から除く教職科目（別表${book.year < 2019 ? "2" : "1"}）`,
  ),
  ...(Number(book.year) === 2018
    ? [
        {
          title:
            "平成30年度入学者用 教育職員免許状取得ハンドブック・工学部（19頁）",
          url: "https://www.kyoshoku.niigata-u.ac.jp/upload/pdf/20190830095530011399300.pdf#page=21",
        },
      ]
    : []),
];

// The 2018 licensing guide names these replacements. The engineering CAP
// table still names the former courses and does not state their CAP treatment.
const alternative2018Titles = new Set(
  [
    "教育・学校心理学Ｂ",
    "教育方法総論Ｂ",
    "生徒指導Ｂ",
    "教育相談・進路指導Ｂ",
  ].map(norm),
);

// Admission years, units and course titles from the designated rows. The 2019
// CAP rule omits subject teaching methods even though they appear in Table 1.
const teachingCourses = [
  [
    2017,
    2026,
    2,
    "教職入門",
    "教育学概論",
    "教育の制度と経営",
    "教職実践演習（中等）",
  ],
  [2017, 2026, 3, "中等教育実習Ⅱ", "中等教育実習Ⅱ（事前・事後指導を含む。）"],
  [
    2017,
    2018,
    2,
    "教育心理学",
    "教育課程総論",
    "生徒指導・教育相談・進路指導Ⅰ",
    "生徒指導・教育相談・進路指導Ⅱ",
  ],
  [2017, 2018, 1, "教育方法・技術Ｂ"],
  [2017, 2018, 2, "工業科教育法Ⅰ", "工業科教育法Ⅱ"],
  [
    2019,
    2026,
    2,
    "特別支援教育概論",
    "教育課程及び総合的な学習の時間の指導法Ｂ",
    "教育方法及び特別活動の指導法Ｂ",
    "生徒指導Ｂ",
    "教育相談・進路指導Ｂ",
  ],
  [2019, 2025, 2, "教育・学校心理学Ｂ"],
  [2020, 2026, 2, "工業科教育法Ⅰ", "工業科教育法Ⅱ"],
  [2022, 2026, 1, "教育情報論"],
  [2025, 2026, 2, "情報科教育法Ⅰ", "情報科教育法Ⅱ"],
  [2026, 2026, 2, "教育心理学Ｂ"],
];
const teachingUnits = new Map();
for (const [first, last, units, ...titles] of teachingCourses) {
  for (let year = first; year <= last; year++) {
    if (!teachingUnits.has(year)) teachingUnits.set(year, new Map());
    for (const title of titles) teachingUnits.get(year).set(norm(title), units);
  }
}

export function engineeringCap(course, year) {
  const codeType = type(course);
  const title = name(course);
  if (
    intensive(course) ||
    course.creditExchange ||
    course.vacationCourse ||
    title === "リメディアル演習" ||
    (year <= 2023 && codeType === "Q")
  )
    return "exclude";
  if (!codeType || !title) return "unknown";
  if (year === 2018 && codeType === "K" && alternative2018Titles.has(title))
    return "unknown";
  const units = teachingUnits.get(year)?.get(title);
  if (units === undefined) return "include";
  // The named classes are offered by the Faculty of Education (K code).
  return codeType === "K" && course.credits === units ? "exclude" : "unknown";
}
