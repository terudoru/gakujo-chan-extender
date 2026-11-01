const vm: any = require('node:vm');
const script = process.argv[2];
const scenario = process.argv[3];
const requests: any = [];
function cell(text?: any) { return {textContent: text}; }
function row(kind?: any, cells?: any) { return {className: kind, cells: cells.map(cell)}; }
const weeks: any = {
  '20261228': [
    row('kyuko-kyuko', ['12月29日(火)', '1限', '263T0506', 'プログラミング基礎Ⅰ', '岩城', '計算機演習室']),
  ],
  '20270104': [
    row('kyuko-hoko', ['1月9日(土)', '3限', '263T0506', 'プログラミング基礎Ⅰ', '岩城', 'A-101']),
  ],
};
let lastUrl = '';
class XMLHttpRequest {
  [key: string]: any;
  open(method, url) { this.url = url; }
  send() {
    lastUrl = this.url;
    const day = (this.url.match(/day=([0-9]{8})/) || [])[1];
    const key = (this.url.match(/_flowExecutionKey=([^&]+)/) || [])[1];
    requests.push(day ? key + ' ' + day : '_flowId=KHW0001100-flow');
    if (day === '20270104' && scenario === 'timeout') throw new Error('Timeout');
    this.status = day === '20270104' && scenario === 'httpError' ? 503 : 200;
    this.responseText = '';
  }
}
let page = 0;
class DOMParser {
  [key: string]: any;
  parseFromString() {
    page += 1;
    const day = (lastUrl.match(/day=([0-9]{8})/) || [])[1];
    const invalidPage = day === '20270104' && scenario === 'htmlError';
    const rows = day && scenario !== 'empty' && !invalidPage ? (weeks[day] || []) : [];
    return {
      querySelector(selector) {
        if (invalidPage) return null;
        return selector.indexOf('_flowExecutionKey') >= 0 ? {value: 'k' + page} : null;
      },
      querySelectorAll() { return rows; }
    };
  }
}
const output: any = vm.runInNewContext(script, {XMLHttpRequest, DOMParser, Date, JSON, String, Number, Array});
const payload: any = JSON.parse(String(output));
payload.requests = requests;
process.stdout.write(JSON.stringify(payload));

