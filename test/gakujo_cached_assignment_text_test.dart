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
}
