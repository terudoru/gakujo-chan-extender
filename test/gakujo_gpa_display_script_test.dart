import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_gpa_display_script.dart';
import 'package:test/test.dart';

void main() {
  test('builds a GPA display script for the grades table GP header', () {
    final script = GakujoGpaDisplayScript.build();

    expect(script, contains('__MBG_GPA_DISPLAY_VERSION'));
    expect(script, contains('__MBG_UPDATE_GPA_DISPLAY'));
    expect(script, contains('MutationObserver'));
    expect(script, contains("document.getElementById('main-frame-if')"));
    expect(script,
        contains("documentRef.querySelector('#taniReferListForm+table')"));
    expect(script, contains('headerCells[12]'));
    expect(script, contains('numberIndex: 0'));
    expect(script, contains('openNumberIndex: 3'));
    expect(script, contains('scoreIndex: 9'));
    expect(script, contains('unitIndex: 8'));
    expect(script, contains('gpIndex: 12'));
    expect(script, contains('function labelOf(element)'));
    expect(script, contains('function isNumberLabel(label)'));
    expect(script, contains('function isScoreLabel(label)'));
    expect(script, contains("label.indexOf('開講番号') >= 0"));
    expect(script, contains('scoreIndex = cellIndex'));
    expect(script, contains("label.indexOf('単位数') >= 0"));
    expect(script, contains("label === 'GP'"));
    expect(script, contains("labels.join('|').indexOf('科目')"));
    expect(script, contains("labels.join('|').indexOf('得点')"));
    expect(script, contains("labels.join('|').indexOf('評価')"));
    expect(script, contains('.toUpperCase()'));
    expect(script, contains("text.replace(/GPA:?\\d*(?:\\.\\d+)?/g, '')"));
    expect(script, contains("var text = 'GPA:' + gpa.toFixed(4)"));
    expect(script, contains('display && display.textContent === text'));
    expect(script, contains('weightedGp += credits * gp'));
    expect(script, contains('totalCredits += credits'));
    expect(script, contains('No.でソート'));
    expect(script, contains('開講番号でソート'));
    expect(script, contains('得点でソート'));
    expect(script, contains('function sortByNumber()'));
    expect(script, contains('function sortByOpenNumber()'));
    expect(script, contains('function sortByScore()'));
    expect(script, contains('function cellsForGradeRow(row, gradeTable)'));
    expect(script, contains('gradeTable.numberIndex'));
    expect(script, contains('gradeTable.openNumberIndex'));
    expect(script, contains('gradeTable.scoreIndex'));
    expect(script, isNot(contains('numberFromCell(a.cells[0])')));
    expect(script, isNot(contains('textOf(a.cells[3])')));
    expect(script, isNot(contains('numberFromCell(a.cells[9])')));
    expect(script, contains('gradeTable.headerRowIndex + 1'));
    expect(script, contains('__MBG_GPA_DISPLAY_INTERVAL'));
    expect(script, contains('.mbg-gpa-display'));
    expect(script, contains("display.style.background = 'transparent'"));
    expect(script, contains("display.style.border = '0'"));
    expect(script, contains("display.style.display = 'block'"));
  });

  test('teardown stops all runtime work and rebuilds exactly one UI', () async {
    final result = await _evaluateGpaDisplayLifecycle(
      buildScript: GakujoGpaDisplayScript.build(),
      teardownScript: GakujoGpaDisplayScript.buildTeardown(),
    );
    final afterBuild = result['afterBuild'] as Map<String, dynamic>;
    final afterTeardown = result['afterTeardown'] as Map<String, dynamic>;
    final afterRebuild = result['afterRebuild'] as Map<String, dynamic>;
    final teardownWithoutBuild =
        result['teardownWithoutBuild'] as Map<String, dynamic>;

    expect(afterBuild['activeIntervalCount'], 1);
    expect(afterBuild['activeTimeoutCount'], 4);
    expect(afterBuild['activeObserverCount'], 1);
    expect(afterBuild['ownedElementCount'], 4);
    expect(afterBuild['gpaDisplayCount'], 1);
    expect(afterBuild['controlIds'], [
      'mbg-grade-no-button',
      'mbg-grade-open-number-button',
      'mbg-grade-score-button',
    ]);

    expect(afterTeardown['activeIntervalCount'], 0);
    expect(afterTeardown['activeTimeoutCount'], 0);
    expect(afterTeardown['activeObserverCount'], 0);
    expect(afterTeardown['ownedElementCount'], 0);
    expect(afterTeardown['gpaDisplayCount'], 0);
    expect(afterTeardown['controlIds'], isEmpty);
    expect(afterTeardown['globalMarkers'], isEmpty);

    expect(afterRebuild['activeIntervalCount'], 1);
    expect(afterRebuild['activeTimeoutCount'], 4);
    expect(afterRebuild['activeObserverCount'], 1);
    expect(afterRebuild['ownedElementCount'], 4);
    expect(afterRebuild['gpaDisplayCount'], 1);
    expect(afterRebuild['controlIds'], hasLength(3));

    expect(teardownWithoutBuild['activeIntervalCount'], 0);
    expect(teardownWithoutBuild['activeTimeoutCount'], 0);
    expect(teardownWithoutBuild['activeObserverCount'], 0);
    expect(teardownWithoutBuild['ownedElementCount'], 0);
    expect(teardownWithoutBuild['globalMarkers'], isEmpty);
  });
}

