const vm: any = require('node:vm');
let called = false;
const location: any = new URL('https://docs.google.com/document');
const context: any = {
  window: { location }, location,
  URL,
  fetch() { called = true; throw new Error('unexpected fetch'); }
};
const result: any = vm.runInNewContext(process.argv[2], context);
if (result !== false || called || context.window.__MBG_AUTHENTICATED_DOWNLOAD_RESULTS) process.exit(1);

