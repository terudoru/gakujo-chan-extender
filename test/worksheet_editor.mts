import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { createContext, runInContext } from 'node:vm';

import { worksheetTextPlacement, writeWorksheetPdf } from '../web_scripts/src/upload_preview/worksheet_pdf.ts';

const require = createRequire(import.meta.url);
const library = require('../assets/js/upload_compression/pdf-lib.min.js');

const plain = {
  width: 300,
  height: 400,
  convertToPdfPoint: (x: number, y: number) => [25 + x, 510 - y],
};
const rotated = {
  width: 400,
  height: 300,
  convertToPdfPoint: (x: number, y: number) => [12 + y, 46 + x],
};
assert.deepEqual(worksheetTextPlacement(plain, {x: .25, y: .5}, .25, .25),
  {x: 100, y: 210, width: 75, height: 100, degrees: 0});
assert.deepEqual(worksheetTextPlacement(rotated, {x: .25, y: .5}, .25, .25),
  {x: 237, y: 146, width: 100, height: 75, degrees: 90});

const source = await library.PDFDocument.create();
const originalText = 'Original worksheet content';
source.addPage([350, 550]).drawText(originalText);
const second = source.addPage([350, 550]);
second.setCropBox(12, 46, 300, 400);
second.setRotation(library.degrees(90));
second.drawText(originalText);
const input = await source.save();

const canvas = {
  toDataURL: () => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lHsAAAAASUVORK5CYII=',
} as HTMLCanvasElement;
const result = await writeWorksheetPdf(library, Uint8Array.from(input).buffer, new Map([
  [2, {viewport: rotated, edits: [
    {kind: 'pen', points: [{x: .25, y: .5}, {x: .35, y: .55}]},
    {kind: 'text', origin: {x: .25, y: .5}, width: .25, height: .25, canvas},
  ]}],
]));
const original = await library.PDFDocument.load(input);
const annotated = await library.PDFDocument.load(result);
assert.equal(annotated.getPageCount(), 2);
assert.equal(annotated.getPage(1).getRotation().angle, 90);
assert.deepEqual(annotated.getPage(1).getCropBox(), original.getPage(1).getCropBox());

function streams(pdf: any, page: number): string[] {
  const contents = pdf.getPage(page).node.Contents();
  return Array.from({length: contents.size()}, (_, index) => {
    const stream = pdf.context.lookup(contents.get(index));
    return Buffer.from(library.decodePDFRawStream(stream).decode()).toString('latin1');
  });
}
assert.deepEqual(streams(annotated, 0), streams(original, 0));
const originalStreams = streams(original, 1);
const editedStreams = streams(annotated, 1);
const originalStart = editedStreams.indexOf(originalStreams[0]);
assert.ok(originalStart >= 0);
assert.deepEqual(editedStreams.slice(originalStart, originalStart + originalStreams.length), originalStreams);
const added = editedStreams.slice(originalStart + originalStreams.length).join('\n');
assert.match(added, /1\.6 w/);
assert.match(added, /\/Image-\d+ Do/);

const messages: boolean[] = [];
const revoked: string[] = [];
let urls = 0;
const window = {
  pdfjsLib: {original: true},
  fail: true,
  __MBG_UPLOAD_PREVIEW_EDIT_LIBRARY_LOADED() {
    messages.push(this['__MBG_UPLOAD_LIBRARY_READY_preview-edit'] === true);
  },
};
const context = createContext({
  window, Blob,
  URL: {
    createObjectURL() { return 'blob:' + ++urls; },
    revokeObjectURL(url: string) { revoked.push(url); },
  },
});
const script = readFileSync(process.argv[2], 'utf8');
assert.equal(runInContext(script, context), 'mbg-failed');
assert.deepEqual(window.pdfjsLib, {original: true});
assert.deepEqual(revoked, ['blob:1']);
window.fail = false;
assert.equal(runInContext(script, context), 'mbg-ready');
assert.equal(runInContext(script, context), 'mbg-ready');
assert.deepEqual(messages, [false, true, true]);
assert.equal(urls, 2);
