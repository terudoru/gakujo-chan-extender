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

  test('unchanged non-grade pages do not rescan cells', () async {
    final result = await _evaluateGpaDisplayLifecycle(
      buildScript: GakujoGpaDisplayScript.build(),
      teardownScript: GakujoGpaDisplayScript.buildTeardown(),
    );
    final scans = result['nonGradeScans'] as Map<String, dynamic>;
    final initial = scans['initial'] as Map<String, dynamic>;

    expect(initial['cellCloneCount'], greaterThan(0));
    expect(initial['tableSearchCount'], 1);
    expect(scans['afterRepeatedUpdates'], initial);
    final afterAddingRow = scans['afterAddingRow'] as Map<String, dynamic>;
    expect(afterAddingRow['cellCloneCount'],
        greaterThan(initial['cellCloneCount'] as int));
    expect(afterAddingRow['tableSearchCount'], 2);
    expect(scans['afterUnchangedRowUpdate'], afterAddingRow);
    final afterAddingTable = scans['afterAddingTable'] as Map<String, dynamic>;
    expect(afterAddingTable['tableSearchCount'], 3);
  });

  test('grade pages still display and recompute GPA on each update', () async {
    final result = await _evaluateGpaDisplayLifecycle(
      buildScript: GakujoGpaDisplayScript.build(),
      teardownScript: GakujoGpaDisplayScript.buildTeardown(),
    );
    final grades = result['gradeUpdates'] as Map<String, dynamic>;

    expect(grades['initialText'], 'GPA:4.0000');
    expect(grades['afterGpChange'], 'GPA:3.0000');
    expect(grades['afterAddingRow'], 'GPA:2.0000');
    expect(grades['gpaDisplayCount'], 1);
    expect(grades['controlCount'], 3);
  });

  test('DOM mutations invalidate misses and the interval discovers frames',
      () async {
    final result = await _evaluateGpaDisplayLifecycle(
      buildScript: GakujoGpaDisplayScript.build(),
      teardownScript: GakujoGpaDisplayScript.buildTeardown(),
    );

    expect(result['gpaAfterHeaderMutation'], 'GPA:4.0000');
    expect(result['gpaInNewFrame'], 'GPA:4.0000');
  });

  test('frame navigation releases old documents and keeps observers aligned',
      () async {
    final result = await _evaluateGpaDisplayLifecycle(
      buildScript: GakujoGpaDisplayScript.build(),
      teardownScript: GakujoGpaDisplayScript.buildTeardown(),
    );
    final navigation = result['frameNavigation'] as Map<String, dynamic>;
    final updates = navigation['updates'] as List<dynamic>;

    expect(updates, hasLength(30));
    for (final update in updates.cast<Map<String, dynamic>>()) {
      expect(update['observedDocumentCount'], 3);
      expect(update['activeObserverCount'], 3);
      expect(update['currentDocumentsOnly'], isTrue);
      expect(update['observersAligned'], isTrue);
      expect(update['replacedObserverDisconnectCount'], 1);
      expect(update['gpaText'], 'GPA:4.0000');
    }
    final afterFrameRemoval =
        navigation['afterFrameRemoval'] as Map<String, dynamic>;
    expect(afterFrameRemoval['observedDocumentCount'], 2);
    expect(afterFrameRemoval['activeObserverCount'], 2);
    expect(afterFrameRemoval['removedObserversDisconnected'], isTrue);
    final afterTeardown = navigation['afterTeardown'] as Map<String, dynamic>;
    expect(afterTeardown['activeObserverCount'], 0);
    expect(afterTeardown['globalMarkers'], isEmpty);
    expect(navigation['allObserversDisconnected'], isTrue);
  });

  test('documents without a defaultView are disconnected and not reobserved',
      () async {
    final result = await _evaluateGpaDisplayLifecycle(
      buildScript: GakujoGpaDisplayScript.build(),
      teardownScript: GakujoGpaDisplayScript.buildTeardown(),
    );
    final detached = result['detachedFrame'] as Map<String, dynamic>;

    expect(detached['observedDocumentCount'], 1);
    expect(detached['activeObserverCount'], 1);
    expect(detached['detachedDocumentRetained'], isFalse);
    expect(detached['disconnectCount'], 1);
    expect(detached['afterTeardownActiveObserverCount'], 0);
  });
}

