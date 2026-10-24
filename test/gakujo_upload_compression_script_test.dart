import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_upload_compression_script.dart';
import 'package:test/test.dart';

void main() {
  test('compresses an oversized photo in place, keeping name and format',
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
  });

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

  test('requests JSZip for Word files', () async {
    final result = await _run({
      'channel': true,
      'files': [
        {'name': 'report.docx', 'type': '', 'size': 8000000},
      ],
    });

    expect(result['channelMessages'], ['office']);
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

  test('selection token invalidates work even for the same File object',
      () async {
    final result = await _run({
      'files': [_photo],
      'holdImage': true,
      'reselectSameFiles': true,
      'teardownBeforeReselect': true,
    });
    expect(result['originalsKept'], isTrue);
    expect(result['replayed'], isEmpty);
  });

  test('checks the original File identity even without a change event',
      () async {
    final result = await _run({
      'files': [_photo],
      'holdImage': true,
      'nextFiles': [_photo],
      'replaceWithoutChange': true,
    });
    expect((result['files'] as List).single['size'], _photo['size']);
    expect(result['replayed'], isEmpty);
  });

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

  test('removes timed-out waiters and requests libraries on the next pick',
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
  });

  test('compresses a PDF whose text and content checks pass', () async {
    final result = await _run({
      'files': [_pdf],
      'pdf': <String, Object?>{}
    });
    expect(result['originalsKept'], isFalse);
    expect((result['files'] as List).single['name'], 'report.pdf');
    expect(result['status'], contains('5MB以下に圧縮しました'));
    expect(result['pdfOptions']['verbosity'], 1);
    expect(result['pdfOptions']['stopAtErrors'], isTrue);
    expect(result['destroyed'], 1);
    expect(result['consoleRestored'], isTrue);
  });

  for (final stage in ['load', 'text', 'operators', 'render', 'destroy']) {
    test('keeps the PDF when $stage warns about a font or CMap', () async {
      final result = await _run({
        'files': [_pdf],
        'pdf': {'warningStage': stage},
      });
      expect(result['originalsKept'], isTrue);
      expect(result['status'], _pdfTextMessage);
      expect(result['replayed'], ['input', 'change']);
      expect(result['destroyed'], 1);
      expect(result['consoleRestored'], isTrue);
    });
  }

  for (final level in ['warn', 'error']) {
    test('observes console.$level for font failures', () async {
      final result = await _run({
        'files': [_pdf],
        'pdf': {'warningStage': 'load', 'warningLevel': level},
      });
      expect(result['originalsKept'], isTrue);
      expect(result['status'], _pdfTextMessage);
    });
  }

  test('keeps a PDF with extracted text but no text drawing operators',
      () async {
    final result = await _run({
      'files': [_pdf],
      'pdf': {'noTextDrawing': true},
    });
    expect(result['originalsKept'], isTrue);
    expect(result['status'], _pdfTextMessage);
    expect(result['pdfRenderCount'], 0);
  });

  test('still compresses image-only PDFs', () async {
    final result = await _run({
      'files': [_pdf],
      'pdf': {'noTextDrawing': true, 'noText': true},
    });
    expect(result['originalsKept'], isFalse);
    expect(result['status'], contains('5MB以下に圧縮しました'));
  });

  test('keeps all originals when a PDF in a multiple selection is unsafe',
      () async {
    final result = await _run({
      'files': [_photo, _pdf],
      'pdf': {'warningStage': 'load'},
    });
    expect(result['originalsKept'], isTrue);
    expect(result['status'], _pdfTextMessage);
  });

  test('keeps PDFs with notes, markup, and other non-Link annotations',
      () async {
    for (final subtype in [
      'Text',
      'FreeText',
      'Ink',
      'Highlight',
      'Square',
      'Stamp',
      'Popup',
    ]) {
      final result = await _run({
        'files': [_pdf],
        'pdf': {
          'annotations': [
            {'subtype': subtype}
          ]
        },
      });
      expect(result['originalsKept'], isTrue, reason: subtype);
      expect(result['status'], contains('元のファイルのままにしました'));
      expect(result['pdfRenderCount'], 0);
      expect(result['destroyed'], 1);
    }
  });

  test('keeps PDFs with decoder diagnostics or missing page image data',
      () async {
    for (final options in [
      for (final level in ['log', 'warn', 'error'])
        {
          'warningStage': 'render',
          'warningLevel': level,
          'warningMessage': 'Warning: Unable to decode image: JpxError',
        },
      {
        'warningStage': 'render',
        'warningMessage': 'Error: Invalid image data',
      },
      for (final imageData in [
        'missingBlob',
        'emptyBlob',
        'missingBytes',
        'emptyBytes'
      ])
        {'imageData': imageData},
    ]) {
      final result = await _run({
        'files': [_pdf],
        'pdf': options
      });
      expect(result['originalsKept'], isTrue, reason: '$options');
      expect(result['status'], contains('元のファイルのまま'));
      expect(result['pdfEmbedCount'], 0);
      expect(result['destroyed'], 1);
      expect(result['consoleRestored'], isTrue);
    }
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
      expect(result['blockedDuring'], [true, true, true, true],
          reason: outcome);
      expect(result['unrelatedBlocked'], [false, false]);
      expect(result['pendingStatus'], 'ファイルを圧縮しています。完了してから提出してください');
      expect(result['blockedAfter'], [false, false, false, false]);
      expect(result['listenerCounts'], {'change': 1, 'submit': 1, 'click': 1});
      expect(result['listenersCapture'], isTrue);
      expect(result['autoSubmits'], 0);
      expect(result['originalsKept'], outcome != 'success');
      expect(result['status'],
          contains(outcome == 'success' ? '5MB以下に圧縮しました' : '元のファイルのまま'));
    }
  });

  for (final content in ['attachments', 'fields', 'link', 'widget']) {
    test('keeps the original PDF with $content', () async {
      final result = await _run({
        'files': [_pdf],
        'pdf': {content: true},
      });
      expect(result['originalsKept'], isTrue);
      expect(result['status'], contains('添付ファイル・フォーム・リンク・注釈を保持できない'));
      expect(result['status'], contains('元のファイルのままにしました'));
      expect(result['pdfRenderCount'], 0);
      expect(result['destroyed'], 1);
    });
  }
}

