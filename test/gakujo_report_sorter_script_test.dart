import 'dart:convert';

import 'package:morebettergakujo_flutter/src/gakujo_report_sorter_script.dart';
import 'package:test/test.dart';

import 'support/page_script_dom_harness.dart';

void main() {
  test('builds report sorting controls from the original README features', () {
    final script = GakujoReportSorterScript.build();

    expect(script, contains('__MBG_REPORT_SORTER_VERSION'));
    expect(script, contains('document.getElementById("main-frame-if")'));
    expect(script, contains('|| document'));
    expect(script,
        contains('doc.querySelector("#enqListForm table:nth-of-type(2)")'));
    expect(script, contains('タイトルでソート'));
    expect(script, contains('開講番号でソート'));
    expect(script, contains('提出期間でソート'));
    expect(script, contains('一時保存|Temporarily saved'));
    expect(script, contains('cell.style.color = "blue"'));
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
      teardownScript: '',
      runOnce: true,
    );
  });

  for (final separator in ['～', '〜', '~']) {
    test('uses the closing date for $separator report periods', () async {
      await _expectDeadlineOrder(
        now: '2026-11-15T03:00:00Z', // Noon in Japan.
        reports: [
          ['expired', 'Not submitted', '2026/11/15 10:00'],
          ['later', 'Not submitted', '2026/11/16 12:00'],
          ['open', 'Not submitted', '2026/11/15 00:00${separator}2026/11/16 10:00'],
        ],
        expected: ['open', 'later', 'expired'],
      );
    });
  }

  for (final deadline in [
    '2026/10/30',
    '2026/10/24 8:45 ～10/30',
    '2026/10/24 8:45 ～2026/10/30',
  ]) {
    test('defaults a missing closing time to 23:59 for $deadline', () async {
      await _expectDeadlineOrder(
        now: '2026-10-30T03:00:00Z', // Noon in Japan.
        reports: [
          ['dateOnly', 'Not submitted', deadline],
          ['midnight', 'Not submitted', '2026/10/30 00:00'],
          ['earlier', 'Not submitted', '2026/10/30 23:58'],
          ['later', 'Not submitted', '2026/10/31 00:00'],
        ],
        expected: ['earlier', 'dateOnly', 'later', 'midnight'],
      );
    });
  }

  test('date-only closing times expire after 23:59 in Japan', () async {
    final reports = [
      ['dateOnly', 'Not submitted', '2026/10/24 8:45 ～10/30'],
      ['midnight', 'Submitted', '2026/10/31 00:00'],
    ];
    await _expectDeadlineOrder(
      now: '2026-10-30T14:59:00Z', // 23:59 in Japan.
      reports: reports,
      expected: ['dateOnly', 'midnight'],
    );
    await _expectDeadlineOrder(
      now: '2026-10-30T15:00:00Z', // Next-day midnight in Japan.
      reports: reports,
      expected: ['midnight', 'dateOnly'],
    );
  });

  test('missing deadlines follow dated reports while preserving other ordering',
      () async {
    await _expectDeadlineOrder(
      now: '2026-11-15T03:00:00Z', // Noon in Japan.
      reports: [
        ['missing', 'Not submitted', ''],
        ['noDate', 'Not submitted', '期限なし'],
        ['submittedMissing', 'Submitted', ''],
        ['later', 'Not submitted', '2026/11/17 10:00'],
        ['earlier', 'Not submitted', '2026/11/16 10:00'],
        ['expired', 'Not submitted', '2026/11/15 10:00'],
        ['submitted', 'Submitted', '2026/11/16 09:00'],
      ],
      expected: [
        'earlier',
        'later',
        'missing',
        'noDate',
        'submitted',
        'submittedMissing',
        'expired'
      ],
    );
  });

  test('yearless range ends inherit the start year and roll across New Year',
      () async {
    await _expectDeadlineOrder(
      now: '2026-12-31T14:30:00Z', // 23:30 in Japan.
      reports: [
        ['newYear', 'Not submitted', '2026/12/31 10:00～01/01 00:00'],
        ['later', 'Not submitted', '2027/01/01 01:00'],
        ['expired', 'Not submitted', '2026/12/31 23:00'],
        ['dateOnlyStart', 'Not submitted', '2026/12/31～12/31 23:40'],
        ['sameYear', 'Not submitted', '2026/12/30 10:00～12/31 23:45'],
      ],
      expected: ['dateOnlyStart', 'sameYear', 'newYear', 'later', 'expired'],
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

  test('sorts full-width deadlines and range ends alongside ASCII dates',
      () async {
    await _expectDeadlineOrder(
      now: '2026-12-31T14:30:00Z', // 23:30 in Japan.
      reports: [
        ['later', 'Not submitted', '2027/01/01 01:00'],
        ['newYear', 'Not submitted', '２０２６／１２／３１　１０：００～０１／０１　００：００'],
        ['endOfDay', 'Not submitted', '２０２６／１２／３１　２４：００'],
        ['expired', 'Not submitted', '２０２６／１２／３１　２３：００'],
        ['mixed', 'Not submitted', '2026/１２/31 ２３:５０'],
        ['sameYear', 'Not submitted', '２０２６／１２／３０　１０：００～１２／３１　２３：４５'],
      ],
      expected: [
        'sameYear',
        'mixed',
        'newYear',
        'endOfDay',
        'later',
        'expired'
      ],
    );
  });

  for (final mode in ['empty', 'inaccessible', 'match']) {
    test('chooses the report table when the named frame is $mode', () async {
      await evaluatePageScriptLifecycle(
        feature: 'report',
        buildScript: '''
(function() {
  const table = document.querySelector('#enqListForm table:nth-of-type(2)');
  const mode = '$mode';
  let rootSorts = 0;
  let frameSorts = 0;
  table.tBodies[0].appendChild = () => { rootSorts += 1; };
  const frameTable = {...table, tBodies: [{appendChild() { frameSorts += 1; }}]};
  const frame = mode === 'inaccessible'
    ? {contentWindow: {get document() { throw new Error('Cross-origin frame'); }}}
    : {contentWindow: {document: {querySelector: () => mode === 'match' ? frameTable : null}}};
  const getElementById = document.getElementById;
  document.getElementById = id => id === 'main-frame-if'
    ? frame
    : getElementById(id);

  ${GakujoReportSorterScript.build()}

  const expected = mode === 'match' ? [0, 1] : [1, 0];
  if (rootSorts !== expected[0] || frameSorts !== expected[1] ||
      table.rows[1].cells[2].style.color !== 'blue') {
    throw new Error('Incorrect report table selection for ' + mode);
  }
})();
''',
        teardownScript: '',
        runOnce: true,
      );
    });
  }

  for (final foreign in [false, true]) {
    test('report controls follow frame navigation (foreign ID: $foreign)',
        () async {
      await evaluatePageScriptLifecycle(
        feature: 'report',
        buildScript: '''
(function() {
  const table = document.querySelector('#enqListForm table:nth-of-type(2)');
  let frame = {contentWindow: {document: {querySelector: () => table}}};
  const getElementById = document.getElementById;
  document.getElementById = id => id === 'main-frame-if' ? frame : getElementById(id);
  document.querySelector = () => null;
  const menu = document.getElementById('tabmenutable');
  const foreign = document.createElement('button');
  foreign.id = ${jsonEncode(foreign ? 'mbg-report-date-button' : 'portal-action')};
  menu.appendChild(foreign);
  const grade = document.createElement('button');
  grade.id = 'mbg-grade-no-button';
  grade.setAttribute('data-mbg-gpa-display-owned', 'true');
  menu.appendChild(grade);
  const setInterval = window.setInterval;
  let tick;
  window.setInterval = function(callback, delay) {
    tick = callback;
    return setInterval(callback, delay);
  };

  ${GakujoReportSorterScript.build()}

  function ownCount() {
    return document.querySelectorAll('[data-mbg-report-sorter-owned="true"]').length;
  }
  const expected = ${foreign ? 2 : 3};
  if (ownCount() !== expected) throw new Error('Missing initial report controls');
  frame.contentWindow.document = {querySelector: () => null};
  tick();
  if (ownCount() !== 0) throw new Error('Report controls remained after leaving reports');
  frame.contentWindow.document = {querySelector: () => table};
  tick();
  ${GakujoReportSorterScript.build()}
  tick();
  if (ownCount() !== expected) throw new Error('Report controls missing or duplicated on return');
  frame = null;
  tick();
  if (ownCount() !== 0) throw new Error('Report controls remained after frame removal');
  if (document.getElementById(foreign.id) !== foreign ||
      document.getElementById(grade.id) !== grade) {
    throw new Error('Unowned portal or GPA controls were removed');
  }
})();
''',
        teardownScript: '',
        runOnce: true,
      );
    });
  }

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
      teardownScript: '',
      runOnce: true,
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
    teardownScript: '',
    runOnce: true,
  );
}
