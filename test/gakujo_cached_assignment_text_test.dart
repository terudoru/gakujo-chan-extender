import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_assignment.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  for (final (dueAt, course, expected) in [
    (
      DateTime.utc(2026, 10, 30, 8),
      '物理学',
      'レポート 第1回（物理学） 未提出 締切 2026/10/30 17:00',
    ),
    (
      DateTime.utc(2026, 12, 31, 15, 5),
      '',
      'レポート 第1回 未提出 締切 2027/01/01 00:05',
    ),
  ]) {
    test('cached assignment text keeps Japan wall-clock time for $dueAt', () {
      for (final moment in [dueAt, dueAt.toLocal()]) {
        final assignment = GakujoAssignment(
          kind: 'レポート',
          title: '第1回',
          status: '未提出',
          course: course,
          dueAt: moment,
          capturedAt: DateTime.utc(2026, 10, 24),
        );

        expect(gakujoCachedAssignmentText(assignment), expected);
      }
    });
  }

  group('report list fallback', () {
    test('headings without dates yield no items', () {
      expect(
        gakujoExtractReportListItems(
          'レポート・小テスト・アンケート提出\n提出期間\n提出期限\n該当する課題はありません',
        ),
        isEmpty,
      );
    });

    for (final date in [
      '2026/1/2',
      '1/2',
      '1月2日',
      '２０２６／１／２',
      '１／２',
      '１月２日',
    ]) {
      test('keeps a dated assignment with $date', () {
        final line = 'レポート 第1回 提出期限 $date';
        expect(
          gakujoExtractReportListItems(
            'レポート・小テスト・アンケート提出\n$line\n提出期間\n$date',
          ),
          [line],
        );
      });
    }

    test('truncates only lines longer than 160 characters', () {
      final line = 'レポート 提出期限 2026/1/2 '.padRight(160, 'あ');
      expect(gakujoExtractReportListItems(line), [line]);
      expect(gakujoExtractReportListItems('${line}続き'), ['$line...']);
    });

    test('caps the list at 80 items', () {
      final lines = List.generate(81, (index) => '課題 $index 提出期限 2026/1/2');
      expect(
        gakujoExtractReportListItems(lines.join('\n')),
        lines.take(80).toList(),
      );
    });
  });
}
