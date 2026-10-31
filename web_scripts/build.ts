/// <reference types="node" />
import { build } from 'esbuild';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const entries: ({ source: string; output: string; name: string; kind?: 'statement' | 'expression'; config?: true; asset?: false } | { source: string; output: string; asset: true; name?: never; kind?: never; config?: never })[] = [
  { source: 'web_scripts/src/qpdf_worker/main.ts', output: 'assets/js/upload_compression/qpdf-worker.js', asset: true },
  { source: 'web_scripts/src/upload_library_ack/main.ts', output: 'lib/src/generated/upload_library_ack.g.dart', name: 'gakujoUploadLibraryAckJs', kind: 'expression' },
  { source: 'web_scripts/src/upload_library_setup/main.ts', output: 'lib/src/generated/upload_library_setup.g.dart', name: 'gakujoUploadLibrarySetupJs', config: true },
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
  { source: 'web_scripts/src/calendar_class_changes_fetch/main.ts', output: 'lib/src/generated/calendar_class_changes_fetch.g.dart', name: 'gakujoCalendarClassChangesFetchJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/calendar_official_google_schedule_integration/main.ts', output: 'lib/src/generated/calendar_official_google_schedule_integration.g.dart', name: 'gakujoCalendarOfficialGoogleScheduleIntegrationJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/calendar_official_schedule_export_execution/main.ts', output: 'lib/src/generated/calendar_official_schedule_export_execution.g.dart', name: 'gakujoCalendarOfficialScheduleExportExecutionJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/calendar_official_schedule_export_fetch/main.ts', output: 'lib/src/generated/calendar_official_schedule_export_fetch.g.dart', name: 'gakujoCalendarOfficialScheduleExportFetchJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/calendar_schedule_month_navigation/main.ts', output: 'lib/src/generated/calendar_schedule_month_navigation.g.dart', name: 'gakujoCalendarScheduleMonthNavigationJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/calendar_schedule_day_selection/main.ts', output: 'lib/src/generated/calendar_schedule_day_selection.g.dart', name: 'gakujoCalendarScheduleDaySelectionJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/calendar_extraction/main.ts', output: 'lib/src/generated/calendar_extraction.g.dart', name: 'gakujoCalendarExtractionJs', kind: 'expression' },
  { source: 'web_scripts/src/calendar_schedule_month_view_activation/main.ts', output: 'lib/src/generated/calendar_schedule_month_view_activation.g.dart', name: 'gakujoCalendarScheduleMonthViewActivationJs', kind: 'expression' },
  { source: 'web_scripts/src/popup_relay/main.ts', output: 'lib/src/generated/popup_relay.g.dart', name: 'gakujoPopupRelayJs' },
  { source: 'web_scripts/src/image_bounds/main.ts', output: 'lib/src/generated/image_bounds.g.dart', name: 'gakujoImageBoundsJs' },
  { source: 'web_scripts/src/upload_preview/main.ts', output: 'lib/src/generated/upload_preview.g.dart', name: 'gakujoUploadPreviewJs', config: true },
  { source: 'web_scripts/src/upload_compression/main.ts', output: 'lib/src/generated/upload_compression.g.dart', name: 'gakujoUploadCompressionJs', config: true },
  { source: 'web_scripts/src/upload_compression/teardown.ts', output: 'lib/src/generated/upload_compression_teardown.g.dart', name: 'gakujoUploadCompressionTeardownJs' },
  { source: 'web_scripts/src/message_filter/main.ts', output: 'lib/src/generated/message_filter.g.dart', name: 'gakujoMessageFilterJs', config: true },
  { source: 'web_scripts/src/message_filter/teardown.ts', output: 'lib/src/generated/message_filter_teardown.g.dart', name: 'gakujoMessageFilterTeardownJs' },
  { source: 'web_scripts/src/report_draft/main.ts', output: 'lib/src/generated/report_draft.g.dart', name: 'gakujoReportDraftJs' },
  { source: 'web_scripts/src/report_draft/list.ts', output: 'lib/src/generated/report_draft_list.g.dart', name: 'gakujoReportDraftListJs', kind: 'expression' },
  { source: 'web_scripts/src/report_draft/delete.ts', output: 'lib/src/generated/report_draft_delete.g.dart', name: 'gakujoReportDraftDeleteJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/login_autofill_assist/main.ts', output: 'lib/src/generated/login_autofill_assist.g.dart', name: 'gakujoLoginAutofillAssistJs', config: true },
  { source: 'web_scripts/src/login_autofill_assist/teardown.ts', output: 'lib/src/generated/login_autofill_assist_teardown.g.dart', name: 'gakujoLoginAutofillAssistTeardownJs' },
  { source: 'web_scripts/src/two_factor_autofill/main.ts', output: 'lib/src/generated/two_factor_autofill.g.dart', name: 'gakujoTwoFactorAutofillJs', config: true },
  { source: 'web_scripts/src/two_factor_autofill/teardown.ts', output: 'lib/src/generated/two_factor_autofill_teardown.g.dart', name: 'gakujoTwoFactorAutofillTeardownJs' },
  { source: 'web_scripts/src/desktop_page_zoom/main.ts', output: 'lib/src/generated/desktop_page_zoom.g.dart', name: 'gakujoDesktopPageZoomJs', config: true },
  { source: 'web_scripts/src/quick_jump/main.ts', output: 'lib/src/generated/quick_jump.g.dart', name: 'gakujoQuickJumpJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/message_star/main.ts', output: 'lib/src/generated/message_star.g.dart', name: 'gakujoMessageStarJs', config: true },
  { source: 'web_scripts/src/message_star/open.ts', output: 'lib/src/generated/message_star_open.g.dart', name: 'gakujoMessageStarOpenJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/message_star/teardown.ts', output: 'lib/src/generated/message_star_teardown.g.dart', name: 'gakujoMessageStarTeardownJs' },
  { source: 'web_scripts/src/message_list_fetch/main.ts', output: 'lib/src/generated/message_list_fetch.g.dart', name: 'gakujoMessageListFetchJs', kind: 'expression' },
  { source: 'web_scripts/src/page_text_activity/main.ts', output: 'lib/src/generated/page_text_activity.g.dart', name: 'gakujoPageTextActivityJs', kind: 'expression' },
  { source: 'web_scripts/src/assignment_list_fetch/main.ts', output: 'lib/src/generated/assignment_list_fetch.g.dart', name: 'gakujoAssignmentListFetchJs', kind: 'expression' },
  { source: 'web_scripts/src/channel_guard/main.ts', output: 'lib/src/generated/channel_guard.g.dart', name: 'gakujoChannelGuardJs', config: true },
  { source: 'web_scripts/src/channel_bridge/main.ts', output: 'lib/src/generated/channel_bridge.g.dart', name: 'gakujoChannelBridgeJs', config: true },
  { source: 'web_scripts/src/authenticated_download/start.ts', output: 'lib/src/generated/authenticated_download_start.g.dart', name: 'gakujoAuthenticatedDownloadStartJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/authenticated_download/poll.ts', output: 'lib/src/generated/authenticated_download_poll.g.dart', name: 'gakujoAuthenticatedDownloadPollJs', kind: 'expression', config: true },
  { source: 'web_scripts/src/authenticated_download/cleanup.ts', output: 'lib/src/generated/authenticated_download_cleanup.g.dart', name: 'gakujoAuthenticatedDownloadCleanupJs', kind: 'expression', config: true },
];
const check = process.argv.includes('--check');
const stale: string[] = [];

