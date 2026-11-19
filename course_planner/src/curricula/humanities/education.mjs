import specializations from "./education-courses.json" with { type: "json" };
import annexes from "./education-annexes.json" with { type: "json" };
import publications from "./publications.json" with { type: "json" };
import { text, source, page, stage, credited, uncertain, mandatory, any, named, gCategory, attendance,
  transferRow, isTransfer, alternative, contribution } from "./rules.mjs";

const subjects=["国語教育","社会科教育","数学教育","理科教育","音楽教育","美術教育","保健体育","技術教育","家庭科教育","英語教育"];
export function programs(year) {
  return ["学校教育学専修","教育心理学専修","特別支援教育専修（小教基礎免）",...(year<=2020?["特別支援教育専修（中教基礎免）"]:[]),
    ...["小学校主免","中学校主免"].flatMap(mode=>subjects.map(s=>s+"専修（"+mode+"）"))];
}
const totalsPages=[106,98,98,102,102,89,104,104,104];
const practicumPages=[59,55,55,58,58,53,60,60,60];
const ed=names=>named(["03","84"],names);
const specificNames=names=>named(["03"],names,{sections:true});
const corrected = {2021:"edx22",2022:"edx20",2025:"edx16"};

function registrationEvidence(key,title,canBeTaking,src) {
  const matches=specificNames([title]);
  return credited(key,title+"（"+(canBeTaking?"履修済みまたは履修中":"履修済み")+"）",1,matches,src,{unit:"condition",
    evaluate:({courses})=>{
      const check=c=>c.evaluated===true || c.earned===true || c.passed===true ||
        ["秀","優","良","可","不可","合格","不合格","修得","認定"].includes(c.grade || c.result) ||
        (canBeTaking && (c.registered===true || c.status==="許可"));
      const selected=courses.filter(c=>matches(c)===true); const hit=selected.find(check);
      return {value:hit?1:0,contributions:hit?[contribution(hit,1,canBeTaking?"履修状況":"評価済み")]:[],
        ...(selected.length && !hit?{unknown:"学務の成績・正式登録で確認してください。履修済みには評価を受けた不合格科目も含みます。"}:{})};
    }});
}

