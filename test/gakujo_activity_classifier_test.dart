import 'package:morebettergakujo_flutter/src/gakujo_activity_classifier.dart';
import 'package:test/test.dart';

void main() {
  for (final (url, title) in [
    (
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/'
          'campusportal.do?page=main&tabId=sch',
      'CampusSquare for WEB [CampusSquare]',
    ),
    (
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do',
      '週間スケジュール [CampusSquare]',
    ),
  ]) {
    test('schedule URL or title wins over assignment keywords: $title', () {
      expect(
        GakujoActivityClassifier.categoryFor(
          url: url,
          title: title,
          text: '[小テスト][263T0506 物理学]第1回【2026/10/30まで】',
        ),
        'スケジュール',
      );
    });
  }

  test('uses the page title before global desktop navigation text', () {
    final category = GakujoActivityClassifier.categoryFor(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
      title: 'レポート・小テスト・アンケート提出 [CampusSquare]',
      text: 'HOME 連絡通知 スケジュール 履修 成績 ダウンロード',
    );

    expect(category, 'レポート・小テスト');
  });

  test('detects the grades page from the tab id without sidebar noise', () {
    final category = GakujoActivityClassifier.categoryFor(
      url:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=si',
      title: '単位修得状況照会 [CampusSquare]',
      text: 'HOME 連絡通知 レポート ダウンロード',
    );

    expect(category, '成績');
  });

  test('does not classify an ordinary page as grades because of the menu', () {
    final category = GakujoActivityClassifier.categoryFor(
      url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
      title: 'HOME [CampusSquare]',
      text: 'HOME 連絡通知 スケジュール シラバス 履修 成績 レポート',
    );

    expect(category, 'Gakujo');
  });

  test('does not turn the generic home portal into a schedule update', () {
    final category = GakujoActivityClassifier.categoryFor(
      url:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main',
      title: 'CampusSquare for WEB [CampusSquare]',
      text: 'HOME\n連絡通知\nスケジュール\nMYスケジュール\n2026年6月',
    );

    expect(category, 'Gakujo');
  });

  test('extracts a readable notice from the generic home portal', () {
    const text = '''
[image]
スマホ版
English
カスタマイズ
残り約20分
ログアウト
吉田 皓彦 さん
前回ログイン日時：
2026年06月29日 09時22分
HOME
連絡通知
スケジュール
お知らせ Gmail CANチェック 学生生活支援
[image]お知らせ
[37]  【マイナー・プログラムの履修登録手続き期間中です】
現在、マイナー・プログラムの履修登録期間中です。
Copyright(c) 2001- NS Solutions Corporation All rights reserved.
''';

    final category = GakujoActivityClassifier.categoryFor(
      url:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main',
      title: 'CampusSquare for WEB [CampusSquare]',
      text: text,
    );
    final title = GakujoActivityClassifier.displayTitleFor(
      url:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main',
      title: 'CampusSquare for WEB [CampusSquare]',
      text: text,
      category: category,
    );

    expect(category, '連絡通知');
    expect(title, 'お知らせ');
  });

  test('extracts only concrete home notices before the schedule section', () {
    const text = '''
スマホ版 English カスタマイズ
新着情報
あなた宛の新着情報があります。
新着のトピックがあります。
授業評価アンケートが登録されました。
MYスケジュール
2026年6月
Mon Tue Wed Thu Fri Sat Sun
1 2 3 4 5 6 7
8 9 10 11 12 13 14
2026/06/30(Tue)
1限: 物理学基礎BⅠ @総合教育研究棟 F-271
リンク
学生共通リンク
''';

    final category = GakujoActivityClassifier.categoryFor(
      url:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main',
      title: 'CampusSquare for WEB [CampusSquare]',
      text: text,
    );
    final title = GakujoActivityClassifier.displayTitleFor(
      url:
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main',
      title: 'CampusSquare for WEB [CampusSquare]',
      text: text,
      category: category,
    );

    expect(title, '新着情報');
  });
}