for (const entry of entries) {
  const result = await build({
    entryPoints: [resolve(root, entry.source)],
    bundle: true,
    format: entry.asset ? 'esm' : 'iife',
    target: entry.asset ? 'es2020' : 'es2017',
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
  if (!entry.asset && (entry.config ? outputJs : js).includes("'''")) {
    throw new Error(`${entry.source}: generated JavaScript contains ''' and cannot be embedded in a Dart raw string`);
  }
  const header = `// GENERATED FILE - DO NOT EDIT.\n// Source: ${entry.source}\n// Regenerate with: npm --prefix web_scripts run build\n\n`;
  const prefix = entry.kind === 'expression'
    ? `(function(__mbgConfig) {\n${outputJs}var __mbgEntryResult;\nreturn __mbgEntryResult;\n})(`
    : `(function(__mbgConfig) {\n${outputJs}})(`;
  const suffix = entry.kind === 'expression' ? ')\n' : ');\n';
  // dart format moves a raw string to the next line when its first line overflows.
  const rawConst = (name: string, value: string) => {
    const head = `const String ${name} = r'''`;
    return (head + value.split('\n')[0]).length > 80
      ? `const String ${name} =\n    r'''${value}''';`
      : `${head}${value}''';`;
  };
  const signatureLine = `String ${entry.name}(Map<String, Object?> config) =>`;
  const signature = signatureLine.length <= 80
    ? signatureLine
    : `String ${entry.name}(\n  Map<String, Object?> config,\n) =>`;
  // Match dart format: one line when it fits in 80 columns.
  const configLine = `    _${entry.name}Prefix + jsonEncode(config) + _${entry.name}Suffix;`;
  const configBody = configLine.length <= 80
    ? configLine
    : `    _${entry.name}Prefix +\n    jsonEncode(config) +\n    _${entry.name}Suffix;`;
  const content = entry.asset ? header + outputJs : entry.config
    ? `${header}import 'dart:convert';\n\n${signature}\n${configBody}\n\n${rawConst(`_${entry.name}Prefix`, prefix)}\n${rawConst(`_${entry.name}Suffix`, suffix)}\n`
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
