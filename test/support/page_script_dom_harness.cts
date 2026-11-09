import type {} from 'node:fs';
const vm: any = require('node:vm');
const feature: any = process.argv[2];
const buildScript: any = process.argv[3];
const teardownScript: any = process.argv[4];
const scenario: any = process.argv[5] ? JSON.parse(process.argv[5]) : null;

const featureConfig: any = {
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
  [key: string]: any;
  constructor(tag: any, onSetSource?: any) {
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
        set(value: any) {
          this.source = value;
          if (this.parentNode) onSetSource(this);
        }
      });
      this.attachSource = () => {
        if (this.source) {
          onSetSource(this);
        } else if (this.onload) {
          this.onload();
        }
      };
    }
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
    if (child.attachSource) child.attachSource();
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

  click() {
    if (this.listeners.click) return this.listeners.click();
  }
}

class FakeCell {
  [key: string]: any;
  constructor(text: any) {
    this.innerText = text;
    this.textContent = text;
    this.style = {};
  }
}

function findById(node: any, id: any) {
  if (!node) return null;
  if (node.id === id) return node;
  for (const child of node.children || []) {
    const match: any = findById(child, id);
    if (match) return match;
  }
  return null;
}

function findByAttribute(node: any, name: any, value: any, matches: any) {
  if (!node) return;
  if (node.getAttribute && node.getAttribute(name) === value) matches.push(node);
  for (const child of node.children || []) {
    findByAttribute(child, name, value, matches);
  }
}

