import test from "node:test";
import assert from "node:assert/strict";
import * as engine from "../src/requirements.mjs";
import * as pack from "../src/curricula/humanities.mjs";
import { activeCourses } from "../src/study.mjs";
import catalog from "../src/catalog-2026.json" with {type:"json"};

const api=engine.createRequirementAPI?.([pack]);
const run=(name,fn)=>test(name,{skip:api?false:"共通エンジンを統合した checkout で実行"},fn);
const profile=(faculty,program,extra={})=>({faculty,program,entry:"1年次入学",handbook:"2026",
  admitted:"2020",yearOfStudy:4,attendanceMonths:48,yearAttendanceMonths:{1:12,2:12,3:12,4:12},
  assessmentDate:"2027-03-31",gpa:"5",...extra});
const state=(profile,grades=[])=>({profile,grades,balances:[],status:{}});
const plan=(code,title,department,credits=2,extra={})=>({code,title,department,credits,year:2026,period:"第1ターム",...extra});
const grade=(c,extra={})=>({code:c.code,title:c.title,year:c.year,credits:c.credits,grade:"優",
  recordId:c.code+"-"+c.year,matchedCourse:{...c,confirmed:true},...extra});
const rows=(s,stage,planned=[])=>new Map(api.requirementRows(s,new Map(),planned,stage).map(r=>[r.key,r]));
const offering=(unit,filter)=>{
  const c=catalog.courses.find(c=>c.department===unit && filter(c.title));
  assert.ok(c,"公開開設一覧の対象授業");
  return {...c,year:2026};
};
run("全50学部年度・366プログラム組を登録し、すべての段階を公開APIで評価する",()=>{
  let programs=0;
  for(const book of api.availableHandbooks()) {
    const options=api.availablePrograms({faculty:book.faculty,handbook:book.year});
    for(const program of options.length?options:[""]) {
      programs++;
      const p=profile(book.faculty,program,{admitted:book.year,handbook:book.year});
      for(const stage of api.availableStages(p)) {
        const result=rows(state(p),stage.id);
        assert.equal(result.size,stage.rows.length,stage.id);
        for(const r of result.values()) {
          assert.ok(["unknown","met","short"].includes(r.status));
          assert.ok(r.source.url.startsWith("https://"));
        }
      }
    }
  }
  assert.equal(api.availableHandbooks().length,50);
  assert.equal(programs,366);
});

