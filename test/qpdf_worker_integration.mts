import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { deflateSync } from 'node:zlib';
import assert from 'node:assert/strict';
import vm from 'node:vm';

const require: any = createRequire(import.meta.url);
const PDFLib: any = require('../assets/js/upload_compression/pdf-lib.min.js');
const { PDFDocument, PDFName, PDFString } = PDFLib;
const workerFile: any = new URL('../assets/js/upload_compression/qpdf-worker.js', import.meta.url);
const moduleUrl: any = new URL('../assets/js/upload_compression/qpdf.js', import.meta.url).href;
const wasmUrl: any = new URL('../assets/js/upload_compression/qpdf.wasm', import.meta.url).href;

// Inspect the actual worker helpers without enabling test-only production APIs.
const workerSource: any = await readFile(workerFile, 'utf8');
const hooks: any = vm.runInNewContext(
  workerSource + '\n;({limitWasmMemory, limitFilesystem})',
  { self: {}, Uint8Array, ArrayBuffer, Number, Math, Error },
);
const wasmBytes: any = await readFile(new URL(wasmUrl));
const capped: any = await WebAssembly.compile(hooks.limitWasmMemory(wasmBytes, 320));
const imports: any = {};
for (const item of WebAssembly.Module.imports(capped)) {
  assert.equal(item.kind, 'function');
  (imports[item.module] ||= {})[item.name] = () => 0;
}
const instance: any = await WebAssembly.instantiate(capped, imports);
const memoryExport: any = WebAssembly.Module.exports(capped).find((item: any) => item.kind === 'memory');
const memory: any = instance.exports[memoryExport.name];
const initialPages: any = memory.buffer.byteLength / 65536;
assert(initialPages < 320);
memory.grow(320 - initialPages);
assert.throws(() => memory.grow(1), RangeError, 'WASM memory must enforce its maximum');
assert.throws(() => hooks.limitWasmMemory(new Uint8Array([0, 1, 2]), 320));

// Check writes, unknown paths and truncate through the actual shared FS hooks.
const testNode: any = { path: '/output.pdf' };
let writes: any = 0, truncates: any = 0;
const streamOps: any = { write() { writes++; return 1; } };
const nodeOps: any = { setattr() { truncates++; } };
const mockFs: any = {
  writeFile() {}, unlink() {},
  lookupPath() { return { node: { stream_ops: streamOps, node_ops: nodeOps } }; },
  getPath(node: any) { return node.path; },
};
hooks.limitFilesystem(mockFs, 10, 4, 8);
streamOps.write({node: testNode}, null, 0, 3, 5, false);
assert.equal(writes, 1);
assert.throws(() => streamOps.write({node: testNode}, null, 0, 4, 5, false));
assert.throws(() => streamOps.write({node: {path: '/other'}}, null, 0, 1, 0, false));
nodeOps.setattr(testNode, {size: 8});
assert.equal(truncates, 1);
assert.throws(() => nodeOps.setattr(testNode, {size: 9}));

// A deterministic, high-entropy image makes qpdf's JPEG stage necessary.
function crc32(buffer: any) {
  let crc: any = -1;
  for (const b of buffer) { crc ^= b; for (let i: any = 0; i < 8; i++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1)); }
  return (crc ^ -1) >>> 0;
}
function chunk(type: any, bytes: any) {
  const name: any = Buffer.from(type), len: any = Buffer.alloc(4), crc: any = Buffer.alloc(4);
  len.writeUInt32BE(bytes.length); crc.writeUInt32BE(crc32(Buffer.concat([name, bytes])));
  return Buffer.concat([len, name, bytes, crc]);
}
function imagePng() {
  const width: any = 1650, height: any = 1200, raw: any = Buffer.alloc((width * 3 + 1) * height);
  let state: any = 42;
  for (let y: any = 0; y < height; y++) {
    for (let x: any = 1; x <= width * 3; x++) {
      state ^= state << 13; state ^= state >>> 17; state ^= state << 5;
      raw[y * (width * 3 + 1) + x] = state & 255;
    }
  }
  const header: any = Buffer.alloc(13); header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 2;
  return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', header),
    chunk('IDAT', deflateSync(raw, { level: 1 })), chunk('IEND', Buffer.alloc(0))]);
}

