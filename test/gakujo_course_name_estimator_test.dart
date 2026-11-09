import 'package:morebettergakujo_flutter/src/gakujo_course_name_estimator.dart';
import 'package:test/test.dart';

void main() {
  test('rejects file rows and generic download page labels', () {
    final course = GakujoCourseNameEstimator.estimateFromHtml('''
      <html><head><title>ダウンロード - 学務情報システム</title></head><body>
      <div class="selected">ダウンロード</div>
      <table><tr><td>副専攻授業科目リスト等の変更について（2021.05.20現在）.pdfプレビューを見る
      2021年5月20日 - 9999年12月31日 2021年5月20日 112725
      令和３年度副専攻授業科目リスト等の変更</td></tr></table>
      </body></html>
    ''');
    expect(course, '未分類');
    expect(GakujoCourseNameEstimator.estimateFromCandidates([
      '2023授業科目一覧.pdf プレビューを見る',
      '科目名：資料.pdf プレビューを見る',
      '科目名：資料.PDF',
      '科目名：線形代数',
    ]), '線形代数');
    expect(GakujoCourseNameEstimator.estimateFromCandidates([
      '2023授業科目一覧.pdf プレビューを見る',
    ]), '未分類');
  });

  test('extracts complete labels with separators', () {
    for (final text in [
      '科目名：線形代数',
      '授業科目 ABC123 線形代数',
      '授業科目名 線形代数',
    ]) {
      expect(GakujoCourseNameEstimator.estimateFromCandidates([text]), '線形代数',
          reason: text);
    }
  });

  test('estimates a course from headings', () {
    final course = GakujoCourseNameEstimator.estimateFromHtml('''
      <html>
        <head><title>学務情報システム</title></head>
        <body><h2>情報工学基礎</h2></body>
      </html>
    ''');

    expect(course, '情報工学基礎');
  });

  test('estimates a course from breadcrumb-like elements', () {
    final course = GakujoCourseNameEstimator.estimateFromHtml('''
      <div class="breadcrumb">授業ポートフォリオ &gt; 線形代数学</div>
    ''');

    expect(course, '授業ポートフォリオ 線形代数学');
  });

  test('extracts course name from labeled subject row', () {
    final course = GakujoCourseNameEstimator.estimateFromHtml('''
      <table>
        <tr><th>科目名</th><td>262G5023  物理学基礎BⅠ</td></tr>
      </table>
    ''');

    expect(course, '物理学基礎BⅠ');
  });

  test('extracts course name from subject row without course code', () {
    final course = GakujoCourseNameEstimator.estimateFromHtml('''
      <table>
        <tr><th>科目名</th><td>コンピュータ基礎</td></tr>
      </table>
    ''');

    expect(course, 'コンピュータ基礎');
  });

  test('extracts course name from combined subject label and code', () {
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      '科目名\t262G5023  物理学基礎BⅠ',
    ]);

    expect(course, '物理学基礎BⅠ');
  });

  test('extracts course name from subject label with course code on the right',
      () {
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      '科目名 252G1234 物理学基礎BⅠ',
    ]);

    expect(course, '物理学基礎BⅠ');
  });

  test('extracts course name from combined subject label without code', () {
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      '科目名 コンピュータ基礎',
    ]);

    expect(course, 'コンピュータ基礎');
  });

  test('extracts course name from subject label with colon', () {
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      '科目：コンピュータ基礎',
    ]);

    expect(course, 'コンピュータ基礎');
  });

  test('ignores generic CampusSquare page titles', () {
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      '連絡通知 [CampusSquare]',
      '科目名 コンピュータ基礎',
    ]);

    expect(course, 'コンピュータ基礎');
  });

  test('ignores generic page labels before subject labels', () {
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      '開設一覧',
      '科目名 協創経営概論RD',
    ]);

    expect(course, '協創経営概論RD');
  });

  test('ignores course table header before subject labels', () {
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      '年度 開講所属 開講番号 科目名',
      '科目名 コンピュータ基礎',
    ]);

    expect(course, 'コンピュータ基礎');
  });

  test('ignores report title label before subject labels', () {
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      'タイトル',
      '科目名 物理学基礎BⅠ',
    ]);

    expect(course, '物理学基礎BⅠ');
  });

  test('extracts course name from mixed CampusSquare page text', () {
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      'レポート・小テスト・アンケート提出 [CampusSquare] 科目名 人工知能入門 担当教員 山田',
    ]);

    expect(course, '人工知能入門');
  });

  test('extracts course name from notification text', () {
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      '連絡通知 [重要] 講義資料 [授業連絡通知 授業連絡] コンピュータ基礎の履修者各位 講義資料のPDFファイルを公開します。',
    ]);

    expect(course, 'コンピュータ基礎');
  });

  test('falls back to unclassified when no useful text is found', () {
    final course = GakujoCourseNameEstimator.estimateFromHtml('''
      <html><head><title>CampusSquare</title></head><body></body></html>
    ''');

    expect(course, '未分類');
  });
}
