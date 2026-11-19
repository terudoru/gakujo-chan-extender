import offerings from "./economics-offerings.json" with { type: "json" };
import currentOfferings from "./economics-courses.json" with { type: "json" };
import openers2026 from "./economics-openers.json" with { type: "json" };
import modules from "./economics-modules.json" with { type: "json" };
import teacherCourses from "./economics-teaching.json" with { type: "json" };
import publications from "./publications.json" with { type: "json" };
import { text, page, source, statute, stage, named, any, credited, uncertain, mandatory, alternative, contribution,
  attendance, transferRow, isTransfer, gCategory, nonLanguage, registrationClass, throughYear,
  gpaSource,previousGpa,assessmentPeriod,minimumYear,mergeContributions } from "./rules.mjs";

export const programs = ["経済学","経営学","学際日本学","地域リーダー"];
// Faculty annexes list shared teaching by title. A general-field label alone does not
// identify the opening department. The 2026 offering list disambiguates that year only.
const verifiedOpeners=new Map(Object.entries(openers2026).map(([t,v])=>[text(t),v]));
const names=values=>{
  const titles=new Set(values.map(text));
  return c=>{
    const full=text(c.title),name=titles.has(full)?full:full.replace(/\([^()]*\)$/,"");
    if(!titles.has(name))return false;
    if(!c.department)return null;
    if(Number(c.year ?? c.matchedCourse?.year)!==2026)
      return c.department==="0C"?true:["84","01","04","03"].includes(c.department)?null:false;
    const openers=verifiedOpeners.get(name) ?? ["0C"];
    if(!openers.includes(c.department))return false;
    if(openers.length===1 || c.department==="0C")return true;
    return null;
  };
};
const official=statute("経済科学部規程第14条・別表第1及び第2","110001598");
const attendanceCriteria=source("経済科学部における進級及び卒業に関する基準（2024年2月15日教授会決定、在籍学生対象）",
  "https://www.econ.niigata-u.ac.jp/topics/files/elfinder/gakumu/進級及び卒業に関する基準.pdf");
const modules2021=source("令和3年度 モジュール一覧（差替版）",
  "https://www.econ.niigata-u.ac.jp/topics/files/elfinder/gakumu/モジュール一覧_令和3年度.pdf");
const graduationPages=[86,86,86,83,85,82,83];
const annexPages=[[67,71,75,80],[67,71,75,80],[67,71,75,80],[64,68,72,77],[64,68,72,78],[63,67,71,76],[64,68,72,77]];
const catalogByYear=new Map();
function catalog(year) {
  if (catalogByYear.has(year)) return catalogByYear.get(year);
  const lists=programs.map(()=>[]);
  if(year===2026) {
    for(const [ix,groups] of Object.entries(currentOfferings)) {
      for(const [group,titles] of Object.entries(groups)) lists[ix].push(...titles.map(title=>({group,title})));
    }
    catalogByYear.set(year,lists);return lists;
  }
  for (const [key,years] of Object.entries(offerings)) {
    if (!years.includes(year)) continue;
    const [ix,...path]=key.split("/");const title=path.pop();
    lists[ix].push({group:path.join("/"),title});
  }
  catalogByYear.set(year,lists);return lists;
}
function englishRequirement(letter,book,y) {
  const direct=named(["84"],["アカデミック英語入門"+letter]);
  const alternatives=[[{match:direct,max:1,label:"アカデミック英語入門"+letter}]];
  if(y>=2025) {
    const pair=letter==="L"?["iStep Listening and Speaking","iStep Presentations"]:["iStep Academic Reading","iStep Academic Writing"];
    alternatives.push(pair.map(title=>({label:title,max:0.5,match:(c,p)=>{
      const match=named(["84"],[title])(c);
      return match===true && p?.iStepApproved!==true ? null : match;
    }})));
  }
  return credited("english-"+letter,"アカデミック英語入門"+letter,1,any(...alternatives.flat().map(x=>x.match)),
    page(book,14,"外国語科目の履修方法"),{evaluate:alternative(alternatives),
      ...(y>=2025?{note:"iStep振替は対応する2科目の修得と学務係への申出を確認します。"}:{})});
}

