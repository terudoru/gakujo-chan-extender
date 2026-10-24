import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_dated_activity.dart';

void main() {
  test('detects common Japanese notice date formats', () {
    expect(GakujoDatedActivity.containsDate('説明会を6/30(火)に開催します'), isTrue);
    expect(GakujoDatedActivity.containsDate('提出期限: 2026/07/01 17:00'), isTrue);
    expect(GakujoDatedActivity.containsDate('7月15日にガイダンスがあります'), isTrue);
    expect(GakujoDatedActivity.containsDate('６月３０日（火）までです'), isTrue);
    expect(
      GakujoDatedActivity.containsDate('令和8年7月29日（水）13：00より開催'),
      isTrue,
    );
  });

  test('filters portal chrome and left schedule dates', () {
    expect(
      GakujoDatedActivity.isNoiseText('MYスケジュール 2026/06/29(Mon)'),
      isTrue,
    );
    expect(
      GakujoDatedActivity.isNoiseText('前回ログイン日時: 2026年06月29日 09時22分'),
      isTrue,
    );
    expect(
      GakujoDatedActivity.isNoiseText('2026年06月29日 17時00分 から'),
      isTrue,
    );
    expect(
      GakujoDatedActivity.isNoiseText('2026/06/29(Mon)'),
      isTrue,
    );
  });

  test('classifies dated notices by intent', () {
    expect(
      GakujoDatedActivity.kindFor(text: '課題の提出期限は7/1です', category: '連絡通知'),
      'deadline',
    );
    expect(
      GakujoDatedActivity.kindFor(text: '説明会を7/1に開催します', category: '連絡通知'),
      'schedule',
    );
    expect(
      GakujoDatedActivity.kindFor(text: '停電作業を7/1に行います', category: '連絡通知'),
      'notice',
    );
  });

  test('a deadline beyond 180 characters survives the stored preview', () {
    final text = '2026/10/24 8:45 課題のお知らせ ${'説明文。' * 60} '
        '提出期限：2026/10/30 17:00';
    final preview = GakujoDatedActivity.datedTextPreview(text);
    expect(text.indexOf('2026/10/30'), greaterThan(180));
    expect(preview.length, lessThan(text.length));
    expect(preview, contains('2026/10/30 17:00'));
    final entry = GakujoDeadlineEntry(
      title: '課題のお知らせ',
      url: 'https://gakujo.example/message',
      dueText: preview,
      detectedAt: DateTime.utc(2026, 10, 24),
      source: '連絡通知',
    );
    final store = GakujoActivityStore();
    expect(
      store.isDeadlinePassed(entry, now: DateTime.utc(2026, 10, 30, 7, 59)),
      isFalse,
    );
    expect(
      store.isDeadlinePassed(entry, now: DateTime.utc(2026, 10, 30, 8)),
      isTrue,
    );
  });

  test('message display and posting dates do not become deadlines', () {
    for (final text in [
      '課題の提出方法について 掲示期間：2026/10/24 8:45 ～2026/10/30 17:00',
      '課題の提出方法について 掲載日時：2026/10/24 8:45',
      '課題の提出方法について 送信日時：2026/10/24 8:45',
      '2026/10/24 8:45 課題の提出方法について 授業連絡 '
          '2026/10/24 8:45から 2026/10/30 17:00まで',
    ]) {
      expect(
        GakujoDatedActivity.kindFor(
          text: text,
          category: '連絡通知',
        ),
        'notice',
        reason: text,
      );
    }
  });

  test('stripping message metadata preserves an explicit body deadline', () {
    const text = '掲載日時：2026/10/24 8:45 課題の提出方法について '
        '掲示期間：2026/10/24 8:45 ～2026/11/30 17:00 '
        '送信日時：2026/10/24 8:45 提出期限：2026/10/30 17:00';
    final content = GakujoDatedActivity.messageContentForDates(text);
    // Full-width colons are normalized while stripping.
    expect(content, matches(RegExp(r'提出期限[:：]2026/10/30 17:00')));
    expect(content, isNot(contains('2026/11/30')));
    expect(content, isNot(contains('2026/10/24')));
    expect(
        GakujoDatedActivity.kindFor(text: text, category: '連絡通知'), 'deadline');
    const range = '課題の提出期間：2026/10/24 8:45 ～2026/10/30 17:00';
    expect(
      GakujoDatedActivity.messageContentForDates(range),
      range.replaceAll('：', ':'),
    );
  });
}