Future<Map<String, dynamic>> _evaluateGpaDisplayLifecycle({
  required String buildScript,
  required String teardownScript,
}) async {
  final result = await Process.run(
      'node',
      [
        '-e',
        _gpaDisplayDomHarness,
        buildScript,
        teardownScript,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8);

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
    if (this.tagName === 'TD' || this.tagName === 'TH') {
      this.ownerDocument.scanCounts.cellCloneCount += 1;
    }
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

function createPage({hasGradeTable = true} = {}) {
  let nextIntervalId = 1;
  let nextTimeoutId = 1;
  const activeIntervals = new Map();
  const activeTimeouts = new Map();
  const activeObservers = new Set();

  const document = {scanCounts: {cellCloneCount: 0, tableSearchCount: 0}};
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
  headerCells[12].innerText = hasGradeTable ? 'GP' : '通知';
  headerCells[12].textContent = headerCells[12].innerText;
  const gradeCells = Array.from({length: 13}, () => cell(''));
  gradeCells[8].innerText = '2';
  gradeCells[8].textContent = '2';
  gradeCells[12].innerText = '4';
  gradeCells[12].textContent = '4';
  const rows = [
    {cells: headerCells, children: headerCells},
    {cells: gradeCells, children: gradeCells}
  ];
  const table = {
    rows,
    tBodies: [{appendChild() {}}],
    querySelectorAll(selector) {
      return selector === 'tr' ? rows : [];
    }
  };
  const tables = [table];

  function allRoots() {
    return [documentElement, ...rows.flatMap((row) => row.cells)];
  }

  document.body = body;
  document.documentElement = documentElement;
  document.createElement = (tag) => new FakeElement(tag, document);
  document.getElementById = (id) => {
    for (const root of allRoots()) {
      const match = findById(root, id);
      if (match) return match;
    }
    return null;
  };
  document.querySelector = (selector) =>
    hasGradeTable && selector === '#taniReferListForm+table' ? table : null;
  document.getElementsByTagName = (tag) => {
    if (tag === 'table') return tables;
    if (tag === 'tr') return rows;
    return [];
  };
  document.querySelectorAll = (selector) => {
    if (selector === 'table') {
      document.scanCounts.tableSearchCount += 1;
      return tables;
    }
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
      this.disconnectCount = 0;
    }

    observe(target) {
      this.target = target;
      this.active = true;
      activeObservers.add(this);
    }

    disconnect() {
      this.disconnectCount += 1;
      this.active = false;
      activeObservers.delete(this);
    }
  }

  const window = {
    document,
    frames: [],
    clearInterval(id) { activeIntervals.delete(id); },
    setInterval(callback) {
      const id = nextIntervalId++;
      activeIntervals.set(id, callback);
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
  document.defaultView = window;

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

  function tickInterval() {
    for (const callback of [...activeIntervals.values()]) callback();
  }

  function flushTimeouts() {
    const callbacks = [...activeTimeouts.values()];
    activeTimeouts.clear();
    for (const callback of callbacks) callback();
  }

  function addRow(credits = '2', gp = '1') {
    const cells = Array.from({length: 13}, () => cell(''));
    cells[8].innerText = cells[8].textContent = credits;
    cells[12].innerText = cells[12].textContent = gp;
    rows.push({cells, children: cells});
  }

  function addTable() {
    tables.push({querySelectorAll() { return []; }});
  }

  function showGradeHeader() {
    hasGradeTable = true;
    headerCells[12].innerText = headerCells[12].textContent = 'GP';
  }

  function setGp(gp) {
    gradeCells[12].innerText = gradeCells[12].textContent = gp;
  }

  function gpaText() {
    const display = headerCells[12].querySelector('.mbg-gpa-display');
    return display ? display.textContent : null;
  }

  return {
    context, snapshot, triggerMutation, tickInterval, flushTimeouts,
    addRow, addTable, showGradeHeader, setGp, gpaText,
    scanCounts: () => ({...document.scanCounts})
  };
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

const nonGradePage = createPage({hasGradeTable: false});
run(buildScript, nonGradePage);
const initial = nonGradePage.scanCounts();
for (let i = 0; i < 5; i += 1) {
  nonGradePage.tickInterval();
  nonGradePage.context.window.__MBG_UPDATE_GPA_DISPLAY();
}
const afterRepeatedUpdates = nonGradePage.scanCounts();
nonGradePage.addRow();
nonGradePage.tickInterval();
const afterAddingRow = nonGradePage.scanCounts();
nonGradePage.tickInterval();
const afterUnchangedRowUpdate = nonGradePage.scanCounts();
nonGradePage.addTable();
nonGradePage.tickInterval();
const afterAddingTable = nonGradePage.scanCounts();

const gradePage = createPage();
run(buildScript, gradePage);
const initialText = gradePage.gpaText();
gradePage.setGp('3');
gradePage.tickInterval();
const afterGpChange = gradePage.gpaText();
gradePage.addRow();
gradePage.tickInterval();
const afterGradeRowAdded = gradePage.gpaText();

const mutatedPage = createPage({hasGradeTable: false});
run(buildScript, mutatedPage);
mutatedPage.showGradeHeader();
mutatedPage.triggerMutation();
mutatedPage.flushTimeouts();

const newFrame = createPage();
nonGradePage.context.window.frames.push(newFrame.context.window);
nonGradePage.tickInterval();

const portal = createPage({hasGradeTable: false});
const portalWindow = portal.context.window;
let currentFrame = createPage();
const frameWindow = {document: currentFrame.context.document, frames: []};
const frameElement = portal.context.document.createElement('iframe');
frameElement.id = 'main-frame-if';
frameElement.contentWindow = frameWindow;
portal.context.document.body.appendChild(frameElement);
const sibling = createPage({hasGradeTable: false});
portalWindow.frames.push(frameWindow, sibling.context.window);
run(buildScript, portal);
const navigationObservers = [...portalWindow.__MBG_GPA_DISPLAY_OBSERVERS];
const navigationUpdates = [];
for (let i = 0; i < 30; i += 1) {
  const previousDocument = currentFrame.context.document;
  const previousIndex =
    portalWindow.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS.indexOf(previousDocument);
  const previousObserver = portalWindow.__MBG_GPA_DISPLAY_OBSERVERS[previousIndex];
  // Some discarded documents still have a defaultView; reachability must suffice.
  if (i % 2 === 0) previousDocument.defaultView = null;
  currentFrame = createPage();
  frameWindow.document = currentFrame.context.document;
  portal.tickInterval();
  const documents = portalWindow.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS;
  const observers = portalWindow.__MBG_GPA_DISPLAY_OBSERVERS;
  const currentDocuments = [
    portal.context.document, currentFrame.context.document, sibling.context.document
  ];
  navigationObservers.push(observers[documents.indexOf(currentFrame.context.document)]);
  navigationUpdates.push({
    observedDocumentCount: documents.length,
    activeObserverCount: portal.snapshot().activeObserverCount,
    currentDocumentsOnly: documents.length === currentDocuments.length &&
      currentDocuments.every((document) => documents.includes(document)),
    observersAligned: observers.length === documents.length &&
      observers.every((observer, index) =>
        observer.active && observer.target === documents[index].documentElement),
    replacedObserverDisconnectCount: previousObserver.disconnectCount,
    gpaText: currentFrame.gpaText()
  });
}
const removedFrameObservers = portalWindow.__MBG_GPA_DISPLAY_OBSERVERS.filter(
  (_, index) => portalWindow.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS[index] ===
    currentFrame.context.document
);
portalWindow.frames = [sibling.context.window];
frameElement.remove();
portal.tickInterval();
const afterFrameRemoval = {
  observedDocumentCount: portalWindow.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS.length,
  activeObserverCount: portal.snapshot().activeObserverCount,
  removedObserversDisconnected: removedFrameObservers.every((observer) =>
    !observer.active && observer.disconnectCount === 1)
};
run(teardownScript, portal);
const frameNavigation = {
  updates: navigationUpdates,
  afterFrameRemoval,
  afterTeardown: portal.snapshot(),
  allObserversDisconnected: navigationObservers.every((observer) =>
    !observer.active && observer.disconnectCount === 1)
};

const detachedPortal = createPage({hasGradeTable: false});
const detachedChild = createPage({hasGradeTable: false});
const detachedWindow = detachedPortal.context.window;
detachedWindow.frames.push(detachedChild.context.window);
run(buildScript, detachedPortal);
const detachedObserver = detachedWindow.__MBG_GPA_DISPLAY_OBSERVERS[1];
detachedChild.context.document.defaultView = null;
detachedPortal.tickInterval();
detachedPortal.tickInterval();
const detachedFrame = {
  observedDocumentCount: detachedWindow.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS.length,
  activeObserverCount: detachedPortal.snapshot().activeObserverCount,
  detachedDocumentRetained: detachedWindow.__MBG_GPA_DISPLAY_OBSERVED_DOCUMENTS
    .includes(detachedChild.context.document),
  disconnectCount: detachedObserver.disconnectCount
};
run(teardownScript, detachedPortal);
detachedFrame.afterTeardownActiveObserverCount =
  detachedPortal.snapshot().activeObserverCount;

process.stdout.write(JSON.stringify({
  afterBuild,
  afterTeardown,
  afterRebuild,
  teardownWithoutBuild,
  nonGradeScans: {
    initial, afterRepeatedUpdates, afterAddingRow, afterUnchangedRowUpdate,
    afterAddingTable
  },
  gradeUpdates: {
    initialText, afterGpChange, afterAddingRow: afterGradeRowAdded,
    gpaDisplayCount: gradePage.snapshot().gpaDisplayCount,
    controlCount: gradePage.snapshot().controlIds.length
  },
  gpaAfterHeaderMutation: mutatedPage.gpaText(),
  gpaInNewFrame: newFrame.gpaText(),
  frameNavigation,
  detachedFrame
}));
''';
