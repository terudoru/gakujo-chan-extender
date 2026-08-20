import 'package:morebettergakujo_flutter/src/gakujo_gpa_display_script.dart';
import 'package:test/test.dart';

import 'support/page_script_dom_harness.dart';

void main() {
  test('builds a GPA display script for the grades table GP header', () {
    final script = GakujoGpaDisplayScript.build();

    expect(script, contains('__MBG_GPA_DISPLAY_VERSION'));
    expect(script, contains('__MBG_UPDATE_GPA_DISPLAY'));
    expect(script, contains('MutationObserver'));
    expect(script, contains("document.getElementById('main-frame-if')"));
    expect(script,
        contains("documentRef.querySelector('#taniReferListForm+table')"));
    expect(script, contains('headerCells[12]'));
    expect(script, contains('numberIndex: 0'));
    expect(script, contains('openNumberIndex: 3'));
    expect(script, contains('scoreIndex: 9'));
    expect(script, contains('unitIndex: 8'));
    expect(script, contains('gpIndex: 12'));
    expect(script, contains('function labelOf(element)'));
    expect(script, contains('function isNumberLabel(label)'));
    expect(script, contains('function isScoreLabel(label)'));
    expect(script, contains("label.indexOf('開講番号') >= 0"));
    expect(script, contains('scoreIndex = cellIndex'));
    expect(script, contains("label.indexOf('単位数') >= 0"));
    expect(script, contains("label === 'GP'"));
    expect(script, contains("labels.join('|').indexOf('科目')"));
    expect(script, contains("labels.join('|').indexOf('得点')"));
    expect(script, contains("labels.join('|').indexOf('評価')"));
    expect(script, contains('.toUpperCase()'));
    expect(script, contains("text.replace(/GPA:?\\d*(?:\\.\\d+)?/g, '')"));
    expect(script, contains("var text = 'GPA:' + gpa.toFixed(4)"));
    expect(script, contains('display && display.textContent === text'));
    expect(script, contains('weightedGp += credits * gp'));
    expect(script, contains('totalCredits += credits'));
    expect(script, contains('No.でソート'));
    expect(script, contains('開講番号でソート'));
    expect(script, contains('得点でソート'));
    expect(script, contains('function sortByNumber()'));
    expect(script, contains('function sortByOpenNumber()'));
    expect(script, contains('function sortByScore()'));
    expect(script, contains('function cellsForGradeRow(row, gradeTable)'));
    expect(script, contains('gradeTable.numberIndex'));
    expect(script, contains('gradeTable.openNumberIndex'));
    expect(script, contains('gradeTable.scoreIndex'));
    expect(script, isNot(contains('numberFromCell(a.cells[0])')));
    expect(script, isNot(contains('textOf(a.cells[3])')));
    expect(script, isNot(contains('numberFromCell(a.cells[9])')));
    expect(script, contains('gradeTable.headerRowIndex + 1'));
    expect(script, contains('__MBG_GPA_DISPLAY_INTERVAL'));
    expect(script, contains('.mbg-gpa-display'));
    expect(script, contains("display.style.background = 'transparent'"));
    expect(script, contains("display.style.border = '0'"));
    expect(script, contains("display.style.display = 'block'"));
  });

  test('teardown stops timers and is safe before injection', () async {
    final teardown = GakujoGpaDisplayScript.buildTeardown();
    expect(teardown, contains("querySelectorAll('.mbg-gpa-display')"));
    expect(teardown, contains("'mbg-grade-no-button'"));
    expect(teardown, contains("'mbg-grade-open-number-button'"));
    expect(teardown, contains("'mbg-grade-score-button'"));

    final result = await evaluatePageScriptLifecycle(
      feature: 'gpa',
      buildScript: GakujoGpaDisplayScript.build(),
      teardownScript: teardown,
    );
    final afterBuild = result['afterBuild'] as Map<String, dynamic>;
    final afterTeardown = result['afterTeardown'] as Map<String, dynamic>;
    final afterRebuild = result['afterRebuild'] as Map<String, dynamic>;
    final teardownWithoutBuild =
        result['teardownWithoutBuild'] as Map<String, dynamic>;

    expect(afterBuild['activeIntervalCount'], 1);
    expect(afterBuild['activeTimeoutCount'], 3);
    expect(afterBuild['globalMarkers'], isNotEmpty);
    expect(afterTeardown['activeIntervalCount'], 0);
    expect(afterTeardown['activeTimeoutCount'], 0);
    expect(afterTeardown['globalMarkers'], isEmpty);
    expect(afterRebuild['activeIntervalCount'], 1);
    expect(afterRebuild['activeTimeoutCount'], 3);
    expect(teardownWithoutBuild['activeIntervalCount'], 0);
    expect(teardownWithoutBuild['activeTimeoutCount'], 0);
    expect(teardownWithoutBuild['globalMarkers'], isEmpty);
  });
}
