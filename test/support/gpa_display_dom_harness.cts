import type {} from 'node:fs';
const vm: any = require('node:vm');
const fs: any = require('node:fs');
const buildScript: any = fs.readFileSync(process.argv[2], 'utf8');
const teardownScript: any = fs.readFileSync(process.argv[3], 'utf8');

class FakeElement {
  [key: string]: any;
  constructor(tag: any, ownerDocument: any) {
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

  setAttribute(name: any, value: any) {
    this.attributes[name] = String(value);
  }

  getAttribute(name: any) {
    return Object.prototype.hasOwnProperty.call(this.attributes, name)
      ? this.attributes[name]
      : null;
  }

  appendChild(child: any) {
    child.parentNode = this;
    this.children.push(child);
    return child;
  }

  remove() {
    if (!this.parentNode) return;
    const index: any = this.parentNode.children.indexOf(this);
    if (index >= 0) this.parentNode.children.splice(index, 1);
    this.parentNode = null;
  }

  addEventListener(type: any, callback: any) {
    this.listeners[type] = callback;
  }

  querySelector(selector: any) {
    return this.querySelectorAll(selector)[0] || null;
  }

  querySelectorAll(selector: any) {
    const matches: any = [];
    function visit(node: any) {
      for (const child of node.children || []) {
        if (matchesSelector(child, selector)) matches.push(child);
        visit(child);
      }
    }
    visit(this);
    return matches;
  }

  cloneNode(deep: any) {
    if (this.tagName === 'TD' || this.tagName === 'TH') {
      this.ownerDocument.scanCounts.cellCloneCount += 1;
    }
    const clone: any = new FakeElement(this.tagName, this.ownerDocument);
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

function matchesSelector(element: any, selector: any) {
  if (selector.startsWith('.')) {
    return element.className.split(/\s+/).includes(selector.slice(1));
  }
  const attribute: any = selector.match(/^\[([^=]+)="([^"]+)"\]$/);
  return !!attribute && element.getAttribute(attribute[1]) === attribute[2];
}

function findById(root: any, id: any) {
  if (!root) return null;
  if (root.id === id) return root;
  for (const child of root.children || []) {
    const match: any = findById(child, id);
    if (match) return match;
  }
  return null;
}

function createPage({hasGradeTable = true} = {}) {
  let nextIntervalId: any = 1;
  let nextTimeoutId: any = 1;
  const activeIntervals: any = new Map();
  const activeTimeouts: any = new Map();
  const activeObservers: any = new Set();

  const document: any = {scanCounts: {cellCloneCount: 0, tableSearchCount: 0}};
  const documentElement: any = new FakeElement('html', document);
  const body: any = new FakeElement('body', document);
  const target: any = new FakeElement('div', document);
  target.id = 'tabmenutable';
  documentElement.appendChild(body);
  body.appendChild(target);

  function cell(text: any) {
    const element: any = new FakeElement('td', document);
    element.innerText = text;
    element.textContent = text;
    return element;
  }
  const headerCells: any = Array.from({length: 13}, () => cell(''));
  headerCells[12].innerText = hasGradeTable ? 'GP' : '通知';
  headerCells[12].textContent = headerCells[12].innerText;
  const gradeCells: any = Array.from({length: 13}, () => cell(''));
  gradeCells[8].innerText = '2';
  gradeCells[8].textContent = '2';
  gradeCells[12].innerText = '4';
  gradeCells[12].textContent = '4';
  const rows: any = [
    {cells: headerCells, children: headerCells},
    {cells: gradeCells, children: gradeCells}
  ];
  const table: any = {
    rows,
    tBodies: [{appendChild() {}}],
    querySelectorAll(selector: any) {
      return selector === 'tr' ? rows : [];
    }
  };
  const tables: any = [table];

  function allRoots() {
    return [documentElement, ...rows.flatMap((row: any) => row.cells)];
  }

  document.addEventListener = () => {};
  document.removeEventListener = () => {};
  document.body = body;
  document.documentElement = documentElement;
  document.createElement = (tag: any) => new FakeElement(tag, document);
  document.getElementById = (id: any) => {
    for (const root of allRoots()) {
      const match: any = findById(root, id);
      if (match) return match;
    }
    return null;
  };
  document.querySelector = (selector: any) =>
    hasGradeTable && selector === '#taniReferListForm+table' ? table : null;
  document.getElementsByTagName = (tag: any) => {
    if (tag === 'table') return tables;
    if (tag === 'tr') return rows;
    return [];
  };
  document.querySelectorAll = (selector: any) => {
    if (selector === 'table') {
      document.scanCounts.tableSearchCount += 1;
      return tables;
    }
    const matches: any = [];
    for (const root of allRoots()) {
      if (matchesSelector(root, selector)) matches.push(root);
      matches.push(...root.querySelectorAll(selector));
    }
    return [...new Set(matches)];
  };

  class FakeMutationObserver {
  [key: string]: any;
    constructor(callback: any) {
      this.callback = callback;
      this.active = false;
      this.disconnectCount = 0;
    }

    observe(target: any) {
      this.target = target;
      this.active = true;
      activeObservers.add(this);
    }

    takeRecords() { return []; }

    disconnect() {
      this.disconnectCount += 1;
      this.active = false;
      activeObservers.delete(this);
    }
  }

  const window: any = {
    document,
    MutationObserver: FakeMutationObserver,
    frames: [],
    clearInterval(id: any) { activeIntervals.delete(id); },
    setInterval(callback: any) {
      const id: any = nextIntervalId++;
      activeIntervals.set(id, callback);
      return id;
    },
    clearTimeout(id: any) { activeTimeouts.delete(id); },
    setTimeout(callback: any) {
      const id: any = nextTimeoutId++;
      activeTimeouts.set(id, callback);
      return id;
    }
  };
  window.window = window;
  document.defaultView = window;

  const context: any = {
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
      controlIds: target.children.map((child: any) => child.id),
      globalMarkers: Object.keys(window)
        .filter((key: any) =>
          key.startsWith('__MBG_GPA_DISPLAY_') ||
          key === '__MBG_UPDATE_GPA_DISPLAY' ||
          key === '__MBG_GPA_LAST_REPORTED')
        .sort()
    };
  }

  function tickInterval() {
    for (const callback of [...activeIntervals.values()]) callback();
  }

  function flushTimeouts() {
    const callbacks: any = [...activeTimeouts.values()];
    activeTimeouts.clear();
    for (const callback of callbacks) callback();
  }

  function addRow(credits: any = '2', gp: any = '1', evaluation: any = '') {
    const cells: any = Array.from({length: 13}, () => cell(''));
    cells[10].innerText = cells[10].textContent = evaluation;
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

  function setGp(gp: any) {
    gradeCells[12].innerText = gradeCells[12].textContent = gp;
  }

  function gpaText() {
    const display: any = headerCells[12].querySelector('.mbg-gpa-display');
    return display ? display.textContent : null;
  }

  return {
    context, snapshot, triggerMutation, tickInterval, flushTimeouts,
    observers: () => [...activeObservers],
    observedDocuments: () => [...activeObservers].map((observer: any) => observer.target.ownerDocument),
    addRow, addTable, showGradeHeader, setGp, gpaText,
    scanCounts: () => ({...document.scanCounts})
  };
}

function run(script: any, page: any) {
  vm.runInNewContext(script, page.context);
}

const page: any = createPage();
run(buildScript, page);
page.triggerMutation();
const afterBuild: any = page.snapshot();
run(teardownScript, page);
const afterTeardown: any = page.snapshot();
run(buildScript, page);
page.triggerMutation();
const afterRebuild: any = page.snapshot();

const freshPage: any = createPage();
run(teardownScript, freshPage);
const teardownWithoutBuild: any = freshPage.snapshot();

const nonGradePage: any = createPage({hasGradeTable: false});
run(buildScript, nonGradePage);
const initial: any = nonGradePage.scanCounts();
for (let i: any = 0; i < 5; i += 1) {
  nonGradePage.tickInterval();
  nonGradePage.context.window.__MBG_UPDATE_GPA_DISPLAY();
}
const afterRepeatedUpdates: any = nonGradePage.scanCounts();
nonGradePage.addRow();
nonGradePage.tickInterval();
const afterAddingRow: any = nonGradePage.scanCounts();
nonGradePage.tickInterval();
const afterUnchangedRowUpdate: any = nonGradePage.scanCounts();
nonGradePage.addTable();
nonGradePage.tickInterval();
const afterAddingTable: any = nonGradePage.scanCounts();

const gradePage: any = createPage();
run(buildScript, gradePage);
const initialText: any = gradePage.gpaText();
gradePage.setGp('3');
gradePage.tickInterval();
const afterGpChange: any = gradePage.gpaText();
gradePage.addRow();
gradePage.tickInterval();
const afterGradeRowAdded: any = gradePage.gpaText();

const reportingPage: any = createPage();
const reportedMessages: any = [];
reportingPage.context.window.GakujoGpaReport = {
  postMessage(message: any) { reportedMessages.push(message); }
};
run(buildScript, reportingPage);
const gpaReport: any = {afterBuild: [...reportedMessages]};
reportingPage.context.window.__MBG_UPDATE_GPA_DISPLAY();
gpaReport.afterUnchangedUpdate = [...reportedMessages];
run(teardownScript, reportingPage);
gpaReport.afterTeardown = reportingPage.snapshot();

// A first-year student has only in-progress courses with blank GP.
const ungradedPage: any = createPage();
const ungradedReports: any = [];
ungradedPage.context.window.GakujoGpaReport = {
  postMessage(message: any) { ungradedReports.push(message); }
};
ungradedPage.setGp('');
ungradedPage.addRow('2', '', '履修中');
run(buildScript, ungradedPage);
gpaReport.withoutGrades = [...ungradedReports];
gpaReport.withoutGradesText = ungradedPage.gpaText();
ungradedPage.setGp('2.5');
ungradedPage.tickInterval();
gpaReport.afterFirstGrade = [...ungradedReports];

// A recognised course shows GP 0 but is not graded.
const recognisedPage: any = createPage();
run(buildScript, recognisedPage);
recognisedPage.addRow('2', '0', '認定');
// Every graded Gakujo row also carries 合 in its own 合否 column.
recognisedPage.addRow('2', '4', '合');
recognisedPage.tickInterval();
const withRecognisedCourse: any = recognisedPage.gpaText();

const mutatedPage: any = createPage({hasGradeTable: false});
run(buildScript, mutatedPage);
mutatedPage.showGradeHeader();
mutatedPage.triggerMutation();
mutatedPage.flushTimeouts();

const newFrame: any = createPage();
nonGradePage.context.window.frames.push(newFrame.context.window);
nonGradePage.tickInterval();

const portal: any = createPage({hasGradeTable: false});
const portalWindow: any = portal.context.window;
let currentFrame: any = createPage();
const frameWindow: any = {document: currentFrame.context.document, frames: []};
const frameElement: any = portal.context.document.createElement('iframe');
frameElement.id = 'main-frame-if';
frameElement.contentWindow = frameWindow;
portal.context.document.body.appendChild(frameElement);
const sibling: any = createPage({hasGradeTable: false});
portalWindow.frames.push(frameWindow, sibling.context.window);
run(buildScript, portal);
const navigationObservers: any = [...portal.observers()];
const navigationUpdates: any = [];
for (let i: any = 0; i < 30; i += 1) {
  const previousDocument: any = currentFrame.context.document;
  const previousIndex: any =
    portal.observedDocuments().indexOf(previousDocument);
  const previousObserver: any = portal.observers()[previousIndex];
  // Some discarded documents still have a defaultView; reachability must suffice.
  if (i % 2 === 0) previousDocument.defaultView = null;
  currentFrame = createPage();
  frameWindow.document = currentFrame.context.document;
  portal.tickInterval();
  const documents: any = portal.observedDocuments();
  const observers: any = portal.observers();
  const currentDocuments: any = [
    portal.context.document, currentFrame.context.document, sibling.context.document
  ];
  navigationObservers.push(observers[documents.indexOf(currentFrame.context.document)]);
  navigationUpdates.push({
    observedDocumentCount: documents.length,
    activeObserverCount: portal.snapshot().activeObserverCount,
    currentDocumentsOnly: documents.length === currentDocuments.length &&
      currentDocuments.every((document: any) => documents.includes(document)),
    observersAligned: observers.length === documents.length &&
      observers.every((observer: any, index: any) =>
        observer.active && observer.target === documents[index].documentElement),
    replacedObserverDisconnectCount: previousObserver.disconnectCount,
    gpaText: currentFrame.gpaText()
  });
}
const removedFrameObservers: any = portal.observers().filter(
  (_: any, index: any) => portal.observedDocuments()[index] ===
    currentFrame.context.document
);
portalWindow.frames = [sibling.context.window];
frameElement.remove();
portal.tickInterval();
const afterFrameRemoval: any = {
  observedDocumentCount: portal.observedDocuments().length,
  activeObserverCount: portal.snapshot().activeObserverCount,
  removedObserversDisconnected: removedFrameObservers.every((observer: any) =>
    !observer.active && observer.disconnectCount === 1)
};
run(teardownScript, portal);
const frameNavigation: any = {
  updates: navigationUpdates,
  afterFrameRemoval,
  afterTeardown: portal.snapshot(),
  allObserversDisconnected: navigationObservers.every((observer: any) =>
    !observer.active && observer.disconnectCount === 1)
};

const detachedPortal: any = createPage({hasGradeTable: false});
const detachedChild: any = createPage({hasGradeTable: false});
const detachedWindow: any = detachedPortal.context.window;
detachedWindow.frames.push(detachedChild.context.window);
run(buildScript, detachedPortal);
const detachedObserver: any = detachedPortal.observers()[1];
detachedChild.context.document.defaultView = null;
detachedPortal.tickInterval();
detachedPortal.tickInterval();
const detachedFrame: any = {
  observedDocumentCount: detachedPortal.observedDocuments().length,
  activeObserverCount: detachedPortal.snapshot().activeObserverCount,
  detachedDocumentRetained: detachedPortal.observedDocuments()
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
    withRecognisedCourse,
    gpaDisplayCount: gradePage.snapshot().gpaDisplayCount,
    controlCount: gradePage.snapshot().controlIds.length
  },
  gpaReport,
  gpaAfterHeaderMutation: mutatedPage.gpaText(),
  gpaInNewFrame: newFrame.gpaText(),
  frameNavigation,
  detachedFrame
}));
