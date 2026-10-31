import 'generated/report_draft.g.dart';
import 'generated/report_draft_list.g.dart';
import 'generated/report_draft_delete.g.dart';

class GakujoReportDraftScript {
  const GakujoReportDraftScript._();

  static String build() => gakujoReportDraftJs;

  static String buildList() => gakujoReportDraftListJs;

  static String buildDelete(String key) =>
      gakujoReportDraftDeleteJs({'key': key});
}
