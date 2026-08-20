import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<Map<String, dynamic>> evaluatePageScriptLifecycle({
  required String feature,
  required String buildScript,
  required String teardownScript,
}) async {
  final result = await Process.run('node', [
    '-e',
    _nodeDomHarness,
    feature,
    buildScript,
    teardownScript,
  ], stdoutEncoding: utf8, stderrEncoding: utf8);

  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> evaluateMessageReaderScript({
  required String buildScript,
  required List<int> fetchStatuses,
  List<bool> iframeOutcomes = const [],
}) async {
  final scenario = jsonEncode({
    'fetchStatuses': fetchStatuses,
    'iframeOutcomes': iframeOutcomes,
  });
  final result = await Process.run('node', [
    '-e',
    _nodeDomHarness,
    'message',
    buildScript,
    '',
    scenario,
  ], stdoutEncoding: utf8, stderrEncoding: utf8);

  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const _nodeDomHarness = r'''
const vm = require('node:vm');
const feature = process.argv[1];
const buildScript = process.argv[2];
const teardownScript = process.argv[3];
const scenario = process.argv[4] ? JSON.parse(process.argv[4]) : null;

const featureConfig = {
  session: {
    markerPrefix: '__MBG_SESSION_EXTENDER_',
    ownedSelector: '[data-mbg-session-extender-owned="true"]'
  },
  report: {
    markerPrefix: '__MBG_REPORT_SORTER_',
    ownedSelector: '[data-mbg-report-sorter-owned="true"]'
  },
  message: {
    markerPrefix: '__MBG_MESSAGE_READER_',
    ownedSelector: '[data-mbg-message-reader-owned="true"]'
  },
  gpa: {
    markerPrefix: '__MBG_GPA_DISPLAY_',
    ownedSelector: '.mbg-gpa-display'
  }
}[feature];

if (!featureConfig) throw new Error(`Unknown feature: ${feature}`);

class FakeElement {
  constructor(tag, onSetSource) {
    this.tagName = tag.toUpperCase();
    this.id = '';
    this.type = '';
    this.textContent = '';
    this.innerText = '';
    this.value = '';
    this.style = {};
    this.attributes = {};
    this.children = [];
    this.parentNode = null;
    this.listeners = {};
    if (onSetSource) {
      Object.defineProperty(this, 'src', {
        set(value) {
          this.source = value;
          onSetSource(this);
        }
      });
    }
  }

  setAttribute(name, value) {
    this.attributes[name] = String(value);
  }

  getAttribute(name) {
    return Object.prototype.hasOwnProperty.call(this.attributes, name)
      ? this.attributes[name]
      : null;
  }

  appendChild(child) {
    child.parentNode = this;
    this.children.push(child);
    return child;
  }

  remove() {
    if (!this.parentNode) return;
    const index = this.parentNode.children.indexOf(this);
    if (index >= 0) this.parentNode.children.splice(index, 1);
    this.parentNode = null;
  }

  addEventListener(type, callback) {
    this.listeners[type] = callback;
  }

  click() {
    if (this.listeners.click) return this.listeners.click();
  }
}

class FakeCell {
  constructor(text) {
    this.innerText = text;
    this.textContent = text;
    this.style = {};
  }
}

function findById(node, id) {
  if (!node) return null;
  if (node.id === id) return node;
  for (const child of node.children || []) {
    const match = findById(child, id);
    if (match) return match;
  }
  return null;
}

function findByAttribute(node, name, value, matches) {
  if (!node) return;
  if (node.getAttribute && node.getAttribute(name) === value) matches.push(node);
  for (const child of node.children || []) {
    findByAttribute(child, name, value, matches);
  }
}

function createReportTable() {
  const header = {cells: []};
  const row = {
    cells: [
      new FakeCell(''),
      new FakeCell('課題'),
      new FakeCell('一時保存'),
      new FakeCell('ABC123'),
      new FakeCell(''),
      new FakeCell(''),
      new FakeCell(''),
      new FakeCell('2099/12/31 23:59')
    ]
  };
  const table = {rows: [header, row]};
  table.tBodies = [{appendChild() {}}];
  return table;
}

function createMessageTable(messageCount) {
  const rows = [{}];
  for (let i = 1; i <= messageCount; i += 1) {
    rows.push({
        querySelector(selector) {
          if (selector !== 'a[href]') return null;
          return {
            getAttribute() { return `/campusweb/message/${i}`; }
          };
        }
      });
  }
  return {rows};
}

function createPage() {
  let nextIntervalId = 1;
  let nextTimeoutId = 1;
  let reloadCount = 0;
  let fetchCallCount = 0;
  let frameCallCount = 0;
  const activeIntervals = new Set();
  const activeTimeouts = new Map();
  const fetchStatuses = scenario ? [...scenario.fetchStatuses] : [200];
  const iframeOutcomes = scenario ? [...scenario.iframeOutcomes] : [];
  const target = new FakeElement('div');
  target.id = 'tabmenutable';
  const body = new FakeElement('body');
  const reportTable = createReportTable();
  const messageTable = createMessageTable(fetchStatuses.length);
  const timeoutTimer = {textContent: '20'};
  const extendButton = {click() {}};

  const document = {
    body,
    createElement(tag) {
      if (tag.toLowerCase() === 'iframe') {
        return new FakeElement(tag, (frame) => {
          frameCallCount += 1;
          const loaded = iframeOutcomes.shift() === true;
          if (loaded && frame.onload) frame.onload();
          if (!loaded && frame.onerror) frame.onerror();
        });
      }
      return new FakeElement(tag);
    },
    getElementById(id) {
      if (id === 'main-frame-if') return null;
      if (id === 'tabmenutable') return target;
      if (id === 'timeout-timer') return timeoutTimer;
      if (id === 'portaltimerimg') return extendButton;
      return findById(target, id) || findById(body, id);
    },
    querySelector(selector) {
      if (feature === 'report' &&
          selector === '#enqListForm table:nth-of-type(2)') {
        return reportTable;
      }
      if (feature === 'message' &&
          selector === 'table.normal:nth-child(9)') {
        return messageTable;
      }
      return null;
    },
    querySelectorAll(selector) {
      const match = selector.match(/^\[([^=]+)="([^"]+)"\]$/);
      if (!match) return [];
      const matches = [];
      findByAttribute(target, match[1], match[2], matches);
      findByAttribute(body, match[1], match[2], matches);
      return matches;
    }
  };

  const location = {
    href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
    reload() { reloadCount += 1; }
  };
  const window = {
    document,
    location,
    clearInterval(id) { activeIntervals.delete(id); },
    setInterval() {
      const id = nextIntervalId++;
      activeIntervals.add(id);
      return id;
    },
    setTimeout(callback) {
      const id = nextTimeoutId++;
      activeTimeouts.set(id, callback);
      return id;
    },
    clearTimeout(id) { activeTimeouts.delete(id); }
  };
  window.window = window;

  const context = {
    window,
    document,
    location,
    URL,
    fetch: async function() {
      fetchCallCount += 1;
      const status = fetchStatuses.shift();
      return {ok: status >= 200 && status < 300, status};
    },
    console: {log() {}}
  };

  function flushTimeouts() {
    const callbacks = [...activeTimeouts.values()];
    activeTimeouts.clear();
    for (const callback of callbacks) callback();
  }

  function snapshot() {
    return {
      activeIntervalCount: activeIntervals.size,
      activeTimeoutCount: activeTimeouts.size,
      ownedElementCount: document.querySelectorAll(
        featureConfig.ownedSelector
      ).length,
      controlIds: target.children.map((child) => child.id),
      statusText: (document.getElementById('mbg-read-status') || {}).textContent,
      statusOwned: document.getElementById('mbg-read-status')?.getAttribute(
        'data-mbg-message-reader-owned'
      ),
      reloadCount,
      fetchCallCount,
      frameCallCount,
      globalMarkers: Object.keys(window)
        .filter((key) => key.startsWith(featureConfig.markerPrefix))
        .sort()
    };
  }

  return {context, snapshot, flushTimeouts};
}

function run(script, page) {
  vm.runInNewContext(script, page.context);
}

async function main() {
  const injectedPage = createPage();
  run(buildScript, injectedPage);

  if (scenario) {
    const input = injectedPage.context.document.getElementById(
      'mbg-read-num-input'
    );
    input.value = String(scenario.fetchStatuses.length);
    await injectedPage.context.document.getElementById('mbg-read-button').click();
    injectedPage.flushTimeouts();
    process.stdout.write(JSON.stringify(injectedPage.snapshot()));
    return;
  }

  const afterBuild = injectedPage.snapshot();
  run(teardownScript, injectedPage);
  const afterTeardown = injectedPage.snapshot();
  run(buildScript, injectedPage);
  const afterRebuild = injectedPage.snapshot();

  const freshPage = createPage();
  run(teardownScript, freshPage);
  const teardownWithoutBuild = freshPage.snapshot();

  process.stdout.write(JSON.stringify({
    afterBuild,
    afterTeardown,
    afterRebuild,
    teardownWithoutBuild
  }));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
''';
