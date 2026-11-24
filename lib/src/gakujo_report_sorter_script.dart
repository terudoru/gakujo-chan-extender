import 'gakujo_automation_settings.dart';
import 'generated/report_sorter.g.dart';

class GakujoReportSorterScript {
  const GakujoReportSorterScript._();
  static String build({
    GakujoReportInitialSort initialSort = GakujoReportInitialSort.deadline,
  }) => gakujoReportSorterJs({'initialSort': initialSort.name});
}
