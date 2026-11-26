import 'package:morebettergakujo_flutter/src/gakujo_course_name_estimator.dart';
import 'package:test/test.dart';

void main() {
  test('rejects file rows and generic download page labels', () {
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

  test('preserves English words in course names', () {
    for (final text in [
      'Academic Writing',
      '科目名：Academic Writing',
      '科目名 Academic Writing',
    ]) {
      expect(GakujoCourseNameEstimator.estimateFromCandidates([text]),
          'Academic Writing', reason: text);
    }
  });

  test('strips course-code prefixes containing digits', () {
    for (final text in ['ABC123 線形代数', 'abc123 線形代数']) {
      expect(GakujoCourseNameEstimator.estimateFromCandidates([text]), '線形代数',
          reason: text);
    }
    expect(GakujoCourseNameEstimator.estimateFromCandidates([
      '262G5023  物理学基礎BⅠ',
    ]), '物理学基礎BⅠ');
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
    final course = GakujoCourseNameEstimator.estimateFromCandidates([
      'CampusSquare',
    ]);

    expect(course, '未分類');
  });
}
