const vm: any = require('node:vm');
const {scripts, scenario, field, storageMode}: any = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const origin = 'https://gakujo.iess.niigata-u.ac.jp';
const expiredTitle = 'ページの有効期限ぎれ';
const normalDoc = () => ({title: '連絡通知', body: {innerText: 'メッセージの本文'},
  querySelectorAll: () => field ? [field] : []});
const expiredDoc = () => ({
  title: expiredTitle,
  body: {innerText: 'ページの有効期限が過ぎています。 メニューから再度操作を行なってください。'},
  querySelectorAll: () => field ? [field] : []
});
const frameReplacements: any = [], topReplacements: any = [], listeners: any = [];
let now = 100000;
let stored = scenario === 'malformedStorage' ? '{invalid json' : null;
const frameWindow: any = {
  document: expiredDoc(),
  location: {replace: target => frameReplacements.push(target)}
};
let src = '/campusweb/campussquare.do?_flowId=KJW0001100-flow';
const frame: any = {
  contentWindow: frameWindow,
  get contentDocument() { return frameWindow.document; },
  getAttribute(name) { return name === 'src' ? src : null; },
  addEventListener(name, callback) {
    if (name !== 'load') throw new Error('Unexpected event: ' + name);
    listeners.push(callback);
  }
};
let hasFrame = !scenario.startsWith('top') || scenario === 'topExpiredWithFrame';
let doc: any = normalDoc();
if (scenario === 'iframeNormal' || scenario === 'laterLoad' ||
    scenario === 'topExpiredWithFrame') frameWindow.document = normalDoc();
if (scenario === 'executionKey') src = '/campusweb/campussquare.do?_flowExecutionKey=stale-key';
if (scenario === 'encodedExecutionKey') src = '/campusweb/campussquare.do?%5FflowExecutionKey=stale-key';
if (scenario === 'otherOrigin') src = 'https://example.com/campusweb/campussquare.do?_flowId=flow';
if (scenario === 'missingSrc') src = null;
if (scenario === 'invalidSrc') src = 'https://[';
if (scenario === 'frameDenied') {
  Object.defineProperty(frame, 'contentDocument', {get() { return null; }});
  Object.defineProperty(frameWindow, 'document', {get() { throw new Error('Access denied'); }});
}
if (scenario === 'topExpired' || scenario === 'topExpiredWithFrame' ||
    scenario === 'topRecoveryLimit') doc = expiredDoc();
