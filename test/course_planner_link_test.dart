import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/course_planner_link.dart';

void main() {
  test(
    'opens the shared planner and passes only an official syllabus course',
    () {
      final detail = coursePlannerLink(
        'https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/84/84_261G7011_ja_JP.html?session=local',
      );
      expect(detail.toString(), '$coursePlannerUrl#course=2026-261G7011');
      for (final other in [
        null,
        'https://example.test/syllabusHtml/2026/84/84_261G7011_ja_JP.html',
        'https://syllabus.niigata-u.ac.jp/syllabusHtml/2026/84/09_261G7011_ja_JP.html',
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
      ]) {
        expect(coursePlannerLink(other).toString(), coursePlannerUrl);
      }
    },
  );
}
