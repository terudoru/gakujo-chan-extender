import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_upload_compression_script.dart';
import 'package:test/test.dart';

void main() {
  test('compresses an oversized photo below the limit before the page sees it',
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
    expect(files.single['name'], 'scan.jpg');
    expect(files.single['type'], 'image/jpeg');
    expect(files.single['size'], lessThanOrEqualTo(4700000));
    expect(result['status'], contains('画像を圧縮しました'));
  });

  test('leaves oversized non-images to the page and explains why', () async {
    final result = await _run({
      'files': [
        {'name': 'report.pdf', 'type': 'application/pdf', 'size': 8000000},
      ],
    });

    expect(result['stopped'], isFalse);
    expect(result['replayed'], isEmpty);
    expect((result['files'] as List).single['name'], 'report.pdf');
    expect(result['status'], contains('画像以外は自動で圧縮できません'));
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

  test('keeps PNG when the input does not accept JPEG', () async {
    final result = await _run({
      'accept': '.png',
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

  test('teardown stops compressing and removes status messages', () async {
    final result = await _run({
      'teardownFirst': true,
      'files': [
        {'name': 'scan.jpg', 'type': 'image/jpeg', 'size': 12 * 1024 * 1024},
      ],
    });

    expect(result['stopped'], isFalse);
    expect((result['files'] as List).single['size'], 12 * 1024 * 1024);
  });
}

Future<Map<String, dynamic>> _run(Map<String, Object?> scenario) async {
  final result = await Process.run(
    'node',
    [
      '-e',
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
    this.size = parts.reduce((sum, part) => sum + part.size, 0);
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
const replayed = [];
let statusNode = null;
const input = {
  tagName: 'INPUT',
  type: 'file',
  files: scenario.files.map((f) => Object.assign({ lastModified: 1 }, f)),
  getAttribute: (name) => name === 'accept' ? (scenario.accept || null) : null,
  dispatchEvent: (event) => {
    replayed.push(event.type);
    for (const listener of listeners) listener(event);
  },
};
const document = {
  querySelectorAll: (selector) =>
    selector.indexOf('upload-compression-owned') >= 0 && statusNode
      ? [statusNode]
      : [],
  addEventListener: (type, listener) => {
    if (type === 'change') listeners.push(listener);
  },
  createElement: (tag) => {
    if (tag === 'canvas') {
      const canvas = {
        width: 0,
        height: 0,
        getContext: () => ({ fillRect() {}, drawImage() {} }),
        toBlob: (callback, type, quality) => {
          // A rough model: bytes scale with pixels, JPEG with quality.
          const perPixel = type === 'image/jpeg' ? 1.2 * (quality || 0.9) : 1.5;
          callback({ size: Math.round(canvas.width * canvas.height * perPixel) });
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

const context = {
  document,
  File: FakeFile,
  DataTransfer: FakeDataTransfer,
  Event: class { constructor(type) { this.type = type; } },
  WeakSet,
  Promise,
  Math,
  Date,
  createImageBitmap: () => Promise.resolve({
    width: scenario.width || 1000,
    height: scenario.height || 1000,
    close() {},
  }),
  setInterval: () => 1,
  clearInterval: () => {},
};
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

setTimeout(() => {
  process.stdout.write(JSON.stringify({
    stopped,
    replayed: replayed.filter((type) => type),
    files: Array.from(input.files).map((f) => ({
      name: f.name, type: f.type, size: f.size,
    })),
    status: statusNode ? statusNode.textContent : null,
  }));
}, 50);
''';