function createReportTable() {
  const header: any = {cells: []};
  const row: any = {
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
  const table: any = {rows: [header, row]};
  table.tBodies = [{appendChild() {}}];
  return table;
}

function createMessageTable(messageCount: any) {
  const rows: any = [{}];
  for (let i: any = 1; i <= messageCount; i += 1) {
    rows.push({
        querySelector(selector: any) {
          if (selector !== 'a[href]') return null;
          return {
            getAttribute() {
              return scenario?.messageUrls?.[i - 1] ?? `/campusweb/message/${i}`;
            }
          };
        }
      });
  }
  return {rows};
}

function createPage() {
  let nextIntervalId: any = 1;
  let nextTimeoutId: any = 1;
  let reloadCount: any = 0;
  let fetchCallCount: any = 0;
  let frameCallCount: any = 0;
  const fetchUrls: any = [];
  const fetchSignals: any = [];
  const activeIntervals: any = new Set();
  const activeTimeouts: any = new Map();
  const fetchStatuses: any = scenario ? [...scenario.fetchStatuses] : [200];
  const fetchBodies: any = scenario && scenario.fetchBodies ? [...scenario.fetchBodies] : [];
  const iframeOutcomes: any = scenario ? [...scenario.iframeOutcomes] : [];
  const target: any = new FakeElement('div');
  target.id = 'tabmenutable';
  const body: any = new FakeElement('body');
  const reportTable: any = createReportTable();
  const messageTable: any = createMessageTable(fetchStatuses.length);
  const timeoutTimer: any = {textContent: '20'};
  const extendButton: any = {click() {}};

  const defaultLocationHref: any =
    'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';
  const owningDocument: any = scenario?.owningDocument || {};
  const location: any = {
    href: Object.prototype.hasOwnProperty.call(owningDocument, 'locationHref')
      ? owningDocument.locationHref
      : defaultLocationHref,
    reload() { reloadCount += 1; }
  };
  const document: any = {
    baseURI: Object.prototype.hasOwnProperty.call(owningDocument, 'baseURI')
      ? owningDocument.baseURI
      : defaultLocationHref,
    location,
    body,
    createElement(tag: any) {
      if (tag.toLowerCase() === 'iframe') {
        return new FakeElement(tag, (frame: any) => {
          frameCallCount += 1;
          const loaded: any = iframeOutcomes.shift() === true;
          if (loaded && frame.onload) frame.onload();
          if (!loaded && frame.onerror) frame.onerror();
        });
      }
      return new FakeElement(tag);
    },
    getElementById(id: any) {
      if (id === 'main-frame-if') return null;
      if (id === 'tabmenutable') return target;
      if (id === 'timeout-timer') return timeoutTimer;
      if (id === 'portaltimerimg') return extendButton;
      return findById(target, id) || findById(body, id);
    },
    querySelector(selector: any) {
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
    querySelectorAll(selector: any) {
      const match: any = selector.match(/^\[([^=]+)="([^"]+)"\]$/);
      if (!match) return [];
      const matches: any = [];
      findByAttribute(target, match[1], match[2], matches);
      findByAttribute(body, match[1], match[2], matches);
      return matches;
    }
  };

  const window: any = {
    document,
    location,
    clearInterval(id: any) { activeIntervals.delete(id); },
    setInterval() {
      const id: any = nextIntervalId++;
      activeIntervals.add(id);
      return id;
    },
    setTimeout(callback: any, delay: any) {
      const id: any = nextTimeoutId++;
      activeTimeouts.set(id, {callback, delay});
      return id;
    },
    clearTimeout(id: any) { activeTimeouts.delete(id); }
  };
  window.window = window;

  const context: any = {
    window,
    document,
    location,
    URL,
    AbortController: scenario?.supportsAbortController === false ? undefined : AbortController,
    fetch: async function(url: any, options: any) {
      fetchCallCount += 1;
      fetchUrls.push(String(url));
      fetchSignals.push(options?.signal);
      const status: any = fetchStatuses.shift();
      if (status === null) throw new Error('simulated fetch failure');
      // A null body models a response stream that never finishes.
      const body: any = fetchBodies.shift();
      return {
        ok: status >= 200 && status < 300, status,
        text: () => body === null ? new Promise(() => {}) :
          Promise.resolve(body || '<html><body>連絡通知</body></html>')
      };
    },
    console: {log() {}}
  };

  function flushTimeouts(delay: any) {
    for (const [id, timer] of [...activeTimeouts]) {
      if (delay !== undefined && timer.delay !== delay) continue;
      activeTimeouts.delete(id);
      timer.callback();
    }
  }

  function snapshot() {
    return {
      activeIntervalCount: activeIntervals.size,
      ownedElementCount: document.querySelectorAll(
        featureConfig.ownedSelector
      ).length,
      controlIds: target.children.map((child: any) => child.id),
      statusText: (document.getElementById('mbg-read-status') || {}).textContent,
      statusOwned: document.getElementById('mbg-read-status')?.getAttribute(
        'data-mbg-message-reader-owned'
      ),
      reloadCount,
      fetchCallCount,
      fetchUrls,
      abortedFetchCount: fetchSignals.filter((signal: any) => signal?.aborted).length,
      frameCallCount,
      buttonDisabled: !!document.getElementById('mbg-read-button')?.disabled,
      buttonText: document.getElementById('mbg-read-button')?.textContent,
      timeoutIds: [...activeTimeouts.keys()],
      globalMarkers: Object.keys(window)
        .filter((key: any) => key.startsWith(featureConfig.markerPrefix))
        .sort()
    };
  }

  return {context, snapshot, flushTimeouts};
}

function run(script: any, page: any) {
  vm.runInNewContext(script, page.context);
}

async function main() {
  const injectedPage: any = createPage();
  run(buildScript, injectedPage);

  if (process.argv[6] === 'once') {
    process.stdout.write(JSON.stringify({afterBuild: injectedPage.snapshot()}));
    return;
  }

  if (scenario) {
    const input: any = injectedPage.context.document.getElementById(
      'mbg-read-num-input'
    );
    input.value = scenario.inputValue ?? String(scenario.fetchStatuses.length);
    const button: any = injectedPage.context.document.getElementById('mbg-read-button');
    const reads: any = [];
    // The first tap only asks for confirmation.
    await button.click();
    const afterArming: any = injectedPage.snapshot();
    let afterCountChange;
    if (scenario.inputValueAfterArming != null) {
      input.value = scenario.inputValueAfterArming;
      await button.click();
      afterCountChange = injectedPage.snapshot();
    }
    for (let i: any = 0; i < scenario.clickCount; i += 1) reads.push(button.click());
    if (scenario.teardownDuringRead) run(teardownScript, injectedPage);
    let beforeTimeout;
    if (scenario.fetchBodies?.includes(null)) {
      await Promise.resolve();
      beforeTimeout = injectedPage.snapshot();
      injectedPage.flushTimeouts(15000);
    }
    await Promise.all(reads);
    if (scenario.teardownAfterRead) run(teardownScript, injectedPage);
    injectedPage.flushTimeouts();
    process.stdout.write(JSON.stringify({
      ...injectedPage.snapshot(), afterArming, afterCountChange, beforeTimeout
    }));
    return;
  }

  const afterBuild: any = injectedPage.snapshot();
  run(teardownScript, injectedPage);
  const afterTeardown: any = injectedPage.snapshot();
  run(buildScript, injectedPage);
  const afterRebuild: any = injectedPage.snapshot();

  const freshPage: any = createPage();
  run(teardownScript, freshPage);
  const teardownWithoutBuild: any = freshPage.snapshot();

  process.stdout.write(JSON.stringify({
    afterBuild,
    afterTeardown,
    afterRebuild,
    teardownWithoutBuild
  }));
}

main().catch((error: any) => {
  console.error(error);
  process.exitCode = 1;
});
