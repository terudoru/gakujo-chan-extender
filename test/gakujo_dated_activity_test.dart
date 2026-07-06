import 'package:flutter_test/flutter_test.dart';
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
}