function moduleRow(key,label,min,entries,src) {
  const titleSets=entries.map(([module,rule])=>[module,rule,rule.titles.map(title=>[text(title),names([title])])]);
  return credited(key,label,min,any(...entries.map(([,v])=>names(v.titles))),src,{unit:"condition",
    evaluate:({courses})=>{
      const contributions=[];let unresolved=false,completed=0;
      for (const [module,rule,matches] of titleSets) {
        const titles=new Map();
        for (const [title,match] of matches) {
          const course=courses.find(c=>match(c)===true && Number(c.credits)>0);
          if (course) titles.set(title,course);
        }
        if (!titles.size) continue;
        let passed=false;
        const count=rule.rule.match(/(\d+)科目/);
        const amount=rule.rule.match(/(\d+)単位分/);
        if (rule.rule==="全ての授業科目の単位修得") passed=titles.size===new Set(rule.titles.map(text)).size;
        else if (amount && rule.rule.startsWith(amount[0])) passed=[...titles.values()].reduce((n,c)=>n+c.credits,0)>=Number(amount[1]);
        else if (count && rule.rule.startsWith(count[0])) passed=titles.size>=Number(count[1]);
        else if (count && /を含む/.test(rule.rule)) {
          const mandatoryTitles=rule.titles.filter(t=>text(rule.rule.split("を含む")[0]).includes(text(t)));
          if (mandatoryTitles.length) passed=titles.size>=Number(count[1]) && mandatoryTitles.every(t=>titles.has(text(t)));
          else unresolved=true;
        } else if (module.includes("東アジア言語文化学")) {
          const language=lang=>courses.filter(c=>gCategory("初修外国語")(c)===true && c.title.includes(lang)).reduce((n,c)=>n+c.credits,0);
          const all=t=>t.every(v=>titles.has(text(v)));
          const korean=rule.titles.find(t=>t.startsWith("朝鮮語オプショナル"));
          passed=all(["アジア言語文化概説C"]) && ((language("中国語")>=8 && all([korean,"アジア言語文化概説A","アジア言語文化概説B"])) ||
            (language("朝鮮語")>=8 && all(["中国語オプショナルA","アジア言語文化研究法A","アジア言語文化研究法B"])));
        } else unresolved=true;
        if (passed) {
          completed++;
          const records=[...new Set(titles.values())];
          for(const c of records) contributions.push(contribution(c,1/records.length,module));
        }
      }
      return {value:completed,contributions:mergeContributions(contributions),
        ...(unresolved || !entries.length?{unknown:"当該年度のモジュール一覧で選択内訳・認定科目を確認してください。"}:{})};
    }});
}

