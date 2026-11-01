import 'dart:convert';

import 'generated/report_draft.g.dart';
import 'generated/report_draft_clear_saved_before.g.dart';
import 'generated/report_draft_export_all.g.dart';
import 'generated/report_draft_import_all.g.dart';
import 'generated/report_draft_delete.g.dart';
import 'generated/report_draft_list.g.dart';

class GakujoReportDraftScript {
  const GakujoReportDraftScript._();

  static String build() => gakujoReportDraftJs;

  static String buildList() => gakujoReportDraftListJs;

  static String buildClearSavedBefore(DateTime cutoff) =>
      gakujoReportDraftClearSavedBeforeJs;

  static String buildExportAll() => gakujoReportDraftExportAllJs;

  static String buildImportAll(
    Map<String, Object?> drafts,
    Map<String, Object?> basedOn,
  ) => gakujoReportDraftImportAllJs({
    'drafts': jsonEncode(drafts),
    'basedOn': jsonEncode(basedOn),
  });

  static String buildDelete(String key) =>
      gakujoReportDraftDeleteJs({'key': key});
}
