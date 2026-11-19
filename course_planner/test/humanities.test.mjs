import test from "node:test";
import assert from "node:assert/strict";
import resolve,{handbooks} from "../src/curricula/humanities.mjs";

const descriptor=(faculty,handbook,program,extra={})=>resolve({faculty,handbook:String(handbook),program,...extra});
const row=(d,key,stage=d.stages.at(-1).id)=>d.stages.find(s=>s.id===stage).rows.find(r=>r.key===key);
const course=(department,title,credits=2,extra={})=>({department,title,credits,code:title,year:2026,period:"第1ターム",...extra});
const evaluate=(r,courses,profile={})=>r.evaluate({courses,profile,baseline:0});
const g=(title,credits,category)=>course("84",title,credits,{category});
const econ=(t,n=2)=>course("0C",t,n);
const law=(t,n=2)=>course("04",t,n);
const passed=(t,n=2)=>course("03",t,n,{evaluated:true});
const E="経済科学部",O="経済学部（旧課程）";

test("公開資料の各年度・プログラムに出典と到達段階がある",()=>{
  assert.equal(resolve({faculty:"農学部"}),null);
  for(const h of handbooks) for(const program of h.programs || [""]) {
    const d=descriptor(h.faculty,h.year,program);
    assert.ok(d.stages.some(s=>s.goal==="graduation"));
    assert.ok(d.stages.some(s=>s.goal==="progress"));
    for(const s of d.stages) {
      assert.equal(new Set(s.rows.map(r=>r.key)).size,s.rows.length,h.title+" "+s.id);
      for(const r of s.rows) {
        assert.ok(r.source?.url?.startsWith("https://"),r.key);
        if(r.required===null) assert.ok(r.unknown);
        if(r.evaluate) assert.doesNotThrow(()=>evaluate(r,[]),h.title+" "+r.label);
      }
    }
  }
  assert.equal(row(descriptor("法学部",2015),"total").required,null);
  assert.equal(row(descriptor("人文学部",2010),"total").required,null);
});
test("人文の58→54単位・同じ外国語・余剰配分と対象外実習",()=>{
  const old=descriptor("人文学部",2013,"歴史文化学"),now=descriptor("人文学部",2026,"心理・人間学");
  assert.equal(row(old,"total","human-third").required,58);
  assert.equal(row(now,"total","human-third").required,54);
  assert.deepEqual(["general","major","surplus"].map(k=>row(old,k).required),[47,64,13]);
  assert.deepEqual(["general","major","surplus"].map(k=>row(now,k).required),[41,60,23]);
  const lang=row(now,"same-language");
  assert.equal(evaluate(lang,[g("初級ドイツ語",4,"初修外国語"),g("初級中国語",4,"初修外国語")]).value,4);
  assert.equal(evaluate(lang,[g("初級ドイツ語",4,"初修外国語"),g("中級ドイツ語",4,"初修外国語")]).value,8);
  assert.equal(row(now,"methods").match(course("01","心理実習")),false);
  assert.equal(row(now,"freshman").match(g("人文初年次演習",2,"大学学習法")),true);
  assert.equal(now.cap.classify(course("01","卒業論文（教材）",10)),"exclude");
});
test("教育学部の改正年度・主免による内訳と日本国憲法",()=>{
  const build=(y,p="英語教育専修（小学校主免）")=>descriptor("教育学部",y,p);
  assert.deepEqual([2017,2018,2019,2020,2021,2022,2026].map(y=>row(build(y),"general").required),[33,29,27,27,17,17,17]);
  assert.deepEqual([2017,2018,2019,2020,2021,2026].map(y=>row(build(y),"total").required),[124,124,124,124,131,131]);
  assert.equal(row(build(2025),"specialization-compulsory").required,12);
  assert.equal(row(build(2025),"english-literacy").required,3);
  assert.equal(row(build(2026),"specialization").required,22);
  assert.equal(row(build(2026,"英語教育専修（中学校主免）"),"specialization").required,38);
  const target=row(build(2026),"constitution");
  assert.equal(target.match(g("日本国憲法",2,"人文社会・教育科学")),true);
  assert.equal(target.match(law("憲法I")),false);
  assert.equal(row(build(2026),"general").match(g("英語基礎L",1,"英語")),false);
  assert.equal(row(build(2026),"total","education-thesis").required,95);
  const pr=row(build(2026),"pedagogy","education-practicum"),before=row(build(2024),"pedagogy","education-practicum");
  const enrolled=course("03","現代教育学概論",2,{registered:true});
  assert.equal(evaluate(pr,[enrolled]).value,1);
  assert.equal(evaluate(before,[enrolled]).value,0);
  assert.equal(evaluate(before,[passed("現代教育学概論")]).value,1);
});
test("教育の過年度別表第6の括弧内と、別枠の専修科目を区別する",()=>{
  const build=(year,program)=>descriptor("教育学部",year,program);
  const special=year=>row(build(year,"特別支援教育専修（小教基礎免）"),"education-choice-0");
  assert.equal(special(2017).match(passed("障害児指導学演習IV")),false);
  assert.equal(special(2018).match(passed("障害児指導学演習IV")),true);
  assert.equal(special(2019).match(passed("障害児指導学演習I")),false);
  assert.equal(special(2025).match(passed("障害児指導学演習I")),true);
  const math=build(2018,"数学教育専修（小学校主免）");
  assert.equal(row(math,"education-choice-4").match(passed("情報数学II")),true);
  assert.equal(row(math,"education-choice-4").match(passed("算数・数学教材研究入門")),false);
  assert.equal(row(math,"specialization").match(passed("算数・数学教材研究入門")),true);
  const music=row(build(2022,"音楽教育専修（小学校主免）"),"specialization-compulsory");
  assert.equal(music.required,22);
  assert.equal(evaluate(music,[passed("合唱A",1),passed("合唱A",1),passed("合奏A",1)]).value,2);
});
test("法学B類のセット・超過振替・F類上限を合計と照合",()=>{
  const p=descriptor("法学部",2026,"法学"),b=row(p,"law-b");
  assert.equal(row(descriptor("法学部",2021,"法学"),"general").required,6);
  assert.equal(row(p,"general").required,7);
  const mixed=[law("民法II"),law("憲法基礎演習")];
  assert.equal(evaluate(b,mixed).value,2);
  const matched=[...mixed,law("民法基礎演習")];
  assert.equal(evaluate(b,matched).value,4);
  const elective=row(p,"law-electives");
  assert.equal(evaluate(elective,matched).value,2);
  assert.equal(evaluate(row(p,"total"),matched).value,6);
  const f=g("健康スポーツ科学講義",65,"健康・スポーツ");
  assert.equal(evaluate(row(p,"total"),[f]).value,60);
  assert.deepEqual([2.4,2.5,3,3.5].map(gpa=>descriptor("法学部",2026,"法学",{gpa}).cap.limit),[22,24,26,30]);
  const professional=descriptor("法学部",2026,"法曹養成"),m=row(professional,"law-m");
  assert.equal(m.match(law("民法基礎演習")),null);
  assert.equal(m.match({...law("民法基礎演習"),lawTrainingSection:true}),true);
  assert.equal(row(professional,"law-electives").required,41);
});
test("経済科学4プログラム・旧年度の選択幅・言語・CAP",()=>{
  const pg=["経済学","経営学","学際日本学","地域リーダー"].map(p=>descriptor(E,2026,p));
  assert.deepEqual(pg.map(d=>row(d,"general").required),[18,18,12,10]);
  assert.deepEqual(pg.map(d=>row(d,"language").required),[10,10,12,10]);
  assert.deepEqual(pg.map(d=>row(d,"free").required),[16,16,19,17]);
  assert.equal(row(pg[0],"own-base").match(econ("入門ミクロ経済学")),true);
  assert.equal(row(pg[1],"own-base").match(econ("入門ミクロ経済学")),false);
  assert.equal(row(pg[1],"own-base").match(econ("会計学概論I")),true);
  assert.equal(row(descriptor(E,2020,"経済学"),"own-base").match(econ("入門ミクロ経済学")),true);
  assert.equal(row(descriptor(E,2023,"経営学"),"flex").required,8);
  assert.equal(row(descriptor(E,2024,"経営学"),"flex"),undefined);
  assert.equal(row(pg[0],"common").match(g("人文社会科学入門(法学)",2,"人文社会・教育科学")),false);
  assert.equal(row(pg[0],"general").match(g("データサイエンス総論I",1,"情報リテラシー")),false);
  const l=row(pg[0],"english-L");
  const pair=["iStep Listening and Speaking","iStep Presentations"].map(n=>g(n,0.5,"英語"));
  assert.equal(evaluate(l,pair).value,0);
  assert.equal(evaluate(l,pair,{iStepApproved:true}).value,1);
  assert.equal(evaluate(row(pg[0],"english-R"),pair,{iStepApproved:true}).value,0);
  assert.deepEqual([3.4,3.5,4,4.5].map(gpa=>descriptor(E,2026,"経営学",{gpa}).cap.limit),[24,26,28,30]);
  assert.equal(pg[0].cap.classify(econ("卒業論文（演習）",8)),"exclude");
  assert.equal(descriptor(E,2026,"経営学",{entry:"編入・転部・再入学"}).cap.limit,null);
  assert.equal(row(pg[0],"year-3-months","econ-year-4").profileValue({enrolledMonths:36}),null);
});
test("必修を含む日本学基礎モジュールと複数年度の履修",()=>{
  for(const year of [2020,2021,2026]){
    const r=row(descriptor(E,year,"学際日本学"),"japan-module");
    const choice=["文化社会論基礎","映像社会論基礎","経済社会論基礎","文字文化史と表現"].map(t=>econ(t));
    assert.equal(evaluate(r,choice).value,0);
    const result=evaluate(r,[econ("Introduction to Interdisciplinary Japanese Studies"),...choice.slice(0,3)]);
    assert.equal(result.value,1,String(year));
    assert.equal(result.contributions.length,4);
  }
});
test("旧経済の昼夜別進級と学科指定・卒業算入の上限",()=>{
  const d=descriptor(O,2018,"経営学科（昼間コース）"),n=descriptor(O,2019,"経済学科（夜間主コース）");
  assert.equal(row(d,"total","old-econ-3").required,60);
  assert.equal(row(n,"total","old-econ-4").required,90);
  assert.equal(row(n,"base","old-econ-4").required,16);
  assert.equal(evaluate(row(d,"accounting","old-econ-3"),[course("05","会計学概論I"),course("05","会計学概論I")]).value,2);
  const readings=[1,2,3,4,5].map(i=>course("05","外書講読I",2,{code:String(i)}));
  assert.equal(evaluate(row(d,"total"),readings).value,8);
  assert.equal(row(n,"foreign").match(g("初級中国語",2,"初修外国語")),true);
  assert.equal(n.cap.classify(course("05","文献研究ⅡB")),"exclude");
});

