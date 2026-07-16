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
  ]);

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
  }
}[feature];

if (!featureConfig) throw new Error(`Unknown feature: ${feature}`);

class FakeElement {
  constructor(tag) {
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
    if (this.listeners.click) this.listeners.click();
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

function createMessageTable() {
  return {
    rows: [
      {},
      {
        querySelector(selector) {
          if (selector !== 'a[href]') return null;
          return {getAttribute() { return '/campusweb/message/1'; }};
        }
      }
    ]
  };
}

function createPage() {
  let nextIntervalId = 1;
  const activeIntervals = new Set();
  const target = new FakeElement('div');
  target.id = 'tabmenutable';
  const body = new FakeElement('body');
  const reportTable = createReportTable();
  const messageTable = createMessageTable();
  const timeoutTimer = {textContent: '20'};
  const extendButton = {click() {}};

  const document = {
    body,
    createElement(tag) { return new FakeElement(tag); },
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
    reload() {}
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
    setTimeout(callback) { callback(); return 1; }
  };
  window.window = window;

  const context = {
    window,
    document,
    location,
    URL,
    console: {log() {}}
  };

  function snapshot() {
    return {
      activeIntervalCount: activeIntervals.size,
      ownedElementCount: document.querySelectorAll(
        featureConfig.ownedSelector
      ).length,
      controlIds: target.children.map((child) => child.id),
      globalMarkers: Object.keys(window)
        .filter((key) => key.startsWith(featureConfig.markerPrefix))
        .sort()
    };
  }

  return {context, snapshot};
}

function run(script, page) {
  vm.runInNewContext(script, page.context);
}

const injectedPage = createPage();
run(buildScript, injectedPage);
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
''';
