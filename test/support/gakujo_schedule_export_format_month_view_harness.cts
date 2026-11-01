const vm: any = require('node:vm');
const script = process.argv[2];

function node(text?: any, extra?: any) {
  return Object.assign({
    innerText: text,
    textContent: text,
    children: [],
    querySelector() { return null; },
    querySelectorAll() { return []; },
    getAttribute() { return null; }
  }, extra || {});
}
function day(date?: any, text?: any) {
  const add: any = node('', {
    getAttribute(name) {
      return name === 'onclick' ? 'addSchedule(' + date + ');' : null;
    }
  });
  return node(text, {
    querySelector(selector) {
      return selector.indexOf('addSchedule') >= 0 ? add : null;
    },
    querySelectorAll() { return [add]; }
  });
}
function row(cells?: any) {
  return node(cells.map((cell) => cell.innerText).join('\t'), {children: cells});
}
const rows: any = [
  row(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => node(d))),
  row([
    day(20260928, '28\n[休日]夏期休業'),
    day(20260929, '29\n[休日]夏期休業'),
    day(20260930, '30\n[休日]夏期休業'),
    day(20261001, '1\n[休日]補講日'),
    day(20261002, '2\n1限:プログラミング基礎@A-101'),
    day(20261003, '3'),
    day(20261004, '4'),
  ]),
  row([
    day(20261005, '5'),
    day(20261006, '6\n4限:基礎数理@B-353'),
    // A quiz deadline names a course code and another day's date.
    day(20261007, '7\n2限:知的財産概論@備考欄参照\n' +
      '[小テスト][263T0005 知的財産概論]第2回【2026/10/14まで】'),
    day(20261008, '8'),
    day(20261009, '9'),
    day(20261010, '10'),
    day(20261011, '11'),
  ]),
];
const table: any = node('', {
  querySelectorAll(selector) { return selector === 'tr' ? rows : []; }
});
const doc: any = node('', {
  body: node(''),
  location: {href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'},
  querySelectorAll(selector) { return selector === 'table' ? [table] : []; }
});
process.stdout.write(String(vm.runInNewContext(script, {
  window: {document: doc, frames: []},
  URL
})));