export default function education(profile,book) {
  const y=+book.year, current=y>=2021, totals=y===2017?87:totalsPages[y-2018];
  const src=page(book,totals,"別表第1 履修基準表");
  const genSrc=page(book,totals+(y>=2024 || y===2017?1:0),"別表第2 教養教育の履修基準");
  const prereq=page(book,y===2023 || y===2017?8:11,"卒業研究の履修資格");
  const pract=page(book,y===2017?52:practicumPages[y-2018],"教育実習の履修要件・履修済みの定義");
  const yrNote=corrected[y]?source(...publications[corrected[y]]):null;
  const prog=text(profile.program).replace(/[()]/g,"").replace(/^学校教員養成課程/,"").replace(/^(学校教育コース|教科教育コース)/,"");
  const valid=programs(y).find(s=>text(s).replace(/[()]/g,"")===prog);
  const special=prog.includes("特別支援教育"),primary=prog.includes("小学校")||prog.includes("小教"),middle=prog.includes("中学校")||prog.includes("中教");
  const idx=!valid?-1:special?(middle?2:1):primary?3:middle?4:0;
  const courseKey=prog.replace(/[小中]教基礎免/,"");
  const spec=specializations[y+"/"+courseKey];
  const specSrc=(y===2025 && courseKey==="英語教育専修小学校主免")?yrNote:
    page(book,spec?.pages[0] || totals+5,"別表第6 所属専修の指定科目");
  const common=ed(annexes[y+"/49"]),specialEd=specificNames(annexes[y+"/75"]);
  function tableGroup(table) {
    const all=new Set(annexes[y+"/"+table]);
    const target=["学校教育学専修・教育心理学専修","特別支援教育専修(小教基礎免)","特別支援教育専修(中教基礎免)","小学校主免","中学校主免"][idx];
    const keys=new Set(annexes[table].map(([title])=>title));
    const filtered=annexes[table].filter(([name,,groups])=>(y===2026 || all.has(name)) && (idx<0 || groups.includes("課程共通必修科目") || groups.includes(target)));
    const match=specificNames([...filtered.map(r=>r[0]),...[...all].filter(v=>!keys.has(v))]);
    return c=>match(c) || (c.department==="03" && (!valid || (y<2026 && all.has(text(c.title))))?null:false);
  }
  const teacher=tableGroup(50), subject=tableGroup(51), specMatch=specificNames(spec?.courses||[]);
  const secondaryOptions=idx===0 && current?[
    ...subjects.map(s=>({label:s+"専修",max:22,match:specificNames(specializations[y+"/"+s+"専修小学校主免"]?.courses||[])})),
    {label:"特別支援教育",max:18,match:c=>!["特別支援教育実習","肢体不自由指導論"].includes(text(c.title)) && specialEd(c)},
  ]:[];
  const thesis=specificNames(["卒業研究"]);
  const listed=any(common,teacher,subject,specMatch,specialEd,thesis,
    specificNames(Object.entries(specializations).filter(([key])=>key.startsWith(y+"/")).flatMap(([,v])=>v.courses)));
  const generalAllowed=gCategory("健康・スポーツ","大学学習法","初修外国語","英語","情報リテラシー","新潟大学個性化科目","人文社会・教育科学","自然系共通専門基礎","自然科学");
  const general=c=>{
    if((y>=2020 && /^(英語基礎[lr])$/.test(text(c.title))) || listed(c)===true) return false;
    return generalAllowed(c);
  };
  const eligible=any(general,listed,gCategory("留学生基本科目","医歯学"),c=>!c.department || c.department==="03"?null:false);
  const gen= y===2017?33:y===2018?29:current?17:27;
  const rows=[attendance(48,src),credited("total","卒業単位の合計",current?131:124,eligible,src),
    credited("general","教養教育に関する授業科目",gen,general,genSrc,{exclusive:"education-graduation"})];
  const genPart=(key,label,req,match)=>rows.push(credited(key,label,req,c=>general(c)===false?false:match(c),genSrc,{exclusive:"education-general"}));
  genPart("sport-lab","体育実技",1,c=>gCategory("健康・スポーツ")(c)===true && /^健康スポーツ科学実習/.test(text(c.title)));
  genPart("sport-lecture","体育講義",2,c=>gCategory("健康・スポーツ")(c)===true && /^健康スポーツ科学講義/.test(text(c.title)));
  genPart("study","大学学習法",2,gCategory("大学学習法"));
  genPart("english","英語",y<=2019?4:2,gCategory("英語"));
  genPart("initial-language","初修外国語",2,gCategory("初修外国語"));
  genPart("information","情報リテラシー",2,gCategory("情報リテラシー"));
  if(y>=2022) rows.push(mandatory("data","データサイエンス総論Ⅰ・Ⅱ",["データサイエンス総論I","データサイエンス総論II"],["84"],genSrc,1));
  const constitution=named(["84"],["日本国憲法"]);
  if (current) genPart("constitution","日本国憲法",2,constitution);
  else {
    rows.push(credited("constitution","日本国憲法",2,constitution,genSrc));
    genPart("niigata","新潟大学個性化科目",2,gCategory("新潟大学個性化科目"));
    genPart("science","自然系共通専門基礎・自然科学",4,gCategory("自然系共通専門基礎","自然科学"));
    genPart("social","人文社会・教育科学（日本国憲法を含む）",6,gCategory("人文社会・教育科学"));
  }
  const elective=gCategory("初修外国語",...(current?["情報リテラシー"]:[]),"新潟大学個性化科目","自然系共通専門基礎","自然科学","人文社会・教育科学");
  genPart("general-choice","指定区分からの選択必修",y===2017?8:y===2019?2:4,elective);
  const matrix=y===2017?[[48,41,31,48,38],[16,10,20,16,0],[10,4,4,14,30],[7,1,1,3,13]]:
    current?[[36,33,0,36,36],[56,26,0,38,16],[10,4,0,22,38],[0,18,0,10,16]]:
    [y===2018?[52,45,33,52,40]:[34,33,35,34,34],y===2018?[18,12,20,18,0]:[38,26,20,38,0],
      y===2018?[10,4,4,14,30]:[10,4,4,14,38],[7,1,5,3,17]];
  const majorPart=(key,label,req,match,ref=src)=>rows.push(credited(key,label,req,match,ref,{exclusive:"education-graduation"}));
  majorPart("common","課程共通科目",y===2017?4:2,common);
  majorPart("thesis","卒業研究",6,thesis);
  if (valid) {
    const teachingSrc=page(book,totals+2,"別表第4 教職専門科目");
    majorPart("teaching","教職専門科目",matrix[0][idx],teacher,teachingSrc);
    const asSubject=any(subject,...secondaryOptions.map(v=>v.match));
    if(matrix[1][idx]) majorPart("subject","教科専門科目",matrix[1][idx],asSubject,page(book,totals+3,"別表第5 教科専門科目"));
    majorPart("specialization","専修専門科目",matrix[2][idx],c=>specMatch(c) || (!spec && c.department==="03"?null:false),specSrc);
    if(special) majorPart("special-support","特別支援教育専門科目",25,specialEd);
    if(matrix[3][idx]) majorPart("free","自由科目・指定区分の超過",matrix[3][idx],eligible);
    if(secondaryOptions.length) {
      const ref=yrNote || page(book,totals+3,"別表第5 学校教育学・教育心理学専修の選択");
      rows.push(credited("secondary-route","1専修22単位または特別支援教育18単位",1,any(...secondaryOptions.map(v=>v.match)),ref,
        {unit:"condition",evaluate:({courses,profile})=>{
          for(const option of secondaryOptions) {
            const result=alternative([[option]])({courses,profile});
            if(result.value===option.max) return {value:1,contributions:result.contributions.map((c,i)=>({...c,applied:i?0:1}))};
          }
          return {value:0,contributions:[],unknown:"副免の履修指定と認定科目を副免ガイダンス資料で照合してください。"};
        },note:"教職36～37・教科56～60・自由0～3。特別支援教育実習は教職専門科目で数えます。"}));
    }
    if(spec?.required) {
      const parts=Object.entries(spec.required).map(([name,max])=>({label:name,max,match:specificNames([name])}));
      if(parts.length) rows.push(credited("specialization-compulsory","所属専修の必修科目",parts.reduce((s,v)=>s+v.max,0),any(...parts.map(v=>v.match)),specSrc,{evaluate:alternative([parts])}));
    }
    if(y===2025 && courseKey==="英語教育専修小学校主免") {
      for (const [key,fields] of [["productive",["スピーキング","リスニング"]],["literacy",["ライティング","リーディング"]]]) {
        rows.push(credited("english-"+key,fields.join("・")+"演習Ⅱ～Ⅳ",3,specificNames(fields.flatMap(f=>["II","III","IV"].map(n=>"英語教育"+f+"演習"+n))),yrNote));
      }
    }
    const tag=["学校教育学専修・教育心理学専修","特別支援教育専修(小教基礎免)","","小学校主免","中学校主免"][idx];
    if(y===2026) {
      const fixed=annexes[50].filter(([, ,g])=>g.includes("課程共通必修科目") || (g.includes(tag) && g.includes("必修科目")));
      const parts=fixed.map(([t,c])=>({label:t,max:c,match:specificNames([t])}));
      rows.push(credited("teacher-compulsory","共通・免許別の教職必修",parts.reduce((s,v)=>s+v.max,0),any(...parts.map(v=>v.match)),teachingSrc,{evaluate:alternative([parts])}));
    }
    const choices=[...(spec?.choices || []),...(y===2026?annexes.subjectChoices2026.filter(group=>group.group===tag):[])];
    choices.forEach((group,i)=>{
      const options=group.titles.map(t=>({label:t,max:2,match:specificNames([t])}));
      const choiceSrc=group.group?page(book,totals+3,"別表第5 選択必修の教科数と単位"):specSrc;
      rows.push(credited("education-choice-"+i,group.titles.slice(0,2).join("・")+(group.titles.length>2?"など":"")+"から選択",group.credits,
        any(...options.map(o=>o.match)),choiceSrc,group.subjects?{evaluate:alternative([options]),note:group.subjects+"教科が必要。"}:{}));
    });
    if(!spec || spec.checkSubgroups || (middle && (prog.includes("理科教育") || prog.includes("社会科教育")))) rows.push(uncertain("specialization-route","専修内の選択分野・選択必修","入学年度の別表第6で、選んだ分野と括弧で指定された科目群ごとの単位を照合してください。分野の適用は専修担当に確認してください。",specSrc));
  } else rows.push(uncertain("education-track","教職・教科・専修・自由科目の内訳","所属専修と主免（特別支援は基礎免）を選択してください。",src));
  if(isTransfer(profile)) rows.push(transferRow(book));
  const gate=[uncertain("guidance","実習前の事前指導","事前指導の出席を実習担当の記録で確認してください。",pract),
    registrationEvidence("profession",y===2017?"教職入門":"教職概論",false,pract),
    registrationEvidence("psychology",y===2017?"教育心理学":y===2018?"教育・学校心理学":y===2026?"教育心理学A":"教育・学校心理学A",false,pract),
    registrationEvidence("pedagogy",y===2017?"教育学概論":"現代教育学概論",y>=2025,pract),
    ...(y===2017?["教育の制度と経営","教育方法・技術"]:["教育政策と法概論",y===2018?"教育方法総論A":"教育方法及び特別活動の指導法A","道徳教育論"]).map((t,i)=>registrationEvidence("practicum-teacher-"+i,t,true,pract)),
    uncertain("methods","実習の校種・教科に対応する教科教育法","小学校は1科目履修済み＋別の1科目が履修済み又は履修中。中等は当該教科1科目が履修済み。実習先の校種・教科と評価記録で照合してください。",pract)];
  if(y===2017) gate.push(uncertain("method-alternative","道徳指導法または特別活動研究","いずれかが履修済み又は履修中であることを登録記録で照合してください。高校免許のみの場合は実習担当に適用を確認してください。",pract));
  if(prog.includes("英語教育") && middle) gate.push(uncertain("eiken","中等英語実習の英検2級以上","実習申請時点の合格証明を実習担当に提示してください。",pract));
  const license=source("教育学部 学生要覧・課程別の必須免許（◎・●）","https://www.ed.niigata-u.ac.jp/?page_id=350");
  rows.push(uncertain("teaching-licenses",current?"主免と副免の取得資格":"主免の取得資格",current?
    "小学校・中学校、又は特別支援学校・小学校等、所属コースの必須の組合せを学生要覧と免許状取得見込確認表で確認してください。":
    "入学年度・所属専修の必須免許の取得資格を教育学部学務係の免許確認表で照合してください。",license));
  const stages=[stage("education-thesis","卒業研究の履修登録","progress",prereq,[attendance(36,prereq),credited("total","履修資格に必要な修得単位",95,eligible,prereq)]),
    stage("education-practicum","初等・中等主専攻実習の履修登録","progress",pract,gate),
    stage("education-minor-practicum","副専攻実習の履修登録","progress",pract,[uncertain("major-practicum","主専攻教育実習の修了","主専攻教育実習の修了・副免の校種別教科教育法・中等英語の英検2級を実習担当の資料で照合してください。",pract)])];
  if(special) stages.push(stage("education-special-practicum","特別支援教育実習の追加履修条件","progress",pract,
    ["特別支援教育の本質と目標","知的障害心理学"].map((t,i)=>registrationEvidence("support-"+i,t,true,pract))));
  stages.push(stage("education-graduation","卒業","graduation",src,rows));
  return {title:book.title,sources:[book,src,genSrc,specSrc,prereq,pract,...(yrNote?[yrNote]:[])],stages,
    note:"卒業研究・実習の履修登録と、卒業時の単位・主免等の判定は別々に表示します。",
    cap:{limit:null,source:source("新潟大学 教務関係Q12・学部別の登録上限","https://www.niigata-u.ac.jp/campus/qa/education/"),
      note:"学生要覧で一律の学期上限を確認できません。登録年度・専修の履修指導と教育学部学務係の回答を確認してください。"}};
}
