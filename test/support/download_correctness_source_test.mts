import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { build } from '../../web_scripts/node_modules/esbuild/lib/main.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
async function bundle(path: string) {
  const result = await build({entryPoints: [`web_scripts/src/${path}.ts`],
    absWorkingDir: root, bundle: true, format: 'iife', target: 'es2017', write: false});
  return result.outputFiles[0].text;
}
const script = await bundle('download_capture/main');
function behavior(scenario: string) {
  const result = spawnSync(process.execPath,
    ['test/support/gakujo_download_capture_script_download_capture_behavior_harness.cts', '-'],
    {cwd: root, encoding: 'utf8', input: JSON.stringify({script, scenario})});
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}
const repeated = behavior('repeatedFormFields').captured[0];
assert.deepEqual(repeated.formFieldPairs,
  [['fileId', 'A'], ['_eventId', 'download'], ['fileId', 'B'], ['fileId', 'C']]);
assert.equal(repeated.formFields.fileId, 'C');
assert.deepEqual(behavior('nonSubmitButtons').postCounts, [0, 1, 2, 3]);

const authenticatedScript = await bundle('authenticated_download/start');
for (const method of ['GET', 'POST']) {
  for (const pairs of [false, true]) {
    const requests: {url: string; body?: string}[] = [];
    const fields = pairs ? [['fileId', 'A'], ['event', 'download'], ['fileId', 'B']] :
      {fileId: 'A', event: 'download'};
    const url = 'https://gakujo.iess.niigata-u.ac.jp/file?keep=x&fileId=old';
    const context = vm.createContext({
      __mbgEntryResult: undefined,
      window: {location: {href: url}}, location: {origin: new URL(url).origin},
      __mbgConfig: {requestId: 'test', url, method, fields: JSON.stringify(fields)},
      URL, URLSearchParams, AbortController,
      fetch: async (url: string, options: {body?: string}) => {
        requests.push({url, body: options.body});
        return {url, ok: false, status: 400, headers: {get() { return ''; }}};
      },
    });
    vm.runInContext(authenticatedScript, context);
    await new Promise(resolve => setImmediate(resolve));
    const actual = method === 'GET' ? new URL(requests[0].url).searchParams :
      new URLSearchParams(requests[0].body);
    assert.deepEqual(actual.getAll('fileId'), pairs ? ['A', 'B'] : ['A']);
    assert.equal(actual.get('event'), 'download');
    if (method === 'GET') assert.equal(actual.get('keep'), 'x');
  }
}
console.log('Download capture/authenticated request source regressions passed');
