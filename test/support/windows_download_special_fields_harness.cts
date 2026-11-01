const vm = require('node:vm');
const [getStart, postStart] = process.argv.slice(2);

(async function() {
  const requests = [];
  const context = vm.createContext({
    window: {
      location: {href: 'https://gakujo.iess.niigata-u.ac.jp/'}
    },
    location: {origin: 'https://gakujo.iess.niigata-u.ac.jp'},
    URL,
    URLSearchParams,
    Uint8Array,
    AbortController,
    fetch: async function(url, options) {
      requests.push({url, options});
      return {
        url,
        status: 400,
        ok: false,
        headers: {get: () => ''}
      };
    },
    btoa: binary => Buffer.from(binary, 'binary').toString('base64')
  });

  vm.runInContext(getStart, context);
  vm.runInContext(postStart, context);
  await new Promise(resolve => setImmediate(resolve));

  const getFields = Object.fromEntries(new URL(requests[0].url).searchParams);
  const postFields = Object.fromEntries(
    new URLSearchParams(requests[1].options.body)
  );
  process.stdout.write(JSON.stringify({getFields, postFields}));
})();