test("卒業の単位枠と初修外国語の重複は履修記録の並びに依存しない",()=>{
  const d=descriptor("人文学部",2026,"社会文化学");
  const pool=d.stages.at(-1).rows.filter(r=>r.exclusive==="graduation-pool");
  const evidence=[g("人文社会の講義",51,"人文社会・教育科学"),course("01","人文入門",73)];
  for(const sorted of [evidence,[...evidence].reverse()]){
    const remaining=new Map(sorted.map(c=>[c,c.credits]));
    const assigned=pool.map(r=>{
      let used=0;
      for(const c of sorted){
        if(r.match(c)!==true)continue;
        const delta=Math.min(remaining.get(c),r.required-used);
        used+=delta;remaining.set(c,remaining.get(c)-delta);
      }
      return used;
    });
    assert.deepEqual(assigned,[41,60,23]);
  }
  const intensive=g("ドイツ語インテンシブ I",4,"初修外国語"),standard=g("ドイツ語スタンダード I",4,"初修外国語");
  for(const ordered of [[intensive,standard],[standard,intensive]]){
    assert.equal(evaluate(row(d,"total"),ordered).value,4);
    assert.equal(evaluate(row(d,"same-language"),ordered).value,4);
  }
});

test("学部認定の代替・旧課程読替・年度境界の判定",()=>{
  const p=descriptor("法学部",2026,"法学",{lawPaperSubstitutionApproved:true});
  const swap=["経済法I","経済法II","情報法I","労働法I"].map(t=>law(t));
  assert.equal(evaluate(row(p,"law-d-paper"),swap).value,4);
  assert.equal(evaluate(row(p,"law-electives"),swap).value,0);
  assert.equal(evaluate(row(p,"total"),swap).value,4);
  assert.equal(evaluate(row(p,"total","law-research"),[{...law("民法I"),studyYear:4}]).value,0);
  const o=descriptor(O,2017,"経済学科（昼間コース）");
  assert.equal(row(o,"base","old-econ-3").match(econ("社会思想史")),true);
  const n=descriptor(O,2019,"経済学科（夜間主コース）");
  assert.equal(evaluate(row(n,"total"),[course("05","入門ミクロ経済学",45,{legacyOffering:"day"})]).value,40);
  const older=descriptor(E,2022,"経済学"),recent=descriptor(E,2026,"学際日本学");
  assert.equal(older.cap.classify(course("03","教育情報論",1)),"exclude");
  assert.equal(older.cap.classify(econ("副専攻入門")),"include");
  assert.equal(older.cap.classify({...econ("副専攻入門"),minorIntro:true}),"exclude");
  assert.equal(recent.cap.classify({...econ("副専攻入門"),minorIntro:true}),"include");
  const practice=row(recent,"japan-practice");
  assert.equal(evaluate(practice,[econ("学際日本学演習",6),{...econ("演習I"),economicsOtherProgramSeminar:true}]).value,8);
  assert.equal(evaluate(practice,[{...econ("演習I",8),economicsOtherProgramSeminar:true}]).value,4);
  const options=row(recent,"foundation-modules");
  assert.equal(evaluate(options,["入門ミクロ経済学","入門マクロ経済学","入門社会経済学"].map(t=>econ(t))).value,1);
});
