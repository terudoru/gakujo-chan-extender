import publications from "./humanities/publications.json" with { type: "json" };
import literature, { recentPrograms, earlyPrograms } from "./humanities/literature.mjs";
import education, { programs as educationPrograms } from "./humanities/education.mjs";
import law, { lawBooks } from "./humanities/law.mjs";
import economics, { programs as econPrograms } from "./humanities/economics.mjs";
import oldEconomics, { oldPrograms } from "./humanities/old-economics.mjs";
import { source, uncertain, stage, isTransfer, transferRow } from "./humanities/rules.mjs";

const directory={
  人文学部:source("人文学部 学生便覧・過年度授業科目一覧","https://www.human.niigata-u.ac.jp/education/handbook/"),
  教育学部:source("教育学部 学生要覧・年度別訂正","https://www.ed.niigata-u.ac.jp/?page_id=350"),
  法学部:source("法学部 在学生向け資料・学務係","https://www.jura.niigata-u.ac.jp/~law-web/for-students/"),
  経済科学部:source("経済科学部 学務関係資料・年度別便覧","https://www.econ.niigata-u.ac.jp/students/contact"),
  "経済学部（旧課程）":source("経済学部 旧課程用便覧・読替表","https://www.econ.niigata-u.ac.jp/students/contact"),
};
function books(prefix,faculty,start,end,getPrograms,kind) {
  return Array.from({length:end-start+1},(_,i)=>{
    const year=start+i, [,url]=publications[prefix+year];
    return {faculty,year:String(year),title:year+"年度 "+faculty+" "+kind,url,programs:getPrograms(year)};
  });
}
export const handbooks=[
  ...books("hu","人文学部",2014,2026,y=>y>=2020?recentPrograms:earlyPrograms,"学生便覧"),
  ...[2012,2013].map(year=>({faculty:"人文学部",year:String(year),title:year+"年度適用 人文学部規程（2014年便覧収録・平成24年改正附則）",url:publications.hu2014[1],programs:earlyPrograms})),
  ...Array.from({length:6},(_,i)=>({faculty:"人文学部",year:String(2004+i),title:publications.hu2004[0],url:publications.hu2004[1]})),
  ...books("ed","教育学部",2017,2026,educationPrograms,"学生要覧"),
  ...lawBooks,
  ...books("ec","経済科学部",2020,2026,()=>econPrograms,"学生便覧"),
  ...books("ec","経済学部（旧課程）",2017,2019,()=>oldPrograms,"学生便覧"),
];
const resolvers={人文学部:literature,教育学部:education,法学部:law,経済科学部:economics,"経済学部（旧課程）":oldEconomics};
export default function resolve(profile={}) {
  const faculty=profile.faculty;
  if(!Object.hasOwn(resolvers,faculty)) return null;
  const year=String(profile.handbook||profile.admitted||"");
  const book=handbooks.find(b=>b.faculty===faculty && b.year===year);
  const index=directory[faculty];
  if(book && !(faculty==="人文学部" && +year<=2009)) return resolvers[faculty](profile,book);
  const contact=faculty.replace("（旧課程）","")+"学務係";
  const why="適用年度（"+(year || "未選択")+"）の便覧・経過措置を"+contact+"で確認してください。";
  const graduation=["総単位と在学期間","教養教育の指定科目と必要数","専門・専修の必修・選択・振替"].map((label,i)=>
    uncertain(["total","general","major"][i],label,why,book||index));
  if(book) graduation.push(uncertain("historic-mapping","旧課程の開講科目と読替","平成16～21年度用授業科目一覧に旧科目と対応する講義が掲載されています。卒業基準は入学時の便覧で照合してください。",book));
  if(isTransfer(profile)) graduation.push(transferRow(index));
  return {title:(year || "年度未指定")+" "+faculty, sources:book?[book,index]:[index],
    stages:[stage("historic-progress","進級・実習等の履修登録","progress",index,
      [uncertain("eligibility","在学年数・必要単位・科目登録要件",why,index)]),
      stage("historic-graduation","卒業","graduation",index,graduation)],cap:{limit:null,source:index,note:why}};
}
