import { confirmHistoricalMatch, courseSource, departmentCode, officialDocument, validYear } from "./identity.mjs";

// A downloaded page stays in a template's inert document. Scripts, frames and remote images never become live.
export function readPublicSyllabusHtml(html, sourceUrl, grade, document, filename = "") {
  const template = document.createElement("template");
  template.innerHTML = html;
  const cells = new Map();
  for (const cell of template.content.querySelectorAll("tr > th")) {
    const label = cell.textContent.trim().split(/[／/]/)[0].trim();
    const value = cell.nextElementSibling;
    if (value?.tagName !== "TD" || !["科目名", "開講番号", "開講学期", "分野", "科目区分"].includes(label)) continue;
    const text = value.textContent.trim();
    if (cells.has(label) && cells.get(label) !== text) throw Error("複数の授業があるファイルは読み込めません。");
    cells.set(label, text);
  }
  // Browsers may retain the original URL in a Mark of the Web comment when saving the public page.
  const embedded = html.match(/<!--\s*saved from url=\(\d+\)(https:\/\/[^\s<>]+?)\s*-->/i)?.[1];
  const url = (sourceUrl || embedded || "").trim();
  const parts = /^https:\/\/syllabus\.niigata-u\.ac\.jp\/syllabusHtml\/(\d{4})\/([0-9A-Z]{2})\//.exec(url);
  const year = cells.get("開講学期")?.normalize("NFKC").match(/(?:^|\s)(\d{4})\s*年度/)?.[1];
  const code = cells.get("開講番号")?.normalize("NFKC");
  const title = cells.get("科目名")?.split("／")[0].trim();
  const officialFilename = /^[\dA-Z]{2}_[\dA-Z]+_(?:ja_JP|en_US)\.html$/i.test(filename);
  if (!parts || parts[1] !== year || (embedded && embedded !== url) || (officialFilename && !url.endsWith("/" + filename)) ||
      !["ja_JP", "en_US"].some((locale) => courseSource(year, parts[2], code, locale) === url) || !title) {
    throw Error("保存したシラバスと公式URLの履修年度・開講所属・開講番号を確認してください。");
  }
  const fieldText = (cells.get("分野") ?? "").normalize("NFKC");
  const fields = [...fieldText.matchAll(/(?:^|[^\d])(\d{2})\s*:/g)].map((m) => m[1]);
  const category = (cells.get("科目区分") ?? "").split(/[\s／]/)[0];
  const course = { year, department: parts[2], code, title, fields, category,
    sourceUrl: url, fieldSource: url, sourceKind: "saved-syllabus" };
  return confirmHistoricalMatch(grade, course);
}

// Students can transcribe a single printed public syllabus record when the annual HTML is unavailable.
// The page reference, faculty and academic field are explicitly confirmed by the student.
export function reviewPublicRecord(record, grade) {
  const year = String(record.year ?? "").trim();
  const department = departmentCode(record.department);
  const sourceUrl = String(record.sourceUrl ?? "").trim();
  if (!validYear(year) || !department || !officialDocument(sourceUrl)) {
    throw Error("資料に記載された年度・開講所属と、新潟大学が公開したPDFのURL（末尾に #page=ページ番号）を入力してください。");
  }
  const input = String(record.fields ?? "").normalize("NFKC").trim();
  const fields = input ? input.split(/[\s,、]+/) : [];
  if (fields.some((value) => !/^\d{2}$/.test(value))) throw Error("分野は資料に記載された2桁の番号を入力してください。");
  const course = { year, department, code: String(record.code ?? "").normalize("NFKC").trim(),
    title: String(record.title ?? "").trim(), fields, category: String(record.category ?? "").trim(),
    sourceUrl, fieldSource: sourceUrl, sourceKind: "manual-record" };
  return confirmHistoricalMatch(grade, course);
}
