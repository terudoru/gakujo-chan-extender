/// <reference types="node" />
import { build } from 'esbuild';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const entries: { source: string; output: string; name: string; kind?: 'statement' | 'expression'; config?: true }[] = [
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
  { source: 'web_scripts/src/portal_auth_state_probe/main.ts', output: 'lib/src/generated/portal_auth_state_probe.g.dart', name: 'gakujoPortalAuthStateProbeJs', kind: 'expression' },
  { source: 'web_scripts/src/authenticated_session_reset/main.ts', output: 'lib/src/generated/authenticated_session_reset.g.dart', name: 'gakujoAuthenticatedSessionResetJs' },
  { source: 'web_scripts/src/course_name_body_text/main.ts', output: 'lib/src/generated/course_name_body_text.g.dart', name: 'gakujoCourseNameBodyTextJs', kind: 'expression' },
  { source: 'web_scripts/src/course_name_tables/main.ts', output: 'lib/src/generated/course_name_tables.g.dart', name: 'gakujoCourseNameTablesJs', kind: 'expression' },
  { source: 'web_scripts/src/calendar_registration_page_fetch/main.ts', output: 'lib/src/generated/calendar_registration_page_fetch.g.dart', name: 'gakujoCalendarRegistrationPageFetchJs', kind: 'expression' },
  { source: 'web_scripts/src/calendar_extraction/main.ts', output: 'lib/src/generated/calendar_extraction.g.dart', name: 'gakujoCalendarExtractionJs', kind: 'expression' },
  { source: 'web_scripts/src/calendar_schedule_month_view_activation/main.ts', output: 'lib/src/generated/calendar_schedule_month_view_activation.g.dart', name: 'gakujoCalendarScheduleMonthViewActivationJs', kind: 'expression' },
  { source: 'web_scripts/src/popup_relay/main.ts', output: 'lib/src/generated/popup_relay.g.dart', name: 'gakujoPopupRelayJs' },
  { source: 'web_scripts/src/image_bounds/main.ts', output: 'lib/src/generated/image_bounds.g.dart', name: 'gakujoImageBoundsJs' },
  { source: 'web_scripts/src/upload_preview/main.ts', output: 'lib/src/generated/upload_preview.g.dart', name: 'gakujoUploadPreviewJs', config: true },
  { source: 'web_scripts/src/upload_compression/main.ts', output: 'lib/src/generated/upload_compression.g.dart', name: 'gakujoUploadCompressionJs', config: true },
  { source: 'web_scripts/src/upload_compression/teardown.ts', output: 'lib/src/generated/upload_compression_teardown.g.dart', name: 'gakujoUploadCompressionTeardownJs' },
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
  const outputJs = result.outputFiles[0].text.replace(/\r\n/g, '\n');
  // var is hoisted above the inner IIFE, keeping the assignment local and the strict directive first.
  const js = entry.kind === 'expression'
    ? `(function() {\n${outputJs}var __mbgEntryResult;\nreturn __mbgEntryResult;\n})()\n`
    : outputJs;
  if ((entry.config ? outputJs : js).includes("'''")) {
    throw new Error(`${entry.source}: generated JavaScript contains ''' and cannot be embedded in a Dart raw string`);
  }
  const header = `// GENERATED FILE - DO NOT EDIT.\n// Source: ${entry.source}\n// Regenerate with: npm --prefix web_scripts run build\n\n`;
  const prefix = entry.kind === 'expression'
    ? `(function(__mbgConfig) {\n${outputJs}var __mbgEntryResult;\nreturn __mbgEntryResult;\n})(`
    : `(function(__mbgConfig) {\n${outputJs}})(`;
  const suffix = entry.kind === 'expression' ? ')\n' : ');\n';
  const content = entry.config
    ? `${header}import 'dart:convert';\n\nString ${entry.name}(Map<String, Object?> config) =>\n    _${entry.name}Prefix +\n    jsonEncode(config) +\n    _${entry.name}Suffix;\n\nconst String _${entry.name}Prefix = r'''${prefix}''';\nconst String _${entry.name}Suffix = r'''${suffix}''';\n`
    : `${header}const String ${entry.name} = r'''\n${js}''';\n`;
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
