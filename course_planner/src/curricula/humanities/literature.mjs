import inventory from "./literature-courses.json" with { type: "json" };
import { text, page, credited, mandatory, stage, sameLanguage, attendance,
  transferRow, isTransfer, any, named, gCategory, general, irregular, contribution, officialDecision, minimumYear } from "./rules.mjs";

export const recentPrograms = ["心理・人間学","社会文化学","言語文化学"];
export const earlyPrograms = ["心理・人間学","社会・地域文化学","歴史文化学","日本・アジア言語文化学","西洋言語文化学","メディア・表現文化学"];
const pageProgress = [43,42,42,42,42,42,41,42,42,42,42,43,44];
const pageCap = [46,45,45,45,45,45,44,45,45,45,45,46,47];
const languagePages=[39,38,38,38,38,38,37,38,38,38,38,39,40];

// The handbook chooses which parallel course counts, even if the transcript lists both.
function languageLedger(courses,y) {
  const titles=courses.filter(c=>c.department==="84").map(c=>text(c.title));
  return courses.filter(c=>{
    if(c.department!=="84" || c.languageOverlapApproved===true) return true;
    const title=text(c.title);
    const language=title.match(/ドイツ語|フランス語|ロシア語|中国語|朝鮮語|スペイン語|イタリア語/)?.[0];
    if(!language)return true;
    const has=(part,level)=>titles.some(t=>t.startsWith(language+part) && t.slice((language+part).length).match(/^(ii|i)/)?.[0]===level);
    const standard=title.match(/スタンダード(ii|i)/);
    const elementary=y>=2024?title.includes("エッセンシャルa"):title.includes("ベーシックii");
    if(standard && has("インテンシブ",standard[1]))return false;
    if(elementary && (has("インテンシブ","i") || (["スペイン語","イタリア語"].includes(language) && has("スタンダード","i")))) return false;
    if(y===2026 && title.includes("圏グローバル理解") && (["ドイツ語","ロシア語","朝鮮語"].includes(language) ||
        (language==="中国語" && title.includes("中国語の基礎知識")))) return !titles.some(t=>t.startsWith(language+"インテンシブ"));
    return true;
  });
}

