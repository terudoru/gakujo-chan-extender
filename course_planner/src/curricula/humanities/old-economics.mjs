import courses from "./old-economics-courses.json" with {type:"json"};
import replacements from "./old-economics-equivalencies.json" with {type:"json"};
import publications from "./publications.json" with {type:"json"};
import { source, page, statute, text, credited, mandatory, stage, attendance, uncertain,
  named, any, gCategory, general, nonLanguage, transferRow, isTransfer, registrationClass, contribution, throughYear,
  assessmentPeriod } from "./rules.mjs";

export const oldPrograms=["経済学科（昼間コース）","経営学科（昼間コース）","経済学科（夜間主コース）","経営学科（夜間主コース）"];
const alias=new Map(replacements.map(([a,b])=>[text(a),text(b)]));
const regulation=statute("経済学部規程第11条・別表第1～3","110000441");
const creditRules=statute("経済学部履修細則第3～16条","110000444");
const equivalents=source("経済学部生用・経済科学部授業科目読替表",publications.ecx40[1]);
export default function oldEconomics(profile,book){
  const src=page(book,25,"学科・昼夜別の進級要件と卒業要件");
  const program=profile.program||"", night=/夜/.test(program), day=/昼/.test(program);
  const management=/経営/.test(program), known= (day!==night) && (management || /経済学科/.test(program));
  const ix=(night?2:0)+(management?1:0);
  const tables=courses[ix], other=courses[ix^1];
  const applies=(table,group)=> {
    const titles=new Set(Object.entries(table).filter(([k])=>group(k)).flatMap(([,v])=>v).map(text));
    return c=>{
      const full=text(c.title);
      const title=(c.department==="0C"?alias.has(full):titles.has(full))?full:full.replace(/\([^()]*\)$/,"");
      if (c.department==="0C") return alias.has(title)?titles.has(alias.get(title)):null;
      if (!titles.has(title)) return false;
      if (!c.department) return null;
      if (!["05","84"].includes(c.department)) return false;
      return true;
    };
  };
  const dayTable=courses[ix%2],otherDayTable=courses[(ix%2)^1];
  const whenDay=match=>c=>{
    if(!night || c.legacyOffering==="night")return false;
    const fits=match(c);
    return c.legacyOffering==="day" || fits===false?fits:null;
  };
  const base=any(applies(tables,k=>k.startsWith("専門基礎科目")),whenDay(applies(dayTable,k=>k.startsWith("専門基礎科目"))));
  const own=any(applies(tables,k=>k.startsWith("専門展開科目")),whenDay(applies(dayTable,k=>k.startsWith("専門展開科目"))));
  const external=any(applies(other,k=>!k.includes("学部共通")&&(k.startsWith("専門展開科目")||(!night&&k.startsWith("専門基礎科目")))),
    whenDay(applies(otherDayTable,k=>!k.includes("学部共通") && (k.startsWith("専門基礎科目") || k.startsWith("専門展開科目")))));
  const explicitFree=applies(tables,k=>k==="自由選択科目");
  const listedMajor=any(base,own,external);
  const oldGeneral=c=>listedMajor(c)===true?false:general(c);
  const eligible=known?any(oldGeneral,listedMajor,explicitFree):c=>general(c)===true?true:null;
  function capped({courses}) {
    const contributions=[],used=new Map(),teachers=new Set();
    const opposite=c=>c.legacyOffering===(night?"day":"night") && (night || general(c)!==true);
    const unspecified=c=>!["day","night"].includes(c.legacyOffering) && (night || general(c)!==true);
    const order=c=>unspecified(c)?2:Number(opposite(c));
    let abroad=0,unknown=false;
    for(const c of [...courses].sort((a,b)=>order(a)-order(b))) {
      const fit=eligible(c);
      if(fit!==true){if(fit===null) unknown=true;continue;}
      const raw=text(c.title).replace(/\([^()]*\)$/,"");
      const name=c.department==="0C"?alias.get(raw)||raw:raw;
      let key="";
      if(/^外書講読i{1,2}$/.test(name)) key="外書講読";
      if(/^(インターンシップ|異文化論|経済学特殊講義|会計学特殊講義|公共経営特殊講義|企業経営特殊講義|異文化間コミュニケーション特殊講義)$/.test(name)) key=name;
      if(night && /^文献研究i{1,2}[ab]$/.test(name)) key="文献研究";
      if(key==="異文化論") {
        if(!c.teacher){unknown=true;continue;}
        if(teachers.has(c.teacher) || teachers.size>=4) continue;
      }
      const ceiling=key?Math.max(0,8-(used.get(key)||0)):Infinity;
      const cross=opposite(c), unverified=unspecified(c);
      const applicable=Math.min(c.credits,ceiling);
      const applied=Math.min(applicable,cross || unverified?(night?40:18)-abroad:Infinity);
      if(unverified && applied<applicable)unknown=true;
      if(applied<=0) continue;
      if(key==="異文化論") teachers.add(c.teacher);
      if(key) used.set(key,(used.get(key)||0)+applied);
      if(cross || unverified) abroad+=applied;
      contributions.push(contribution(c,applied,key || (cross?"昼夜間の相互履修":"卒業算入")));
    }
    return {value:contributions.reduce((sum,c)=>sum+c.applied,0),contributions,
      ...(unknown?{unknown:"旧課程の開講区分・異文化論の異なる担当者・科目読替を学部の履修科目確認表で確認してください。"}:{})};
  }
  const prog=credited("total","進級判定の対象単位",night?90:60,eligible,src,{evaluate:capped});
  const grade=credited("total","卒業単位の合計",124,eligible,src,{evaluate:capped});
  const g=credited("general","教養科目",32,oldGeneral,src);
  const unknownTrack=uncertain("old-track","昼間・夜間主コースと学科の指定区分","経済学科・経営学科と昼間・夜間主コースを選択してください。",src);
  const graduation=[attendance(48,src),attendance(12,src,4),grade,g,
    credited("fourth-year-earned","4年次に修得した単位",8,c=>{
      const year=c.studyYear ?? c.yearOfStudy;
      if (!year) return null;
      if (+year!==4) return false;
      if (c.recognized) return c.exchangeWithoutLeave===true?eligible(c):null;
      return eligible(c);
    },src,{note:"認定単位は原則対象外。休学せず協定校で修得した認定単位を含みます。"})];
  if(known){
    graduation.push(credited("english","英語",4,gCategory("英語"),src),credited("foreign","初修外国語",night?4:6,
      night?c=>gCategory("初修外国語")(c)===true?(/ドイツ語|ロシア語|中国語/.test(c.title)?true:/フランス語|朝鮮語|スペイン語|イタリア語/.test(c.title)?false:null):gCategory("初修外国語")(c):gCategory("初修外国語"),src),
      credited("general-other","外国語以外の教養科目",night?24:22,c=>oldGeneral(c)===false?false:nonLanguage(c),src));
    const assignment={exclusive:"old-economics"};
    graduation[3]={...g,...assignment};
    graduation.push(credited("base","自学科専門基礎",16,base,creditRules,assignment),
      credited("own-expanded","自学科専門展開（基礎の超過を含む）",night?24:30,any(base,own),creditRules,assignment),
      credited("other-expanded","他学科専門（自学科展開の超過を含む）",night?22:26,any(base,own,external),creditRules,assignment),
      credited("free","自由選択・指定区分の超過",night?30:20,eligible,creditRules,assignment));
  }else graduation.push(unknownTrack);
  const stages=[];
  for(const year of [2,3,4]){
    const rows=[attendance(12,src,year-1),{...assessmentPeriod(creditRules,[3],"原則の学年末進級判定月"),
      note:"学年末以外の判定は旧経済学部の学務係に個別の適用を確認してください。"}];
    if (known && year===(night?4:3)){
      rows.push(prog,credited("base","進級に必要な自学科専門基礎",night?16:12,base,src));
      if(management && day) rows.push(mandatory("accounting","会計学概論Ⅰ・Ⅱ",["会計学概論I","会計学概論II"],["05","0C"],src,2));
    }else if(!known && year!==2) rows.push(unknownTrack);
    stages.push(stage("old-econ-"+year,year+"年次進級","progress",src,rows.map(r=>throughYear(r,year-1)),[year-1,year-1]));
  }
  const seminar=night?"文献研究":"演習";
  stages.push(stage("old-econ-research","卒業論文の履修登録","progress",creditRules,known?[
    ...["IA","IB","IIA","IIB"].map(s=>credited("prereq-"+s,seminar+s+"の履修",1,named(["05"],[seminar+s],{sections:true}),creditRules,{unit:"courses"})),
    uncertain("old-thesis-supervision","担当教員の指導・ⅡA/Bの同時履修","ⅠA/Bを3年次末までに修得し、4年次にⅡA/Bを履修する場合も可。担当教員に履修時期を確認してください。",creditRules)
  ]:[unknownTrack],[4,4]));
  if(isTransfer(profile)) graduation.push(transferRow(book));
  stages.push(stage("old-econ-graduation","卒業","graduation",src,graduation));
  return {title:book.title,sources:[book,src,regulation,creditRules,equivalents],stages,
    note:"昼間コースの経済学部向けスタディ・スキルズは原則1年次に履修。昼間開設の夜間主による履修は40単位、夜間主の専門科目の昼間コースによる履修は18単位まで。開講区分は旧課程時間表で照合してください。",
    cap:{period:"semester",unit:"credits",limit:/編入/.test(profile.entry || "")?null:22,source:creditRules,
      classify:c=>/^(演習(i|ii)[ab]|文献研究(i|ii)[ab]|異文化間コミュニケーション(基礎演習)?i{1,2}|卒業論文|インターンシップ)$/.test(text(c.title))?"exclude":registrationClass(c),
      note:"各学期22単位。指定の演習・文献研究・卒業論文・インターンシップ、不定期開設科目、教職専門科目は除外。編入生は別規定。"}};
}
