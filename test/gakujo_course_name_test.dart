import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  test('only the exact download page label is ignored', () {
    expect(isUsefulGakujoCourseName('ダウンロード'), isFalse);
    expect(isUsefulGakujoCourseName('ダウンロード入門'), isTrue);
    expect(isUsefulGakujoCourseName('now loading'), isFalse);
    expect(isUsefulGakujoCourseName('Now Loading...'), isFalse);
    expect(isGakujoSharedDownloadsUrl('https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=sd'), isTrue);
    expect(isGakujoSharedDownloadsUrl('https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=home'), isFalse);
    expect(isGakujoSharedDownloadsUrl(null), isFalse);
  });

  test('error and notice page titles are not course names', () {
    for (final title in [
      'ページの有効期限ぎれ',
      '＜タイムアウトのお知らせ＞',
      'インターネットに接続していないようです',
      'Webpage not available',
      'ログイン',
      'エラー',
    ]) {
      expect(isUsefulGakujoCourseName(title), isFalse, reason: title);
    }
  });

  test('real course names stay usable', () {
    for (final name in ['プログラミング基礎Ⅰ', '情報セキュリティ概論', '健康スポーツ科学講義a']) {
      expect(isUsefulGakujoCourseName(name), isTrue, reason: name);
    }
  });
}
