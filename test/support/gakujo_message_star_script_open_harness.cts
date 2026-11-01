const vm: any = require('node:vm');
const {scripts, scenario}: any = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const script = scripts[0];
const base = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
const requests: any = [];
const link = href => ({getAttribute: name => name === 'href' ? href : null,
  textContent: '  授業のお知らせ  [新着]  '});
const mobile: any = scenario.startsWith('smartphone');
const paged: any = ['laterPage', 'smartphoneLaterPage', 'offsetPage', 'pagedGone',
  'pageLoop', 'pageCap', 'pageHttpError', 'pageMissing'].includes(scenario);
const keyAt = index => ['first%20key', 'second-key', 'third-key'][index] || 'page-' + index + '-key';
const action = href => ({
  getAttribute: name => name === 'onclick' ? 'location.href="' + href.replace(/&/g, '&amp;') + '"' : null,
  textContent: 'スター 授業のお知らせ 掲示期間： 2026/10/01 ～ 2026/11/01',
  querySelector: selector => selector === 'p' ? {textContent: '  授業のお知らせ [新着]  '} : null
});
function makeDoc(index?: any) {
  const missing = scenario === 'missing' + index || (scenario === 'pageMissing' && index === 3);
  const hasKey = scenario !== 'noKey';
  return {
    title: missing ? 'ログイン' : scenario === 'systemError' ? 'SYSTEM ERROR'
      : mobile ? 'CampusSquare for WEB' : '連絡通知一覧',
    body: {textContent: mobile && !missing ? '連絡通知 未読一覧' : ''},
    querySelector(selector) {
      if (mobile && (scenario !== 'smartphoneMixedKeys' || index === 0)) return null;
      if (selector.startsWith('a[')) return hasKey && index !== 1
        ? link('campussquare.do?_flowExecutionKey=' + keyAt(index)) : null;
      return hasKey && index === 1 ? {value: 'second-key'} : null;
    },
    querySelectorAll(selector) {
      if (paged && index >= 2) {
        if (selector === 'a,button,input[type="button"],input[type="submit"]') {
          if (index !== 2 && scenario !== 'pageCap' && scenario !== 'pageLoop') return [];
          const href = (scenario === 'offsetPage' ? '?' : 'campussquare.do?') + (scenario === 'offsetPage' ? '' :
            '_flowExecutionKey=' + keyAt(index) + '&_eventId=paging&') +
            '_displayOffset=' + ((index - 1) * 500) + '&_displayCount=500';
          const attributes = mobile ? {onclick: 'location.href="' + href + '"'} : {href};
          return [{textContent: '次へ', getAttribute: name => attributes[name] || null}];
        }
        const rowSelector = mobile ? '[onclick*="seqNo="]' : 'a[href*="seqNo="]';
        if (selector === rowSelector) {
          const found = index === 3 && ['laterPage', 'smartphoneLaterPage', 'offsetPage'].includes(scenario);
          return Array.from({length: index === 2 || scenario === 'pageLoop' ? 500 : 1}, (_, row) => {
            const seq = found ? '507762' : String(scenario === 'pageLoop' ? row : index * 500 + row);
            const href = 'campussquare.do?_flowExecutionKey=' + keyAt(index) +
              '&_eventId=confirm&keijitype=1&genrecd=40&seqNo=' + seq;
            return mobile ? action(href) : link(href);
          });
        }
      }
      if (mobile) {
        if (selector === '[onclick*="_flowExecutionKey="]') return [action(
          'campussquare.do?_flowExecutionKey=' + keyAt(index) + '&_eventId=paging')];
        if (selector !== '[onclick*="seqNo="]' || index !== 2 || scenario === 'smartphoneGone') return [];
        return [action('campussquare.do?_flowExecutionKey=third-key&_eventId=confirm&keijitype=1&genrecd=' +
          (scenario === 'smartphoneWrongGenre' ? '41' : '40') + '&seqNo=507762')];
      }
      if (selector !== 'a[href*="seqNo="]' || index !== 2 || scenario === 'gone') return [];
      return [link('campussquare.do?_flowExecutionKey=third-key&_eventId=confirm&keijitype=1&genrecd=' +
        (scenario === 'wrongGenre' ? '41' : '40') + '&seqNo=507762')];
    }
  };
}
// List responses followed by the detail response consumed by WebView.
const listResponses = scenario === 'pageCap' ? 22 : paged ? 4 : 3;
const responses: any = Array.from({length: listResponses + 1}, (_, index) => ({
  status: scenario === 'httpError' || (scenario === 'pageHttpError' && index === 3) ? 500 : 200,
  text: index === listResponses ? 'detail response' : String(index)
}));
class XHR {
  [key: string]: any;
  open(method, url, async) { this.url = url; this.async = async; }
  send() {
    requests.push(this.url);
    const response: any = responses.shift();
    if (!response) throw new Error('unexpected detail fetch');
    this.status = response.status; this.responseText = response.text;
  }
}
const context: any = {URL, XMLHttpRequest: XHR,
  DOMParser: class {
  [key: string]: any; parseFromString(text) { return makeDoc(Number(text)); } },
  location: {origin: scenario === 'otherOrigin' ? 'https://login.example.test' : 'https://gakujo.iess.niigata-u.ac.jp'}
};
const storage: any = new Map();
context.window = {top: {get sessionStorage() {
  if (scenario === 'storageDenied') throw new Error('storage denied');
  return {setItem: (key, value) => storage.set(key, value)};
}}};
const result: any = JSON.parse(vm.runInNewContext(script, context));
const beforeNavigationCount = requests.length;
let navigatedResponse;
if (result.status === 'ok') {
  const navigation: any = new XHR(); navigation.open('GET', result.url, true); navigation.send();
  navigatedResponse = navigation.responseText;
}
const remembered: any = JSON.parse(storage.get('__MBG_MESSAGE_STARS_OPEN_MESSAGE') || 'null');
process.stdout.write(JSON.stringify({result, requests, beforeNavigationCount, navigatedResponse, remembered}));

