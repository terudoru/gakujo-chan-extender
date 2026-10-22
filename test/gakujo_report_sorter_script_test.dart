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

  test('sorts expired reports by Japan time when the UTC date differs',
      () async {
    await evaluatePageScriptLifecycle(
      feature: 'report',
      buildScript: '''
(function() {
  const NativeDate = Date;
  const instant = NativeDate.parse('2026-10-22T16:30:00Z');
  globalThis.Date = class extends NativeDate {
    constructor(...args) {
      super(...(args.length ? args : [instant]));
    }
    static now() { return instant; }
  };
  // Model a UTC device regardless of the timezone running the test.
  for (const part of ['FullYear', 'Month', 'Date', 'Hours', 'Minutes']) {
    Date.prototype['get' + part] = NativeDate.prototype['getUTC' + part];
  }

  const table = document.querySelector('#enqListForm table:nth-of-type(2)');
  function reportRow(id, status, deadline) {
    return {
      id,
      cells: ['', '', status, '', '', '', '', deadline].map(
        (text) => ({innerText: text, style: {}})
      )
    };
  }
  const expired = reportRow('expired', 'Not submitted', '2026/10/23 00:30');
  const open = reportRow('open', 'Submitted', '2026/10/23 02:00');
  table.rows = [table.rows[0], expired, open];
  table.tBodies[0].appendChild = function(row) {
    table.rows.splice(table.rows.indexOf(row), 1);
    table.rows.push(row);
  };

  ${GakujoReportSorterScript.build()}

  if (table.rows[1] !== open || table.rows[2] !== expired) {
    throw new Error('Expected the open report before the report expired in Japan');
  }
})();
''',
      teardownScript: GakujoReportSorterScript.buildTeardown(),
    );
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
