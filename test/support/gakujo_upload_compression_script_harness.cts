process.argv = [process.argv[0], ...process.argv.slice(2).map((path) => require('node:fs').readFileSync(path, 'utf8'))];
const vm: any = require('node:vm');
const [build, teardown, rawScenario]: any = process.argv.slice(1);
const scenario: any = JSON.parse(rawScenario);

class FakeFile {
  [key: string]: any;
  constructor(parts, name, options) {
    this.parts = parts;
    this.name = name;
    this.type = options && options.type || '';
    this.size = parts.reduce((sum, part) => sum + (part.size || part.byteLength), 0);
    this.lastModified = options && options.lastModified || 0;
  }
}

class FakeDataTransfer {
  [key: string]: any;
  constructor() {
    const list: any = [];
    this.files = list;
    this.items = { add: (file) => list.push(file) };
  }
}

const listeners: any = [];
const documentListeners: any = { change: [], submit: [], click: [] };
const replayed: any = [];
let statusNode = null;
let pdfReadCount = 0, activePdfReads = 0, maxPdfReads = 0;
let releasePdfRead;
const pdfReadGate: any = new Promise(resolve => { releasePdfRead = resolve; });
function filesFor(files?: any) {
  const header: any = Uint8Array.from([
    137,80,78,71,13,10,26,10, 0,0,0,13, 73,72,68,82,
    0,0,0,1, 0,0,0,1, 8,2,0,0,0, 0,0,0,0,
    0,0,0,0, 73,68,65,84, 0,0,0,0
  ]);
  new DataView(header.buffer).setUint32(16, scenario.headerWidth || 1, false);
  return files.map((f) => Object.assign({
    lastModified: 1, arrayBuffer: async () => {
      if (scenario.holdPdfRead && f.type === 'application/pdf') {
        pdfReadCount++; activePdfReads++;
        maxPdfReads = Math.max(maxPdfReads, activePdfReads);
        await pdfReadGate;
        activePdfReads--;
      }
      return new ArrayBuffer(16);
    },
    slice: () => ({arrayBuffer: async () => header.buffer.slice(0)}),
  }, f));
}
const input: any = {
  tagName: 'INPUT',
  type: 'file',
  files: filesFor(scenario.files),
  getAttribute: (name) => name === 'accept' ? (scenario.accept || null) : null,
  dispatchEvent: (event) => {
    replayed.push(event.type);
    event.target = input;
    if (event.type === 'change') {
      for (const listener of listeners) {
        listener(event);
        if (event.stopped) return;
      }
      if (input.onchange) input.onchange(event);
    }
  },
};
const originalFiles: any = input.files.slice();
let autoSubmits = 0;
class FakeForm {
  [key: string]: any;
  constructor() { this.tagName = 'FORM'; this.elements = [input]; }
  submit() { autoSubmits++; }
  requestSubmit() { autoSubmits++; }
}
const form: any = new FakeForm();
input.form = form;
let pendingOnChange;
if (scenario.submitOnChange) input.onchange = () => {
  pendingOnChange = !!input.__mbgUploadCompressionPending;
  form.submit();
};
const submitButton: any = { tagName: 'BUTTON', form };
const submitInput: any = { tagName: 'INPUT', type: 'submit', form };
const imageInput: any = { tagName: 'INPUT', type: 'image', form };
const submissionTargets: any = [
  ['submit', form],
  ['click', { tagName: 'SPAN', parentNode: submitButton }],
  ['click', submitInput],
  ['click', imageInput],
];
function attemptSubmission(type?: any, target?: any) {
  let prevented = false;
  let stopped = false;
  for (const { listener } of documentListeners[type]) {
    listener({ type, target,
      preventDefault() { prevented = true; },
      stopImmediatePropagation() { stopped = true; },
    });
    if (stopped) break;
  }
  if (prevented !== stopped) throw new Error('Submission must also stop page handlers');
  return prevented;
}
const document: any = {
  querySelectorAll: (selector) =>
    selector === 'input[type="file"]' ? [input] :
    selector.indexOf('upload-compression-owned') >= 0 && statusNode
      ? [statusNode]
      : [],
  addEventListener: (type, listener, capture) => {
    if (type === 'change') listeners.push(listener);
    if (documentListeners[type]) documentListeners[type].push({ listener, capture });
  },
  createElement: (tag) => {
    if (tag === 'canvas') {
      const canvas: any = {
        width: 0,
        height: 0,
        getContext: () => ({
          canvas, fillRect() {}, drawImage() {}, save() {}, restore() {},
          scale() {},
          transform() {}, setTransform() {}, beginPath() {}, rect() {},
          clip() {}, fill() {}, moveTo() {}, lineTo() {}, closePath() {},
          createImageData: (width, height) => ({
            width, height, data: new Uint8ClampedArray(width * height * 4),
          }),
          putImageData() {},
          getTransform: () => ({
            a: 1, b: 0, c: 0, d: 1, e: 0, f: 0,
            invertSelf() { return this; },
          }),
        }),
        toBlob: (callback, type, quality) => {
          if (scenario.realPdf) return callback(new Blob([jpeg], { type }));
          const imageData = scenario.pdf && scenario.pdf.imageData;
          if (imageData === 'missingBlob') return callback(null);
          // A rough model: bytes scale with pixels, JPEG with quality.
          const perPixel = type === 'image/jpeg' ? 1.2 * (quality || 0.9) : 1.5;
          const size: any = Math.round(canvas.width * canvas.height * perPixel);
          callback({ type, size: imageData === 'emptyBlob' ? 0 : size,
            arrayBuffer: async () => imageData === 'missingBytes' ? null :
              new ArrayBuffer(imageData === 'emptyBytes' ? 0 : size),
          });
        },
      };
      return canvas;
    }
    const node: any = {
      style: {},
      isConnected: true,
      setAttribute() {},
      remove() { node.isConnected = false; statusNode = null; },
    };
    statusNode = node;
    return node;
  },
};
const parentNode: any = { insertBefore: () => {} };
input.parentNode = parentNode;
input.ownerDocument = document;

