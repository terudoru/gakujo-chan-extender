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

  test('download prefers a useful estimate from the original navigation', () {
    expect(
      resolveGakujoDownloadCourseName(
        pageCourseName: 'Course A',
        initialCourseName: 'Cached course',
        navigationRevision: 1,
        currentNavigationRevision: 1,
      ),
      'Course A',
    );
  });

  test('download keeps its starting course after navigation changes', () {
    expect(
      resolveGakujoDownloadCourseName(
        pageCourseName: 'Course B',
        initialCourseName: 'Course A',
        navigationRevision: 1,
        currentNavigationRevision: 2,
      ),
      'Course A',
    );
  });

  test('download rejects a stale estimate without a useful starting course', () {
    for (final initialCourseName in [null, '', '未分類', 'ダウンロード']) {
      expect(
        resolveGakujoDownloadCourseName(
          pageCourseName: 'Course B',
          initialCourseName: initialCourseName,
          navigationRevision: 1,
          currentNavigationRevision: 2,
        ),
        isNull,
      );
    }
  });

  test('download falls back when the original page has no useful estimate', () {
    for (final pageCourseName in [null, '', '未分類', 'ダウンロード']) {
      expect(
        resolveGakujoDownloadCourseName(
          pageCourseName: pageCourseName,
          initialCourseName: 'Course A',
          navigationRevision: 1,
          currentNavigationRevision: 1,
        ),
        'Course A',
      );
    }
    expect(
      resolveGakujoDownloadCourseName(
        pageCourseName: null,
        initialCourseName: null,
        navigationRevision: 1,
        currentNavigationRevision: 1,
      ),
      isNull,
    );
  });
}
