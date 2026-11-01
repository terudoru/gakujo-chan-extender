const vm: any = require('node:vm');
const options: any = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const owned = '[data-mbg-message-reader-owned="true"]';
const frameUrls: any = [], timers: any = new Map(), intervals: any = new Map();
let timerId = 0, reloadCount = 0;

class Element {
  [key: string]: any;
  constructor(tag, doc) {
    this.tagName = tag.toUpperCase(); this.ownerDocument = doc;
    this.children = []; this.attributes = {}; this.listeners = {}; this.style = {};
  }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  getAttribute(name) { return this.attributes[name] ?? null; }
  addEventListener(name, callback) { this.listeners[name] = callback; }
  appendChild(node) { return this.insertBefore(node, null); }
  insertBefore(node, before) {
    if (node.parentNode) node.remove();
    const index = before ? this.children.indexOf(before) : this.children.length;
    if (index < 0) throw new Error('Reference node is not a child');
    this.children.splice(index, 0, node); node.parentNode = this;
    if (node.tagName === 'IFRAME' && node.src) {
      frameUrls.push(node.src); node.onload();
    }
    return node;
  }
  remove() {
    if (this.parentNode) this.parentNode.children.splice(this.parentNode.children.indexOf(this), 1);
    this.parentNode = null;
  }
  closest(selector) {
    for (let node = this; node; node = node.parentNode) {
      if (node.tagName.toLowerCase() === selector) return node;
    }
    return null;
  }
  contains(node) { return node === this || elements(this).includes(node); }
}

function elements(root?: any) {
  return root.children.flatMap(child => [child, ...elements(child)]);
}
function add(parent?: any, tag?: any) { return parent.appendChild(new Element(tag, parent.ownerDocument)); }
function makeDocument(hasList?: any) {
  const doc: any = {
    baseURI: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/' +
      (hasList ? 'mobile/list.do' : 'empty/frame.do'),
    location: {href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/ignored.do'},
    createElement(tag) { return new Element(tag, doc); },
    getElementById(id) {
      if (id === 'main-frame-if') return doc.frame || null;
      return elements(doc.body).find(node => node.id === id) || null;
    },
    querySelector() { return null; }, // No desktop table or tab menu.
    querySelectorAll(selector) {
      if (selector === 'div.button[onclick*="seqNo="]') {
        return elements(doc.body).filter(node => node.tagName === 'DIV' &&
          node.getAttribute('class') === 'button' && node.getAttribute('onclick').includes('seqNo='));
      }
      if (selector === owned) return elements(doc.body).filter(node =>
        node.getAttribute('data-mbg-message-reader-owned') === 'true');
      throw new Error('Unexpected selector: ' + selector);
    }
  };
  doc.body = new Element('body', doc);
  doc.body.textContent = hasList ? (options.unread ? '連絡通知 未読一覧' : '連絡通知 授業連絡') : '';
  if (hasList) {
    const navigation: any = add(doc.body, 'table');
    add(navigation, 'tr');
    const urls = options.messageUrls || [1, 2, 3, 4].map(seqNo =>
      'campussquare.do?_flowExecutionKey=mobile%20key&_eventId=' +
      (options.unread ? 'displayMidoku' : 'confirm') + '&keijitype=1&genrecd=40&seqNo=' + seqNo);
    doc.listTable = add(doc.body, 'table');
    const listBody: any = add(doc.listTable, 'tbody');
    doc.messageRows = [];
    for (const [index, url] of urls.entries()) {
      const row: any = add(listBody, 'tr');
      doc.messageRows.push(row);
      add(row, 'td').setAttribute('class', 'category-frame');
      const itemTable: any = add(add(row, 'td'), 'table');
      itemTable.setAttribute('class', 'bgnone');
      const button: any = add(add(add(add(itemTable, 'tbody'), 'tr'), 'td'), 'div');
      button.setAttribute('class', 'button');
      const quote = index % 2 ? '"' : "'";
      button.setAttribute('onclick', 'location.href=' + quote + url.replace(/&/g, '&amp;') + quote);
    }
  }
  return doc;
}

const document: any = makeDocument(options.frame !== 'list');
let frameDocument;
if (options.frame === 'empty' || options.frame === 'list') {
  frameDocument = makeDocument(options.frame === 'list');
  document.frame = {contentWindow: {document: frameDocument}};
} else if (options.frame === 'inaccessible') {
  document.frame = {get contentWindow() { throw new Error('Cross-origin frame'); }};
}
const docs = frameDocument ? [document, frameDocument] : [document];
const listDoc = options.frame === 'list' ? frameDocument : document;
const context: any = {
  document, URL, location: {reload() { reloadCount += 1; }},
  fetch: async () => { throw new Error('Use the fake iframe fallback'); },
  setInterval(fn) { intervals.set(++timerId, fn); return timerId; },
  clearInterval(id) { intervals.delete(id); },
  setTimeout(fn) { timers.set(++timerId, fn); return timerId; },
  clearTimeout(id) { timers.delete(id); }
};
context.window = context;
vm.createContext(context);

async function main() {
  vm.runInContext(options.script, context);
  vm.runInContext(options.script, context);
  for (const callback of intervals.values()) callback();
  listDoc.messageRows[0].style.display = 'none'; // The exclude filter hides this message.
  const input: any = listDoc.getElementById('mbg-read-num-input');
  const button: any = listDoc.getElementById('mbg-read-button');
  if (input) input.value = '3';
  if (button) {
    // The first tap only asks for confirmation.
    await button.listeners.click();
    await button.listeners.click();
  }
  for (const callback of [...timers.values()]) callback();
  const status: any = listDoc.getElementById('mbg-read-status');
  const table = listDoc.listTable;
  const wrapper: any = listDoc.getElementById('mbg-read-controls');
  const controls: any = listDoc.querySelectorAll(owned);
  const result: any = {
    wrapperIsPreviousSibling: !!wrapper &&
      table.parentNode.children[table.parentNode.children.indexOf(table) - 1] === wrapper,
    wrapperCount: controls.filter(node => node.id === 'mbg-read-controls').length,
    controlIdsInWrapper: wrapper ? wrapper.children.map(node => node.id) : [],
    controlsOutsideMessageRows: controls.every(node =>
      !listDoc.messageRows.some(row => row.contains(node))),
    controlsVisibleAfterFirstRowHidden: controls.length > 0 && controls.every(node => {
      for (let current = node; current; current = current.parentNode) {
        if (current.style.display === 'none') return false;
      }
      return true;
    }),
    buttonText: button?.textContent, inputType: input?.type, defaultValue: input?.defaultValue,
    statusLive: status?.getAttribute('aria-live'), statusText: status?.textContent,
    frameUrls, reloadCount, ownedElementCount: docs.reduce((sum, doc) => sum + doc.querySelectorAll(owned).length, 0)
  };
  vm.runInContext(options.teardown, context);
  result.ownedAfterTeardown = docs.reduce((sum, doc) => sum + doc.querySelectorAll(owned).length, 0);
  process.stdout.write(JSON.stringify(result));
}
main().catch(error => { console.error(error); process.exitCode = 1; });

