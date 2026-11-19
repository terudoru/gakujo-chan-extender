import type {} from 'node:fs';
const vm: any = require('node:vm');
const options: any = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const {scripts, initialDisplays} = options;

class FakeElement {
  [key: string]: any;
  constructor(tag: any, text: any = '') {
    this.tagName = tag.toUpperCase();
    this.id = '';
    this.text = text;
    this.textReads = 0;
    this.textWrites = 0;
    this.attributeWrites = 0;
    this.displayWrites = 0;
    this.value = '';
    this.style = new Proxy({}, {
      set: (target: any, name: any, value: any) => {
        if (name === 'display') this.displayWrites += 1;
        target[name] = value;
        return true;
      }
    });
    this.attributes = {};
    this.listeners = {};
    this.children = [];
    this.parentNode = null;
  }

  addEventListener(type: any, listener: any) {
    this.listeners[type] = listener;
  }

  get innerText() {
    this.textReads += 1;
    return this.text + this.children.map((child: any) => child.innerText).join(' ');
  }

  get textContent() {
    return this.innerText;
  }

  set textContent(value: any) {
    this.textWrites += 1;
    this.text = value;
  }

  setAttribute(name: any, value: any) {
    this.attributeWrites += 1;
    this.attributes[name] = String(value);
  }

  getAttribute(name: any) {
    if (name === 'id') return this.id || null;
    return this.attributes[name] ?? null;
  }

  removeAttribute(name: any) {
    this.attributeWrites += 1;
    delete this.attributes[name];
  }

  appendChild(child: any) {
    return this.insertBefore(child, null);
  }

  insertBefore(child: any, before: any) {
    if (child.parentNode) child.remove();
    child.parentNode = this;
    const index: any = before ? this.children.indexOf(before) : this.children.length;
    if (index < 0) throw new Error('Reference node is not a child');
    this.children.splice(index, 0, child);
    return child;
  }