const _photo = {'name': 'scan.jpg', 'type': 'image/jpeg', 'size': 12000000};
const _pdf = {'name': 'report.pdf', 'type': 'application/pdf', 'size': 8000000};
const _pdfTextMessage =
    'PDFの文字が正しく変換できないため、元のファイルのままにしました（5MBを超える場合は提出前に容量を減らしてください）';

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
function filesFor(files) {
  return files.map((f) => Object.assign({
    lastModified: 1, arrayBuffer: async () => new ArrayBuffer(16),
  }, f));
}
const input = {
  tagName: 'INPUT',
  type: 'file',
  files: filesFor(scenario.files),
  getAttribute: (name) => name === 'accept' ? (scenario.accept || null) : null,
  dispatchEvent: (event) => {
    replayed.push(event.type);
    for (const listener of listeners) listener(event);
  },
};
const originalFiles = input.files.slice();
let autoSubmits = 0;
const form = {
  tagName: 'FORM', elements: [input],
  submit() { autoSubmits++; }, requestSubmit() { autoSubmits++; },
};
input.form = form;
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
        getContext: () => ({ fillRect() {}, drawImage() {} }),
        toBlob: (callback, type, quality) => {
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
const savedConsole = { log() {}, warn() {}, error() {} };
const context = {
  console: { ...savedConsole },
  document,
  File: FakeFile,
  DataTransfer: FakeDataTransfer,
  Event: class { constructor(type) { this.type = type; } },
  WeakSet,
  Promise,
  Math,
  Date,
  createImageBitmap: async () => {
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
  Uint8Array,
};
let pdfOptions;
let pdfRenderCount = 0;
let pdfEmbedCount = 0;
let destroyed = 0;
function loadPdfLibraries() {
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
    OPS: { showText: 44, showSpacedText: 45, nextLineShowText: 46, nextLineSetSpacingShowText: 47 },
    getDocument: (params) => {
      pdfOptions = { verbosity: params.verbosity, stopAtErrors: params.stopAtErrors };
      warning('load');
      return {
        destroy: async () => { destroyed++; warning('destroy'); },
        promise: Promise.resolve({
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
if (scenario.pdf && !scenario.timeoutLibrary) loadPdfLibraries();
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
for (const listener of listeners) listener(event);

async function settle() {
  await new Promise(resolve => setImmediate(resolve));
}
(async () => {
  await settle();
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
  if (scenario.nextFiles || scenario.reselectSameFiles) {
    if (scenario.teardownBeforeReselect) vm.runInContext(teardown, context);
    if (scenario.nextFiles) input.files = filesFor(scenario.nextFiles);
    if (!scenario.replaceWithoutChange) {
      for (const listener of listeners) listener(event);
    }
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
  process.stdout.write(JSON.stringify({
    stopped,
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
    consoleRestored: Object.keys(savedConsole).every(key => context.console[key] === savedConsole[key]),
    blockedDuring, unrelatedBlocked, pendingStatus,
    blockedAfter: scenario.checkSubmission &&
      submissionTargets.map(args => attemptSubmission(...args)),
    listenerCounts: Object.fromEntries(Object.entries(documentListeners)
      .map(([type, handlers]) => [type, handlers.length])),
    listenersCapture: Object.values(documentListeners).flat().every(({ capture }) => capture === true),
    autoSubmits,
  }));
})().catch(error => { console.error(error); process.exitCode = 1; });
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
