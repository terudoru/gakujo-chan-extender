import 'package:morebettergakujo_flutter/src/gakujo_report_sorter_script.dart';
import 'package:test/test.dart';

void main() {
  test('builds report sorting controls from the original README features', () {
    final script = GakujoReportSorterScript.build();

    expect(script, contains('__MBG_REPORT_SORTER_VERSION'));
    expect(script, contains("document.getElementById('main-frame-if')"));
    expect(script,
        contains("doc.querySelector('#enqListForm table:nth-of-type(2)')"));
    expect(script, contains('タイトルでソート'));
    expect(script, contains('開講番号でソート'));
    expect(script, contains('提出期間でソート'));
    expect(script, contains('一時保存|Temporarily saved'));
    expect(script, contains("cell.style.color = 'blue'"));
    expect(script, contains('sortByDate();'));
  });
}
