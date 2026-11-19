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
export const officialDecision = (key,label,note,source) =>
  ({key,label,kind:"個別判定",unit:"condition",required:1,officialDecision:true,note,source});
export const isTransfer = p => /編入|転部|転入|再入学/.test(p.entry || "");
export const gpaSource = source("新潟大学 成績評価・GPAの算出式",
  "https://www.niigata-u.ac.jp/university/about/announce/studysupport/");
export function previousGpa(p) {
  if(!["string","number"].includes(typeof p.gpa) || !/^\d+(\.\d+)?$/.test(String(p.gpa).trim()))return null;
  const n = Number(p.gpa);
  return n >= 0 && n <= 5 ? n : null;
}
function wholeNumber(v) {
  if (!["number","string"].includes(typeof v) || !/^\d+$/.test(String(v))) return null;
  const n = Number(v);
  return Number.isSafeInteger(n) ? n : null;
}
export const attendance = (required, src, year) => ({
  key: year ? "year-" + year + "-months" : "months", kind: "在学期間",
  label: year ? year + "年次の在学期間" : "学部での通算在学期間", required, unit: "months", source: src,
  profileValue: p => {
    return wholeNumber(year ? p.yearAttendanceMonths?.[year] : p.attendanceMonths);
  },
  note: "休学期間を除き、編入等は学部が通算を認定した期間を用います。",
});
function assessmentDate(p) {
  const s=p.assessmentDate;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s ?? "")) return null;
  const d=new Date(s+"T00:00:00Z");
  return Number.isFinite(+d) && d.toISOString().slice(0,10)===s ? d : null;
}
export const assessmentPeriod=(src,months,label)=>({
  key:"assessment-period",kind:"判定時期",label,required:1,unit:"condition",source:src,
  profileValue:p=>{const d=assessmentDate(p);return d?Number(months.includes(d.getUTCMonth()+1)):null;},
  note:"学期末の判定月は9月・3月、学年末は3月です。正式な判定日は学部の通知で確認してください。",
});
export const minimumYear=(year,src)=>({
  key:"study-year",kind:"在籍年次",label:year+"年次以降の在籍",required:1,unit:"condition",source:src,
  profileValue:p=>{const n=wholeNumber(p.yearOfStudy);return n>=1 && n<=6?Number(n>=year):null;},
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
  function inTime(c,p={}) {
    const actual=wholeNumber(c.studyYear ?? c.yearOfStudy);
    if(actual!==null && actual>0) return actual<=lastYear;
    const year=wholeNumber(c.year), admitted=wholeNumber(p.admitted);
    if(!year)return null;
    if(!isTransfer(p) && admitted && year>=admitted && year-admitted<lastYear) return true;
    const date=assessmentDate(p),current=wholeNumber(p.yearOfStudy);
    if(!date || !current || (admitted && year<admitted))return null;
    const academicYear=date.getUTCFullYear() - Number(date.getUTCMonth()<3);
    if(year<academicYear && current<=lastYear && !isTransfer(p))return true;
    // September progression can change the year of study within one academic year.
    if(year===academicYear && current<=lastYear && c.column==="earned" && !isTransfer(p))return true;
    return null;
  }
  const match=(c,p)=>{
    const fits=row.match(c,p),timely=inTime(c,p);
    return fits===false || timely===false ? false : fits===true && timely===true ? true : null;
  };
  if(!row.evaluate)return {...row,match};
  return {...row,match,evaluate:ctx=>{
    const result=row.evaluate({...ctx,courses:ctx.courses.filter(c=>inTime(c,ctx.profile)===true)});
    if(ctx.courses.some(c=>inTime(c,ctx.profile)===null && row.match(c,ctx.profile)!==false))
      result.unknown ??= "休学・留年等を含む修得時の在籍年次を履修科目確認表で照合してください。";
    return result;
  }};
}
export function contribution(c, applied, reason) {
  return { course:c, title:c.title,code:c.code || "",year:c.year ?? "",credits:c.credits,applied,reason };
}
// The engine consumes one applied amount per ledger record, including split allocations.
export function mergeContributions(entries) {
  const result=new Map();
  for(const ref of entries) {
    const existing=result.get(ref.course);
    if(existing)existing.applied+=ref.applied;
    else result.set(ref.course,{...ref});
  }
  return [...result.values()];
}
// Imported credit quantities may be decimal strings. Preserve ledger identity when
// passing their numeric form to a custom evaluator and when returning its evidence.
export function numericEvidence(row) {
  if(!row.evaluate)return row;
  return {...row,evaluate:ctx=>{
    if(ctx.courses.every(c=>typeof c.credits==="number" && Number.isFinite(c.credits) && c.credits>=0))
      return row.evaluate(ctx);
    const originals=new Map(),courses=[];
    let missing=false;
    for(const c of ctx.courses) {
      if(typeof c.credits==="number" && Number.isFinite(c.credits) && c.credits>=0){courses.push(c);continue;}
      const known=typeof c.credits==="string" && /^\d+(\.\d+)?$/.test(c.credits.trim());
      if(!known && row.match?.(c,ctx.profile)!==false)missing=true;
      if(!known && (row.unit??"credits")==="credits")continue;
      const copy={...c,credits:known?Number(c.credits):0};
      originals.set(copy,c);
      courses.push(copy);
    }
    const result=row.evaluate({...ctx,courses});
    if(missing)result.unknown??="該当科目の単位数を成績確認表で確認してください。";
    for(const ref of result.contributions??[])if(originals.has(ref.course))ref.course=originals.get(ref.course);
    return result;
  }};
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