async function makePdf({ signed = false } = {}) {
  const pdf: any = await PDFDocument.create();
  const page: any = pdf.addPage([595, 842]);
  const image: any = await pdf.embedPng(imagePng());
  page.drawImage(image, { x: 0, y: 100, width: 595, height: 700 });
  page.drawText('OCR TEST 0123456789', { x: 20, y: 30, size: 14, opacity: 0 });
  await pdf.attach(Buffer.from('attachment content'), 'notes.txt');
  const field: any = pdf.getForm().createTextField('answer');
  field.setText('form value'); field.addToPage(page);
  if (signed) {
    const signature: any = pdf.context.obj({ FT: 'Sig', T: PDFString.of('signature'),
      V: { Type: 'Sig', ByteRange: [0, 1, 2, 3] } });
    pdf.catalog.set(PDFName.of('TestSignature'), pdf.context.register(signature));
  }
  return pdf.save({ useObjectStreams: false });
}

const nativeFetch: any = globalThis.fetch;
globalThis.fetch = async (url: any, options: any) => url.startsWith('file:')
  ? new Response(await readFile(new URL(url)) as any) : nativeFetch(url, options);
let messages: any = [];
(globalThis as any).self = { postMessage(message: any) { messages.push(message); } };
await import(workerFile.href);
async function compress(bytes: any, target: any = 4700000) {
  messages = [];
  await (self as any).onmessage({ data: { bytes: bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), moduleUrl, wasmUrl, target } });
  return messages;
}
function decodedPage(pdf: any) {
  const page: any = pdf.getPage(0);
  const contents: any = page.node.Contents();
  const refs: any = contents instanceof PDFLib.PDFArray ? contents.asArray() : [contents];
  return refs.map((ref: any) => {
    const stream: any = pdf.context.lookup(ref);
    return Buffer.from(PDFLib.decodePDFRawStream(stream).decode()).toString('latin1');
  }).join('\n');
}

const original: any = await makePdf();
assert(original.length > 5242880, `fixture too small: ${original.length}`);
const events: any = await compress(original);
const result: any = events.at(-1);
assert.equal(result.type, 'result', JSON.stringify(events.map(({ type, quality, message }) => ({ type, quality, message }))));
assert(result.bytes.byteLength <= 4700000);
assert(events.some((event: any) => event.type === 'progress' && event.quality !== null));
const before: any = await PDFDocument.load(original), after: any = await PDFDocument.load(result.bytes);
assert.equal(after.getPageCount(), before.getPageCount());
assert.equal(decodedPage(after), decodedPage(before), 'page graphics and OCR text streams changed');
assert.equal(after.getForm().getTextField('answer').getText(), 'form value');
const namesRoot: any = after.catalog.lookup(PDFName.of('Names'), PDFLib.PDFDict);
const embeddedFiles: any = namesRoot.lookup(PDFName.of('EmbeddedFiles'), PDFLib.PDFDict);
const attachmentNames: any = embeddedFiles.lookup(PDFName.of('Names'), PDFLib.PDFArray);
assert.equal(attachmentNames.lookup(0).decodeText(), 'notes.txt');
const fileSpec: any = attachmentNames.lookup(1, PDFLib.PDFDict);
const embedded: any = fileSpec.lookup(PDFName.of('EF'), PDFLib.PDFDict)
  .lookup(PDFName.of('F'), PDFLib.PDFRawStream);
assert.equal(Buffer.from(PDFLib.decodePDFRawStream(embedded).decode()).toString(),
  'attachment content', 'attachment contents changed');

