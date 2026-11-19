import catalog from "./law-courses.json" with { type: "json" };
import { page, statute, named, credited, uncertain, mandatory, alternative, any, text, attendance,
  contribution, general, transferRow, isTransfer, stage, registrationClass, throughYear } from "./rules.mjs";

const regs = statute("法学部規程第12条・附則", "110000435", "at10");
const details = statute("法学部履修細則第3～7条・別表", "110000438");
const editions = "https://www.jura.niigata-u.ac.jp/~law-web/uploads/934b45ea38ccc713e978656e5a5065a7b1b30e48.pdf";
export const lawBooks = Array.from({length:9},(_,i)=>{
  const year=2018+i;
  return {faculty:"法学部", year:String(year),
    title:year+"年度 法学部"+(year<2022?"卒業要件チェックシート・使用マニュアル":"規程（第12条・当該年度適用附則）"),
    url:year<2022?editions:regs.url, programs:year===2018?["法学"]:["法学","法曹養成"]};
});
const law = names => named(["04"],names,{sections:true});
const variants = (base,n) => ["I","II","III","IV","V","VI","VII","VIII","IX"].slice(0,n).map(x=>base+x);
const fields = [["憲法",3],["民法",4],["刑法",3]];
const sets = fields.map(([field,n])=>[
  {match:law(variants(field,n)),max:2,label:field+"の講義"},
  {match:law([field+"基礎演習"]),max:2,label:field+"基礎演習"},
]);
const pair = alternative(sets);
const allB = any(...sets.flat().map(p=>p.match));
const lawSpecials = ["特殊講義(公法発展)","特殊講義(刑法各論発展)","特殊講義(手形小切手法)","特殊講義(国家補償法)"];
const L = [["憲法",3,lawSpecials[0]],["民法",9],["刑法",3,lawSpecials[1]],["会社法",3,lawSpecials[2]],
  ["民事訴訟法",2],["刑事訴訟法",2],["行政法",3,lawSpecials[3]]];

