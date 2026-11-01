const vm: any = require('node:vm');
const startScript = process.argv[2];
const pollScript = process.argv[3];
const cleanupScript = process.argv[4];

(async function() {
  let requestedUrl = '';
  let requestOptions = null;
  const window: any = {
    location: new URL('https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do')
  };
  const context: any = vm.createContext({
    window,
    location: window.location,
    URL,
    URLSearchParams,
    Uint8Array,
    AbortController,
    fetch: async function(url, options) {
      requestedUrl = url;
      requestOptions = options;
      return {
        status: 200,
        ok: true,
        url: process.argv[8] ?? url,
        headers: {
          get(name) {
            if (name === 'content-type') {
              return process.argv[5] ?? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
            }
            if (name === 'content-disposition') {
              return process.argv[7] ?? 'attachment; filename=internal.docx';
            }
            return null;
          }
        },
        body: {
          getReader() {
            const bytes = process.argv[6] === undefined ? Buffer.from([1, 2, 3]) :
              Buffer.from(process.argv[6], 'utf8');
            let offset = 0;
            return {
              async read() {
                if (offset === bytes.length) return {done: true};
                // Fragment even the BOM and tag across reader results.
                return {done: false, value: Uint8Array.from([bytes[offset++]])};
              },
              releaseLock() {}
            };
          }
        }
      };
    },
    btoa(binary) {
      return Buffer.from(binary, 'binary').toString('base64');
    }
  });

  const started: any = vm.runInContext(startScript, context);
  await new Promise((resolve) => setImmediate(resolve));
  let polled;
  const chunks: any = [];
  do {
    polled = JSON.parse(vm.runInContext(pollScript, context));
    if (polled.state === 'chunk') chunks.push(Buffer.from(polled.bodyBase64, 'base64'));
  } while (polled.state === 'chunk');
  vm.runInContext(cleanupScript, context);
  const afterCleanup: any = JSON.parse(vm.runInContext(pollScript, context));

  process.stdout.write(JSON.stringify({
    started,
    requestedUrl,
    requestMethod: requestOptions && requestOptions.method,
    credentials: requestOptions && requestOptions.credentials,
    redirect: requestOptions && requestOptions.redirect,
    state: polled && polled.state,
    code: polled && polled.code,
    message: polled && polled.message,
    status: polled && polled.payload && polled.payload.status,
    bodyBase64: Buffer.concat(chunks).toString('base64'),
    contentDisposition:
      polled && polled.payload && polled.payload.contentDisposition,
    afterCleanup
  }));
})();