const signatureEvents: any = await compress(await makePdf({ signed: true }));
assert.equal(signatureEvents.at(-1).type, 'error');
assert.match(signatureEvents.at(-1).message, /署名/);
const createModule: any = (await import(moduleUrl)).default;
const compiled: any = await WebAssembly.compile(await readFile(new URL(wasmUrl)) as any);
let versionOutput: any = '';
const encryptionModule: any = await createModule({
  thisProgram: 'qpdf',
  print(line: any) { versionOutput += line + '\n'; }, printErr() {},
  instantiateWasm(imports: any, done: any) {
    WebAssembly.instantiate(compiled, imports).then((instance: any) => done(instance, compiled));
    return {};
  },
});
assert.equal(encryptionModule.callMain(['--version']), 0);
assert.match(versionOutput, /qpdf version 12\.4\.2/);
encryptionModule.FS.writeFile('/input.pdf', original);
assert.equal(encryptionModule.callMain(['/input.pdf', '--encrypt', '', 'owner', '256', '--', '/encrypted.pdf']), 0);
const encryptedEvents: any = await compress(encryptionModule.FS.readFile('/encrypted.pdf'));
assert.equal(encryptedEvents.at(-1).type, 'error');
assert.match(encryptedEvents.at(-1).message, /暗号化/);
hooks.limitFilesystem(encryptionModule.FS, 8 * 1024 * 1024, 1024, 8 * 1024 * 1024);
let inspectionBlocked: any = false;
try {
  inspectionBlocked = encryptionModule.callMain([
    '/input.pdf', '--json', '--json-key=qpdf', '/inspect.json',
  ]) !== 0;
} catch (_) {
  inspectionBlocked = true;
}
assert(inspectionBlocked, 'qpdf must not write an oversized inspection file');
const brokenEvents: any = await compress(new TextEncoder().encode('not a PDF'));
assert.equal(brokenEvents.at(-1).type, 'error');
// Invalid predictor dimensions must not be silently rewritten into a PDF.
const malformed: any = await PDFDocument.create();
const malformedPage: any = malformed.addPage([72, 72]);
const malformedStream: any = malformed.context.stream(
  deflateSync(new Uint8Array([0, 0, 0, 0, 0])),
  { Filter: 'FlateDecode',
    DecodeParms: { Predictor: 15, Columns: 1073741825, Colors: 4, BitsPerComponent: 8 } },
);
const malformedRef: any = malformed.context.register(malformedStream);
malformedPage.node.addContentStream(malformedRef);
encryptionModule.FS.writeFile('/input.pdf', await malformed.save({useObjectStreams: false}));
let malformedBlocked: any = false;
try {
  malformedBlocked = encryptionModule.callMain([
    '/input.pdf', '--show-object=' + malformedRef.objectNumber, '--filtered-stream-data',
  ]) !== 0;
} catch (_) {
  malformedBlocked = true;
}
assert(malformedBlocked, 'decoding an invalid predictor must be rejected');
// Exercise the worker's image-optimization stage, not only qpdf's direct
// decoder. The tiny target forces it past the lossless attempt.
const malformedImagePdf: any = await PDFDocument.create();
const malformedImagePage: any = malformedImagePdf.addPage([72, 72]);
const malformedImage: any = malformedImagePdf.context.stream(
  deflateSync(new Uint8Array([0, 0, 0, 0, 0])),
  { Type: 'XObject', Subtype: 'Image', Width: 400, Height: 400,
    ColorSpace: 'DeviceRGB', BitsPerComponent: 8, Filter: 'FlateDecode',
    DecodeParms: { Predictor: 15, Columns: 1073741825, Colors: 4, BitsPerComponent: 8 } },
);
const imageName: any = malformedImagePage.node.newXObject(
  'BadImage', malformedImagePdf.context.register(malformedImage),
);
malformedImagePage.node.addContentStream(malformedImagePdf.context.register(
  malformedImagePdf.context.stream('q 72 0 0 72 0 0 cm ' + imageName.toString() + ' Do Q\n'),
));
const malformedImageEvents: any = await compress(
  await malformedImagePdf.save({useObjectStreams: false}), 1,
);
assert(malformedImageEvents.some((event: any) => event.type === 'progress' && event.quality !== null));
assert.equal(malformedImageEvents.at(-1).type, 'error');
assert.match(malformedImageEvents.at(-1).message, /columns|overflow|predictor/i);
const tooSmallEvents: any = await compress(original, 100);
assert.equal(tooSmallEvents.at(-1).type, 'error');
assert.match(tooSmallEvents.at(-1).message, /5MB以下/);
console.log('qpdf WASM: JPEG stages, unchanged page text/graphics, form and attachment, signature, corrupt and size failure passed');
