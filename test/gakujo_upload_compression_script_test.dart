import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_download_capture_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_compression_script.dart';
import 'package:test/test.dart';

void main() {
  test(
    'compresses an oversized photo in place, keeping name and format',
    () async {
      final result = await _run({
        'files': [
          {'name': 'scan.JPG', 'type': 'image/jpeg', 'size': 12 * 1024 * 1024},
        ],
        'width': 4000,
        'height': 3000,
      });

      expect(result['stopped'], isTrue);
      expect(result['replayed'], ['input', 'change']);
      final files = result['files'] as List;
      expect(files.single['name'], 'scan.JPG');
      expect(files.single['type'], 'image/jpeg');
      expect(files.single['size'], lessThanOrEqualTo(4700000));
      expect(result['status'], contains('5MB以下に圧縮しました'));
    },
  );

  test('keeps PNG files as PNG', () async {
    final result = await _run({
      'files': [
        {'name': 'diagram.png', 'type': 'image/png', 'size': 9000000},
      ],
      'width': 3000,
      'height': 3000,
    });

    final file = (result['files'] as List).single;
    expect(file['name'], 'diagram.png');
    expect(file['type'], 'image/png');
    expect(file['size'], lessThanOrEqualTo(4700000));
  });

  test('compresses files above 5,000,000 bytes, even below 5 MiB', () async {
    final result = await _run({
      'files': [
        {'name': 'scan.jpg', 'type': 'image/jpeg', 'size': 5000001},
      ],
      'width': 2000,
      'height': 2000,
    });
    expect(result['stopped'], isTrue);
    expect(result['files'].single['size'], lessThanOrEqualTo(4700000));
  });

  test('requests the PDF libraries from the app', () async {
    final result = await _run({
      'channel': true,
      'files': [
        {'name': 'report.pdf', 'type': 'application/pdf', 'size': 8000000},
      ],
    });

    expect(result['stopped'], isTrue);
    expect(result['channelMessages'], ['pdf']);
    expect(result['status'], contains('PDFを圧縮しています'));
  });

  test('keeps a PDF above the safe input limit without starting a worker', () async {
    final result = await _run({
      'files': [
        {'name': 'large.pdf', 'type': 'application/pdf', 'size': 64 * 1024 * 1024 + 1},
      ],
      'pdf': <String, Object?>{},
    });
    expect(result['originalsKept'], isTrue);
    expect(result['workerCreated'], 0);
    expect(result['status'], contains('64 MiB'));
  });

  test('does not start a second PDF compression while another is running', () async {
    final result = await _run({
      'files': [_pdf],
      'pdf': <String, Object?>{},
      'pdfAlreadyRunning': true,
    });
    expect(result['originalsKept'], isTrue);
    expect(result['workerCreated'], 0);
    expect(result['status'], contains('別のPDFを圧縮中'));
  });

  test('cancelled PDF reads do not overlap a reselected file', () async {
    final result = await _run({
      'files': [_pdf],
      'nextFiles': [_pdf],
      'pdf': <String, Object?>{},
      'holdPdfRead': true,
    });
    expect(result['pdfReadCount'], 1);
    expect(result['maxPdfReads'], 1);
    expect(result['workerCreated'], 0);
    expect(result['files'].single['size'], 8000000);
  });

  test('requests JSZip for Word files', () async {
    final result = await _run({
      'channel': true,
      'files': [
        {'name': 'report.docx', 'type': '', 'size': 8000000},
      ],
    });

    expect(result['channelMessages'], ['office']);
  });

  test('terminates a stalled PDF worker on timeout', () async {
    final result = await _run({
      'files': [_pdf],
      'pdf': {'hold': true},
      'compressionTimeout': true,
    });
    expect(result['workerTerminated'], 1);
    expect(result['pending'], isFalse);
    expect(result['originalsKept'], isTrue);
    expect(result['consoleRestored'], isTrue);
  });

  test(
    'a cancelled PDF never starts a worker after libraries load late',
    () async {
      final result = await _run({
        'files': [_pdf],
        'pdf': <String, Object?>{},
        'channel': true,
        'latePdfLibrary': true,
        'nextFiles': [_photo],
      });
      expect(result['workerCreated'], 0);
      expect(result['files'].single['name'], 'scan.jpg');
    },
  );

  test(
    'bounds real Office archive expansion and preserves normal content',
    () async {
      for (final bomb in [false, true]) {
        final result = await _run({
          'files': [
            {'name': 'report.docx', 'type': '', 'size': 8000000},
          ],
          'realOffice': true,
          'officeBomb': bomb,
        });
        expect(result['originalsKept'], bomb);
        if (bomb) {
          expect(result['status'], contains('大きすぎます'));
        } else {
          expect(result['officeContent'], 'normal office content');
          expect(result['status'], contains('5MB以下に圧縮しました'));
        }
      }
    },
  );

  test('rejects ZIP64 directory metadata before invoking JSZip', () async {
    final result = await _run({
      'files': [
        {'name': 'report.docx', 'type': '', 'size': 8000000},
      ],
      'realOffice': true,
      'officeZip64': true,
    });
    expect(result['originalsKept'], isTrue);
    expect(result['officeParseCalls'], 0);
    expect(result['status'], contains('ZIP構造'));
  });

  test('rejects oversized image dimensions before invoking the decoder', () async {
    final result = await _run({
      'files': [
        {'name': 'photo.png', 'type': 'image/png', 'size': 8000000},
      ],
      'headerWidth': 10001,
    });
    expect(result['originalsKept'], isTrue);
    expect(result['bitmapCalls'], 0);
    expect(result['status'], contains('ピクセル数'));
  });

  test('keeps the original file when the libraries are unavailable', () async {
    final result = await _run({
      'files': [
        {'name': 'report.pdf', 'type': 'application/pdf', 'size': 8000000},
      ],
    });

    expect(result['stopped'], isTrue);
    expect(result['replayed'], ['input', 'change']);
    expect((result['files'] as List).single['size'], 8000000);
    expect(result['status'], contains('圧縮できませんでした'));
  });

  test('explains formats it cannot compress', () async {
    final result = await _run({
      'files': [
        {'name': 'data.zip', 'type': 'application/zip', 'size': 8000000},
      ],
    });

    expect(result['stopped'], isFalse);
    expect(result['status'], contains('この形式は自動で圧縮できません'));
  });

  test('ignores files that already fit', () async {
    final result = await _run({
      'files': [
        {'name': 'small.png', 'type': 'image/png', 'size': 1024},
      ],
    });

    expect(result['stopped'], isFalse);
    expect(result['status'], isNull);
  });

  test('teardown stops compressing', () async {
    final result = await _run({
      'teardownFirst': true,
      'files': [
        {'name': 'scan.jpg', 'type': 'image/jpeg', 'size': 12 * 1024 * 1024},
      ],
    });

    expect(result['stopped'], isFalse);
    expect((result['files'] as List).single['size'], 12 * 1024 * 1024);
  });

  test(
    'disabling during compression discards completion and releases submit',
    () async {
      for (final teardown in [false, true]) {
        for (final failure in [false, true]) {
          final result = await _run({
            'files': [_photo],
            'holdImage': true,
            'imageError': failure,
            'disableDuringPending': true,
            'useTeardown': teardown,
            'checkSubmission': true,
          });
          expect(result['originalsKept'], isTrue);
          expect(result['replayed'], isEmpty);
          expect(result['status'], result['statusAfterDisable']);
          expect(result['blockedWhenDisabled'], [false, false, false, false]);
          expect(result['blockedAfter'], [false, false, false, false]);
          expect(result['pending'], isFalse);
        }
      }
    },
  );

  test(
    're-enabling compression never revives a job cancelled by teardown',
    () async {
      for (final failure in [false, true]) {
        final result = await _run({
          'files': [_photo],
          'holdImage': true,
          'imageError': failure,
          'disableDuringPending': true,
          'useTeardown': true,
          'reenableDuringPending': true,
          'checkSubmission': true,
        });
        expect(result['originalsKept'], isTrue);
        expect(result['replayed'], isEmpty);
        expect(result['status'], isNull);
        expect(result['blockedAfterReenable'], [false, false, false, false]);
        expect(result['pending'], isFalse);
      }
    },
  );

  for (final failure in [false, true]) {
    test('discards stale image ${failure ? 'failure' : 'result'}', () async {
      final result = await _run({
        'files': [_photo],
        'holdImage': true,
        'imageError': failure,
        'nextFiles': [
          {'name': 'new.pdf', 'type': 'application/pdf', 'size': 1000},
        ],
      });
      expect((result['files'] as List).single['name'], 'new.pdf');
      expect(result['replayed'], isEmpty);
      expect(result['status'], isEmpty);
    });
  }

  test(
    'selection token invalidates work even for the same File object',
    () async {
      final result = await _run({
        'files': [_photo],
        'holdImage': true,
        'reselectSameFiles': true,
        'teardownBeforeReselect': true,
      });
      expect(result['originalsKept'], isTrue);
      expect(result['replayed'], isEmpty);
    },
  );

  test(
    'checks the original File identity even without a change event',
    () async {
      final result = await _run({
        'files': [_photo],
        'holdImage': true,
        'nextFiles': [_photo],
        'replaceWithoutChange': true,
      });
      expect((result['files'] as List).single['size'], _photo['size']);
      expect(result['replayed'], isEmpty);
    },
  );

  test('cancelling the selection discards an in-flight result', () async {
    final result = await _run({
      'files': [_photo],
      'holdImage': true,
      'nextFiles': <Object?>[],
    });
    expect(result['files'], isEmpty);
    expect(result['replayed'], isEmpty);
    expect(result['status'], isEmpty);
  });

  test(
    'removes timed-out waiters and requests libraries on the next pick',
    () async {
      final result = await _run({
        'files': [_pdf],
        'channel': true,
        'timeoutLibrary': true,
        'pdf': <String, Object?>{},
      });
      expect(result['channelMessages'], ['pdf', 'pdf']);
      expect(result['originalsKept'], isFalse);
      expect(result['status'], contains('5MB以下に圧縮しました'));
    },
  );

  test('replaces a PDF only when the worker succeeds', () async {
    final result = await _run({
      'files': [_pdf],
      'pdf': <String, Object?>{},
    });
    expect(result['originalsKept'], isFalse);
    expect(result['files'].single['name'], 'report.pdf');
    expect(result['status'], contains('5MB以下に圧縮しました'));
    expect(result['workerTerminated'], 1);
  });

  test('preserves all selected originals when PDF compression fails', () async {
    final result = await _run({
      'files': [_photo, _pdf],
      'pdf': {'error': '署名付きPDFは圧縮できません'},
    });
    expect(result['originalsKept'], isTrue);
    expect(result['status'], contains('署名付きPDF'));
    expect(result['replayed'], ['input', 'change']);
  });

  test('blocks only the busy form until success, error, or timeout', () async {
    for (final outcome in ['success', 'error', 'timeout']) {
      final result = await _run({
        'files': [_photo],
        'holdImage': true,
        'imageError': outcome == 'error',
        'compressionTimeout': outcome == 'timeout',
        'checkSubmission': true,
      });
      expect(result['blockedDuring'], [
        true,
        true,
        true,
        true,
      ], reason: outcome);
      expect(result['unrelatedBlocked'], [false, false]);
      expect(result['pendingStatus'], 'ファイルを圧縮しています。完了してから提出してください');
      expect(result['blockedAfter'], [false, false, false, false]);
      expect(result['listenerCounts'], {'change': 1, 'submit': 1, 'click': 1});
      expect(result['listenersCapture'], isTrue);
      expect(result['autoSubmits'], 0);
      expect(result['originalsKept'], outcome != 'success');
      expect(
        result['status'],
        contains(outcome == 'success' ? '5MB以下に圧縮しました' : '元のファイルのまま'),
      );
    }
  });

  test(
    'releases the submit hold before a replayed change handler submits',
    () async {
      for (final failure in [false, true]) {
        final result = await _run({
          'files': [_photo],
          'holdImage': true,
          'imageError': failure,
          'checkSubmission': true,
          'submitOnChange': true,
        });
        expect(result['stopped'], isTrue);
        expect(result['blockedDuring'], [true, true, true, true]);
        expect(result['submitsDuring'], 0);
        expect(result['replayed'], ['input', 'change']);
        expect(result['autoSubmits'], 1);
        expect(result['pendingOnChange'], isFalse);
        expect(result['pending'], isFalse);
        expect(result['blockedAfter'], [false, false, false, false]);
        expect(result['originalsKept'], failure);
      }
    },
  );

  test(
    'keeps only live submit hooks after 30 iframe document replacements',
    () async {
      final result = await _runNode([
        _iframeDocumentReplacementHarness,
        GakujoUploadCompressionScript.build(),
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    },
  );

  test(
    'blocks programmatic submits with either download hook install order',
    () async {
      final result = await _runNode([
        _programmaticSubmissionHarness,
        GakujoUploadCompressionScript.build(),
        GakujoUploadCompressionScript.buildTeardown(),
        GakujoDownloadCaptureScript.build(),
        GakujoDownloadCaptureScript.buildTeardown(),
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    },
  );
}

const _photo = {'name': 'scan.jpg', 'type': 'image/jpeg', 'size': 12000000};
const _pdf = {'name': 'report.pdf', 'type': 'application/pdf', 'size': 8000000};
Future<Map<String, dynamic>> _run(Map<String, Object?> scenario) async {
  final result = await _runNode(
    [
      _harness,
      GakujoUploadCompressionScript.build(),
      GakujoUploadCompressionScript.buildTeardown(),
      jsonEncode(scenario),
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const _harness = r'''
const vm = require('node:vm');
const [build, teardown, rawScenario] = process.argv.slice(1);
const scenario = JSON.parse(rawScenario);

class FakeFile {
  constructor(parts, name, options) {
    this.parts = parts;
    this.name = name;
    this.type = options && options.type || '';
    this.size = parts.reduce((sum, part) => sum + (part.size || part.byteLength), 0);
    this.lastModified = options && options.lastModified || 0;
  }
}

class FakeDataTransfer {
  constructor() {
    const list = [];
    this.files = list;
    this.items = { add: (file) => list.push(file) };
  }
}

const listeners = [];
const documentListeners = { change: [], submit: [], click: [] };
const replayed = [];
let statusNode = null;
let pdfReadCount = 0, activePdfReads = 0, maxPdfReads = 0;
let releasePdfRead;
const pdfReadGate = new Promise(resolve => { releasePdfRead = resolve; });
function filesFor(files) {
  const header = Uint8Array.from([
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
const input = {
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
const originalFiles = input.files.slice();
let autoSubmits = 0;
class FakeForm {
  constructor() { this.tagName = 'FORM'; this.elements = [input]; }
  submit() { autoSubmits++; }
  requestSubmit() { autoSubmits++; }
}
const form = new FakeForm();
input.form = form;
let pendingOnChange;
if (scenario.submitOnChange) input.onchange = () => {
  pendingOnChange = !!input.__mbgUploadCompressionPending;
  form.submit();
};
const submitButton = { tagName: 'BUTTON', form };
const submitInput = { tagName: 'INPUT', type: 'submit', form };
const imageInput = { tagName: 'INPUT', type: 'image', form };
const submissionTargets = [
  ['submit', form],
  ['click', { tagName: 'SPAN', parentNode: submitButton }],
  ['click', submitInput],
  ['click', imageInput],
];
function attemptSubmission(type, target) {
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
const document = {
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
      const canvas = {
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
          const size = Math.round(canvas.width * canvas.height * perPixel);
          callback({ type, size: imageData === 'emptyBlob' ? 0 : size,
            arrayBuffer: async () => imageData === 'missingBytes' ? null :
              new ArrayBuffer(imageData === 'emptyBytes' ? 0 : size),
          });
        },
      };
      return canvas;
    }
    const node = {
      style: {},
      isConnected: true,
      setAttribute() {},
      remove() { node.isConnected = false; statusNode = null; },
    };
    statusNode = node;
    return node;
  },
};
const parentNode = { insertBefore: () => {} };
input.parentNode = parentNode;
input.ownerDocument = document;

let finishImage;
const imageGate = new Promise(resolve => { finishImage = resolve; });
const timers = new Map();
let nextTimer = 0;
let workerTerminated = 0;
let workerCreated = 0;
let officeParseCalls = 0;
let bitmapCalls = 0;
const savedConsole = { log() {}, warn() {}, error() {} };
const pdfWarnings = [];
if (scenario.realPdf) savedConsole.log = (...args) => pdfWarnings.push(args.join(' '));
// A valid 1x1 white JPEG stands in for canvas encoding. Parsing, page checks,
// vector rendering, worker setup, JPEG embedding and PDF writing use the assets.
const jpeg = Buffer.from('/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD9U6KKKAP/2Q==', 'base64');
const context = {
  console: { ...savedConsole },
  document,
  File: FakeFile,
  DataTransfer: FakeDataTransfer,
  HTMLFormElement: FakeForm,
  Event: class {
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
  function warning(stage) {
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
const channelMessages = [];
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
const event = {
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
    const zip = new context.JSZip();
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
  const { Worker: NodeWorker } = require('node:worker_threads');
  const workerSource = require('node:fs').readFileSync('assets/js/upload_compression/pdf.worker.min.js', 'utf8');
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
    const fs = require('node:fs');
    for (const name of ['pdf.worker.min.js', 'pdf.min.js', 'pdf-lib.min.js']) {
      const source = fs.readFileSync(`assets/js/upload_compression/${name}`, 'utf8');
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
        const task = getDocument(options);
        task.promise.then(pdf => {
          const getPage = pdf.getPage.bind(pdf);
          pdf.getPage = async number => {
            const page = await getPage(number);
            const render = page.render.bind(page);
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
    for (const [id, fn] of Array.from(timers)) { timers.delete(id); fn(); }
    await settle();
    for (const listener of listeners) listener(event);
  }
  if (scenario.compressionTimeout) {
    for (const [id, fn] of Array.from(timers)) { timers.delete(id); fn(); }
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
    files: Array.from(input.files).map((f) => ({
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
    listenerCounts: Object.fromEntries(Object.entries(documentListeners)
      .map(([type, handlers]) => [type, handlers.length])),
    listenersCapture: Object.values(documentListeners).flat().every(({ capture }) => capture === true),
    autoSubmits, submitsDuring, pendingOnChange,
  }));
})().catch(error => { console.error(error); process.exit(1); });
''';

const _iframeDocumentReplacementHarness = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const [upload] = process.argv.slice(1);

function makeDocument() {
  return {
    defaultView: {HTMLFormElement: class {
      submit() {}
      requestSubmit() {}
    }},
    addEventListener() {},
    querySelectorAll(selector) {
      return this === top && selector === 'iframe,frame' ? [iframe] : [];
    },
  };
}
const top = makeDocument();
const iframe = {contentWindow: {document: makeDocument()}};
const window = {setInterval() { return 1; }};
const context = vm.createContext({window, document: top});
vm.runInContext(upload, context);

function checkHooks() {
  const liveDocuments = [top, iframe.contentWindow.document];
  const hooks = window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES;
  assert.equal(hooks.length, liveDocuments.length * 2);
  for (const doc of liveDocuments) {
    for (const method of ['submit', 'requestSubmit']) {
      assert.equal(hooks.filter(entry =>
        entry.prototype === doc.defaultView.HTMLFormElement.prototype &&
        entry.method === method).length, 1);
    }
  }
}
checkHooks();
for (let i = 0; i < 30; i++) {
  iframe.contentWindow.document = makeDocument();
  window.__MBG_UPLOAD_COMPRESSION_UPDATE();
  checkHooks();
}
''';

const _programmaticSubmissionHarness = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const [upload, stopUpload, download, stopDownload] = process.argv.slice(1);

for (const uploadFirst of [true, false]) {
  for (const stopUploadFirst of [true, false]) {
    const calls = [], captured = [], result = {};
    function makeDocument() {
      const doc = {
        baseURI: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/page.do',
        inputs: [], statuses: [], listeners: new Map(),
        defaultView: {HTMLFormElement: class {
          submit(...args) { calls.push({form: this, args, method: 'submit'}); return result; }
          requestSubmit(...args) { calls.push({form: this, args, method: 'requestSubmit'}); return result; }
        }},
        addEventListener(type, fn) {
          const handlers = doc.listeners.get(type) || new Set();
          handlers.add(fn); doc.listeners.set(type, handlers);
        },
        removeEventListener(type, fn) { doc.listeners.get(type)?.delete(fn); },
        querySelectorAll(selector) {
          if (selector === 'input[type="file"]') return doc.inputs;
          if (selector === 'iframe,frame') return doc === top ? [{contentWindow: frame}] : [];
          return selector.includes('upload-compression-owned') ? doc.statuses : [];
        },
        createElement() {
          const node = {style: {}, isConnected: true, setAttribute() {},
            remove() { node.isConnected = false; }};
          doc.statuses.push(node); return node;
        },
      };
      return doc;
    }
    const top = makeDocument(), child = makeDocument();
    const frame = {document: child, frames: []};
    let refreshUpload;
    const window = {document: top, frames: [frame], location: {href: top.baseURI},
      setInterval(fn) { refreshUpload = fn; return 1; },
      MoreBetterGakujoDownloads: {postMessage(value) { captured.push(JSON.parse(value)); }}};
    const context = vm.createContext({window, document: top, URL,
      FormData: class { forEach() {} }});
    const run = script => vm.runInContext(script, context);
    const originals = [top, child].map(doc => ({
      submit: doc.defaultView.HTMLFormElement.prototype.submit,
      requestSubmit: doc.defaultView.HTMLFormElement.prototype.requestSubmit}));
    function makeForm(doc) {
      const input = {tagName: 'INPUT', type: 'file', ownerDocument: doc,
        parentNode: {insertBefore() {}}};
      const form = Object.assign(new doc.defaultView.HTMLFormElement(), {
        tagName: 'FORM', elements: [input], ownerDocument: doc, action: 'campussquare.do',
        getAttribute(name) { return name === 'action' ? this.action : null; },
        querySelectorAll() { return []; },
      });
      doc.inputs.push(input);
      return form;
    }
    const forms = [makeForm(top), makeForm(child)];
    function checkSubmissions() {
      for (const form of forms) {
        const input = form.elements[0];
        for (const method of ['submit', 'requestSubmit']) {
          input.__mbgUploadCompressionPending = 1;
          const args = [];
          const button = {tagName: 'BUTTON', type: 'button', form,
            onclick() { return form[method](...args); }};
          if (method === 'submit') args.push(button);
          const before = calls.length;
          for (const listener of form.ownerDocument.listeners.get('click')) {
            listener({type: 'click', target: button,
              preventDefault() { assert.fail('type=button must reach its page handler'); }});
          }
          assert.equal(button.onclick(), undefined);
          assert.equal(calls.length, before);
          assert.equal(input.__mbgUploadCompressionStatus.textContent,
            'ファイルを圧縮しています。完了してから提出してください');
          const other = makeForm(form.ownerDocument);
          assert.equal(other[method](...args), result);
          assert.equal(calls.at(-1).form, other);
          delete input.__mbgUploadCompressionPending;
          assert.equal(calls.length, before + 1, 'completion must never submit automatically');
          assert.equal(button.onclick(), result);
          assert.equal(calls.length, before + 2);
          assert.equal(calls.at(-1).form, form);
          assert.deepEqual(calls.at(-1).args, args);
          assert.equal(calls.at(-1).method, method);
        }
      }
      assert.equal(captured.length, 0);
      assert.equal(window.__MBG_UPLOAD_COMPRESSION_SUBMIT_PROTOTYPES.length, 4);
    }
    for (const script of uploadFirst ? [upload, download] : [download, upload]) run(script);
    checkSubmissions();
    run(download); run(upload); run(download); run(upload);
    checkSubmissions();
    if (stopUploadFirst) {
      run(stopUpload);
      refreshUpload();
      forms[0].action = 'campussquare.do?_eventId=download';
      forms[0].submit();
      assert.equal(captured.length, 1, 'download hook must survive upload teardown');
      forms[0].action = 'campussquare.do';
      captured.length = 0;
      run(upload);
      checkSubmissions();
      run(stopUpload); run(stopDownload);
    } else {
      run(stopDownload);
      forms[0].action = 'campussquare.do?_eventId=download';
      assert.equal(forms[0].submit(), result, 'download teardown must remove nested capture');
      assert.equal(captured.length, 0);
      forms[0].action = 'campussquare.do';
      checkSubmissions();
      run(stopUpload);
    }
    run(stopUpload); run(stopDownload);
    refreshUpload();
    for (const [index, doc] of [top, child].entries()) {
      for (const method of ['submit', 'requestSubmit']) {
        assert.equal(doc.defaultView.HTMLFormElement.prototype[method], originals[index][method]);
      }
    }
  }
}
''';

/// Runs a node harness with its arguments passed through temp files: the
/// scripts exceed Windows' command-line length limit when inlined.
Future<ProcessResult> _runNode(
  List<String> harnessAndArgs, {
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) async {
  final dir = Directory.systemTemp.createTempSync('gakujo_upload_compression_');
  try {
    final paths = <String>[];
    for (var i = 0; i < harnessAndArgs.length; i += 1) {
      final file = File('${dir.path}${Platform.pathSeparator}arg$i.txt')
        ..writeAsStringSync(harnessAndArgs[i]);
      paths.add(file.path);
    }
    final wrapper = File('${dir.path}${Platform.pathSeparator}run.js')
      ..writeAsStringSync(
        "const fs = require('fs');\n"
        "const [harness, ...args] = process.argv.slice(2)\n"
        "  .map((path) => fs.readFileSync(path, 'utf8'));\n"
        "process.argv = [process.argv[0], ...args];\n"
        'eval(harness);\n',
      );
    return await Process.run(
      'node',
      [wrapper.path, ...paths],
      stdoutEncoding: stdoutEncoding ?? utf8,
      stderrEncoding: stderrEncoding ?? utf8,
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}
