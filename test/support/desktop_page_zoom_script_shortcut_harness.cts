const vm: any = require('node:vm');
const script = process.argv[2];
const actions: any = [];
function page() {
  const listeners: any = {};
  return {
    document: {
      body: {style: {}, scrollWidth: 800, scrollHeight: 600},
      documentElement: {style: {}, clientWidth: 800}
    },
    frames: [], innerWidth: 800, innerHeight: 600,
    addEventListener(type, callback) {
      (listeners[type] ||= []).push(callback);
    },
    listeners,
    scrollTo() {}, clearTimeout() {}, setTimeout() {}
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
process.stdout.write(JSON.stringify({
  actions, prevented, zoom: window.__MBG_PAGE_ZOOM_VALUE,
  keydownListeners: [window, frame].map(win => win.listeners.keydown.length)
}));