export default function literature(profile, book) {
  const y = Math.max(2014,+book.year), historical = y < 2020;
  const grad = page(book,y===2014?17:16,"人文学部規程第15条・卒業要件");
  const promotion = page(book,pageProgress[y-2014],"第5セメスターへの進級");
  const capSrc = page(book,pageCap[y-2014],"履修登録の上限");
  const list = page(book,y===2014?21:y<2020?20:y<2025?21:22,"別表第2・専門教育の科目表");
  const languageSource=page(book,languagePages[y-2014],"初修外国語の重複・卒業要件への算入");
  const selected = text(profile.program).replace(/プログラム$/, "");
  const index = new Map(inventory.filter(([, , , first,last])=>first<=y && y<=last)
    .map(([name, group, program])=>[text(name),{group,program}]));
  function departmentCourse(c, predicate) {
    if (c.department && c.department !== "01") return false;
    const name = text(c.title);
    const entry = index.get(name) ?? index.get(name.replace(/\([^()]*\)$/,""));
    if (!entry || !c.department) return null;
    return predicate(entry);
  }
  const subset = (pattern, own=false) => c => departmentCourse(c, item => {
    if (!pattern.test(item.group)) return false;
    if (!own) return true;
    if (!selected || !item.program.trim()) return null;
    return item.program.split("/").some(v => text(v).replace(/プログラム$/, "") === selected);
  });
  const major = subset(/./);
  // G-code general courses and faculty courses listed in Annex 2 have disjoint allocations.
  // Other faculties' university-wide offerings require the published target or official balance.
  const gen = c => c.department && !["01","84"].includes(c.department)
    ? (c.openToAll === true ? true : null) : general(c);
  const eligible = any(gen,major);
  const foundation = historical ? (y<=2016?"人文総合演習":"人文初年次演習") : "人文初年次演習";
  const fresh = mandatory("freshman","大学学習法・"+foundation,historical?[foundation+"A",foundation+"B"]:[foundation],["84"],grad,2);
  const intro = subset(/^入門講義$/);
  const rows = [], requiredGen = historical?47:41, requiredMajor=historical?64:60;
  const append = (key,label,n,match,src=grad,extra={}) => rows.push(credited(key,label,n,match,src,extra));
  rows.push(attendance(48,grad));
  append("total","卒業単位の合計",124,eligible);
  append("general","教養教育に関する授業科目",requiredGen,gen,grad,{exclusive:"graduation-pool"});
  append("major","専門教育に関する授業科目",requiredMajor,major,grad,{exclusive:"graduation-pool"});
  append("surplus","教養・専門の超過分",124-requiredGen-requiredMajor,eligible,grad,{exclusive:"graduation-pool"});
  const global=c=>y>=2024 && text(c.title).includes("グローバル理解");
  const langs = c=>!global(c) && any(gCategory("英語"),gCategory("初修外国語"))(c);
  const genRow = (key,label,n,test) => append(key,label,n,test,grad,{exclusive:"general-breakdown"});
  genRow("languages","英語・初修外国語",12,langs);
  if (historical) append("english","英語",4,gCategory("英語"));
  else rows.push(mandatory("english","アカデミック英語入門L・R",["アカデミック英語入門L","アカデミック英語入門R"],["84"],grad,1));
  function singleLanguage(n,src) {
    const row=sameLanguage(n,src);
    return {...row,evaluate:ctx=>row.evaluate({...ctx,courses:languageLedger(ctx.courses,y).filter(c=>!global(c))})};
  }
  const sumEligible=({courses})=>{
    const contributions=[];let unknown=false;
    for(const c of languageLedger(courses,y)){
      const fits=c.recognized && ["total","general","major","surplus"].includes(c.allocationKey)?true:eligible(c);
      if(fits===true) contributions.push(contribution(c,c.credits,"卒業算入"));
      if(fits===null) unknown=true;
    }
    return {value:contributions.reduce((n,c)=>n+c.applied,0),contributions,
      ...(unknown?{unknown:"当該年度の科目区分・学部の算入指定を確認してください。"}:{})};
  };
  rows.find(r=>r.key==="total").evaluate=sumEligible;
  rows.find(r=>r.key==="total").allocationKeys=["general","major","surplus"];
  rows.push(singleLanguage(8,grad));
  genRow("sport","体育実技",1,c=>gCategory("健康・スポーツ")(c) && /^健康スポーツ科学実習/.test(text(c.title)));
  const career = historical ? ["キャリアデザイン","キャリア形成","インターンシップ実習"] : ["キャリアデザイン"];
  genRow("career","指定のキャリア科目・表現プロジェクト演習",historical?4:2,
    any(named(["84"],career,{sections:true}),c=>c.category==="新潟大学個性化科目" && text(c.title).startsWith("表現プロジェクト演習")));
  genRow("study","大学学習法の指定科目",fresh.required,fresh.match);
  rows.push(fresh);
  genRow("science","情報・自然科学・医歯学等の指定区分",4,gCategory(...(y>=2017?["情報リテラシー"]:[]),"自然系共通専門基礎","自然科学","医歯学"));
  if (y>=2022) append("data","データサイエンス総論Ⅰまたは基礎演習",1,named(["84"],["データサイエンス総論I","データサイエンス基礎演習"]));
  genRow("human","人文社会・教育科学",historical?12:8,gCategory("人文社会・教育科学"));
  if (historical) {
    const topic = y<2017?"領域融合・超域科目":"人文系展開科目";
    append("human-advanced",topic+"から2科目4単位",4,c=>c.department==="84" && text(c.title).startsWith(topic));
    // Count the four adjustable credits once after all fixed general requirements.
    genRow("gen-free","自由選択の最低単位",6,gen);
    genRow("gen-adjustable","外国語または自由選択で補う4単位",4,gen);
  } else genRow("gen-free","教養の自由選択",12,gen);
  append("intro","入門講義",6,intro,list);
  if (!historical) append("human-intro","人文入門",2,named(["01"],["人文入門"]));
  if (historical) {
    append("foundation","基礎講義・実習",14,subset(/^基礎講義/),list);
    append("basic-seminar","基礎演習",4,subset(/^基礎演習/),list);
  } else {
    append("foundation","基礎講義・実習・研究法および基礎演習",18,subset(/^基礎/),list);
    append("methods","実習・研究法の指定科目",2,c=>{
      if (/博物館実習/.test(c.title || "") || (y>=2026 && /心理実習/.test(c.title || ""))) return false;
      if (!/実習|研究法|調査法|統計法|実験/.test(c.title || "")) return false;
      return subset(/^基礎講義/)(c);
    },list);
    append("own-foundation","所属プログラムの基礎演習",2,subset(/^基礎演習/,true),list);
  }
  append("advanced","発展講義"+(historical?"・実習":""),historical?18:14,subset(/^発展講義/),list);
  append("own-advanced","所属プログラムの発展講義",historical?10:6,subset(/^発展講義/,true),list);
  append("seminar","発展演習",12,subset(/^発展演習/),list);
  const ownSeminar = subset(/^発展演習/,true);
  append("own-seminar","所属プログラムの発展演習",8,ownSeminar,list);
  rows.push({...credited("seminar-years","所属プログラムの発展演習を2か年履修",2,ownSeminar,list),unit:"condition",
    evaluate:({courses})=>{
      const years=new Set(), contributions=[];
      for (const c of courses) {
        if (ownSeminar(c)!==true || !c.year || years.has(c.year)) continue;
        years.add(c.year); contributions.push(contribution(c,1,String(c.year)+"年度"));
      }
      return {value:years.size, contributions, ...(courses.some(c=>ownSeminar(c)!==false && !c.year)
        ? {unknown:"発展演習の履修年度を成績確認表で照合してください。"} : {})};
    }});
  append("thesis","卒業論文",10,subset(/^卒業論文/),list);
  if (isTransfer(profile)) rows.push(transferRow(book));
  // The exclusion follows the credit into every nested or surplus bucket.
  for(const row of rows.filter(r=>["general","surplus","languages","human","gen-free","gen-adjustable"].includes(r.key))) {
    const peers=new Set(rows.filter(r=>r.exclusive===row.exclusive).map(r=>r.key));
    row.evaluate=({courses,profile})=>{
      const refs=[],pending=[];
      for(const c of languageLedger(courses,y)){
        const fits=c.recognized && peers.has(c.allocationKey)?row.key===c.allocationKey:row.match(c,profile);
        if(fits===true) refs.push(contribution(c,c.credits,row.label));
        if(fits===null) pending.push(c);
      }
      return {value:refs.reduce((n,r)=>n+r.applied,0),contributions:refs,
        ...(pending.length?{unknown:"履修年度の科目区分・教養への算入先を確認してください。"}:{})};
    };
  }
  const steps = [stage("human-third","3年次進級（第5セメスター）","progress",promotion,[
    attendance(24,promotion),credited("total","進級に算入する単位",historical?58:54,eligible,promotion,{evaluate:sumEligible}),
    {...fresh,source:promotion},singleLanguage(4,promotion),credited("intro","入門講義",4,intro,promotion),
    ...(isTransfer(profile)?[transferRow(book)]:[])],[1,2])];
  if(+book.year>=2014) {
    const filing=page(book,y===2014 || y>=2025?30:29,"人文学部履修細則第9条・卒業論文題目の届出");
    steps.push(stage("human-thesis-filing","卒業論文題目の届出","progress",filing,[minimumYear(4,filing),
      officialDecision("thesis-topic-approval","卒業論文指導教員による題目の承認",
        "学部長に届け出る題目について、卒業論文指導教員の承認結果を確認してください。",filing)],[3,4]));
  }
  steps.push(stage("human-graduation","卒業","graduation",grad,rows));
  return {title:book.title, sources:[book,grad,list,promotion,capSrc,languageSource,
    page(book,y===2014 || y>=2025?29:28,"履修細則・卒業論文のCAP除外と3年次編入の扱い")], stages:steps,
    note:"公的語学検定・留学生科目の振替、体育実技の代替、外国語の併修制限は、学部学務係の認定結果を確認してください。",
    cap:{period:"semester",unit:"credits",limit:/編入/.test(profile.entry || "")?null:22, source:capSrc,
      note:"卒業論文、非常勤講師の集中講義、他学部の教職・学芸員資格科目、休暇中の実習等を除外。3年次編入生はガイダンスの別扱いです。",
      classify:c=>{
        if (named(["01"],["卒業論文"],{sections:true})(c)===true || (c.department!=="01" && (c.teacherTrainingOnly===true || c.museumQualificationOnly===true)) || c.holidayPracticum===true) return "exclude";
        if (irregular(c)) return c.partTimeInstructor===true?"exclude":"unknown";
        return c.period?"include":"unknown";
      }}};
}