Future<Map<String, dynamic>> _evaluateGpaDisplayLifecycle({
  required String buildScript,
  required String teardownScript,
}) async {
  final result = await Process.run('node', [
    '-e',
    _gpaDisplayDomHarness,
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

const _gpaDisplayDomHarness = r'''
const vm = require('node:vm');
const buildScript = process.argv[1];
const teardownScript = process.argv[2];

class FakeElement {
  constructor(tag, ownerDocument) {
    this.tagName = tag.toUpperCase();
    this.ownerDocument = ownerDocument;
    this.id = '';
    this.type = '';
    this.className = '';
    this.textContent = '';
    this.innerText = '';
    this.title = '';
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

  querySelector(selector) {
    return this.querySelectorAll(selector)[0] || null;
  }

  querySelectorAll(selector) {
    const matches = [];
    function visit(node) {
      for (const child of node.children || []) {
        if (matchesSelector(child, selector)) matches.push(child);
        visit(child);
      }
    }
    visit(this);
    return matches;
  }

  cloneNode(deep) {
    const clone = new FakeElement(this.tagName, this.ownerDocument);
    clone.id = this.id;
    clone.type = this.type;
    clone.className = this.className;
    clone.textContent = this.textContent;
    clone.innerText = this.innerText;
    clone.title = this.title;
    clone.attributes = {...this.attributes};
    if (deep) {
      for (const child of this.children) clone.appendChild(child.cloneNode(true));
    }
    return clone;
  }
}

function matchesSelector(element, selector) {
  if (selector.startsWith('.')) {
    return element.className.split(/\s+/).includes(selector.slice(1));
  }
  const attribute = selector.match(/^\[([^=]+)="([^"]+)"\]$/);
  return !!attribute && element.getAttribute(attribute[1]) === attribute[2];
}

function findById(root, id) {
  if (!root) return null;
  if (root.id === id) return root;
  for (const child of root.children || []) {
    const match = findById(child, id);
    if (match) return match;
  }
  return null;
}

function createPage() {
  let nextIntervalId = 1;
  let nextTimeoutId = 1;
  const activeIntervals = new Set();
  const activeTimeouts = new Map();
  const activeObservers = new Set();

  const document = {};
  const documentElement = new FakeElement('html', document);
  const body = new FakeElement('body', document);
  const target = new FakeElement('div', document);
  target.id = 'tabmenutable';
  documentElement.appendChild(body);
  body.appendChild(target);

  function cell(text) {
    const element = new FakeElement('td', document);
    element.innerText = text;
    element.textContent = text;
    return element;
  }
  const headerCells = Array.from({length: 13}, () => cell(''));
  headerCells[12].innerText = 'GP';
  headerCells[12].textContent = 'GP';
  const gradeCells = Array.from({length: 13}, () => cell(''));
  gradeCells[8].innerText = '2';
  gradeCells[8].textContent = '2';
  gradeCells[12].innerText = '4';
  gradeCells[12].textContent = '4';
  const rows = [{cells: headerCells}, {cells: gradeCells}];
  const table = {
    rows,
    tBodies: [{appendChild() {}}],
    querySelectorAll(selector) {
      return selector === 'tr' ? rows : [];
    }
  };

  function allRoots() {
    return [documentElement, ...headerCells, ...gradeCells];
  }

  document.body = body;
  document.documentElement = documentElement;
  document.createElement = (tag) => new FakeElement(tag, document);
  document.getElementById = (id) => {
    if (id === 'main-frame-if') return null;
    for (const root of allRoots()) {
      const match = findById(root, id);
      if (match) return match;
    }
    return null;
  };
  document.querySelector = (selector) =>
    selector === '#taniReferListForm+table' ? table : null;
  document.querySelectorAll = (selector) => {
    if (selector === 'table') return [table];
    const matches = [];
    for (const root of allRoots()) {
      if (matchesSelector(root, selector)) matches.push(root);
      matches.push(...root.querySelectorAll(selector));
    }
    return [...new Set(matches)];
  };

  class FakeMutationObserver {
    constructor(callback) {
      this.callback = callback;
      this.active = false;
    }

    observe() {
      this.active = true;
      activeObservers.add(this);
    }

    disconnect() {
      this.active = false;
      activeObservers.delete(this);
    }
  }

  const window = {
    document,
    frames: [],
    clearInterval(id) { activeIntervals.delete(id); },
    setInterval() {
      const id = nextIntervalId++;
      activeIntervals.add(id);
      return id;
    },
    clearTimeout(id) { activeTimeouts.delete(id); },
    setTimeout(callback) {
      const id = nextTimeoutId++;
      activeTimeouts.set(id, callback);
      return id;
    }
  };
  window.window = window;

  const context = {
    window,
    document,
    MutationObserver: FakeMutationObserver,
    console: {log() {}}
  };

  function triggerMutation() {
    for (const observer of [...activeObservers]) observer.callback();
  }

  function snapshot() {
    return {
      activeIntervalCount: activeIntervals.size,
      activeTimeoutCount: activeTimeouts.size,
      activeObserverCount: activeObservers.size,
      ownedElementCount: document.querySelectorAll(
        '[data-mbg-gpa-display-owned="true"]'
      ).length,
      gpaDisplayCount: document.querySelectorAll('.mbg-gpa-display').length,
      controlIds: target.children.map((child) => child.id),
      globalMarkers: Object.keys(window)
        .filter((key) =>
          key.startsWith('__MBG_GPA_DISPLAY_') ||
          key === '__MBG_UPDATE_GPA_DISPLAY')
        .sort()
    };
  }

  return {context, snapshot, triggerMutation};
}

function run(script, page) {
  vm.runInNewContext(script, page.context);
}

const page = createPage();
run(buildScript, page);
page.triggerMutation();
const afterBuild = page.snapshot();
run(teardownScript, page);
const afterTeardown = page.snapshot();
run(buildScript, page);
page.triggerMutation();
const afterRebuild = page.snapshot();

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