let finishImage;
const imageGate: any = new Promise(resolve => { finishImage = resolve; });
const timers: any = new Map();
let nextTimer = 0;
let workerTerminated = 0;
let workerCreated = 0;
let officeParseCalls = 0;
let bitmapCalls = 0;
const savedConsole: any = { log() {}, warn() {}, error() {} };
const pdfWarnings: any = [];
if (scenario.realPdf) savedConsole.log = (...args) => pdfWarnings.push(args.join(' '));
// A valid 1x1 white JPEG stands in for canvas encoding. Parsing, page checks,
// vector rendering, worker setup, JPEG embedding and PDF writing use the assets.
const jpeg: any = Buffer.from('/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD9U6KKKAP/2Q==', 'base64');
const context: any = {
  console: { ...savedConsole },
  document,
  File: FakeFile,
  DataTransfer: FakeDataTransfer,
  HTMLFormElement: FakeForm,
  Event: class {
  [key: string]: any;
    constructor(type) { this.type = type; }
    stopImmediatePropagation() { this.stopped = true; }
  },
  WeakSet,
  Promise,
  Math,
  Date,
  createImageBitmap: async () => {
    bitmapCalls++;
    if (scenario.holdImage) await imageGate;
    if (scenario.imageError) throw new Error('image decoding failed');
    return {
      width: scenario.width || 1000,
      height: scenario.height || 1000,
      close() {},
    };
  },
  setInterval: () => 1,
  clearInterval: () => {},
  setTimeout: (fn) => { timers.set(++nextTimer, fn); return nextTimer; },
  clearTimeout: (id) => timers.delete(id),
  RegExp,
  Uint8Array, ArrayBuffer,
  Blob, TextDecoder, TextEncoder, URL, URLSearchParams, atob, btoa,
  ReadableStream, AbortController, structuredClone, DOMException,
  requestAnimationFrame: callback => setTimeout(callback, 0),
  __MBG_PDF_WORKER_URL: 'test-worker',
  Worker: class {
  [key: string]: any;
    constructor() { workerCreated++; }
    postMessage() {
      if (scenario.pdf && scenario.pdf.hold) return;
      setImmediate(() => {
        if (scenario.pdf && scenario.pdf.error) {
          this.onmessage({data: {type: 'error', message: scenario.pdf.error}});
        } else {
          this.onmessage({data: {type: 'result', bytes: new ArrayBuffer(1000)}});
        }
      });
    }
    addEventListener() {}
    terminate() { workerTerminated++; }
  },
};
if (scenario.realPdf || scenario.realOffice) {
  context.setTimeout = setTimeout;
  context.clearTimeout = clearTimeout;
}
let pdfOptions;
let pdfRenderCount = 0;
let pdfEmbedCount = 0;
let destroyed = 0;
function loadPdfLibraries() {
  context.__MBG_QPDF_WORKER_URL = 'worker';
  context.__MBG_QPDF_MODULE_URL = 'module';
  context.__MBG_QPDF_WASM_URL = 'wasm';
  const options = scenario.pdf;
  function warning(stage?: any) {
    if (options.warningStage === stage) {
      context.console[options.warningLevel || 'log'](
        options.warningMessage || 'Warning: loadFont - translateFont failed: Unknown CMap name'
      );
    }
  }
  context.pdfjsLib = {
    VerbosityLevel: { WARNINGS: 1 },
    PDFWorker: {fromPort: ({port}) => ({port})},
    OPS: { showText: 44, showSpacedText: 45, nextLineShowText: 46, nextLineSetSpacingShowText: 47 },
    getDocument: (params) => {
      pdfOptions = { verbosity: params.verbosity, stopAtErrors: params.stopAtErrors };
      warning('load');
      return {
        destroy: async () => { destroyed++; warning('destroy'); },
        promise: options.hold ? new Promise(() => {}) : Promise.resolve({
          numPages: 1,
          getAttachments: async () => options.attachments ? { 'notes.txt': {} } : null,
          getFieldObjects: async () => options.fields ? { answer: [] } : null,
          getPage: async () => ({
            getTextContent: async () => {
              warning('text');
              return { items: options.noText ? [] : [{ str: '日本語のレポート' }] };
            },
            getOperatorList: async () => {
              warning('operators');
              return { fnArray: options.noTextDrawing ? [] : [44] };
            },
            getAnnotations: async () => options.annotations || (options.link ? [{ subtype: 'Link' }] :
              options.widget ? [{ subtype: 'Widget' }] : []),
            getViewport: ({ scale }) => ({ width: 600 * scale, height: 800 * scale }),
            render: () => {
              pdfRenderCount++;
              warning('render');
              return { promise: Promise.resolve() };
            },
            cleanup() {},
          }),
        }),
      };
    },
  };
  context.PDFLib = {
    PDFDocument: {
      create: async () => ({
        embedJpg: async () => { pdfEmbedCount++; return {}; },
        addPage: () => ({ drawImage() {} }),
        save: async () => new Uint8Array(1000),
      }),
    },
  };
}
if (scenario.pdf && !scenario.timeoutLibrary && !scenario.latePdfLibrary) loadPdfLibraries();
const channelMessages: any = [];
if (scenario.channel) {
  context.MbgUploadCompression = { postMessage: (m) => {
    channelMessages.push(m);
    if (scenario.timeoutLibrary && channelMessages.length === 2 && scenario.pdf) {
      loadPdfLibraries();
      context.__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED(m);
    }
  } };
}
context.window = context;
if (scenario.pdfAlreadyRunning) context.__MBG_ACTIVE_PDF_COMPRESSION = {};
document.defaultView = context;
vm.createContext(context);
vm.runInContext(build, context);
if (scenario.teardownFirst) vm.runInContext(teardown, context);

