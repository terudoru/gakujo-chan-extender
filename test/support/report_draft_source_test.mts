import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { build } from '../../web_scripts/node_modules/esbuild/lib/main.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
async function bundle(name: string, expression = false) {
  const result = await build({
    entryPoints: [`web_scripts/src/report_draft/${name}.ts`],
    absWorkingDir: root, bundle: true, format: 'iife', target: 'es2017', write: false,
  });
  const js = result.outputFiles[0].text;
  return expression ? `(function() {${js}\nvar __mbgEntryResult; return __mbgEntryResult;})()` : js;
}
const generatedScript = await bundle('main');
const exportScript = await bundle('export_all', true);
const importScript = `(function(__mbgConfig) {return ${await bundle('import_all', true)};})(__MBG_IMPORT_CONFIG__)`;
for (const source of ['legacy', 'rawPath']) {
  for (const cleanup of [false, true]) {
    const result = spawnSync(process.execPath, ['test/support/report_draft_dom_harness.cts', '-'], {
      cwd: root, encoding: 'utf8',
      input: JSON.stringify({generatedScript, exportScript, importScript,
        spec: {scenario: 'remoteDeleteMigrationSource', source, cleanup}}),
    });
    assert.equal(result.status, 0, result.stderr);
    const actual = JSON.parse(result.stdout);
    assert.equal(actual.restored, 'Saved draft');
    assert.equal(actual.linked, true);
    assert.equal(actual.sourceRemoved, true);
    assert.equal(actual.linkRemoved, true);
    if (cleanup) assert.equal(actual.canonicalRetained, true);
    else {
      assert.equal(actual.refused, true);
      assert.equal(actual.retained, true);
      assert.equal(actual.applied, true);
      assert.equal(actual.canonicalRemoved, true);
      assert.equal(actual.restoredAgain, '');
    }
  }
}
console.log('Report draft source migration: 4 cases passed');
