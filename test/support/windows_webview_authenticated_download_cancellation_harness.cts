const vm: any = require('node:vm');
(async function() {
  const [start, poll, cleanup]: any = process.argv.slice(2);
  const pending: any = [];
  const location: any = new URL('https://gakujo.iess.niigata-u.ac.jp/');
  const context: any = vm.createContext({
    window: { location }, location,
    URL, URLSearchParams, Uint8Array, AbortController,
    fetch(url, options) {
      return new Promise(resolve => pending.push({ url, options, resolve }));
    },
    btoa: binary => Buffer.from(binary, 'binary').toString('base64')
  });
  vm.runInContext(start, context);
  vm.runInContext(cleanup, context);
  const aborted = !!(pending[0].options.signal && pending[0].options.signal.aborted);
  const afterCleanup: any = JSON.parse(vm.runInContext(poll, context));
  const restarted: any = vm.runInContext(start, context);
  // Simulate a fetch that resolves despite cancellation; it must not overwrite
  // a later request that reuses the same identifier.
  pending[0].resolve({url: pending[0].url, ok: true, status: 200,
    headers: { get: () => '' }, arrayBuffer: async () => Uint8Array.from([1]).buffer});
  await new Promise(resolve => setImmediate(resolve));
  const afterLateResult: any = JSON.parse(vm.runInContext(poll, context));
  vm.runInContext(cleanup, context);
  process.stdout.write(JSON.stringify({aborted, afterCleanup, restarted,
    lateResultIgnored: afterLateResult && afterLateResult.state === 'pending'}));
})();

