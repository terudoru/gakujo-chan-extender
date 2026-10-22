const vm = require('node:vm');
const {mode, scenario, scripts} = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const base = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
const title = '情報セキュリティ概論 第4回 授業資料';
let rowReads = 0, urlReads = 0, navigations = 0;

class Element {
  constructor(tag, value = '') {
    this.nodeName = this.tagName = tag.toUpperCase();
    this.nodeType = tag === '#text' ? 3 : 1;
    this._text = value; this.childNodes = []; this.attributes = {};
    this.style = {}; this.listeners = {}; this.captures = {};
  }
  get children() { return this.childNodes.filter(node => node.nodeType === 1); }
  get firstChild() { return this.childNodes[0] || null; }
  get textContent() { return this._text + this.childNodes.map(node => node.textContent).join(''); }
  set textContent(value) { this._text = value; this.childNodes = []; }
  get innerText() { return this.textContent; }
  get href() { return this.attributes.href ? new URL(this.attributes.href, this.ownerDocument.baseURI).href : ''; }
  get nextSibling() { return this.parentNode?.childNodes[this.parentNode.childNodes.indexOf(this) + 1] || null; }
  get nextElementSibling() { return this.parentNode?.children[this.parentNode.children.indexOf(this) + 1] || null; }
  get cells() { rowReads += 1; return this.children.filter(node => /^(TD|TH)$/.test(node.tagName)); }
  get isConnected() { return !!this.parentNode; }
  setAttribute(key, value) { this.attributes[key] = String(value); }
  getAttribute(key) { return this.attributes[key] ?? null; }
  addEventListener(type, callback, capture) {
    this.listenerAdds = (this.listenerAdds || 0) + 1;
    this.listeners[type] = callback; this.captures[type] = capture;
  }
  removeEventListener(type, callback, capture) {
    if (this.listeners[type] === callback && this.captures[type] === capture) delete this.listeners[type];
  }
  appendChild(node) { return this.insertBefore(node, null); }
  insertBefore(node, before) {
    node.ownerDocument = this.ownerDocument; node.parentNode = this;
    this.childNodes.splice(before ? this.childNodes.indexOf(before) : this.childNodes.length, 0, node);
    return node;
  }
  remove() {
    if (this.parentNode) this.parentNode.childNodes = this.parentNode.childNodes.filter(node => node !== this);
    this.parentNode = null;
  }
  matches(selector) {
    if (this.nodeType !== 1) return false;
    const attributes = [...selector.matchAll(/\[([\w-]+)(?:(\*?=)"([^"]*)")?\]/g)];
    selector = selector.replace(/\[[^\]]*\]/g, '');
    if (!/^(?:\w+)?(?:[.#][\w-]+)*$/.test(selector)) return false;
    const tag = selector.match(/^\w+/)?.[0];
    if (tag && this.tagName !== tag.toUpperCase()) return false;
    for (const match of selector.matchAll(/([.#])([\w-]+)/g)) {
      if (match[1] === '#' && this.attributes.id !== match[2]) return false;
      if (match[1] === '.' && !(this.attributes.class || '').split(/\s+/).includes(match[2])) return false;
    }
    return attributes.every(([, key, operator, value]) => key in this.attributes &&
      (!operator || (operator === '*=' ? this.attributes[key].includes(value) : this.attributes[key] === value)));
  }
  closest(selector) {
    for (let node = this; node; node = node.parentNode) if (node.matches(selector)) return node;
    return null;
  }
  querySelectorAll(selector) {
    const selectors = selector.split(',').map(part => part.trim().split(/\s+/));
    const result = [];
    for (const child of this.children) {
      if (selectors.some(parts => {
        if (!child.matches(parts[parts.length - 1])) return false;
        let ancestor = child.parentNode;
        for (let i = parts.length - 2; i >= 0; i -= 1) {
          while (ancestor && !ancestor.matches(parts[i])) ancestor = ancestor.parentNode;
          if (!ancestor) return false;
          ancestor = ancestor.parentNode;
        }
        return true;
      })) result.push(child);
      result.push(...child.querySelectorAll(selector));
    }
    return result;
  }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
}
function add(parent, tag, value = '', attributes = {}) {
  const node = new Element(tag, value); node.ownerDocument = parent.ownerDocument;
  Object.entries(attributes).forEach(([key, value]) => node.setAttribute(key, value));
  return parent.appendChild(node);
}
function doc() {
  const root = new Element('html'); root.ownerDocument = root;
  root.title = 'CampusSquare for WEB'; root.baseURI = base + 'campussquare.do?_flowExecutionKey=detail-key';
  root.location = {href: root.baseURI}; root.URL = root.baseURI;
  root.head = add(root, 'head'); root.body = add(root, 'body', '連絡通知 ');
  root.createElement = tag => { const node = new Element(tag); node.ownerDocument = root; return node; };
  root.getElementById = id => id === 'main-frame-if' ? root.frame || null
    : root.querySelectorAll('style').find(node => node.id === id) || null;
  return root;
}
function list() {
  const root = doc();
  if (scenario === 'desktop') {
    root.title = '連絡通知一覧';
    const table = add(root.body, 'table', '', {class: 'normal'});
    const header = add(table, 'tr');
    for (const label of ['掲載日時','表題','返信未読','ジャンル','所属','氏名','連絡通知期間']) add(header, 'th', label);
    for (let i = 0; i < 160; i += 1) {
      const row = add(table, 'tr');
      for (const value of ['2026/10/22 14:00:54 ', null, ' - ', '授業連絡 ', '工学部 ', '落合 博幸 ', '2026/10/22 13:57～2026/11/05 13:57']) {
        const cell = add(row, 'td', value || '');
        if (value === null) {
          const heading = add(cell, 'a', ` ${title} `, {href:
            'campussquare.do?_flowExecutionKey=desktop%20key&_eventId=displayMidoku&keijitype=1&genrecd=40&seqNo=' + (508182 + i)});
          if (i === 0) { root.heading = heading; root.row = row; }
        }
      }
    }
    return root;
  }
  if (scenario === 'missing') { root.title = 'ログイン'; root.body.textContent = 'ログイン'; return root; }
  if (scenario === 'noMessageLabel') root.body.textContent = '別の機能';
  add(root.body, '#text', '未読一覧 未読が160件あります。 ');
  for (let i = 0; i < 160; i += 1) {
    const table = add(add(add(add(root.body, 'table'), 'tr'), 'td'), 'table', '', {class: 'bgnone'});
    const body = add(table, 'tbody');
    add(add(add(add(add(add(body, 'tr'), 'td'), 'table', '', {class: 'bgnone'}), 'tbody'), 'tr'), 'td', ' 授業連絡 ', {class: 'center category-frame'});
    const row = add(body, 'tr');
    const date = add(add(add(add(row, 'td'), 'nobr'), 'table'), 'tbody');
    add(add(date, 'tr'), 'td', scenario === 'singleDigitDate' ? ' 2026/1 ' : ' 2026/10 ');
    const day = add(add(date, 'tr'), 'td');
    add(add(day, 'font'), 'b', scenario === 'singleDigitDate' ? ' 2 ' : ' 22 ');
    add(day, 'br'); add(day, '#text', ' 14:00:54 ');
    const button = add(add(row, 'td'), 'div', '', {class: 'button', onclick:
      "location.href='campussquare.do?_flowExecutionKey=mobile%20key&amp;_eventId=" +
      (scenario === 'genre' ? 'confirm' : 'displayMidoku') + '&amp;keijitype=1&amp;genrecd=40&amp;seqNo=' + (508182 + i) + "'"});
    button.listeners.click = () => { navigations += 1; };
    const heading = add(button, 'p', ` ${title} `);
    add(button, '#text', scenario === 'officeSender' ? ' 学務部 教務課 ' : ' (工) 落合 博幸 ');
    add(button, 'br'); add(button, '#text', '掲示期間： 2026/10/22 13:57 \u00a0～\u00a0 2026/11/05 13:57 ');
    if (i === 0) { root.action = button; root.heading = heading; root.row = row; }
  }
  return root;
}
function detail(attachment = false) {
  const root = doc();
  const portlet = add(root.body, 'div', '', {id: 'main-portlet-body'});
  const fields = add(portlet, 'ul', '', {class: 'campussmart-list'});
  for (const [label, value] of Object.entries({
    '表題': title, '内容': scenario === 'longBody' ? '文'.repeat(4001) : ' 本文の一行目\n二行目 ',
    '所属': '工学部', '氏名': '落合 博幸', 'メール': '非表示',
    '掲載日時': '2026/10/20 10:14:19', '添付ファイル': ''
  })) {
    add(fields, 'li', label, {class: 'header center'});
    const item = add(fields, 'li', value);
    if (label === '表題') root.heading = item;
    if (label === '添付ファイル' && attachment) add(item, 'a', '資料.pdf', {
      href: 'campussquare.do?_flowExecutionKey=temporary&_eventId=download&keijitype=1&genrecd=40&seqNo=508182'
    });
  }
  return root;
}
function click(target) {
  const event = {target, prevented: false, stopped: false,
    preventDefault() { this.prevented = true; }, stopPropagation() { this.stopped = true; }};
  const ancestors = [];
  for (let node = target; node; node = node.parentNode) ancestors.push(node);
  for (const node of [...ancestors].reverse()) if (node.captures.click) node.listeners.click?.(event);
  for (const node of ancestors) {
    if (!node.captures.click) node.listeners.click?.(event);
    if (event.stopped) break;
  }
  return event;
}
let inner = mode === 'detail'
  ? detail(['attachment', 'longBody', 'topWithIframe', 'iframe', 'bothDocuments'].includes(scenario)) : list();
const outer = scenario === 'iframe' || (mode === 'remember' && scenario !== 'topWithIframe') ? doc() : inner;
if (outer !== inner) outer.frame = {contentWindow: {document: inner}};
if (scenario === 'topWithIframe') outer.frame = {contentWindow: {document: doc()}};
if (scenario === 'bothDocuments') {
  const framed = mode === 'detail' ? detail(true) : list();
  framed.heading.textContent = 'フレームの連絡通知';
  outer.frame = {contentWindow: {document: framed}};
}
if (scenario === 'sameDocument') outer.frame = {contentWindow: {document: outer}};
if (scenario === 'inaccessibleIframe') outer.frame = {get contentWindow() { throw new Error('cross origin'); }};
const other = outer !== inner ? outer
  : ['topWithIframe', 'bothDocuments'].includes(scenario) ? outer.frame.contentWindow.document : null;
const storage = new Map(); const storageKey = '__MBG_MESSAGE_STARS_OPEN_MESSAGE';
if (mode === 'detail' && ['remembered', 'mismatch', 'storageDenied'].includes(scenario)) storage.set(storageKey, JSON.stringify({
  keijitype: '1', genrecd: '40', seqNo: '508182', title: scenario === 'mismatch' ? '別の表題' : title
}));
const messages = [], requests = [], scans = [], intervals = new Map(); let timerId = 0;
const context = {document: outer, frames: outer.frame && scenario !== 'sameDocument' && scenario !== 'inaccessibleIframe'
    ? [{document: outer.frame.contentWindow.document, frames: []}] : [],
  URL: class extends URL { constructor(...args) { super(...args); urlReads += 1; } },
  location: {origin: new URL(base).origin}, window: null,
  top: {get sessionStorage() {
    if (scenario === 'storageDenied') throw new Error('storage denied');
    return {setItem: (key, value) => storage.set(key, value), getItem: key => storage.get(key) || null};
  }},
  GakujoMessageStars: {postMessage: value => messages.push(JSON.parse(value))},
  setInterval: callback => { intervals.set(++timerId, callback); return timerId; },
  clearInterval: id => intervals.delete(id),
  XMLHttpRequest: class {
    open(method, url, async) { requests.push({method, url, async}); }
    send() {
      if (scenario === 'networkError') throw new Error('network');
      this.status = scenario === 'httpError' ? 500 : 200; this.responseText = 'fixture';
    }
  },
  DOMParser: class { parseFromString() { return inner; } }
};
context.window = context; vm.createContext(context);
const counts = [], pressed = [], intervalCounts = [], listenerCounts = [], styleCounts = [];
const listenerAddCounts = [], otherListenerCounts = [], otherButtonCounts = [], otherStyleCounts = [];
const originalText = inner.row?.textContent;
let result, event, inside, beforeTitle, staleButton, rowTextUnchanged = true, timerReadsUnchanged = true;
scripts.forEach((script, index) => {
  const output = vm.runInContext(script, context);
  if (mode === 'fetch') result = JSON.parse(output);
  if (mode === 'scan' && index > 0) scans.push(JSON.parse(output));
  const buttons = inner.querySelectorAll('button');
  counts.push(buttons.length); pressed.push(buttons[0]?.getAttribute('aria-pressed') ?? null);
  intervalCounts.push(intervals.size); listenerCounts.push(inner.listeners.click ? 1 : 0);
  listenerAddCounts.push(inner.listenerAdds || 0);
  styleCounts.push(inner.querySelectorAll('style').length);
  otherListenerCounts.push(other?.listeners.click ? 1 : 0);
  otherButtonCounts.push(other?.querySelectorAll('button').length || 0);
  otherStyleCounts.push(other?.querySelectorAll('style').length || 0);
  const beforeReads = [rowReads, urlReads];
  for (const callback of intervals.values()) callback();
  if (mode === 'list' || mode === 'documents') timerReadsUnchanged &&= rowReads === beforeReads[0] && urlReads === beforeReads[1];
  rowTextUnchanged &&= inner.row?.textContent === originalText;
  if (index === 0 && buttons[0] && (mode === 'list' || mode === 'detail')) {
    staleButton = buttons[0]; inside = staleButton.parentNode === inner.action;
    beforeTitle = staleButton.nextElementSibling === inner.heading;
    event = click(staleButton);
  }
  if (index === 3 && staleButton) click(staleButton);
});
let capture, remembered, oldListenerRemoved, oldButtonCount, detailCounts = [];
let rememberedTitles, removedFrameListener, removedFrameButtons, remainingTopButtons;
if (mode === 'documents') {
  rememberedTitles = [];
  for (const current of [inner, other]) {
    click(current.querySelector('button'));
    click(current.heading);
    rememberedTitles.push(JSON.parse(storage.get(storageKey)).title);
  }
  delete outer.frame;
  for (const callback of intervals.values()) callback();
  removedFrameListener = !other.listeners.click;
  removedFrameButtons = other.querySelectorAll('button').length;
  remainingTopButtons = inner.querySelectorAll('button').length;
}
if (mode === 'remember') {
  const old = inner;
  capture = inner.captures.click;
  click(add(inner.heading, 'span'));
  remembered = JSON.parse(storage.get(storageKey) || 'null');
  for (let i = 0; i < 2; i += 1) {
    inner = detail();
    if (scenario === 'topWithIframe') {
      inner.frame = outer.frame;
      context.document = inner;
    } else outer.frame.contentWindow.document = inner;
    for (const callback of intervals.values()) callback();
    detailCounts.push(inner.querySelectorAll('button').length);
  }
  oldListenerRemoved = !old.listeners.click; oldButtonCount = old.querySelectorAll('button').length;
}
process.stdout.write(JSON.stringify({result, requests, scans, counts, pressed, intervalCounts, listenerCounts,
  styleCounts, listenerAddCounts, otherListenerCounts, otherButtonCounts, otherStyleCounts,
  rememberedTitles, removedFrameListener, removedFrameButtons, remainingTopButtons,
  inside, beforeTitle, prevented: event?.prevented, stopped: event?.stopped, navigations,
  messages, rowTextUnchanged, timerReadsUnchanged, capture, remembered, detailCounts, oldListenerRemoved, oldButtonCount}));
