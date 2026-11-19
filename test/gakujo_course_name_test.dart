import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_course_name_estimator.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/course_name_body_text.g.dart';
import 'package:morebettergakujo_flutter/src/generated/course_name_estimate.g.dart';
import 'package:morebettergakujo_flutter/src/generated/course_name_tables.g.dart';

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

  group('page course evidence', () {
    final calls = <String>[];
    const primary = gakujoCourseNameEstimateJs;
    const tables = gakujoCourseNameTablesJs;
    const body = gakujoCourseNameBodyTextJs;
    Future<GakujoCourseEstimate> estimate(
      Map<String, Object?> responses, {
      String? title,
    }) {
      calls.clear();
      return estimateGakujoPageCourseName(
        evaluate: (script) async {
          calls.add(script);
          if (!responses.containsKey(script)) throw StateError('unavailable');
          return responses[script];
        },
        isUseful: isUsefulGakujoCourseName,
        fallbackTitle: title,
      );
    }

    test('confirmed ambiguity or a useful primary ends estimation', () async {
      for (final ambiguous in [true, false]) {
        final name = ambiguous ? '未分類' : 'Physics';
        final wire = jsonEncode({
          'courseName': name,
          'courseNameAmbiguous': ambiguous,
        });
        for (final response in [wire, jsonEncode(wire)]) {
          final result = await estimate({
            primary: response,
          }, title: 'Chemistry');
          expect(result.courseName, name);
          expect(result.isAmbiguous, ambiguous);
          expect(calls, [primary]);
        }
      }
    });

    test('legacy unknown and invalid responses still consult every labelled course', () async {
      for (final response in [
        null,
        '{broken',
        'null',
        jsonEncode({'courseName': '未分類', 'courseNameAmbiguous': false}),
        jsonEncode({'courseNameAmbiguous': true}),
        jsonEncode({'courseName': 'Physics', 'courseNameAmbiguous': true}),
      ]) {
        for (final distinct in [false, true]) {
          final evidence = jsonEncode({
            'courseNameCandidates': [
              'ABC123 Physics',
              'Physics',
              'エラー',
              'notes.pdf',
              if (distinct) 'Chemistry',
            ],
          });
          final result = await estimate({
            primary: response,
            tables: jsonEncode(evidence),
          });
          expect(result.courseName, distinct ? '未分類' : 'Physics');
          expect(result.isAmbiguous, distinct);
          expect(calls, [primary, tables]);
        }
      }
    });

    test(
      'missing evidence falls back through body and title in order',
      () async {
        final fromBody = await estimate({
          body: jsonEncode('科目名：Physics'),
        }, title: 'Chemistry');
        expect(fromBody.courseName, 'Physics');
        expect(calls, [primary, tables, body]);
        for (final title in ['Chemistry', 'CampusSquare']) {
          final result = await estimate({
            tables: jsonEncode({
              'courseNameCandidates': ['資料.pdf'],
            }),
            body: 'CampusSquare',
          }, title: title);
          expect(result.courseName, title == 'Chemistry' ? title : isNull);
          expect(result.isAmbiguous, isFalse);
          expect(calls, [primary, tables, body]);
        }
      },
    );

    test('only a current ambiguous result overrides the starting course', () {
      for (final current in [true, false]) {
        final result = resolveGakujoDownloadCourseEstimate(
          pageEstimate: const GakujoCourseEstimate.ambiguous(),
          initialCourseName: 'Physics',
          navigationRevision: 3,
          currentNavigationRevision: current ? 3 : 4,
        );
        expect(result.isAmbiguous, current);
        expect(result.courseName, current ? '未分類' : 'Physics');
      }
    });
  });
}
