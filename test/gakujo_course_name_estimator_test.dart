import 'package:morebettergakujo_flutter/src/gakujo_course_name_estimator.dart';
import 'package:test/test.dart';

void main() {
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

  test('falls back to unclassified when no useful text is found', () {
    final course = GakujoCourseNameEstimator.estimateFromHtml('''
      <html><head><title>CampusSquare</title></head><body></body></html>
    ''');

    expect(course, '未分類');
  });
}
