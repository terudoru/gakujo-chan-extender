const vm: any = require('node:vm');
const assert: any = require('node:assert/strict');
const {scripts, scenario}: any = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const base = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
let headerQueryCount = 0, urlParseCount = 0, rowCellReadCount = 0, pressedWriteCount = 0;
const performanceScenario = scenario === 'largeList' || scenario === 'growingList';
class Element {
  [key: string]: any;
  constructor(tag, value = '') {
    this.tagName = tag.toUpperCase(); this._text = value; this.children = [];
    this.attributes = {}; this.style = {}; this.listeners = {}; this.captures = {}; this.parentNode = null;
  }
  get textContent() { return this._text + this.children.map(e => e.textContent).join(''); }
  set textContent(value) { this._text = value; this.children = []; }
  get innerText() { return this.textContent; }
  setAttribute(key, value) { if (key === 'aria-pressed') pressedWriteCount++; this.attributes[key] = value; }
  getAttribute(key) { return this.attributes[key] || null; }
  addEventListener(key, callback, capture) { this.listeners[key] = callback; this.captures[key] = capture; }
  removeEventListener(key, callback, capture) {
    if (this.listeners[key] === callback && this.captures[key] === capture) {
      delete this.listeners[key]; delete this.captures[key];
    }
  }
  appendChild(child) { return this.insertBefore(child, null); }
  insertBefore(child, before) {
    child.parentNode = this; child.ownerDocument = this.ownerDocument;
    const index = before ? this.children.indexOf(before) : this.children.length;
    this.children.splice(index, 0, child); return child;
  }
  remove() {
    if (this.parentNode) this.parentNode.children = this.parentNode.children.filter(e => e !== this);
    this.parentNode = null;
  }
  get isConnected() { return this.parentNode !== null; }
  get nextElementSibling() {
    return this.parentNode.children[this.parentNode.children.indexOf(this) + 1] || null;
  }
  get cells() {
    rowCellReadCount += 1;
    return this.children.filter(e => e.tagName === 'TD' || e.tagName === 'TH');
  }
  closest(selector) {
    for (let e = this; e; e = e.parentNode) if (e.matches(selector)) return e;
    return null;
  }
  matches(selector) {
    const parts: any = /^(\w+)(?:\.([\w-]+))?(?:\[(\w+)(?:\*="([^"]*)")?\])?$/.exec(selector);
    if (!parts || this.tagName !== parts[1].toUpperCase()) return false;
    if (parts[2] && this.attributes.class !== parts[2]) return false;
    if (parts[3] && !(parts[3] in this.attributes)) return false;
    if (parts[4] && !this.attributes[parts[3]].includes(parts[4])) return false;
    return true;
  }
  querySelectorAll(selector) {
    if (this.tagName === 'TABLE' && selector === 'th') headerQueryCount += 1;
    const result: any = [];
    for (const child of this.children) {
      if (child.matches(selector)) result.push(child);
      result.push(...child.querySelectorAll(selector));
    }
    return result;
  }
  querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
}
function doc(url?: any) {
  const root: any = new Element('html'); root.ownerDocument = root;
  root.baseURI = base + url; root.URL = root.baseURI; root.location = {href: root.baseURI};
  root.createElement = tag => { const e: any = new Element(tag); e.ownerDocument = root; return e; };
  root.getElementById = id => id === 'main-frame-if' ? root.frame || null
    : root.querySelectorAll('style').find(e => e.id === id) || null;
  root.head = root.appendChild(root.createElement('head'));
  root.body = root.appendChild(root.createElement('body'));
  return root;
}
function add(parent?: any, tag?: any, text: any = '', attrs: any = {}) {
  const e: any = parent.ownerDocument.createElement(tag); e.textContent = text;
  Object.entries(attrs).forEach(([k,v]) => e.setAttribute(k,v)); return parent.appendChild(e);
}
function list(genre?: any, allGenre: any = false, missingHeaders: any = false) {
  const d: any = doc('campussquare.do?_flowId=KJW0001100-flow');
  const table: any = add(d.body, 'table'); const header: any = add(table, 'tr');
  const labels = missingHeaders ? ['表題','未読','返信未読'] : allGenre
    ? ['ジャンル','表題','未読','返信未読','連絡通知期間','掲載日時'] : genre
    ? ['ジャンル','科目名','担当者','開講学期','曜日時限','表題','未読','返信未読','連絡通知期間','掲載日時']
    : ['掲載日時','表題','返信未読','ジャンル','所属','氏名','連絡通知期間'];
  const values = missingHeaders ? [null,'○','-'] : allGenre
    ? ['授業連絡',null,'○','-','2026/10/01～2026/11/01','2026/10/01 09:00'] : genre
    ? ['授業連絡','科目','担当教員','後期','月1',null,'','','2026/10/01～2026/11/01','2026/10/01 09:00']
    : ['2026/10/01 09:00',null,'','授業連絡','工学部','担当教員','2026/10/01～2026/11/01'];
  // Split headers across rows so lookup must include every th.
  let lowerHeader;
  function secondHeader() { return lowerHeader || (lowerHeader = add(table, 'tr')); }
  d.headers = labels.map((label, index) => add(index < 5 ? header : secondHeader(), 'th', label));
  d.addRow = seqNo => {
    const row: any = add(table, 'tr');
    let link;
    values.forEach(value => {
      const cell: any = add(row, 'td', value || '');
      if (value === null) link = add(cell, 'a', '授業のお知らせ [新着]', {
        href: 'campussquare.do?_flowExecutionKey=temporary&_eventId=' +
          (genre || allGenre ? 'confirm' : 'displayMidoku') + '&keijitype=1&genrecd=40&seqNo=' + seqNo
      });
    });
    if (!d.heading) d.heading = link;
    return link;
  };
  for (let i = 0; i < (scenario === 'largeList' ? 160 : 1); i += 1) d.addRow(507762 + i);
  return d;
}
function detail(attachment?: any, longBody?: any, noIds: any = false) {
  const d: any = doc('campussquare.do?' + (attachment || noIds ? '_flowExecutionKey=temporary' : 'keijitype=1&genrecd=40&seqNo=507762'));
  d.heading = add(d.body, 'span', '授業のお知らせ [新着]', {class: 'keiji-title'});
  add(d.body, 'span', scenario === 'detailDuplicateGenre'
    ? '[全学連絡通知 全学連絡通知]' : '[授業連絡通知 授業連絡]', {class: 'keiji-t-genre'});
  add(d.body, 'div', longBody ? '文'.repeat(4001) : ' 本文の一行目\n二行目 ', {class: 'keiji-naiyo'});
  for (const [label, value] of Object.entries({
    '連絡通知元': '担当教員', '連絡通知期間': '2026/10/01～2026/11/01',
    'メール送信': '送信済み', '送信日時': '2026/10/01 09:00', '添付ファイル': ''
  })) {
    const table: any = add(d.body, 'table', '', {class: 'keiji-normal'});
    add(add(table, 'tr'), 'th', label); const cell: any = add(add(table, 'tr'), 'td', value);
    if (label === '添付ファイル' && attachment) add(cell, 'a', '資料.pdf', {
      href: 'campussquare.do?_flowExecutionKey=temporary&_eventId=download&keijitype=1&genrecd=40&seqNo=507762&index=0'
    });
  }
  return d;
}
const isDetail: any = scenario.startsWith('detail');
const remembers: any = scenario.startsWith('remembered');
let inner = isDetail ? detail(scenario === 'detailAttachment', scenario === 'detailLong')
  : list(scenario === 'genre' || scenario === 'rememberedGenre', scenario === 'allGenre', scenario === 'missingHeaders');
const outer = scenario === 'iframe' || scenario === 'navigate' || remembers ? doc('campusportal.do') : inner;
if (outer !== inner) outer.frame = {contentWindow: {document: inner}};
const messages: any = []; const intervals: any = new Map(); let intervalId = 0;
const context: any = {document: outer, URL: class extends URL {
  [key: string]: any;
  constructor(...args: [string | URL, (string | URL)?]) { super(...args); urlParseCount += 1; }
}, Set, window: null};
context.window = context;
const storage: any = new Map();
const storageKey = '__MBG_MESSAGE_STARS_OPEN_MESSAGE';
// A separate top object catches accidental use of the frame's own storage.
context.top = {get sessionStorage() {
  if (scenario === 'rememberedStorageDenied') throw new Error('storage denied');
  return {setItem: (key, value) => storage.set(key, value), getItem: key => storage.get(key) || null};
}};
context.GakujoMessageStars = {postMessage: value => messages.push(JSON.parse(value))};
context.setInterval = fn => { intervals.set(++intervalId, fn); return intervalId; };
context.clearInterval = id => intervals.delete(id);
vm.createContext(context);
const counts: any = [], buttonTexts: any = [], pressedStates: any = [], intervalCounts: any = [], listenerCounts: any = [];
const styleCounts: any = [], styleTexts: any = [], outerStyleCounts: any = [], rowTexts: any = [];
const headerQueryCounts: any = [], urlParseCounts: any = [], rowCellReadCounts: any = [];
let timerReadsUnchanged = true, headersAfterClick;
const originalRowText = inner.heading.closest('tr')?.innerText || null;
let beforeTitle, label, buttonTitle, prevented = false, stopped = false, oldButton;
scripts.forEach((script, index) => {
  if (scenario === 'reusedLink' && index === 1) {
    inner.heading.setAttribute('href', inner.heading.getAttribute('href').replace('507762', '507763'));
    inner.heading.textContent = '別のお知らせ';
  }
  vm.runInContext(script, context);
  headerQueryCounts.push(headerQueryCount);
  urlParseCounts.push(urlParseCount);
  rowCellReadCounts.push(rowCellReadCount);
  if (performanceScenario) {
    const pressedWritesBeforeTick = pressedWriteCount;
    for (const callback of intervals.values()) callback();
    assert.equal(pressedWriteCount, pressedWritesBeforeTick, 'unchanged stars must not rewrite aria-pressed');
    timerReadsUnchanged = timerReadsUnchanged &&
      headerQueryCount === headerQueryCounts[index] &&
      urlParseCount === urlParseCounts[index] && rowCellReadCount === rowCellReadCounts[index];
  }
  const buttons: any = inner.querySelectorAll('button');
  counts.push(buttons.length);
  buttonTexts.push(buttons[0] ? buttons[0].textContent : null);
  pressedStates.push(buttons[0] ? buttons[0].getAttribute('aria-pressed') : null);
  const styles: any = inner.querySelectorAll('style');
  styleCounts.push(styles.length);
  styleTexts.push(inner.getElementById('mbg-message-star-style')?.textContent || null);
  outerStyleCounts.push(outer.querySelectorAll('style').length);
  rowTexts.push(inner.heading.closest('tr')?.innerText || null);
  intervalCounts.push(intervals.size);
  listenerCounts.push(inner.listeners.click ? 1 : 0);
  if (index === 0 && buttons[0] && !performanceScenario) {
    oldButton = buttons[0]; label = oldButton.getAttribute('aria-label');
    buttonTitle = oldButton.title;
    beforeTitle = oldButton.nextElementSibling === inner.heading;
    oldButton.listeners.click({preventDefault() { prevented = true; }, stopPropagation() { stopped = true; }});
  }
  if (index === 3) oldButton.listeners.click({preventDefault() {}, stopPropagation() {}});
  if (scenario === 'growingList' && index === 0) {
    inner.headers.find(th => th.textContent === '氏名').textContent = '非表示';
    inner.addRow(507763);
  }
});
if (performanceScenario) {
  const link = scenario === 'growingList'
    ? inner.querySelectorAll('a[href*="seqNo="]')[1] : inner.heading;
  link.textContent = '更新された表題';
  link.parentNode.querySelector('button').listeners.click({preventDefault() {}, stopPropagation() {}});
  headersAfterClick = headerQueryCount;
}
let reusedLabel, reusedButtonTitle, clickedPressed, clickedLabel;
if (scenario === 'reusedLink') {
  const button: any = inner.querySelector('button');
  reusedLabel = button.getAttribute('aria-label'); reusedButtonTitle = button.title;
  inner.heading.setAttribute('href', inner.heading.getAttribute('href').replace('507763', '507764'));
  inner.heading.textContent = 'クリック直前のお知らせ';
  button.listeners.click({preventDefault() {}, stopPropagation() {}});
  clickedPressed = button.getAttribute('aria-pressed');
  clickedLabel = button.getAttribute('aria-label');
}
let navigatedTitle, navigatedButtonText, navigatedPressed, navigatedStyleCount;
let reloadedButtonText, reloadedPressed, reloadedStyleCount, capture, oldListListenerRemoved;
let rememberedBeforeClick, remembered, rememberedAfterReload, oldListButtonCount;
let oldListStyleCount, oldDetailStyleCount;
if (scenario === 'navigate' || remembers) {
  const oldList = inner;
  if (remembers) {
    rememberedBeforeClick = JSON.parse(storage.get(storageKey) || 'null');
    capture = inner.captures.click;
    inner.listeners.click({target: add(inner.heading, 'span')});
    remembered = JSON.parse(storage.get(storageKey) || 'null');
  }
  inner = detail(false, false, remembers); outer.frame.contentWindow.document = inner;
  if (scenario === 'rememberedMismatch') inner.heading.textContent = '別の連絡通知';
  // The detail need not retain the list's [新着] suffix.
  else if (remembers) inner.heading.textContent = '授業のお知らせ';
  for (const callback of intervals.values()) callback();
  oldListListenerRemoved = !oldList.listeners.click;
  oldListButtonCount = oldList.querySelectorAll('button').length;
  oldListStyleCount = oldList.querySelectorAll('style').length;
  navigatedTitle = inner.heading.textContent;
  navigatedButtonText = inner.querySelector('button')?.textContent ?? null;
  navigatedPressed = inner.querySelector('button')?.getAttribute('aria-pressed') || null;
  navigatedStyleCount = inner.querySelectorAll('style').length;
  if (remembers) {
    const oldDetail = inner;
    const heading = inner.heading.textContent;
    inner = detail(false, false, true); inner.heading.textContent = heading;
    outer.frame.contentWindow.document = inner;
    for (const callback of intervals.values()) callback();
    oldDetailStyleCount = oldDetail.querySelectorAll('style').length;
    reloadedButtonText = inner.querySelector('button')?.textContent ?? null;
    reloadedPressed = inner.querySelector('button')?.getAttribute('aria-pressed') || null;
    reloadedStyleCount = inner.querySelectorAll('style').length;
    rememberedAfterReload = JSON.parse(storage.get(storageKey) || 'null');
  }
}
process.stdout.write(JSON.stringify({counts, buttonTexts, pressedStates, styleCounts, styleTexts,
  outerStyleCounts, originalRowText, rowTexts, intervalCounts, listenerCounts, beforeTitle, label, buttonTitle,
  prevented, stopped, messages, navigatedTitle, navigatedButtonText, navigatedPressed,
  navigatedStyleCount, reloadedButtonText, reloadedPressed, reloadedStyleCount, capture,
  oldListListenerRemoved, oldListButtonCount, oldListStyleCount, oldDetailStyleCount,
  rememberedBeforeClick, remembered, rememberedAfterReload,
  reusedLabel, reusedButtonTitle, clickedPressed, clickedLabel,
  headerQueryCounts, urlParseCounts, rowCellReadCounts, timerReadsUnchanged, headersAfterClick}));

