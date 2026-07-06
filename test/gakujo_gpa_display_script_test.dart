import 'package:morebettergakujo_flutter/src/gakujo_gpa_display_script.dart';
import 'package:test/test.dart';

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
    expect(script, contains('unitIndex: 8'));
    expect(script, contains('gpIndex: 12'));
    expect(script, contains('function labelOf(element)'));
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
    expect(script, contains('gradeTable.headerRowIndex + 1'));
    expect(script, contains('__MBG_GPA_DISPLAY_INTERVAL'));
    expect(script, contains('.mbg-gpa-display'));
    expect(script, contains("display.style.background = 'transparent'"));
    expect(script, contains("display.style.border = '0'"));
    expect(script, contains("display.style.display = 'block'"));
  });
}
