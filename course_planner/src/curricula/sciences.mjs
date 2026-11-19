import { engineering, engineeringOptions } from "./sciences/engineering.mjs";
import {
  legacyEngineering,
  engineeringTransition,
  engineeringAssessment,
  formerDepartments,
} from "./sciences/engineering-legacy.mjs";
import { agriculture, agricultureOptions } from "./sciences/agriculture.mjs";
import {
  legacyAgriculture,
  agricultureLaw,
  agricultureReport,
} from "./sciences/agriculture-legacy.mjs";
import {
  formerAgriculturePrograms,
  formerAgriculture,
} from "./sciences/agriculture-departments.mjs";
import {
  science,
  sciencePrograms,
  scienceOptions,
} from "./sciences/science.mjs";
import { check, stage } from "./sciences/common.mjs";

const faculties = {
  理学部: {
    first: 2005,
    resolve: science,
    title: "理学部 履修の手引",
    index: "https://www.sc.niigata-u.ac.jp/sc/edu/rishu_tebiki.html",
    url: (year) =>
      `https://www.sc.niigata-u.ac.jp/sc/edu/rishu_tebiki/tebiki${year}.pdf`,
    programs: (year) =>
      year < 2017
        ? sciencePrograms.slice(0, 6).map((name) => name + "科")
        : scienceOptions,
  },
  工学部: {
    first: 2010,
    resolve: (book, p) =>
      book.year < 2017 ? legacyEngineering(book, p) : engineering(book, p),
    title: "工学部 学生必携",
    index: "https://www.eng.niigata-u.ac.jp/student/",
    url: (year) =>
      `https://www.eng.niigata-u.ac.jp/student/files/hikkei_${year}.pdf`,
    programs: (year) =>
      year >= 2022
        ? engineeringOptions
        : engineeringOptions.filter((name) => !name.includes("パッケージ")),
  },
  農学部: {
    first: 2004,
    resolve: (book, p) =>
      book.year < 2017
        ? formerAgriculture(book, p)
        : book.year < 2022
          ? legacyAgriculture(book, p)
          : agriculture(book, p),
    title: "農学部 履修の手引",
    index: "https://www.agr.niigata-u.ac.jp/students",
    url: (year) =>
      encodeURI(
        `https://www.agr.niigata-u.ac.jp/wp/wp-content/uploads/R${year - 2018}_新大農学部履修の手引.pdf`,
      ),
    programs: () => agricultureOptions,
  },
};

export const handbooks = Object.entries(faculties).flatMap(
  ([faculty, config]) =>
    Array.from({ length: 2027 - config.first }, (_, index) => {
      const year = 2026 - index;
      if (faculty === "農学部" && year < 2017)
        return {
          faculty,
          year: String(year),
          title: year + "年度 農学部旧学科・規程と経過措置",
          url: agricultureLaw.url,
          programs: formerAgriculturePrograms,
        };
      if (faculty === "工学部" && year < 2017)
        return {
          faculty,
          year: String(year),
          title: year + "年度 工学部旧学科・読替表",
          url:
            year === 2015
              ? engineeringAssessment.url
              : engineeringTransition.url,
          programs: formerDepartments,
        };
      if (faculty === "農学部" && year < 2022)
        return {
          faculty,
          year: String(year),
          title:
            year +
            "年度 農学部" +
            (year === 2021 ? "規程・経過措置" : "・設置計画履行状況報告書"),
          url: year === 2021 ? agricultureLaw.url : agricultureReport(year),
          programs: config.programs(year),
        };
      return {
        faculty,
        year: String(year),
        title: `${year}年度入学者用 ${config.title}`,
        url: config.url(year),
        programs: config.programs(year),
      };
    }),
);

export default function resolve(profile) {
  const faculty = profile.faculty,
    config = faculties[faculty];
  if (!config) return null;
  const year = String(profile.handbook || profile.admitted || "");
  const book = handbooks.find((b) => b.faculty === faculty && b.year === year);
  if (book) {
    const descriptor = config.resolve(book, profile);
    const classify = descriptor.cap.classify;
    descriptor.cap.classify = (course, student) => {
      const result = classify(course, student);
      if (result !== "include") return result;
      const period = String(course.period ?? "").normalize("NFKC");
      // All three faculties publish semester limits. A full-year course needs
      // its registered credit allocation before it can be charged to either.
      const crosses =
        /通年/.test(period + (course.semester ?? "")) ||
        (/ターム/.test(period) && /[12]/.test(period) && /[34]/.test(period));
      return crosses ? "unknown" : "include";
    };
    return descriptor;
  }
  const source = { title: config.title + "・学務係", url: config.index };
  const reason =
    year +
    "年度適用の" +
    config.title +
    "を" +
    faculty +
    "学務係で確認してください。";
  const legal = {
    title: faculty + "規程・改組前の入学者に関する附則",
    url:
      "https://public1.legalcrud.com/niigata_univ/act/" +
      (faculty === "工学部" ? "110000527" : "110000544") +
      ".html",
  };
  const transition = Number(year) <= 2016 && faculty !== "理学部";
  const sources = transition ? [source, legal] : [source];
  if (transition && faculty === "工学部")
    sources.push({
      title: "改組前7学科の工学部公表資料（当時の別表は資料12・13）",
      url: "https://www.niigata-u.ac.jp/wp-content/uploads/2016/07/H27_genkyo_kyoiku_08.pdf#page=9",
    });
  return {
    title: year + "年度 " + faculty,
    sources,
    note: transition
      ? "2016年度以前に入学した学生には改組前の学科の規程を適用します。"
      : reason,
    stages: [
      stage("progress", "進級・配属", [
        check("progress-criteria", "所属学科の進級・配属条件", reason, source),
      ]),
      stage("graduation", "卒業", [
        check("total", "卒業に必要な総単位", reason, source),
        check("program", "所属学科・コースの指定科目と読替", reason, source),
      ]),
    ],
    cap: { limit: null, source, classify: () => "unknown", note: reason },
  };
}
