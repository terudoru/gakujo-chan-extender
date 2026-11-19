import { delimitedRows, kinds, validatePacket } from "./imports/tables.mjs";
import { pdfPageRows } from "./imports/pdf-rows.mjs";
import pdfURL from "../../assets/js/upload_compression/pdf.min.js?url";
import workerURL from "../../assets/js/upload_compression/pdf.worker.min.js?url";
import mapsURL from "../../assets/js/upload_compression/pdf-cmaps.json?url";

let pdfReady;
async function readPdf(bytes, kind) {
  if (!pdfReady)
    pdfReady = Promise.all([
      new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src = pdfURL;
        script.onload = resolve;
        script.onerror = () => reject(Error("PDFリーダーを開けません。"));
        document.head.append(script);
      }),
      fetch(mapsURL).then((r) => {
        if (!r.ok) throw Error("PDF文字データを開けません。");
        return r.json();
      }),
    ]).catch((e) => {
      pdfReady = null;
      throw e;
    });
  const [, maps] = await pdfReady;
  class CMapReaderFactory {
    async fetch({ name }) {
      if (!Object.hasOwn(maps, name))
        throw Error("PDFの文字を確認できません。");
      return {
        cMapData: Uint8Array.from(atob(maps[name]), (c) => c.charCodeAt(0)),
        compressionType: 1,
      };
    }
  }
  const lib = window.pdfjsLib;
  lib.GlobalWorkerOptions.workerSrc = workerURL;
  const doc = await lib.getDocument({
    data: bytes,
    CMapReaderFactory,
    useSystemFonts: false,
    isEvalSupported: false,
    disableFontFace: true,
  }).promise;
  try {
    if (doc.numPages > 150)
      throw Error("150ページ以内の帳票を選んでください。");
    const tables = [];
    for (let n = 1; n <= doc.numPages; n++) {
      const page = await doc.getPage(n);
      const { items } = await page.getTextContent();
      const rows = pdfPageRows(items, kind);
      tables.push({ heading: "", rows });
      page.cleanup();
    }
    if (!tables.some((t) => t.rows.length))
      throw Error(
        "文字を抽出できません。文字を選択できるPDFまたは表形式のテキストを選んでください。",
      );
    return tables;
  } finally {
    await doc.destroy();
  }
}

function decodeText(bytes) {
  if (bytes[0] === 0xff && bytes[1] === 0xfe)
    return new TextDecoder("utf-16le", { fatal: true }).decode(bytes);
  if (bytes[0] === 0xfe && bytes[1] === 0xff)
    return new TextDecoder("utf-16be", { fatal: true }).decode(bytes);
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return new TextDecoder("shift_jis", { fatal: true }).decode(bytes);
  }
}

export async function readPlannerFile(file, kind) {
  if (!kinds.includes(kind)) throw Error("帳票の種類を選んでください。");
  if (!file?.size || file.size > 20 * 1024 * 1024)
    throw Error("20 MB以内で、内容のあるファイルを選んでください。");
  const bytes = new Uint8Array(await file.arrayBuffer());
  const pdf = new TextDecoder("ascii")
    .decode(bytes.subarray(0, 1024))
    .includes("%PDF-");
  if (!pdf && /\.pdf$/i.test(file.name))
    throw Error("PDFの形式を確認してください。");
  const tables = pdf
    ? await readPdf(bytes, kind)
    : [{ heading: "", rows: delimitedRows(decodeText(bytes)) }];
  return validatePacket({ v: 1, kind, tables });
}
export async function readGradeFile(file) {
  return (await readPlannerFile(file, "grades")).tables.flatMap((t, index) =>
    index ? [["成績確認表"], ...t.rows] : t.rows,
  );
}
