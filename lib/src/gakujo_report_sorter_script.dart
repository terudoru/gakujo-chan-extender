import 'generated/report_sorter.g.dart';
import 'generated/report_sorter_teardown.g.dart';

class GakujoReportSorterScript {
  const GakujoReportSorterScript._();

  static String build() {
    return gakujoReportSorterJs;
  }

  static String buildTeardown() {
    return gakujoReportSorterTeardownJs;
  }
}
