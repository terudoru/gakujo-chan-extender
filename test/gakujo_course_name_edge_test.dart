import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/download_file_name_policy.dart';
import 'package:morebettergakujo_flutter/src/gakujo_course_name_estimator.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

String est(String s) => GakujoCourseNameEstimator.estimateFromCandidates([s]);

void main() {
  final unknown = DownloadFileNamePolicy.unknownCourseFolderName;
  group('estimator', () {
    final cases = <String, String>{
      '科目名：線形代数Ⅰ': '線形代数Ⅰ',
      '科目名: 線形代数Ⅰ': '線形代数Ⅰ',
      '授業科目 ABC123 情報基礎': '情報基礎',
      '授業科目：ABC123 情報基礎': '情報基礎',
      '授業科目名　情報基礎': '情報基礎',
      '授業科目概論': '授業科目概論',
      '授業概論': '授業概論',
      '科目論': '科目論',
      '教養科目': '教養科目',
      '専門科目 線形代数': '専門科目 線形代数',
      '科目名：情報基礎 担当教員 山田': '情報基礎',
      '[科目名：情報基礎]': '情報基礎]',
      '授業科目名：統計学 曜日 月': '統計学',
      'ABC123 情報基礎': '情報基礎',
      'ABC 情報基礎': 'ABC 情報基礎',
      '微分積分の履修者各位': '微分積分',
      'Now Loading...': unknown,
      'now loading': unknown,
      'NOW LOADING 科目': unknown,
      'Loading': 'Loading',
      '': unknown,
      '   ': unknown,
    };
    cases.forEach((input, expected) {
      test('"$input"', () => expect(est(input), expected));
    });
    test('.pdf inside a sentence is a file row', () {
      expect(est('科目名：レポート.pdf を提出'), unknown);
    });
    test('.pdf in a course title without trailing space is not a file row', () {
      expect(est('科目名：C.pdfライブラリ入門'), 'C.pdfライブラリ入門');
    });
    test('very long name does not throw and respects limit', () {
      final out = est('科目名：${'あ' * 2000}');
      expect(out.length, lessThanOrEqualTo(DownloadFileNamePolicy.maxCourseFolderNameLength));
      expect(out, isNotEmpty);
    });
    test('html entities', () {
      expect(GakujoCourseNameEstimator.estimateFromHtml('<tr><td>科目名：A&amp;B 入門</td></tr>'), 'A&B 入門');
    });
  });
  group('isUseful', () {
    for (final v in ['線形代数Ⅰ', '情報基礎', '誤り訂正', 'Webページ設計', '接続論']) {
      test('useful: $v', () => expect(isUsefulGakujoCourseName(v), isTrue));
    }
    for (final v in ['', ' ', '未分類', 'Now Loading', 'now loading...', 'エラー', 'ダウンロード', 'ログイン']) {
      test('not useful: $v', () => expect(isUsefulGakujoCourseName(v), isFalse));
    }
    test('exactly max length ok, one over rejected', () {
      final m = DownloadFileNamePolicy.maxCourseFolderNameLength;
      expect(isUsefulGakujoCourseName('あ' * m), isTrue);
      expect(isUsefulGakujoCourseName('あ' * (m + 1)), isFalse);
    });
    test('estimator output is accepted by isUseful when non-unknown', () {
      for (final s in ['科目名：線形代数Ⅰ', '授業科目 ABC123 情報基礎']) {
        expect(isUsefulGakujoCourseName(est(s)), isTrue);
      }
    });
  });
}