let stopped = false;
const event: any = {
  type: 'change',
  target: input,
  stopImmediatePropagation: () => { stopped = true; },
};
async function settle() {
  await new Promise(resolve => setImmediate(resolve));
}
(async () => {
  if (scenario.realOffice) {
    context.JSZip = require(require('node:path').resolve('assets/js/upload_compression/jszip.min.js'));
    const zip: any = new context.JSZip();
    zip.file('word/document.xml', scenario.officeBomb ? new Uint8Array(33 * 1024 * 1024) : 'normal office content');
    const bytes = await zip.generateAsync({type: 'uint8array', compression: 'DEFLATE'});
    if (scenario.officeZip64) {
      bytes[bytes.length - 12] = 255;
      bytes[bytes.length - 11] = 255;
    }
    const originalLoad = context.JSZip.loadAsync;
    context.JSZip.loadAsync = function() { officeParseCalls++; return originalLoad.apply(this, arguments); };
    input.files = [{name: 'report.docx', type: '', size: 8000000,
      arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)}];
    originalFiles.splice(0, originalFiles.length, ...input.files);
  }
  if (scenario.realPdf) {
  const { Worker: NodeWorker }: any = require('node:worker_threads');
  const workerSource: any = require('node:fs').readFileSync('assets/js/upload_compression/pdf.worker.min.js', 'utf8');
  const bootstrap = `
    const {parentPort, workerData} = require('node:worker_threads');
    const listeners = new Set();
    globalThis.self = globalThis;
    globalThis.onmessage = null;
    globalThis.postMessage = (value, transfer) => parentPort.postMessage(value, transfer);
    globalThis.addEventListener = (type, fn) => { if (type === 'message') listeners.add(fn); };
    globalThis.removeEventListener = (type, fn) => listeners.delete(fn);
    parentPort.on('message', data => { for (const fn of listeners) fn({data}); });
    globalThis.process = undefined;
    eval(workerData);
  `;
  context.Worker = class {
  [key: string]: any;
    constructor() {
      this.listeners = new Set();
      this.worker = new NodeWorker(bootstrap, {eval: true, workerData: workerSource});
      this.worker.on('message', data => { for (const fn of this.listeners) fn({data}); });
    }
    addEventListener(type, fn) { if (type === 'message') this.listeners.add(fn); }
    removeEventListener(type, fn) { this.listeners.delete(fn); }
    postMessage(value, transfer) { this.worker.postMessage(value, transfer); }
    terminate() { workerTerminated++; this.worker.terminate(); }
  };
    const fs: any = require('node:fs');
    for (const name of ['pdf.worker.min.js', 'pdf.min.js', 'pdf-lib.min.js']) {
      const source: any = fs.readFileSync(`assets/js/upload_compression/${name}`, 'utf8');
      vm.runInContext(`(function(define, module, exports) {\n${source}\n}).call(window);`, context);
    }
    const bytes = await vm.runInContext(`(async () => {
      const pdf = await PDFLib.PDFDocument.create();
      const page = pdf.addPage([72, 72]);
      let image = '';
      if (${JSON.stringify(scenario.unsupportedMask || '')}) {
        const imageStream = pdf.context.stream(new Uint8Array([255, 255, 255]), {
          Type: 'XObject', Subtype: 'Image', Width: 1, Height: 1,
          ColorSpace: 'DeviceRGB', BitsPerComponent: 8,
          [${JSON.stringify(scenario.unsupportedMask || '')}]: PDFLib.PDFName.of('Unsupported'),
        });
        const name = page.node.newXObject('Image', pdf.context.register(imageStream));
        image = 'q 72 0 0 72 0 0 cm ' + name.toString() + ' Do Q\\n';
      }
      // Keep the page stream uncompressed and >5MB without a binary fixture.
      const content = image + '0 0 1 rg 0 0 72 72 re f\\n%' + 'padding'.repeat(900000) + '\\n';
      page.node.addContentStream(pdf.context.register(pdf.context.stream(content)));
      return pdf.save({ useObjectStreams: false });
    })()`, context);
    input.files = [{ name: 'report.pdf', type: 'application/pdf', size: bytes.length,
      arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) }];
    originalFiles.splice(0, originalFiles.length, ...input.files);
    const getDocument = context.pdfjsLib.getDocument;
    context.pdfjsLib = {
      ...context.pdfjsLib,
      getDocument: (options) => {
        context.console.warn('Deprecated API usage: useSystemFonts');
        context.console.warn('Info: image decoding available');
        const task: any = getDocument(options);
        task.promise.then(pdf => {
          const getPage: any = pdf.getPage.bind(pdf);
          pdf.getPage = async number => {
            const page = await getPage(number);
            const render: any = page.render.bind(page);
            page.render = params => {
              pdfRenderCount++;
              if (scenario.decodeWarning) {
                context.console.warn('Warning: Unable to decode image: JpxError');
              }
              return render(params);
            };
            return page;
          };
        });
        return task;
      },
    };
  }
  for (const listener of listeners) listener(event);
  if (!stopped && input.onchange) input.onchange(event);
  await settle();
  const submitsDuring = autoSubmits;
  if (scenario.realPdf || scenario.realOffice) {
    for (let i = 0; input.__mbgUploadCompressionPending && i < 1000; i++) {
      await new Promise(resolve => setTimeout(resolve, 5));
    }
    if (input.__mbgUploadCompressionPending) throw new Error('PDF compression did not settle');
  }
  let blockedDuring;
  let unrelatedBlocked;
  let pendingStatus;
  if (scenario.checkSubmission) {
    vm.runInContext(build, context);
    blockedDuring = submissionTargets.map(args => attemptSubmission(...args));
    unrelatedBlocked = [
      attemptSubmission('submit', { tagName: 'FORM', elements: [] }),
      attemptSubmission('click', { tagName: 'BUTTON', type: 'button', form }),
    ];
    pendingStatus = statusNode.textContent;
  }
  let statusAfterDisable;
  let blockedWhenDisabled;
  let blockedAfterReenable;
  if (scenario.disableDuringPending) {
    if (scenario.useTeardown) vm.runInContext(teardown, context);
    else context.__MBG_UPLOAD_COMPRESSION_ENABLED = false;
    statusAfterDisable = statusNode ? statusNode.textContent : null;
    blockedWhenDisabled = submissionTargets.map(args => attemptSubmission(...args));
  }
  if (scenario.reenableDuringPending) {
    vm.runInContext(build, context);
    blockedAfterReenable = submissionTargets.map(args => attemptSubmission(...args));
  }
  if (scenario.nextFiles || scenario.reselectSameFiles) {
    if (scenario.teardownBeforeReselect) vm.runInContext(teardown, context);
    if (scenario.nextFiles) input.files = filesFor(scenario.nextFiles);
    if (!scenario.replaceWithoutChange) {
      for (const listener of listeners) listener(event);
    }
  }
  if (scenario.holdPdfRead) {
    await settle();
    releasePdfRead();
  }
  if (scenario.latePdfLibrary) {
    loadPdfLibraries();
    context.__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED('pdf');
    await settle();
  }
  if (scenario.timeoutLibrary) {
    for (const [id, fn] of Array.from(timers) as any[]) { timers.delete(id); fn(); }
    await settle();
    for (const listener of listeners) listener(event);
  }
  if (scenario.compressionTimeout) {
    for (const [id, fn] of Array.from(timers) as any[]) { timers.delete(id); fn(); }
    await settle();
  }
  finishImage();
  await settle();
  if (scenario.timeoutLibrary) await settle();
  let outputPages;
  let officeContent;
  if (scenario.realOffice && input.files[0] !== originalFiles[0]) {
    const output = await context.JSZip.loadAsync(input.files[0].parts[0]);
    officeContent = await output.file('word/document.xml').async('string');
  }
  if (scenario.realPdf && input.files[0] !== originalFiles[0]) {
    const output = await context.PDFLib.PDFDocument.load(input.files[0].parts[0]);
    outputPages = output.getPageCount();
  }
  process.stdout.write(JSON.stringify({
    stopped,
    pending: !!input.__mbgUploadCompressionPending,
    statusAfterDisable, blockedWhenDisabled, blockedAfterReenable,
    originalSize: originalFiles[0] && originalFiles[0].size,
    pdfWarnings, outputPages, officeContent,
    pdfReadCount, maxPdfReads,
    officeParseCalls,
    bitmapCalls,
    replayed: replayed.filter((type) => type),
    files: (Array.from(input.files) as any[]).map((f) => ({
      name: f.name, type: f.type, size: f.size,
    })),
    status: statusNode ? statusNode.textContent : null,
    channelMessages,
    originalsKept: input.files.length === originalFiles.length &&
      originalFiles.every((file, i) => input.files[i] === file),
    pdfOptions,
    pdfRenderCount,
    pdfEmbedCount,
    destroyed,
    workerTerminated,
    workerCreated,
    consoleRestored: Object.keys(savedConsole).every(key => context.console[key] === savedConsole[key]),
    blockedDuring, unrelatedBlocked, pendingStatus,
    blockedAfter: scenario.checkSubmission &&
      submissionTargets.map(args => attemptSubmission(...args)),
    listenerCounts: Object.fromEntries((Object.entries(documentListeners) as any[])
      .map(([type, handlers]) => [type, handlers.length])),
    listenersCapture: Object.values(documentListeners).flat().every(({ capture }) => capture === true),
    autoSubmits, submitsDuring, pendingOnChange,
  }));
})().catch(error => { console.error(error); process.exit(1); });

