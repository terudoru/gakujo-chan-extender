import { delimitedRows } from "./transcript.mjs";
import pdfURL from "../../assets/js/upload_compression/pdf.min.js?url";
import workerURL from "../../assets/js/upload_compression/pdf.worker.min.js?url";
import mapsURL from "../../assets/js/upload_compression/pdf-cmaps.json?url";

let pdfReady;
async function readPdf(bytes) {
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
      throw Error("150ページ以内の成績確認表を選んでください。");
    const rows = [];
    for (let n = 1; n <= doc.numPages; n++) {
      const page = await doc.getPage(n),
        text = await page.getTextContent(),
        lines = [];
      for (const token of text.items) {
        if (!token.str?.trim()) continue;
        const y = token.transform[5],
          x = token.transform[4];
        let line = lines.find((l) => Math.abs(l.y - y) < 2);
        if (!line) {
          line = { y, items: [] };
          lines.push(line);
        }
        line.items.push({
          x,
          end: x + token.width,
          height: token.height,
          text: token.str,
        });
      }
      for (const line of lines.sort((a, b) => b.y - a.y)) {
        const cells = [];
        for (const item of line.items.sort((a, b) => a.x - b.x)) {
          const previous = cells.at(-1);
          // Japanese glyphs in a single table cell can use separate font runs.
          if (
            previous &&
            item.x - previous.end <= Math.max(1, item.height * 0.22)
          ) {
            previous.text += item.text;
            previous.end = Math.max(previous.end, item.end);
          } else cells.push({ ...item });
        }
        rows.push(cells.map((c) => c.text));
      }
    }
    return rows;
  } finally {
    await doc.destroy();
  }
}
export async function readGradeFile(file) {
  if (file.size > 20 * 1024 * 1024)
    throw Error("20 MB以内のファイルを選んでください。");
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (/\.pdf$/i.test(file.name)) return readPdf(bytes);
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    text = new TextDecoder("shift_jis").decode(bytes);
  }
  return delimitedRows(text);
}
