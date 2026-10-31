/// <reference types="node" />
import { build } from 'esbuild';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const entries = [
  { source: 'web_scripts/src/session_extender/main.ts', output: 'lib/src/generated/session_extender.g.dart', name: 'gakujoSessionExtenderJs' },
  { source: 'web_scripts/src/session_extender/teardown.ts', output: 'lib/src/generated/session_extender_teardown.g.dart', name: 'gakujoSessionExtenderTeardownJs' },
  { source: 'web_scripts/src/download_capture/main.ts', output: 'lib/src/generated/download_capture.g.dart', name: 'gakujoDownloadCaptureJs' },
  { source: 'web_scripts/src/download_capture/teardown.ts', output: 'lib/src/generated/download_capture_teardown.g.dart', name: 'gakujoDownloadCaptureTeardownJs' },
  { source: 'web_scripts/src/expired_page_recovery/main.ts', output: 'lib/src/generated/expired_page_recovery.g.dart', name: 'gakujoExpiredPageRecoveryJs' },
  { source: 'web_scripts/src/gpa_display/main.ts', output: 'lib/src/generated/gpa_display.g.dart', name: 'gakujoGpaDisplayJs' },
  { source: 'web_scripts/src/gpa_display/teardown.ts', output: 'lib/src/generated/gpa_display_teardown.g.dart', name: 'gakujoGpaDisplayTeardownJs' },
  { source: 'web_scripts/src/message_reader/main.ts', output: 'lib/src/generated/message_reader.g.dart', name: 'gakujoMessageReaderJs' },
  { source: 'web_scripts/src/message_reader/teardown.ts', output: 'lib/src/generated/message_reader_teardown.g.dart', name: 'gakujoMessageReaderTeardownJs' },
  { source: 'web_scripts/src/report_sorter/main.ts', output: 'lib/src/generated/report_sorter.g.dart', name: 'gakujoReportSorterJs' },
  { source: 'web_scripts/src/report_sorter/teardown.ts', output: 'lib/src/generated/report_sorter_teardown.g.dart', name: 'gakujoReportSorterTeardownJs' },
  { source: 'web_scripts/src/timeout_popup/main.ts', output: 'lib/src/generated/timeout_popup.g.dart', name: 'gakujoTimeoutPopupJs' },
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
