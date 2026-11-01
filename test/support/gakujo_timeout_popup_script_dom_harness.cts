const vm: any = require('node:vm');
const {scripts, scenario, url}: any = JSON.parse(require('node:fs').readFileSync(process.argv[2], 'utf8'));
const origin = 'https://gakujo.iess.niigata-u.ac.jp';
class Element {
  [key: string]: any;
  constructor(tagName) {
    this.tagName = tagName;
    this.children = [];
    this.style = {};
    this.listeners = {};
    this.attributes = {};
    this.parentNode = null;
    this.text = '';
  }
  set textContent(value) {
    for (const child of this.children) child.parentNode = null;
    this.children = [];
    this.text = value;
  }
  get textContent() {
    return this.text + this.children.map(child => child.textContent).join('');
  }
  appendChild(child) {
    child.parentNode = this;
    this.children.push(child);
    return child;
  }
  remove() {
    if (!this.parentNode) return;
    const siblings = this.parentNode.children;
    siblings.splice(siblings.indexOf(this), 1);
    this.parentNode = null;
  }
  setAttribute(name, value) { this.attributes[name] = value; }
  addEventListener(name, callback) {
    (this.listeners[name] ||= []).push(callback);
  }
  click() {
    for (const callback of this.listeners.click || []) callback();
  }
}
function descendants(element?: any) {
  return element.children.flatMap(child => [child, ...descendants(child)]);
}
function createDocument() {
  const body: any = new Element('body');
  return {
    body,
    createElement: tagName => new Element(tagName),
    getElementById: id => descendants(body).find(element => element.id === id) || null
  };
}
const doc: any = createDocument();
const openCalls: any = [], listeners: any = [];
const originalResult: any = {originalPopup: true};
let receivedArgs, receivedThis;
function originalOpen(name?: any) {
  return function(...args) {
    receivedArgs = args;
    receivedThis = this;
    openCalls.push({window: name, args});
    return originalResult;
  };
}
function createFrameWindow() {
  return {document: createDocument(), open: originalOpen('frame'),
    location: {href: origin + '/campusweb/campussquare.do?_flowId=flow'}};
}
const frameDocument: any = createDocument();
let frameWindow: any = createFrameWindow();
let denyFrame = scenario === 'frameDenied';
const frame: any = {
  get contentWindow() { return frameWindow; },
  addEventListener(name, callback) {
    if (name !== 'load') throw new Error('Unexpected event: ' + name);
    listeners.push(callback);
  }
};
Object.defineProperty(frameWindow, 'document', {
  configurable: true,
  get() {
    if (denyFrame) throw new Error('Access denied');
    return frameDocument;
  }
});
const getElementById = doc.getElementById;
doc.getElementById = id => id === 'main-frame-if' && scenario !== 'noFrame'
  ? frame : getElementById(id);
const originalAlert = function() {};
const context: any = {document: doc, open: originalOpen('top'), alert: originalAlert,
  URL, location: {href: origin + '/campusweb/campusportal.do?page=main'}};
if (scenario === 'iframeBlank' || scenario === 'iframeInvalidBase') {
  frameWindow.location.href = 'about:blank';
}
if (scenario === 'iframeInvalidBase') context.location.href = 'about:blank';
context.window = context;
context.top = context.parent = context;
vm.createContext(context);
let extendCalls = 0, extendThisIsWindow = false, extendThisIsFrame = false;
context.recordExtend = function(receiver) {
  extendCalls += 1;
  extendThisIsWindow = receiver === vm.runInContext('window', context);
  extendThisIsFrame = receiver === frameWindow;
};
if (scenario !== 'extendMissing' && scenario !== 'iframeOwnExtend') {
  vm.runInContext(scenario === 'extendNotFunction'
    ? 'window.extendSession = true;'
    : 'window.extendSession = function() { recordExtend(this); };', context);
}
if (scenario.startsWith('iframeOwnExtend')) {
  frameWindow.extendSession = function() { context.recordExtend(this); };
}
let topWrapper, frameWrapper;
for (const script of scripts) {
  vm.runInContext(script, context);
  if (!topWrapper) {
    topWrapper = context.open;
    frameWrapper = frameWindow.open;
  }
}
const sameTopWrapper = context.open === topWrapper;
const sameFrameWrapper = frameWindow.open === frameWrapper;
if (scenario === 'iframeReload') {
  frameWindow = createFrameWindow();
  for (const listener of listeners) listener();
}
if (scenario === 'frameDeniedOnLoad') {
  denyFrame = true;
  for (const listener of listeners) listener();
}
const warningUrl = '/campusweb/theme/default/TimeoutAlert.html';
const expiredUrl = '/campusweb/theme/default/Timeout.html';
const passthrough = scenario === 'passthrough' || scenario === 'iframePassthrough';
const target = scenario.startsWith('iframe') ? frameWindow : context;
const args: any = [url ?? (passthrough ? '/campusweb/report.do'
  : scenario === 'closeExpired' || scenario === 'expiredThenWarning' ? expiredUrl : warningUrl),
  'report-window', 'width=750,height=240', true];
const result: any = target.open(...args);
const bannerBeforeClose = !!doc.getElementById('mbg-timeout-banner');
let stub = null;
if (!passthrough && result !== originalResult) {
  const closedBefore = result.closed;
  const focusResult: any = result.focus();
  const blurResult: any = result.blur();
  if (scenario === 'popupClose' || scenario === 'iframePopupClose') {
    result.close();
    result.close();
  }
  stub = {closedBefore, closedAfter: result.closed,
    focusResult: focusResult ?? null, blurResult: blurResult ?? null,
    document: result.document, location: result.location};
}
const firstBanner: any = doc.getElementById('mbg-timeout-banner');
if (scenario === 'warningThenExpired') context.open(expiredUrl);
if (scenario === 'staleClose') {
  context.open(expiredUrl);
  result.close();
}
if (scenario === 'expiredThenWarning') context.open(warningUrl);
if (['extend', 'extendMissing', 'extendNotFunction', 'iframeExtend'].includes(scenario) ||
    scenario.startsWith('iframeOwnExtend')) {
  firstBanner.children.find(child => child.textContent === '延長する').click();
}
if (scenario === 'closeWarning' || scenario === 'closeExpired') {
  firstBanner.children.find(child => child.textContent === '閉じる').click();
}
const banner: any = doc.getElementById('mbg-timeout-banner');
process.stdout.write(JSON.stringify({
  openCalls, stub, extendCalls, extendThisIsWindow, extendThisIsFrame, bannerBeforeClose,
  bannerCount: descendants(doc.body).filter(element => element.id === 'mbg-timeout-banner').length,
  frameBannerCount: scenario === 'frameDenied' || scenario === 'frameDeniedOnLoad' ? null
    : descendants(frameWindow.document.body).filter(element => element.id === 'mbg-timeout-banner').length,
  message: banner ? banner.children[0].textContent : null,
  buttons: banner ? banner.children.filter(child => child.tagName === 'button').map(child => child.textContent) : [],
  sameBanner: banner === firstBanner,
  sameTopWrapper, sameFrameWrapper, listenerCount: listeners.length,
  sameReturnValue: result === originalResult,
  sameArguments: !!receivedArgs && receivedArgs.length === args.length && receivedArgs.every((arg, i) => arg === args[i]),
  sameReceiver: receivedThis === target,
  alertUnchanged: context.alert === originalAlert
}));

