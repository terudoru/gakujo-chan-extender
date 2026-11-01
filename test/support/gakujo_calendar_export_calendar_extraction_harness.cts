const vm: any = require('node:vm');
const extractionScript = process.argv[2];

function cell(text?: any) {
  return {
    innerText: String(text || ''),
    textContent: String(text || ''),
    querySelectorAll() { return []; }
  };
}

function row(values?: any) {
  const children: any = values.map(cell);
  const text: any = values.join(' ');
  return {
    children,
    innerText: text,
    textContent: text
  };
}

function table(rows?: any) {
  return {
    querySelectorAll(selector) {
      return selector === 'tr' ? rows : [];
    }
  };
}

function documentWithTables(tables?: any) {
  return {
    body: cell(''),
    location: {href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/'},
    querySelectorAll(selector) {
      return selector === 'table' ? tables : [];
    }
  };
}

const scheduleTable: any = table([
  row(['', '月', '火', '水']),
  row(['', '1限: コンピュータ基礎 @ A-101', '', ''])
]);
const structuredTable: any = table([
  row(['開講番号', '科目名', '曜日', '時限', '教室']),
  row(['262G5001', '物理学基礎BⅠ', '火', '2限', 'F-271'])
]);
const child: any = {
  document: documentWithTables([structuredTable]),
  frames: []
};
const root: any = {
  document: documentWithTables([scheduleTable]),
  frames: [child]
};

const output: any = vm.runInNewContext(extractionScript, {
  window: root,
  URL
});
process.stdout.write(String(output));