if (scenario === 'topKanjiExpired') doc.title = 'ページの有効期限切れ';
if (scenario === 'topTitleOnly') {
  doc.title = expiredTitle;
  Object.defineProperty(doc, 'body', {get() { throw new Error('Body must not be read'); }});
}
const expiredMessage = 'ページの有効期限が過ぎています';
if (scenario === 'topInnerTextExpired') doc.body.innerText = expiredMessage;
if (scenario === 'topTextContentExpired') doc.body = {textContent: expiredMessage};
if (scenario === 'topBodyBeyondLimit') doc.body.innerText = 'x'.repeat(200) + expiredTitle;
if (scenario === 'topExpiryNotice') doc.body.innerText = 'ページの有効期限切れについてのお知らせ。通常の連絡通知です。';
if (scenario === 'topShortExpiryBody') doc.body.innerText = expiredMessage.padEnd(299, 'x');
if (scenario === 'topLongExpiryBody') doc.body.innerText = expiredMessage.padEnd(300, 'x');
doc.getElementById = id => id === 'main-frame-if' && hasFrame ? frame : null;
const location: any = {
  origin,
  href: origin + (hasFrame ? '/campusweb/campusportal.do?page=main&tabId=XX'
    : '/campusweb/campussquare.do?_flowExecutionKey=stale-key'),
  replace: target => topReplacements.push(target)
};
const sessionStorage: any = {
  getItem(key) {
    if (key !== '__MBG_EXPIRED_RECOVERY') throw new Error('Unexpected storage key');
    if (scenario === 'storageReadDenied' ||
        ['readDenied', 'denied', 'deniedTop'].includes(storageMode)) throw new Error('Storage read denied');
    return stored;
  },
  setItem(key, value) {
    if (key !== '__MBG_EXPIRED_RECOVERY') throw new Error('Unexpected storage key');
    if (scenario === 'storageWriteDenied' ||
        ['writeDenied', 'denied', 'deniedTop'].includes(storageMode)) throw new Error('Storage write denied');
    stored = value;
  }
};
const context: any = {document: doc, location, sessionStorage, URL, Date: {now: () => now}};
context.window = context;
context.top = {};
if (storageMode === 'deniedTop') {
  Object.defineProperty(context, 'top', {get() { throw new Error('Cross-origin top'); }});
}
// Use the same URL for both scopes to verify their budgets are independent.
if (scenario.endsWith('RecoveryLimit')) src = origin + '/campusweb/campusportal.do?page=main';
vm.createContext(context);
for (const script of scripts) vm.runInContext(script, context);
const beforeLoad: any = frameReplacements.slice();
if (scenario === 'laterLoad') frameWindow.document = expiredDoc();
if (scenario === 'guardElapsed') now += 10000;
if (scenario === 'differentTarget') src = '/campusweb/campussquare.do?_flowId=KJW0001200-flow';
if (['laterLoad', 'guardElapsed', 'differentTarget'].includes(scenario)) {
  for (const listener of listeners) listener();
}
let recoveryCounts: any = [], otherTargetRecoveries = 0;
let multiTargetCounts: any = [], boundedTargetCount = null, prunedTargetCount = null;
if (scenario === 'multipleTargets') {
  const firstSrc = src;
  for (let i = 1; i < 4; i++) {
    src = firstSrc + '&page=' + i;
    for (const listener of listeners) listener();
  }
  multiTargetCounts.push(frameReplacements.length);
  src = firstSrc;
  for (const offset of [9999, 10000, 20000, 30000]) {
    now = 100000 + offset;
    for (const listener of listeners) listener();
    multiTargetCounts.push(frameReplacements.length);
  }
  for (let i = 0; i < 25; i++) {
    src = firstSrc + '&page=' + (i + 4);
    for (const listener of listeners) listener();
  }
  boundedTargetCount = Object.keys(context.__MBG_EXPIRED_RECOVERY).length;
  now += 120000;
  for (const listener of listeners) listener();
  prunedTargetCount = Object.keys(context.__MBG_EXPIRED_RECOVERY).length;
}
let repeatedBackCounts: any = [];
if (scenario === 'repeatedBack') {
  // Each Back lands on an expired page; recovery then loads the tab normally.
  for (let i = 1; i <= 5; i++) {
    now = 100000 + i * 15000;
    frameWindow.document = expiredDoc();
    for (const listener of listeners) listener();
    frameWindow.document = normalDoc();
    for (const listener of listeners) listener();
    repeatedBackCounts.push(frameReplacements.length);
  }
}
if (scenario.endsWith('RecoveryLimit')) {
  const initialHasFrame = hasFrame;
  const replacements = hasFrame ? frameReplacements : topReplacements;
  recoveryCounts.push(replacements.length);
  for (const offset of [0, 40000, 80000, 119999]) {
    now = 100000 + offset;
    // A fresh iframe loses its own memory; the top window must retain the guard.
    if (storageMode !== 'deniedTop') delete context.__MBG_EXPIRED_RECOVERY;
    vm.runInContext(scripts[0], context);
    recoveryCounts.push(replacements.length);
  }
  hasFrame = !initialHasFrame;
  doc.title = expiredTitle;
  vm.runInContext(scripts[0], context);
  otherTargetRecoveries = (hasFrame ? frameReplacements : topReplacements).length;
  hasFrame = initialHasFrame;
  now = 220000;
  vm.runInContext(scripts[0], context);
  recoveryCounts.push(replacements.length);
}
process.stdout.write(JSON.stringify({
  frameReplacements, topReplacements, beforeLoad, recoveryCounts, otherTargetRecoveries,
  repeatedBackCounts,
  multiTargetCounts, boundedTargetCount, prunedTargetCount,
  listenerCount: listeners.length,
  stored: stored ? JSON.parse(stored) : null
}));