run("実エンジンで在学期間・学期末・編転入・GPA5と学期CAPを評価する",()=>{
  const p=profile("経済科学部","経営学");
  const check=q=>rows(state(q),"econ-year-4");
  assert.equal(check(p).get("year-3-months").current,12);
  assert.equal(check({...p,yearAttendanceMonths:{3:11}}).get("year-3-months").remaining,1);
  assert.equal(check({...p,yearAttendanceMonths:{}}).get("year-3-months").status,"unknown");
  assert.equal(check({...p,attendanceMonths:35}).get("months").remaining,1);
  assert.equal(check({...p,assessmentDate:"2026-08-31"}).get("assessment-period").status,"short");
  assert.equal(check({...p,assessmentDate:"2026-09-30"}).get("assessment-period").status,"met");
  assert.equal(check({...p,assessmentDate:"2026-02-30"}).get("assessment-period").status,"unknown");
  assert.equal(rows(state({...p,yearOfStudy:3}),"econ-thesis").get("study-year").status,"short");
  assert.deepEqual(["1年次入学","編入","転部","再入学"].map(entry=>api.resolveCAP({...p,entry}).limit),[30,null,30,30]);
  assert.deepEqual(["1年次入学","編入","転部","再入学"].map(entry=>api.resolveCAP({...p,faculty:"法学部",entry}).limit),[30,null,null,30]);
  assert.equal(api.resolveCAP({...p,gpa:6}).limit,24);
  assert.equal(api.resolveCAP(p).period,"semester");
  assert.equal(api.resolveCAP(p).unit,"credits");
  assert.equal(api.resolveCAP(p).classify(plan("E","卒業論文","0C",8)),"exclude");
  assert.equal(api.resolveCAP({...p,faculty:"教育学部"}).status,"unknown");
});
run("在籍年次に合う次の進級・履修登録を開き、別の段階も明示して照合できる",()=>{
  const choose="progress-selection";
  const cases=[
    [profile("経済科学部","経済学"),["econ-year-2","econ-year-3","econ-year-4","econ-thesis",choose,choose]],
    [profile("経済学部（旧課程）","経済学科（夜間主コース）",{handbook:"2018",admitted:"2018"}),
      ["old-econ-2","old-econ-3","old-econ-4","old-econ-research",choose,choose]],
    [profile("人文学部","社会文化学"),["human-third","human-third","human-thesis-filing","human-thesis-filing",choose,choose]],
    [profile("教育学部","特別支援教育専修（小教基礎免）"),
      ["education-practicum","education-practicum",choose,choose,choose,choose]],
    [profile("法学部","法学"),Array(6).fill("law-research")]
  ];
  for(const [base,ids] of cases) for(const [i,id] of ids.entries()) {
    const p={...base,yearOfStudy:String(i+1)};
    const result=api.requirementRows(state(p),new Map(),[],"progress");
    assert.equal(result[0].stageId,id,base.faculty+" "+p.yearOfStudy);
    for(const s of api.availableStages(p,"progress"))
      assert.equal(api.requirementRows(state(p),new Map(),[],s.id)[0].stageId,s.id);
    assert.ok(api.requirementRows(state(p),new Map(),[],"graduation")[0].stageId.endsWith("-graduation"));
  }
  const old=profile("教育学部","学校教育学専修",{admitted:"2018",handbook:"2018",yearOfStudy:"3"});
  for(const [date,id] of [["2021-03-31","education-practicum"],["2021-04-01",choose]]) {
    const p={...old,assessmentDate:date};
    assert.equal(api.requirementRows(state(p),new Map(),[],"progress")[0].stageId,id,date);
  }
  for(const entered of ["",null,0,7]) {
    const p={...cases[0][0],yearOfStudy:entered};
    const r=api.requirementRows(state(p),new Map(),[],"progress")[0];
    assert.deepEqual([r.stageId,r.status],[choose,"unknown"]);
  }
});
run("法学のB類を正式な開講名で判定し、正の差分だけを候補とする",()=>{
  const lecture=offering("04",s=>s.startsWith("民法II("));
  const seminar=offering("04",s=>s==="民法基礎演習/民事法基礎演習");
  const other=offering("04",s=>s==="憲法基礎演習");
  const s=state(profile("法学部","法学"),[grade(lecture)]);
  const r=rows(s,"law-graduation",[other,seminar]).get("law-b");
  assert.deepEqual([r.current,r.future,r.remaining,r.after],[2,4,2,0]);
  assert.equal(r.earned[0].code,lecture.code);
  assert.equal(r.planned[0].code,seminar.code);
  const filter=api.shortageFilter(s,new Map(),[],{key:"law-b",stageId:"law-graduation"});
  assert.equal(filter(seminar),true);
  assert.equal(filter(other),false);
  assert.equal(filter(lecture),false);
  const x=api.slotRequirements(s,new Map(),[seminar],[seminar],"graduation").find(r=>r.key==="law-b");
  assert.deepEqual([x.previousFuture,x.future],[2,4]);
  const unknown=rows(state(s.profile,[{...grade(lecture),matchedCourse:null,matchStatus:"unresolved"}]),"law-graduation").get("law-b");
  assert.equal(unknown.status,"unknown");
  assert.equal(unknown.unresolved[0].recordId,lecture.code+"-2026");
  const split=rows(state(s.profile,[grade({...lecture,credits:"4"}),grade(seminar)]),"law-graduation");
  assert.deepEqual([split.get("total").current,split.get("law-electives").current],[6,2]);
  assert.equal(split.get("total").earned.find(c=>c.code===lecture.code).applied,4);
});
run("長期在学・休学を含む履歴で修得時の年次と単位の根拠を保持する",()=>{
  const p=profile("法学部","法学",{admitted:"2018",handbook:"2018",yearOfStudy:4});
  const c=(id,year,studyYear)=>grade(plan(id,id,"84",2,{year,category:"健康・スポーツ"}),{studyYear});
  const records=Array.from({length:60},(_,i)=>c("GS"+i,2018+i%3,undefined));
  const extra=[c("AFTER",2025,4),c("ON-TIME",2024,3),c("LEAVE",2025,undefined)];
  for(const list of [[...records,...extra],[...extra,...records].reverse()]) {
    const x=rows(state(p,list),"law-research").get("total");
    assert.equal(x.current,60); // The F ceiling also applies to the progression total.
    assert.equal(x.earned.reduce((n,c)=>n+c.applied,0),60);
    assert.ok(x.earned.every(c=>c.code!=="AFTER" && c.code!=="LEAVE"));
  }
  const insufficient=rows(state(p,extra),"law-research").get("total");
  assert.deepEqual([insufficient.current,insufficient.status],[2,"unknown"]);
});
run("教育実習で最終評価を受けた不可は履修済みとし、卒業単位は加算しない",()=>{
  const p=profile("教育学部","英語教育専修（小学校主免）");
  const ped=offering("03",s=>s==="現代教育学概論"),constitution=offering("84",s=>s==="日本国憲法");
  const s=state(p,[grade(ped,{grade:"履修中"}),grade(constitution)]);
  const pract=rows(s,"education-practicum").get("pedagogy");
  assert.deepEqual([pract.current,pract.future,pract.futureStatus],[0,1,"met"]);
  assert.equal(rows(s,"education-graduation").get("constitution").current,2);
  const failed=grade(ped,{grade:"不可",finalEvaluation:true,counts:false});
  const get=(records,profile=p)=>rows(state(profile,records),"education-practicum").get("pedagogy");
  const failure=get([failed]);
  assert.deepEqual([failure.current,failure.status,failure.earned[0]?.recordId],[1,"met",failed.recordId]);
  assert.deepEqual([failure.earned[0].column,failure.earned[0].applied,failure.earned[0].earnedCredits],["evaluation",1,0]);
  for(const letter of ["不合格","F","D"])assert.equal(get([{...failed,grade:letter}]).status,"met");
  assert.equal(rows(state(p,[failed]),"education-graduation").get("total").current,0);
  assert.equal(get([failed],{...p,handbook:"2024"}).status,"unknown");
  for(const record of [grade(ped,{grade:"---"}),grade(ped,{grade:"欠席"}),grade(ped,{grade:"出席"}),
    {...failed,finalEvaluation:false}, {...failed,matchedCourse:null,matchStatus:"unresolved"}, {...failed,identityUnresolved:true}]) {
    assert.deepEqual([get([record]).current,get([record]).status],[0,"unknown"]);
  }
  const retake=grade({...ped,year:2027});
  const credits=rows(state(p,[failed,retake]),"education-graduation").get("total");
  assert.deepEqual([credits.current,credits.earned[0].recordId],[Number(ped.credits),retake.recordId]);
});
run("教育実習で正式な履修中だけを認め、申請中や出席予定は履修済みにしない",()=>{
  const p=profile("教育学部","英語教育専修（小学校主免）");
  const ped=offering("03",s=>s==="現代教育学概論"),profession=offering("03",s=>s==="教職概論");
  const projected=(s,planned,key="pedagogy")=>rows(s,"education-practicum",planned).get(key);
  const pending=grade(ped,{grade:"申請中",registered:true});
  const applying=projected(state(p,[pending]),[]);
  assert.deepEqual([applying.future,applying.futureStatus],[0,"short"]);
  assert.equal(projected(state(p),[{...ped,registered:true}]).future,1);
  assert.equal(projected(state(p),[{...ped,registered:false}]).future,0);
  assert.equal(projected(state(p),[{...profession,registered:true}],"profession").future,0);
  for(const [status,met] of [["許可",1],["申請中",0],["不許可",0],["",0]]) {
    const s={...state(p),plan:[ped.code],status:{[ped.code]:status}};
    const index=new Map([[ped.code,ped]]);
    const visible=activeCourses(s,index);
    const r=api.requirementRows(s,index,visible,"education-practicum").find(row=>row.key==="pedagogy");
    assert.deepEqual([r.current,r.future],[0,met],status);
    if(status==="申請中")assert.equal(r.futureStatus,"short");
    if(!status)assert.equal(r.futureStatus,"unknown");
    const suggest=api.shortageFilter(s,index,[],{key:"pedagogy",stageId:"education-practicum"});
    assert.equal(suggest(ped),Boolean(met),status);
  }
});
run("教育実習の本人宛て確認結果を同じ適用年度・科目・段階だけに使う",()=>{
  const p=profile("教育学部","英語教育専修（小学校主免）");
  const stage="education-practicum",scope={...p,stageId:stage,goal:"progress"};
  const balance={scope,key:"pedagogy",unit:"condition",current:1,required:1,confirmed:true};
  const check=(b,profile=p)=>rows({...state(profile),balances:[b]},stage).get("pedagogy");
  assert.deepEqual([0,1].map(current=>check({...balance,current}).status),["short","met"]);
  const ambiguous=grade(offering("03",s=>s==="現代教育学概論"),{grade:"出席"});
  const verified={...state(p,[ambiguous]),balances:[balance]};
  assert.equal(rows(verified,stage).get("pedagogy").current,1);
  assert.equal(rows(verified,stage).get("guidance").status,"unknown");
  assert.equal(rows(verified,"education-graduation").get("total").current,0);
  for(const b of [{...balance,confirmed:false},{...balance,key:"profession"},{...balance,scope:{...scope,stageId:"education-thesis"}},
    {...balance,scope:{...scope,handbook:"2025"}},{...balance,scope:{...scope,program:"学校教育学専修"}}])
    assert.equal(check(b).status,"unknown");
});
run("人文の外国語重複と経済の科目数・履修根拠を実エンジンで照合する",()=>{
  const p=profile("人文学部","社会文化学");
  const language=t=>plan(t,t,"84",4,{category:"初修外国語"});
  const intensive=language("ドイツ語インテンシブ I"),standard=language("ドイツ語スタンダード I");
  const x=rows(state(p,[grade(standard),grade(intensive)]),"human-graduation");
  for(const key of ["total","general","languages","same-language"])assert.equal(x.get(key).current,4,key);
  const ep=profile("経済科学部","地域リーダー"),course=offering("0C",s=>s.startsWith("課題演習B("));
  const a=rows(state(ep,[grade(course)]),"econ-graduation");
  assert.equal(a.get("課題演習").unit,"courses");
  assert.equal(a.get("課題演習").current,1);
  assert.equal(a.get("practice").current,course.credits);
  const q=profile("経済科学部","学際日本学");
  const titles=["Introduction to Interdisciplinary Japanese Studies","文化社会論基礎","映像社会論基礎","経済社会論基礎"];
  const confirmed=titles.map((t,i)=>grade(plan("EC"+i,t,"0C")));
  const m=rows(state(q,confirmed),"econ-graduation").get("japan-module");
  assert.equal(m.current,1);
  assert.equal(m.earned.length,4);
  assert.equal(m.earned.reduce((n,c)=>n+c.applied,0),1);
  const suggest=api.shortageFilter(state(q,confirmed.slice(1)),new Map(),[],{key:"japan-module",stageId:"econ-graduation"});
  assert.equal(suggest(confirmed[0].matchedCourse),true);
  assert.equal(suggest(confirmed[1].matchedCourse),false);
  const base=pack.default(profile("経済科学部","経済学")).stages.at(-1).rows.find(r=>r.key==="own-base");
  assert.equal(base.match(plan("X","入門ミクロ経済学","01")),false);
  assert.equal(base.match(plan("X","入門ミクロ経済学","")),null);
});
run("旧経済の昼間開設上限と開設区分未確定の差を保持する",()=>{
  const p=profile("経済学部（旧課程）","経済学科（夜間主コース）",{admitted:"2018",handbook:"2018"});
  const course=plan("OLD","入門ミクロ経済学","05",42,{year:"2019"});
  const stage="old-econ-graduation";
  const get=legacyOffering=>rows(state(p,[grade({...course,legacyOffering})]),stage).get("total");
  assert.deepEqual([get("day").current,get("night").current,get(undefined).current],[40,42,40]);
  assert.equal(get(undefined).status,"unknown");
  assert.equal(get("day").status,"short");
});
run("個別認定された区分の単位は同じ学部・段階の合計へ一度だけ加える",()=>{
  for(const [f,program,id] of [["人文学部","言語文化学","human-graduation"],["経済科学部","経営学","econ-graduation"],
    ["教育学部","学校教育学専修","education-graduation"]]){
    const p=profile(f,program,{entry:"編入"});
    const record={title:"既修得認定",credits:"2",grade:"認定",recordId:"R",year:"2023",matchedCourse:null,
      allocationKey:"general",allocationScope:{...p,goal:"graduation",stageId:id}};
    const result=rows(state(p,[record,{...record}]),id);
    assert.equal(result.get("general").current,2,f);
    assert.equal(result.get("total").current,2,f);
    assert.equal(result.get("total").earned[0].recordId,"R");
    const other=rows(state(p,[{...record,allocationScope:{...record.allocationScope,entry:"転部"}}]),id);
    assert.deepEqual([other.get("total").current,other.get("total").status],[0,"unknown"]);
  }
});
run("本人宛ての決定だけに入力を許し、法学の課程・早期卒業区分・段階に限定する",()=>{
  const decisions=(p,stage)=>api.availableStages(p).find(s=>s.id===stage)?.rows.filter(r=>r.officialDecision)??[];
  const p=profile("法学部","法学",{earlyGraduation:true});
  const ordinary=profile("法学部","法学"),pro={...p,program:"法曹養成"};
  const keys=(q,id)=>decisions(q,id).map(r=>r.key);
  assert.deepEqual(keys(p,"law-research"),["early-interview"]);
  assert.deepEqual(keys(p,"law-graduation"),["early-degree-decision"]);
  assert.deepEqual(keys(pro,"law-research"),[]);
  assert.deepEqual(keys(pro,"law-graduation"),["early-degree-decision"]);
  assert.deepEqual(keys({...p,entry:"転部"},"law-graduation"),[]);
  assert.deepEqual(keys({...p,program:""},"law-graduation"),[]);
  assert.deepEqual(keys({...p,admitted:"2018",handbook:"2018"},"law-graduation"),[]);
  assert.deepEqual(keys(ordinary,"law-graduation"),[]);
  assert.deepEqual(keys({...ordinary,deanException:true},"law-research"),["law-d-dean-decision"]);
  const hu=profile("人文学部","言語文化学"),edu=profile("教育学部","英語教育専修（中学校主免）");
  assert.deepEqual(keys(hu,"human-thesis-filing"),["thesis-topic-approval"]);
  assert.deepEqual(keys(hu,"human-graduation"),[]);
  assert.deepEqual(keys(edu,"education-practicum"),["profession","psychology","pedagogy","practicum-teacher-0","practicum-teacher-1","practicum-teacher-2"]);
  assert.deepEqual(keys({...edu,handbook:"2024"},"education-practicum"),[]);
  assert.deepEqual(keys(edu,"education-minor-practicum"),[]);
  assert.deepEqual(keys(edu,"education-graduation"),[]);
  for(const rule of [...decisions(p,"law-research"),...decisions(p,"law-graduation"),...decisions(hu,"human-thesis-filing")]) {
    assert.equal(rule.unit,"condition");assert.equal(rule.required,1);
    assert.equal(rule.match,undefined);assert.equal(rule.profileValue,undefined);
  }
  const decision="early-degree-decision",s=state(p),stage="law-graduation";
  const evaluate=current=>rows({...s,balances:current===null?[]:[{scope:{...p,goal:"graduation",stageId:stage},
    key:decision,unit:"condition",current,required:1,confirmed:true}]},stage);
  assert.deepEqual([null,0,1].map(n=>evaluate(n).get(decision).status),["unknown","short","met"]);
  assert.equal(evaluate(1).get("total").current,0);
  assert.equal(evaluate(1).get("total").remaining,124);
});
