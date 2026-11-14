const vm: any = require('node:vm');
const script = process.argv[2];
const actions: any = [];
function page() {
  const listeners: any = {};
  const documentListeners: any = {};
  const timers = new Map<number, () => void>();
  let nextTimer = 0;
  return {
    document: {
      body: {style: {}, scrollWidth: 800, scrollHeight: 600},
      documentElement: {style: {}, clientWidth: 800},
      addEventListener(type, callback, capture) {
        if (type === 'load' && capture !== true) throw new Error('iframe loads need capture');
        (documentListeners[type] ||= []).push(callback);
      }
    },
    frames: [], innerWidth: 800, innerHeight: 600,
    addEventListener(type, callback) {
      (listeners[type] ||= []).push(callback);
    },
    listeners,
    documentListeners,
    MutationObserver: class { observe() {} },
    scrollTo() {},
    clearTimeout(id) { timers.delete(id); },
    setTimeout(callback) { const id = ++nextTimer; timers.set(id, callback); return id; },
    flushTimers() {
      const callbacks = [...timers.values()];
      timers.clear();
      for (const callback of callbacks) callback();
    }
  };
}
const window: any = page();
const frame: any = page();
window.frames.push(frame);
window.MoreBetterGakujoDesktopZoom = {postMessage: action => actions.push(action)};
const context: any = vm.createContext({window});
vm.runInContext(script, context);
vm.runInContext(script, context);
const prevented: any = [];
for (const [target, key, ctrlKey, metaKey] of [
  [window, '+', true, false],
  [window, '=', true, false],
  [window, '-', true, false],
  [window, '_', true, false],
  [window, '0', true, false],
  [frame, '+', false, true],
  [window, '+', false, false],
  [window, 'a', true, false]
]) {
  let blocked = false;
  const event: any = {key, ctrlKey, metaKey, preventDefault() { blocked = true; }};
  for (const listener of target.listeners.keydown) listener(event);
  prevented.push(blocked);
}
const initial = {
  actions: actions.slice(), prevented, zoom: window.__MBG_PAGE_ZOOM_VALUE,
  keydownListeners: [window, frame].map(win => win.listeners.keydown.length)
};
window.__MBG_SET_PAGE_ZOOM(1.5);
const setZoom = window.__MBG_SET_PAGE_ZOOM;
let reapplyCount = 0;
window.__MBG_SET_PAGE_ZOOM = function(zoom, cause) {
  reapplyCount++;
  return setZoom(zoom, cause);
};
const navigatedFrame: any = page();
window.frames[0] = navigatedFrame;
function fireFrameLoad(parent) {
  for (const listener of parent.documentListeners.load || []) {
    listener({target: {tagName: 'IFRAME'}});
  }
}
fireFrameLoad(window);
fireFrameLoad(window);
window.flushTimers();
const nestedFrame: any = page();
navigatedFrame.frames.push(nestedFrame);
fireFrameLoad(navigatedFrame);
window.flushTimers();
const navigationPrevented: boolean[] = [];
for (const target of [navigatedFrame, nestedFrame]) {
  for (const type of ['keydown', 'wheel']) {
    let blocked = false;
    const event = {key: '+', ctrlKey: true, preventDefault() { blocked = true; }};
    for (const listener of target.listeners[type] || []) listener(event);
    navigationPrevented.push(blocked);
  }
}
process.stdout.write(JSON.stringify({
  ...initial,
  navigation: {
    actions: actions.slice(initial.actions.length),
    prevented: navigationPrevented,
    keydownListeners: [navigatedFrame, nestedFrame].map(win => (win.listeners.keydown || []).length),
    loadListeners: [window, navigatedFrame, nestedFrame].map(win => (win.documentListeners.load || []).length),
    observers: [navigatedFrame, nestedFrame].map(win => !!win.__MBG_PAGE_ZOOM_OBSERVER),
    reapplyCount,
    zoom: window.__MBG_PAGE_ZOOM_VALUE,
    transform: window.document.body.style.transform,
    frameTransforms: [navigatedFrame, nestedFrame].map(win => win.document.body.style.transform || '')
  }
}));