  matches(selector: any) {
    if (selector === '*') return true;
    const attributes: any = [...selector.matchAll(/\[([\w-]+)(?:(\*?=)"([^"]*)")?\]/g)];
    const simple: any = selector.replace(/\[[^\]]*\]/g, '');
    if (!/^(?:\w+)?(?:\.[\w-]+)*$/.test(simple)) return false;
    const tag: any = simple.match(/^\w+/)?.[0];
    if (tag && this.tagName !== tag.toUpperCase()) return false;
    for (const match of simple.matchAll(/\.([\w-]+)/g)) {
      if (!(this.attributes.class || '').split(/\s+/).includes(match[1])) return false;
    }
    return attributes.every(([, key, operator, value]) => {
      const actual: any = this.getAttribute(key);
      return actual !== null &&
        (!operator || (operator === '*=' ? actual.includes(value) : actual === value));
    });
  }

  closest(selector: any) {
    for (let node: any = this; node; node = node.parentNode) {
      if (node.matches(selector)) return node;
    }
    return null;
  }

  querySelectorAll(selector: any) {
    const result: any = [];
    for (const child of this.children) {
      if (child.matches(selector)) result.push(child);
      result.push(...child.querySelectorAll(selector));
    }
    return result;
  }

  querySelector(selector: any) {
    return this.querySelectorAll(selector)[0] || null;
  }

  remove() {
    if (!this.parentNode) return;
    const index: any = this.parentNode.children.indexOf(this);
    if (index >= 0) this.parentNode.children.splice(index, 1);
    this.parentNode = null;
  }
}

function findById(root: any, id: any) {
  if (root.id === id) return root;
  for (const child of root.children || []) {
    const match: any = findById(child, id);
    if (match) return match;
  }
  return null;
}

function add(parent: any, tag: any, text: any = '', attributes: any = {}) {
  const child: any = new FakeElement(tag, text);
  Object.entries(attributes).forEach(([name, value]) => child.setAttribute(name, value));
  return parent.appendChild(child);
}

function makeDocument(withList: any) {
  const root: any = new FakeElement('body');
  const doc: any = {
    root,
    rows: [],
    getElementById(id: any) {
      if (id === 'main-frame-if') return this.frame || null;
      return findById(root, id);
    },
    querySelector(selector: any) {
      if (selector === 'table.normal:nth-child(9)') {
        return options.directTable && !options.smartphone ? this.listTable : null;
      }
      return root.querySelector(selector);
    },
    querySelectorAll(selector: any) { return root.querySelectorAll(selector); },
    createElement(tag: any) { return new FakeElement(tag); },
    createTextNode(text: any) { return new FakeElement('#text', text); }
  };
  if (options.smartphone) {
    doc.navigationTable = add(root, 'table');
    add(add(doc.navigationTable, 'tr'), 'td', '連絡通知');
    add(add(add(doc.navigationTable, 'tr'), 'td'), 'a', '授業掲示板',
      {href: 'campussquare.do?_flowId=掲示'});
    add(add(add(doc.navigationTable, 'tr'), 'td'), 'a', '授業連絡',
      {href: 'campussquare.do?_flowId=連絡'});
    if (options.fallbackTable) {
      const fallback: any = add(root, 'table', '連絡通知');
      add(fallback, 'tr', '件名');
      add(add(fallback, 'tr'), 'a', '重要なお知らせ',
        {href: 'campussquare.do?seqNo=508181'});
    }
  }
  if (!withList) return doc;
  if (!options.smartphone) {
    const table: any = add(root, 'table', '連絡通知 ');
    add(add(table, 'tr', '件名'), 'a', '', {href: 'campussquare.do'});
    doc.rows = [
      add(table, 'tr', '授業アンケートのお願い'),
      add(table, 'tr', '重要なお知らせ')
    ];
    add(doc.rows[0], 'a', '', {href: 'campussquare.do?seqNo=508182'});
    add(doc.rows[1], 'a', '', {href: 'campussquare.do?seqNo=508183'});
    if (options.displayCountControl) {
      doc.location = {origin: 'https://gakujo.iess.niigata-u.ac.jp'};
      const size = add(root, 'select', '', {name: '_displayCount'});
      size.value = '20';
      size.options = ['20', '100', '500', '1000'].map(value => ({value}));
      doc.rows[0].querySelector('a').setAttribute('href',
        'campussquare.do?_flowExecutionKey=actual&seqNo=508182');
    }
    if (options.searchQueries) {
      for (const [index, row] of doc.rows.entries()) {
        row.cells = [
          add(row, 'td', '2026/11/19 10:00:00'),
          add(row, 'td', index === 0 ? 'ＡＰＩ　資料' : 'API 資料 重要'),
          add(row, 'td', index === 0 ? '工学部 講義担当' : '文学部 講義担当')
        ];
      }
    }
    doc.listTable = table;
  } else {
    // All messages share this layout row and list table. Only the outer row of
    // each message contains both its category and its nested div.button row.
    const container: any = add(add(add(root, 'table'), 'tr'), 'td');
    doc.listTable = add(container, 'table');
    const body: any = add(doc.listTable, 'tbody');
    for (let index: any = 0; index < options.smartphoneMessageCount; index += 1) {
      const row: any = add(body, 'tr');
      doc.rows.push(row);
      const itemBody: any = add(add(add(row, 'td'), 'table', '', {class: 'bgnone'}), 'tbody');
      add(add(itemBody, 'tr'), 'td', index === 1 ? 'セキュリティ' : '授業連絡',
        {class: 'center category-frame'});
      const button: any = add(add(add(itemBody, 'tr'), 'td'), 'div', '', {
        class: 'button',
        onclick: "location.href='campussquare.do?seqNo=" + (508182 + index) + "'"
      });
      add(button, 'p', index === 0 ? '情報セキュリティ概論 第4回 授業資料'
        : index === 1 ? '重要なお知らせ' : '授業アンケートのお願い');
    }
  }
  doc.rows.forEach((row: any, index: any) => { row.style.display = initialDisplays[index] || ''; });
  return doc;
}

const document: any = makeDocument(options.frame !== 'list');
if (!options.smartphone) {
  const target: any = add(document.root, 'div');
  target.id = 'tabmenutable';
}
let frameDocument;
if (['empty', 'list', 'both'].includes(options.frame)) {
  frameDocument = makeDocument(options.frame !== 'empty');
  document.frame = {contentWindow: {document: frameDocument}};
} else if (options.frame === 'sameDocument') {
  document.frame = {contentWindow: {document}};
} else if (options.frame === 'inaccessible') {
  document.frame = {get contentWindow() { throw new Error('Cross-origin frame'); }};
}
const documents: any = frameDocument ? [document, frameDocument] : [document];
const listDocument: any = options.frame === 'list' ? frameDocument : document;
for (const doc of documents) {
  for (let index: any = 0; index < options.initialStatusCount; index += 1) {
    const status: any = add(doc.root, 'span', 'stale status');
    status.id = 'mbg-message-filter-status';
  }
}

let nextIntervalId: any = 1;
const activeIntervals: any = new Map();
const storage = new Map();
const window: any = {
  document,
  sessionStorage: {
    getItem(key: any) { return storage.get(key) ?? null; },
    setItem(key: any, value: any) { storage.set(key, value); }
  },
  clearInterval(id: any) { activeIntervals.delete(id); },
  setInterval(callback: any, delay: any) {
    if (delay !== 500) throw new Error('Expected a 500 ms interval');
    const id: any = nextIntervalId++;
    activeIntervals.set(id, callback);
    return id;
  }
};
window.window = window;
const context: any = {window, document, URL};

function documentSnapshot(doc: any) {
  const rows: any = doc.rows;
  const elements: any = doc.querySelectorAll('*');
  const status: any = doc.getElementById('mbg-message-filter-status');
  const table: any = doc.listTable;
  const navigation: any = doc.navigationTable;
  const search: any = doc.getElementById('mbg-message-search');
  const sum: any = (nodes: any, field: any) => nodes.reduce((total: any, node: any) => total + node[field], 0);
  return {
    searchQuery: search?.querySelector('input').value ?? null,
    searchCount: search?.querySelector('span').textContent ?? null,
    searchHint: search?.querySelector('div').textContent ?? null,
    searchLargerHref: search?.querySelector('a')?.href ?? null,
    rowDisplays: rows.map((row: any) => row.style.display || ''),
    rowAttributes: rows.map((row: any) => ({...row.attributes})),
    rowTextReads: sum(elements.filter((node: any) => node.tagName === 'TR'), 'textReads'),
    tableTextReads: sum(elements.filter((node: any) => node.tagName === 'TABLE'), 'textReads'),
    attributeWrites: sum(elements, 'attributeWrites'),
    displayWrites: sum(elements, 'displayWrites'),
    statusWrites: status ? status.textWrites : 0,
    statusText: status ? status.textContent : null,
    statusCount: doc.querySelectorAll('[id="mbg-message-filter-status"]').length,
    hasTabMenu: !!doc.getElementById('tabmenutable'),
    statusInTabMenu: !!status && status.parentNode === doc.getElementById('tabmenutable'),
    navigationRowDisplays: navigation ? navigation.querySelectorAll('tr').map((row: any) => row.style.display || '') : [],
    navigationUntouched: !navigation || [navigation, ...navigation.querySelectorAll('*')].every((node: any) =>
      node.attributeWrites === 0 && node.displayWrites === 0 && node.textWrites === 0),
    statusBeforeList: !!status && status.parentNode === table?.parentNode &&
      status.parentNode.children.indexOf(status) + 1 === status.parentNode.children.indexOf(table),
    onlyMessageUnitsTouched: elements.filter((node: any) => !rows.includes(node)).every((node: any) =>
      node.displayWrites === 0 && !Object.keys(node.attributes).some((key: any) => key.startsWith('data-mbg-message-filter')))
  };
}

const snapshots: any = [];
for (const [index, script] of scripts.entries()) {
  for (const doc of documents) {
    for (const element of doc.querySelectorAll('*')) {
      element.textReads = 0;
      element.textWrites = 0;
      element.attributeWrites = 0;
      element.displayWrites = 0;
    }
  }
  vm.runInNewContext(script, context);
  let enterPrevented = false;
  let enterStopped = false;
  const input = listDocument.getElementById('mbg-message-search')?.querySelector('input');
  if (options.searchQueries && input) {
    const query = options.searchQueries[index];
    if (query !== null) {
      input.value = query;
      input.listeners.input();
    }
    input.listeners.keydown({
      key: 'Enter',
      preventDefault() { enterPrevented = true; },
      stopPropagation() { enterStopped = true; }
    });
  }
  for (let pass: any = 0; pass < options.intervalPasses; pass += 1) {
    for (const callback of activeIntervals.values()) callback();
  }
  snapshots.push({...documentSnapshot(listDocument),
    documents: documents.map(documentSnapshot), activeIntervalCount: activeIntervals.size,
    enterPrevented, enterStopped});
}
process.stdout.write(JSON.stringify(snapshots));
