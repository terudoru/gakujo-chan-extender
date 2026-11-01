const vm: any = require('node:vm');
const script = process.argv[2];
const base = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do?_flowExecutionKey=k1';

function input(name?: any, type?: any, value?: any, checked?: any) {
  return {
    name, value, checked: !!checked, id: '', className: '',
    innerText: '', textContent: '',
    getAttribute(attr) { return attr === 'type' ? type : null; },
    dispatchEvent() {}
  };
}
const fields: any = [
  input('_flowExecutionKey', 'hidden', 'k1'),
  input('_eventId', 'hidden', ''),
  input('check1', 'checkbox', 'true', true),
  input('check2', 'checkbox', 'true', true),
  input('startYmd', 'text', '2026/10/07'),
  input('endYmd', 'text', '2026/11/04'),
];
const form: any = {
  name: 'scheduleExportForm', id: 'scheduleExportForm', className: '',
  method: 'post', action: '/campusweb/campussquare.do', value: '',
  innerText: 'カテゴリ 時間割コマ情報 対象期間 エクスポート実行',
  textContent: '',
  fields,
  getAttribute() { return null; },
  querySelector(selector) {
    return selector.indexOf('_eventId') >= 0 ? fields[1] : null;
  },
  querySelectorAll(selector) {
    if (selector.indexOf('checkbox') >= 0) {
      return fields.filter((f) => f.getAttribute('type') === 'checkbox');
    }
    return selector === 'input' ? fields : fields;
  }
};
class FormData {
  [key: string]: any;
  constructor(owner) {
    this.entries = owner.fields
      .filter((f) => f.getAttribute('type') !== 'checkbox' || f.checked)
      .map((f) => [f.name, f.value]);
  }
  [Symbol.iterator]() { return this.entries[Symbol.iterator](); }
}
const requests: any = [];
let postedBody = '';
const progressPage = '<html><body><meta http-equiv="REFRESH" content="0; ' +
  'URL=/campusweb/campussquare.do?_flowExecutionKey=k2&amp;_eventId=output">' +
  '<span>データ出力処理が完了しました。</span></body></html>';
class XMLHttpRequest {
  [key: string]: any;
  open(method, url) { this.method = method; this.url = new URL(url); }
  setRequestHeader() {}
  send(body) {
    requests.push(this.method + ' ' + this.url.pathname + this.url.search);
    if (this.method === 'POST') {
      postedBody = body;
      this.responseText = progressPage;
      this.contentType = 'text/html;charset=UTF-8';
    } else {
      this.responseText = 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n';
      this.contentType = 'text/plain;charset=UTF-8';
    }
    this.status = 200;
    this.responseURL = this.url.href;
  }
  getResponseHeader(name) {
    return name === 'Content-Type' ? this.contentType : null;
  }
}
class DOMParser {
  [key: string]: any;
  parseFromString(html) {
    const metas: any = [];
    const pattern = /<meta\s+http-equiv="([^"]*)"\s+content="([^"]*)"/gi;
    let match;
    while ((match = pattern.exec(html)) !== null) {
      const attrs: any = {
        'http-equiv': match[1],
        content: match[2].replace(/&amp;/g, '&')
      };
      metas.push({getAttribute(name) { return attrs[name] || null; }});
    }
    return {querySelectorAll(selector) { return selector === 'meta' ? metas : []; }};
  }
}
const doc: any = {
  location: {href: base},
  title: 'スケジュール',
  querySelectorAll(selector) { return selector === 'form' ? [form] : []; }
};
const output: any = vm.runInNewContext(script, {
  window: {document: doc, frames: []},
  URL, URLSearchParams, FormData, XMLHttpRequest, DOMParser, Event: class {
  [key: string]: any;}
});
const payload: any = JSON.parse(String(output));
payload.requests = requests;
payload.body = postedBody;
process.stdout.write(JSON.stringify(payload));

