import { normalize } from "../../course-facts.mjs";

export const text = normalize;
export const source = (title, url) => ({ title, url });
export const page = (book, n, title) =>
  source(book.year + "年度 " + title + "（PDF " + n + "頁）", book.url + "#page=" + n);
export const statute = (title, id, anchor = "") =>
  source(title, "https://public1.legalcrud.com/niigata_univ/act/" + id + ".html" + (anchor && "#" + anchor));

export function any(...matches) {
  return (course, profile) => {
    const results = matches.map(match => match(course, profile));
    return results.includes(true) ? true : results.includes(null) ? null : false;
  };
}

// Several departments offer identically titled courses. Grade-only titles cannot resolve those.
export function named(units, names, { sections = false } = {}) {
  const wanted = new Set(names.map(text));
  return c => {
    const title = text(c.title);
    if (!wanted.has(title) && !(sections && wanted.has(title.replace(/\([^()]*\)$/, "")))) return false;
    return c.department ? units.includes(c.department) : null;
  };
}
export const generalCategories = ["英語", "初修外国語", "健康・スポーツ", "情報リテラシー",
  "新潟大学個性化科目", "留学生基本科目", "大学学習法", "自然系共通専門基礎", "自然科学",
  "人文社会・教育科学", "医歯学"];
export function gCategory(...categories) {
  return c => {
    if (c.department && c.department !== "84") return false;
    if (!c.category || !c.department) return null;
    return categories.includes(c.category);
  };
}
export const credited = (key, label, required, match, source, extra = {}) =>
  ({ key, label, kind: "必要単位", required, match, source, ...extra });
export const uncertain = (key, label, why, source) =>
  ({ key, label, kind: "要確認", required: null, unknown: why, source });
export const isTransfer = p => /編入|転部|転入|再入学/.test(p.entry || "");
export const attendance = (required, src, year) => ({
  key: year ? "year-" + year + "-months" : "months", kind: "在学期間",
  label: year ? year + "年次の在学期間" : "学部での通算在学期間", required, unit: "months", source: src,
  profileValue: p => {
    const value = year ? p.yearMonths?.[year] : (p.enrolledMonths ?? p.attendanceMonths);
    return value !== "" && value != null && Number.isFinite(Number(value)) && Number(value) >= 0 ? Number(value) : null;
  },
  note: "休学期間を除き、編入等は学部が通算を認定した期間を用います。",
});
export function transferRow(book) {
  return uncertain("recognition", "適用便覧・既修得単位と在学期間の認定",
    "学部学務係の適用年度通知、単位認定結果と履修科目確認表で、認定先と通算期間を確認してください。", book);
}
export function stage(id, label, goal, src, rows) {
  return { id, label, goal, rows, sources: [src] };
}
export function throughYear(row,lastYear) {
  if(!row.match)return row;
  const inTime=c=>!c.studyYear || (Number(c.studyYear)>0 && Number(c.studyYear)<=lastYear);
  return {...row,match:(c,p)=>inTime(c) && row.match(c,p),
    ...(row.evaluate?{evaluate:ctx=>row.evaluate({...ctx,courses:ctx.courses.filter(inTime)})}:{})};
}
export function contribution(c, applied, reason) {
  return { title: c.title, code: c.code || "", year: c.year ?? "", credits: c.credits, applied, reason };
}

// Each alternative is a list of independent minima. Keep the complete best alternative,
// including its evidence, so credits from different alternatives never complete one another.
export function alternative(groups) {
  return ({ courses, profile }) => {
    let best = { value: 0, contributions: [] };
    let ambiguous = false;
    for (const parts of groups) {
      const contributions = [];
      let value = 0;
      for (const { match, max, label } of parts) {
        let remaining = max;
        for (const course of courses) {
          const fits = match(course, profile);
          if (fits === null) ambiguous = true;
          if (fits !== true || remaining <= 0) continue;
          const applied = Math.min(Number(course.credits) || 0, remaining);
          if (applied <= 0) continue;
          remaining -= applied;
          value += applied;
          contributions.push(contribution(course, applied, label));
        }
      }
      if (value > best.value) best = { value, contributions };
    }
    if (ambiguous && best.value < Math.max(...groups.map(g => g.reduce((n,x) => n+x.max,0)))) {
      best.unknown = "科目の対応・算入先を成績確認表と適用便覧で確認してください。";
    }
    return best;
  };
}
export function mandatory(key, label, names, units, src, creditsEach, options) {
  const parts = names.map(name => ({ label: name, max: creditsEach, match: named(units,[name], options) }));
  return credited(key, label, parts.length * creditsEach, any(...parts.map(part => part.match)), src,
    { kind: "必修", evaluate: alternative([parts]) });
}
export const general = gCategory(...generalCategories);
export const nonLanguage = gCategory(...generalCategories.filter(x => !["英語", "初修外国語"].includes(x)));
export function languageMatch(language) {
  return c => {
    const cat = gCategory("初修外国語")(c);
    if (cat === false) return false;
    if (!c.title || !/ドイツ語|フランス語|中国語|ロシア語|朝鮮語|スペイン語|イタリア語/.test(c.title)) return cat === true ? null : false;
    return text(c.title).includes(language) ? cat : false;
  };
}
export function sameLanguage(required, src) {
  const names = ["ドイツ語","フランス語","中国語","ロシア語","朝鮮語","スペイン語","イタリア語"];
  const parts = names.map(label => [{ label, max: required, match: languageMatch(label) }]);
  return credited("same-language","同じ初修外国語",required,any(...parts.map(p=>p[0].match)),src,
    { evaluate: alternative(parts) });
}
export function irregular(c) {
  return c.period === "集中" || c.period === "不定期" || c.irregular === true;
}
export function registrationClass(c) {
  if (irregular(c) || c.teacherTrainingOnly === true) return "exclude";
  if (!c.period || /教職|教育実習|教育法/.test(c.title || "")) return "unknown";
  return "include";
}
