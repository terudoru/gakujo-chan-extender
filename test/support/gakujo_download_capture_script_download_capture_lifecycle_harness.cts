process.argv = [process.argv[0], ...process.argv.slice(2).map((path) => require('node:fs').readFileSync(path, 'utf8'))];
const vm: any = require('node:vm');
const buildScript = process.argv[1];
const teardownScript = process.argv[2];
const clickListeners: any = new Set();
const loadListeners: any = new Set();
const document: any = {
  addEventListener(type, handler) {
    if (type === 'click') clickListeners.add(handler);
    if (type === 'load') loadListeners.add(handler);
  },
  removeEventListener(type, handler) {
    if (type === 'click') clickListeners.delete(handler);
    if (type === 'load') loadListeners.delete(handler);
  }
};
const window: any = {
  document,
  frames: [],
  location: {
    href: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do'
  }
};
window.window = window;
const context: any = vm.createContext({window, document, console, URL});
vm.runInContext(buildScript, context);
const listenersAfterBuild = clickListeners.size;
const loadListenersAfterBuild = loadListeners.size;
vm.runInContext(teardownScript, context);
process.stdout.write(JSON.stringify({
  listenersAfterBuild,
  loadListenersAfterBuild,
  listenersAfterTeardown: clickListeners.size,
  loadListenersAfterTeardown: loadListeners.size,
  handlerCleared: window.__MBG_DOWNLOAD_CAPTURE_HANDLER === null,
  loadHandlerCleared: window.__MBG_DOWNLOAD_CAPTURE_LOAD_HANDLER === null,
  versionCleared: window.__MBG_DOWNLOAD_CAPTURE_VERSION === null
}));

