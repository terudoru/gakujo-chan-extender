/// <reference types="node" />
import { build } from 'esbuild';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const entries = [
  { source: 'web_scripts/src/session_extender/main.ts', output: 'lib/src/generated/session_extender.g.dart', name: 'gakujoSessionExtenderJs' },
  { source: 'web_scripts/src/session_extender/teardown.ts', output: 'lib/src/generated/session_extender_teardown.g.dart', name: 'gakujoSessionExtenderTeardownJs' },
];
const check = process.argv.includes('--check');
const stale: string[] = [];

for (const entry of entries) {
  const result = await build({
    entryPoints: [resolve(root, entry.source)],
    bundle: true,
    format: 'iife',
    target: 'es2017',
    minify: false,
    charset: 'utf8',
    legalComments: 'none',
    write: false,
    absWorkingDir: root,
  });
  const js = result.outputFiles[0].text.replace(/\r\n/g, '\n');
  if (js.includes("'''")) {
    throw new Error(`${entry.source}: generated JavaScript contains ''' and cannot be embedded in a Dart raw string`);
  }
  const content = `// GENERATED FILE - DO NOT EDIT.\n// Source: ${entry.source}\n// Regenerate with: npm --prefix web_scripts run build\n\nconst String ${entry.name} = r'''\n${js}''';\n`;
  const output = resolve(root, entry.output);
  if (check) {
    let existing: string | undefined;
    try {
      existing = await readFile(output, 'utf8');
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
    }
    if (existing !== content) stale.push(entry.output);
  } else {
    await mkdir(dirname(output), { recursive: true });
    await writeFile(output, content, 'utf8');
  }
}

if (stale.length) {
  console.error(`Stale generated files:\n${stale.join('\n')}`);
  process.exitCode = 1;
}
