const vm: any = require('node:vm');
(async function() {
  const [start, poll, cleanup]: any = process.argv.slice(2);
  const length = 8 * 1024 * 1024 + 13;
  let sourceOffset = 0, receivedBytes = 0, maximumMessageBytes = 0, validBytes = true;
  function makeBytes(size?: any, offset?: any) {
    const bytes: any = new Uint8Array(size);
    for (let i=0;i<size;i++) bytes[i] = (offset + i) % 251;
    return bytes;
  }
  const location: any = new URL('https://gakujo.iess.niigata-u.ac.jp/');
  const context: any = vm.createContext({
    window: {location}, location,
    URL, URLSearchParams, Uint8Array, AbortController,
    fetch: async url => ({url, status: 200, ok: true, headers: {get: () => ''},
      arrayBuffer: async () => { sourceOffset=length; return makeBytes(length, 0).buffer; },
      body: { getReader: () => ({
        async read() {
          if (sourceOffset===length) return {done:true};
          const size: any=Math.min(65537, length-sourceOffset);
          const value: any=makeBytes(size, sourceOffset); sourceOffset+=size;
          return {value, done:false};
        },
        releaseLock() {}, async cancel() {}
      })}
    }),
    btoa: binary => Buffer.from(binary, 'binary').toString('base64')
  });
  vm.runInContext(start, context);
  await new Promise(resolve=>setImmediate(resolve));
  const readBeforePolling=sourceOffset;
  for (let attempts=0; attempts<1000; attempts++) {
    const raw: any=vm.runInContext(poll, context);
    maximumMessageBytes=Math.max(maximumMessageBytes, Buffer.byteLength(raw));
    const state: any=JSON.parse(raw);
    if (state.state==='error') throw Error(state.message);
    const encoded=state.state==='chunk' ? state.bodyBase64 : state.payload && state.payload.bodyBase64;
    if (encoded) {
      const bytes: any=Buffer.from(encoded,'base64');
      for(let i=0;i<bytes.length;i++) if(bytes[i] !== (receivedBytes+i)%251) validBytes=false;
      receivedBytes+=bytes.length;
    }
    if(state.state==='done') break;
    await new Promise(resolve=>setImmediate(resolve));
  }
  vm.runInContext(cleanup,context);
  process.stdout.write(JSON.stringify({receivedBytes,validBytes,maximumMessageBytes,
    readBeforePolling,afterCleanup:JSON.parse(vm.runInContext(poll,context))}));
})();