export default function lawRules(profile,book) {
  const historical = +book.year<2022;
  const src = historical?page(book,2,"旧法学プログラムの卒業要件"):regs;
  const track = text(profile.program).replace(/プログラム$/,"") || (+book.year===2018?"法学":"");
  const professional=track==="法曹養成", selected=["法学","法曹養成"].includes(track);
  const aSrc=src;
  const coreA=mandatory("law-a-core","A類・導入3科目",["スタディ・スキルズ",historical?"人文社会科学入門":"人文社会科学入門(法学)","リーガル・システム"],["84"],aSrc,2);
  const data=mandatory("law-a-data","A類・データサイエンス総論Ⅰ",["データサイエンス総論I"],["84"],aSrc,1);
  const aParts=[...(!historical?[data]:[]),coreA];
  const a = credited("general","教養必修A類",historical?6:7,any(...aParts.map(r=>r.match)),src);
  const seminar=mandatory("law-c","C類・法政演習ⅠとⅡ",variants("法政演習",2),["04"],src,2,{sections:true});
  const research=mandatory("law-d-studies","D類・卒業研究ⅠとⅡ",variants("卒業研究",2),["04"],src,2,{sections:true});
  const originalPaper=mandatory("law-d-paper","D類・ジュニア・リサーチ・ペーパー",["ジュニア・リサーチ・ペーパー"],["04"],src,4,{sections:true});
  const b = credited("law-b","B類・同じ分野の講義2単位＋基礎演習2単位",4,allB,src,{evaluate:pair});
  const lp = L.map(([field,n,special])=>mandatory("law-l-"+field,"L類・"+field+"関係",
    [...variants(field,n),...(special?[special]:[])],["04"],details,2,{sections:true}));
  const mTest=c=>{
    const fits=any(...sets.map(parts=>parts[1].match))(c);
    if (fits!==true) return fits;
    if (c.lawTrainingSection===true || /法曹養成/.test(c.title)) return true;
    return c.lawTrainingSection===false?false:null;
  };
  const m=credited("law-m","M類・法曹養成向けの基礎演習1科目",2,mTest,src,
    {note:"開講指定をシラバスまたは成績確認表のM類で照合。"});
  const n=mandatory("law-n","N類・法文書作成ⅠとⅡ",variants("法文書作成",2),["04"],src,2);
  const table=catalog[professional?"1":"0"];
  const e=law(table["選択科目E類"] || []);
  const fNamed=named(["04","84"],table["選択科目F類"] || [],{sections:true});
  const paper={...originalPaper};
  function substitution(courses) {
    if(profile.lawPaperSubstitutionApproved!==true || originalPaper.evaluate({courses,profile}).value>=4) return [];
    let left=8;const used=[];
    for(const c of courses.filter(c=>e(c)===true && !c.teacherTrainingOnly)) {
      const n=Math.min(c.credits,left);if(n>0)used.push([c,n]);left-=n;
    }
    return left===0?used:[];
  }
  if(profile.lawPaperSubstitutionApproved===true) {
    paper.label+="（学部長認定のE類8単位代替を含む）";
    paper.evaluate=context=>{
      const used=substitution(context.courses);
      return used.length?{value:4,contributions:used.map(([c,n])=>contribution(c,n/2,"認定E類2単位につきD類1単位"))}:originalPaper.evaluate(context);
    };
  }
  const mandatoryRows=[coreA,...(!historical?[data]:[]),seminar,research,paper,...(selected?(professional?[...lp,m,n]:[b]):[])];
  const isMandatory=any(...mandatoryRows.map(r=>r.match));
  const electiveType=c=>{
    if (c.teacherTrainingOnly || c.counts===false) return false;
    if (isMandatory(c)===true) return false;
    if (professional && mTest(c)===null) return null;
    if (e(c)===true) return "E";
    if (fNamed(c)===true || general(c)===true) return "F";
    return c.department==="04" || !c.department ? null : false;
  };
  const electiveMatch=c=>electiveType(c)===null?null:!!electiveType(c);
  const elective=({courses,profile})=>{
    const contributions=[]; let fUsed=0, unknown=false;
    const reserved=new Map(substitution(courses));
    for (const c of courses) {
      const type=electiveType(c);
      if (type===null) unknown=true;
      if (!type) continue;
      const available=c.credits-(reserved.get(c)||0);
      const applied=type==="F" && !professional ? Math.min(available,60-fUsed):available;
      if (type==="F") fUsed+=applied;
      if (applied>0) contributions.push(contribution(c,applied,type+"類"));
    }
    // Unused B/C (or C/M) credits carry to E. Consume the exact selected pair first.
    for (const r of professional?[seminar,m]:[seminar,b]) {
      const candidates=courses.filter(c=>r.match(c,profile)===true);
      const used=r.evaluate?.({courses:candidates,profile}).contributions ?? [];
      let fallback=r.evaluate?0:r.required;
      const taken=new Map();
      for (const a of used) {
        const key=JSON.stringify([a.code,a.year,a.title]); taken.set(key,(taken.get(key)||0)+a.applied);
      }
      for (const c of candidates) {
        const key=JSON.stringify([c.code||"",c.year??"",c.title]);
        const debit=Math.min(c.credits,r.evaluate?(taken.get(key)||0):fallback);
        if (r.evaluate) taken.set(key,(taken.get(key)||0)-debit); else fallback-=debit;
        if (c.credits>debit) contributions.push(contribution(c,c.credits-debit,"超過分をE類へ"));
      }
    }
    return {value:contributions.reduce((s,c)=>s+c.applied,0),contributions,...(unknown?{unknown:"当該年度のE・F類指定を履修科目確認表で確認してください。"}:{})};
  };
  function total(context) {
    const choice=elective(context);const contributions=[...choice.contributions];
    for (const r of mandatoryRows) {
      if (r.evaluate) contributions.push(...r.evaluate(context).contributions);
      else {
        let left=r.required;
        for (const c of context.courses.filter(c=>r.match(c)===true)) {
          const n=Math.min(c.credits,left); if(n>0) contributions.push(contribution(c,n,r.label));left-=n;
        }
      }
    }
    return {value:contributions.reduce((sum,c)=>sum+c.applied,0),contributions,...(choice.unknown?{unknown:choice.unknown}:{})};
  }
  const combined=any(electiveMatch,isMandatory);
  const requiredTotal=(threshold,label)=>credited("total",label,threshold,combined,src,{evaluate:total});
  const early=profile.earlyGraduation===true && !isTransfer(profile);
  const graduation=[attendance(early?36:48,src),requiredTotal(124,"卒業単位の合計"),a,...mandatoryRows];
  if (selected) graduation.push(credited("law-electives","選択E・F類"+(professional?"":"（F類は60単位まで）"),
    124-a.required-4-8-(professional?64:4),any(electiveMatch,professional?mTest:allB,seminar.match),src,{evaluate:elective}));
  else graduation.push(uncertain("law-program","B類またはL・M・N類、E・F類の必要数","所属する法学・法曹養成プログラムを選択してください。",src));
  const exceptional=isTransfer(profile)||profile.earlyGraduation===true||profile.deanException===true;
  if (isTransfer(profile)) graduation.push({...transferRow(details),note:"3年次編入・転部は60単位以内、2年次転部は30単位以内で認定。早期卒業は適用外（履修細則第11条）。"});
  if(early) {
    if(professional) {
      const lm=any(mTest,...lp.map(r=>r.match));
      graduation.push(credited("early-law-grades","L・M類で秀または優",20,c=>lm(c)===true && ["秀","優"].includes(c.grade),details,{unit:"courses"}),
        {...credited("early-gpa","3年次終了時の累積GPA",2.8,()=>false,details),unit:"condition",profileValue:p=>p.thirdYearCumulativeGpa??null});
    }
    graduation.push(uncertain("early-approval","早期卒業の申請と学部判定",professional?
      "2年次末に在学2年・累積GPA2.8以上の届出をしたことを学務係で確認してください。":
      "教養・専門それぞれ累積GPA3.0以上、可・不可なし、2年次末の書面申請と面接合格を学務係で確認してください。",details));
  }
  const gate=exceptional?[uncertain("law-d-exception","D類の履修許可・特例","編入・転部、早期卒業、学部長の特認について法学部学務係の履修登録通知を確認してください。",details)]
    : [requiredTotal(60,"3年次終了時点の卒業要件算入単位"),a,...aParts,seminar];
  const g=Number(profile.gpa);
  return {title:book.title,sources:[book,src,details],stages:[
    stage("law-research","4年次必修D類の履修登録","progress",details,gate.map(r=>throughYear(r,3))),
    stage("law-graduation","卒業","graduation",src,graduation)],
    note:"学部長の特認によるジュニア・リサーチ・ペーパーの代替はE類8単位。早期卒業には申請・成績等に別要件があります（履修細則第10条）。",
    cap:{limit:isTransfer(profile)?null:g>=3.5?30:g>=3?26:g>=2.5?24:22,source:details,classify:registrationClass,
      note:"各学期の上限は前学期GPAによる。不定期開設・教員免許の教職科目は除外。編入・転部には通常上限を適用しません。"}};
}