export default function economics(p,book) {
  const y=+book.year,ix=programs.indexOf(text(p.program).replace(/プログラム$/,""));
  const src=page(book,graduationPages[y-2020]+Math.max(0,ix),"別表第2・プログラム別の卒業要件");
  const annex=page(book,annexPages[y-2020][Math.max(0,ix)],"別表第1・授業科目の指定");
  const progress=page(book,graduationPages[y-2020]+5,"履修細則第9・10条");
  const capSrc=page(book,y>=2025?26:34,"履修登録単位数の上限・成績優秀者の特例");
  const groups=catalog(y);
  const own=groups[Math.max(ix,0)];
  const common=mandatory("common","知識・理解の学部共通基礎4科目",["経済学入門","経営学入門","日本経済入門","人文社会科学入門"],["0C"],src,2);
  const skills=mandatory("skills","スタディスキルズⅠ～Ⅲ・データサイエンス総論Ⅰ",["スタディスキルズI","スタディスキルズII","スタディスキルズIII","データサイエンス総論I"],["84"],src,1);
  const knownTitle=names(groups.flat().map(v=>v.title));
  const hasGroup=(pred,records=own)=>{
    const listed=names(records.filter(v=>pred(v.group)).map(v=>v.title));
    return c=>{
      const result=listed(c);
      if(result===false && c.department==="0C" && knownTitle(c)!==true) return null;
      return result;
    };
  };
  const spec=(group)=>group.includes("/専門科目/");
  const allSpec=hasGroup(spec,groups.flat());
  const general=c=>{
    const major=any(common.match,skills.match,allSpec)(c), category=nonLanguage(c);
    if (major===true || c.teacherTrainingOnly===true || category===false) return false;
    return major===null?null:category;
  };
  const language=gCategory("英語","初修外国語"),practical=hasGroup(g=>g==="実践学修科目");
  const designatedFree=hasGroup(g=>g==="自由選択科目"),thesis=named(["0C"],["卒業論文"],{sections:true});
  const teaching=named(["03","0C"],teacherCourses[y]);
  const eligible=any(general,language,common.match,skills.match,thesis,hasGroup(()=>true),allSpec,c=>{
    if(y>=2024 && teaching(c)===true) return true;
    if(c.facultyApprovedFree===true) return true;
    return !c.department || c.department==="0C" || c.teacherTrainingOnly ? null : false;
  });
  const total=n=>credited("total",n===124?"卒業単位の合計":"学部の教育課程の修得単位",n,eligible,src);
  const termEnd=()=>assessmentPeriod(attendanceCriteria,[3,9],"学期末の進級・卒業判定月");
  const rows=[attendance(48,src),attendance(12,attendanceCriteria,4),termEnd(),total(124)];
  const add=(key,label,min,match,source=src,extra={})=>rows.push(credited(key,label,min,match,source,extra));
  const pool={exclusive:"economics-graduation"};
  rows.push({...common,...pool},{...skills,...pool});
  rows.push(englishRequirement("L",book,y),englishRequirement("R",book,y));
  add("initial-language","初修外国語",6,gCategory("初修外国語"));
  if(ix<0) rows.push(uncertain("program","専門・教養・外国語・実践・自由選択の内訳","所属プログラムを選択し、適用年度便覧別表第2の列を指定してください。",src));
  else {
    add("general","外国語を除く教養教育", [18,18,12,10][ix],general,src,pool);
    add("language","外国語（英語・初修外国語）",ix===2?12:10,language,src,pool);
    if(ix<=1) {
      const ownType=programs[ix]+"プログラム";
      const base=hasGroup(g=>g.includes("プログラム基礎科目")),core=hasGroup(g=>g.includes("プログラム中核科目"));
      add("own-base","自プログラム基礎",6,hasGroup(g=>g.endsWith(ownType+"基礎科目")),annex);
      add("base","プログラム基礎",10,base,src,pool);
      add("own-core","自プログラム中核",8,hasGroup(g=>g.endsWith(ownType+"中核科目")),annex);
      add("core","プログラム中核",12,core,src,pool);
      add("own-advanced","自プログラム専門展開",16,hasGroup(g=>g.endsWith(ownType+"専門展開科目")),annex);
      add("advanced","その他専門（基礎・中核の超過を含む）",30,allSpec,src,pool);
      rows.push(mandatory("practical-mandatory","演習Ⅲ・Ⅳ",["演習III","演習IV"],["0C"],annex,2,{sections:true}));
    } else {
      add("major","専門科目",ix===2?40:46,allSpec,src,pool);
      const allModules=Object.entries(modules[y]);
      const mSrc=y===2021?modules2021:page(book,[93,93,93,90,93,90,91][y-2020],"基礎・中核モジュールと修了条件");
      rows.push(moduleRow("foundation-modules","基礎モジュール",ix===2?2:1,allModules.filter(([k])=>k.includes("基礎モジュール")),mSrc),
        moduleRow("core-modules","中核モジュール",1,allModules.filter(([k])=>!k.includes("基礎モジュール")),mSrc));
      if(ix===2) rows.push(moduleRow("japan-module","日本学基礎モジュール",1,allModules.filter(([k])=>k==="日本学基礎モジュール"),mSrc));
      else rows.push(mandatory("statistics","統計入門",["統計入門"],["0C"],annex,2));
      const writing=hasGroup(g=>g.includes("ライティング"));
      add("writing","アカデミックライティング区分",ix===2?2:3,writing,src,pool);
      if(ix===3) rows.push(mandatory("writing-skill","ライティングスキル",["ライティングスキル"],["0C"],annex,1));
      const base=ix===2?"学修デザイン演習":"課題解決スキル";
      rows.push(mandatory("practical-i",base+"Ⅰ",[base+"I"],["0C"],annex,2,{sections:true}),
        mandatory("practical-ii",base+"Ⅱ",[base+"II"],["0C"],annex,1,{sections:true}));
      if(ix===2) {
        rows.push(mandatory("foreign-reading","外国語文献講読Ⅰ・Ⅱ",["外国語文献講読I","外国語文献講読II"],["0C"],annex,2,{sections:true}));
        const native=names(["学際日本学実習","学際日本学演習","共修日本学演習"]);
        const other=c=>c.economicsOtherProgramSeminar===true;
        const seminarOptions=({courses})=>{
          let value=0,external=0;const contributions=[];
          for(const c of courses) {
            const direct=native(c)===true;
            if(!direct && !other(c))continue;
            const applied=Math.min(8-value,c.credits,direct?8:4-external);
            if(applied<=0)continue;
            value+=applied;if(!direct)external+=applied;
            contributions.push(contribution(c,applied,direct?"学際日本学の実習・演習":"他プログラム演習の振替"));
          }
          return {value,contributions};
        };
        add("japan-practice","学際日本学実習・演習、共修日本学演習",8,any(native,other),page(book,21,"学際日本学の実践学修"),
          {evaluate:seminarOptions,note:"他プログラム演習は確認表の算入区分に従い4単位まで。"});
      } else {
        const letters=y<=2023?["A","B","C"]:["A","B","D"];
        for(const name of ["課題演習","社会開放演習"]) add(name,name+"から1科目",1,names(letters.map(l=>name+l)),src,{unit:"courses"});
        if(y<=2023) add("regional-practice","課題演習・社会開放演習",12,names(letters.flatMap(l=>["課題演習"+l,"社会開放演習"+l])),src);
      }
    }
    add("practice","実践学修科目",[8,8,19,18][ix],practical,src,pool);
    add("thesis","卒業論文",8,thesis,src,pool);
    add("free","自由選択・指定区分の超過",ix<=1 && y<2024?8:[16,16,19,17][ix],eligible,src,pool);
    if(ix<=1 && y<2024) add("flex","実践・自由選択に配分する残り",8,any(practical,designatedFree,eligible),src,pool);
  }
  if(isTransfer(p)) rows.push(transferRow(book));
  rows.find(r=>r.key==="total").allocationKeys=rows.filter(r=>r.exclusive==="economics-graduation").map(r=>r.key);
  const stages=[2,3,4].map(n=>stage("econ-year-"+n,n+"年次進級","progress",progress,[
    attendance(12,attendanceCriteria,n-1),termEnd(),...(n===4?[attendance(36,progress),throughYear({...total(90),source:progress},3)]:[]),
    ...(isTransfer(p)?[transferRow(book)]:[])]));
  stages.push(stage("econ-thesis","4年次の卒業論文履修","progress",progress,[minimumYear(4,progress),uncertain("supervisor","指導教員の決定","所属プログラム担当教員との協議・指導教員決定は学部の通知を確認してください。",progress)]),
    stage("econ-graduation","卒業","graduation",src,rows));
  const g=previousGpa(p);
  const errata=({2022:"ecx29",2023:"ecx31",2024:"ecx33"})[y];
  return {title:book.title,sources:[book,src,annex,official,progress,attendanceCriteria,capSrc,gpaSource,
    source("2026年度 新潟大学授業科目開設一覧（開設部局・開講番号の照合）","https://www.iess.niigata-u.ac.jp/acpb/upload/20260327161315092692700.pdf"),page(book,25,"CAPの算入対象外"),
    page(book,y<=2022?60:58,"教員免許の指定科目"),...(errata?[source(...publications[errata])]:[])],stages,
    note:"編入・転部では学部が指定した年度の便覧を使います。別表第1との対応が定まらない授業と個別の振替は、履修科目確認表の算入区分を照合してください。",
    cap:{period:"semester",unit:"credits",limit:/編入/.test(p.entry || "")?null:g>=4.5?30:g>=4?28:g>=3.5?26:24,source:capSrc,
      classify:c=>thesis(c)===true || teaching(c)===true || (y<=2023 && c.minorIntro===true)?"exclude":
        c.teacherTrainingOnly===true && !["集中","不定期"].includes(c.period) && !c.irregular?"unknown":registrationClass(c),
      note:"不定期開設・学部指定の教職科目"+(y<=2023?"・副専攻プログラムの入門科目":"")+"を除外。編入学の上限は別定。前学期GPAで24～30単位。"}};
}
