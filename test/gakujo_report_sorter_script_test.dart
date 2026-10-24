import 'dart:convert';

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

  test('yearless range ends inherit the start year and roll across New Year',
      () async {
    await _expectDeadlineOrder(
      now: '2026-12-31T14:30:00Z', // 23:30 in Japan.
      reports: [
        ['newYear', 'Not submitted', '2026/12/31 10:00～01/01 00:00'],
        ['later', 'Not submitted', '2027/01/01 01:00'],
        ['expired', 'Not submitted', '2026/12/31 23:00'],
        ['sameYear', 'Not submitted', '2026/12/30 10:00～12/31 23:45'],
      ],
      expected: ['sameYear', 'newYear', 'later', 'expired'],
    );
  });

  test('24:00 shares expiry state and stable sort order with next-day midnight',
      () async {
    await _expectDeadlineOrder(
      now: '2026-12-31T15:00:00Z', // Midnight in Japan.
      reports: [
        ['endOfDay', 'Not submitted', '2026/12/31 24:00'],
        ['midnight', 'Submitted', '2027/01/01 00:00'],
      ],
      expected: ['endOfDay', 'midnight'],
    );
    await _expectDeadlineOrder(
      now: '2026-12-31T14:59:00Z',
      reports: [
        ['midnight', 'Not submitted', '2027/01/01 00:00'],
        ['endOfDay', 'Not submitted', '2026/12/31 24:00'],
      ],
      expected: ['midnight', 'endOfDay'],
    );
  });

  test('sorts the top report table when a readable iframe has none', () async {
    await evaluatePageScriptLifecycle(
      feature: 'report',
      buildScript: '''
(function() {
  const table = document.querySelector('#enqListForm table:nth-of-type(2)');
  let sortedRows = 0;
  table.tBodies[0].appendChild = () => { sortedRows += 1; };
  const getElementById = document.getElementById;
  document.getElementById = id => id === 'main-frame-if'
    ? {contentWindow: {document: {querySelector: () => null}}}
    : getElementById(id);

  ${GakujoReportSorterScript.build()}

  if (sortedRows !== 1 || table.rows[1].cells[2].style.color !== 'blue') {
    throw new Error('Expected the top report table to be sorted and styled');
  }
})();
''',
      teardownScript: GakujoReportSorterScript.buildTeardown(),
    );
  });

  test('auto-sorts each new iframe table once after navigation', () async {
    await evaluatePageScriptLifecycle(
      feature: 'report',
      buildScript: '''
(function() {
  function reportTable() {
    function row(id, deadline) {
      return {id, cells: ['', '', 'Not submitted', '', '', '', '', deadline]
        .map(text => ({innerText: text, style: {}}))};
    }
    const table = {rows: [{cells: []}, row('later', '2099/12/31'), row('earlier', '2099/01/01')]};
    table.moves = 0;
    table.tBodies = [{appendChild(row) {
      table.moves += 1;
      table.rows.splice(table.rows.indexOf(row), 1);
      table.rows.push(row);
    }}];
    return table;
  }
  const first = reportTable();
  const frame = {contentWindow: {document: {querySelector: () => first}}};
  const getElementById = document.getElementById;
  document.getElementById = id => id === 'main-frame-if' ? frame : getElementById(id);

  ${GakujoReportSorterScript.build()}

  window.__MBG_REPORT_SORTER_UPDATE();
  if (first.rows[1].id !== 'earlier' || first.moves !== 2) {
    throw new Error('Expected one initial sort of the first iframe table');
  }
  const second = reportTable();
  frame.contentWindow.document = {querySelector: () => second};
  window.__MBG_REPORT_SORTER_UPDATE();
  if (second.rows[1].id !== 'earlier' || second.moves !== 2) {
    throw new Error('Expected the replacement iframe table to be sorted');
  }
  // A manual order must survive further polling of the same table.
  [second.rows[1], second.rows[2]] = [second.rows[2], second.rows[1]];
  window.__MBG_REPORT_SORTER_UPDATE();
  if (second.rows[1].id !== 'later' || second.moves !== 2 || first.moves !== 2) {
    throw new Error('Expected one initial sort of the replacement iframe table');
  }
})();
''',
      teardownScript: GakujoReportSorterScript.buildTeardown(),
    );
  });
}

Future<void> _expectDeadlineOrder({
  required String now,
  required List<List<String>> reports,
  required List<String> expected,
}) async {
  await evaluatePageScriptLifecycle(
    feature: 'report',
    buildScript: '''
(function() {
  const NativeDate = Date;
  const instant = NativeDate.parse(${jsonEncode(now)});
  globalThis.Date = class extends NativeDate {
    constructor(...args) { super(...(args.length ? args : [instant])); }
    static now() { return instant; }
  };
  const table = document.querySelector('#enqListForm table:nth-of-type(2)');
  table.rows = [table.rows[0], ...${jsonEncode(reports)}.map(([id, status, deadline]) => ({
    id, cells: ['', '', status, '', '', '', '', deadline]
      .map(text => ({innerText: text, style: {}}))
  }))];
  table.tBodies[0].appendChild = function(row) {
    table.rows.splice(table.rows.indexOf(row), 1);
    table.rows.push(row);
  };

  ${GakujoReportSorterScript.build()}

  const actual = table.rows.slice(1).map(row => row.id);
  if (JSON.stringify(actual) !== JSON.stringify(${jsonEncode(expected)})) {
    throw new Error('Unexpected deadline order: ' + JSON.stringify(actual));
  }
})();
''',
    teardownScript: GakujoReportSorterScript.buildTeardown(),
  );
}
