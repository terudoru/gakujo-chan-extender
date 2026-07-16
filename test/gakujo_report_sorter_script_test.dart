import 'package:morebettergakujo_flutter/src/gakujo_report_sorter_script.dart';
import 'package:test/test.dart';

import 'support/page_script_dom_harness.dart';

void main() {
  test('builds report sorting controls from the original README features', () {
    final script = GakujoReportSorterScript.build();

    expect(script, contains('__MBG_REPORT_SORTER_VERSION'));
    expect(script, contains("document.getElementById('main-frame-if')"));
    expect(script, contains('|| document'));
    expect(script,
        contains("doc.querySelector('#enqListForm table:nth-of-type(2)')"));
    expect(script, contains('タイトルでソート'));
    expect(script, contains('開講番号でソート'));
    expect(script, contains('提出期間でソート'));
    expect(script, contains('一時保存|Temporarily saved'));
    expect(script, contains("cell.style.color = 'blue'"));
    expect(script, contains('sortByDate();'));
  });

  test('teardown stops polling, removes controls, and is idempotent', () async {
    final result = await evaluatePageScriptLifecycle(
      feature: 'report',
      buildScript: GakujoReportSorterScript.build(),
      teardownScript: GakujoReportSorterScript.buildTeardown(),
    );
    final afterBuild = result['afterBuild'] as Map<String, dynamic>;
    final afterTeardown = result['afterTeardown'] as Map<String, dynamic>;
    final afterRebuild = result['afterRebuild'] as Map<String, dynamic>;
    final teardownWithoutBuild =
        result['teardownWithoutBuild'] as Map<String, dynamic>;

    expect(afterBuild['activeIntervalCount'], 1);
    expect(afterBuild['ownedElementCount'], 3);
    expect(afterBuild['controlIds'], [
      'mbg-report-title-button',
      'mbg-report-number-button',
      'mbg-report-date-button',
    ]);
    expect(afterTeardown['activeIntervalCount'], 0);
    expect(afterTeardown['ownedElementCount'], 0);
    expect(afterTeardown['controlIds'], isEmpty);
    expect(afterTeardown['globalMarkers'], isEmpty);
    expect(afterRebuild['activeIntervalCount'], 1);
    expect(afterRebuild['ownedElementCount'], 3);
    expect(teardownWithoutBuild['activeIntervalCount'], 0);
    expect(teardownWithoutBuild['ownedElementCount'], 0);
  });
}
