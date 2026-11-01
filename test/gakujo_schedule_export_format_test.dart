import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_service.dart';

/// Shapes observed on Gakujo's live schedule pages (2026-10).
void main() {
  String allDay(String date, String summary) => [
        'BEGIN:VEVENT',
        'DTSTART;VALUE=DATE:$date',
        'SUMMARY:$summary',
        'END:VEVENT',
      ].join('\r\n');
  List<GakujoCalendarCourse> coursesFrom(List<String> events) =>
      GakujoCalendarExport.coursesFromOfficialScheduleExportText(
        ['BEGIN:VCALENDAR', ...events, 'END:VCALENDAR'].join('\r\n'),
      );

  test('a single ordinary-day make-up meeting stays a one-off', () {
    final courses = coursesFrom([
      allDay('20261023', '3限:A'),
      allDay('20261002', '1限:B'),
      allDay('20261030', '1限:B'),
    ]);
    final makeUp = courses.where((course) => course.title == 'A').toList();
    expect(makeUp.single.recursWeekly, isFalse);
    expect(
      courses
          .where((course) => course.title == 'B')
          .every((course) => course.recursWeekly),
      isTrue,
    );
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: makeUp,
      rangeStart: DateTime(2026, 10, 2),
      rangeEnd: DateTime(2026, 11, 30),
    );
    expect(events.map((event) => event.start), [DateTime(2026, 10, 23, 13)]);
    final ics = GakujoCalendarExport.buildIcs(
      courses: makeUp,
      rangeStart: DateTime(2026, 10, 2),
      rangeEnd: DateTime(2026, 11, 30),
    );
    expect(RegExp('BEGIN:VEVENT').allMatches(ics), hasLength(1));
    expect(ics, contains('DTSTART;TZID=Asia/Tokyo:20261023T130000'));
    expect(ics, isNot(contains('RRULE:')));
  });

  test('duplicate dates and other weekdays or periods do not prove a series',
      () {
    final courses = coursesFrom([
      allDay('20261023', '3限:A'),
      allDay('20261023', '3限:A'),
      allDay('20261030', '4限:A'),
      allDay('20261026', '3限:A'),
    ]);
    expect(courses, hasLength(3));
    expect(courses.every((course) => !course.recursWeekly), isTrue);
  });

  test('the same slot in different weeks proves a weekly series', () {
    final courses = coursesFrom([
      allDay('20261228', '3限:A'),
      allDay('20270104', '3限:A'),
    ]);
    expect(courses, hasLength(2));
    expect(courses.every((course) => course.recursWeekly), isTrue);
  });

  test('the schedule export lists classes as all-day "N限：" events', () {
    String event(String date, String summary) => [
          'BEGIN:VEVENT',
          'DTSTAMP:20261021T074911Z',
          r'UID:UID:20261021T075059Z-uidGen@csweb3\n',
          'SUMMARY:$summary',
          'DTSTART;VALUE=DATE:$date',
          'END:VEVENT',
        ].join('\r\n');
    final ics = [
      'BEGIN:VCALENDAR',
      'PRODID:campusCalendar',
      event('20261002', '1限：プログラミング基礎'),
      event('20261007', '2限：知的財産概論'),
      event('20261009', '1限：プログラミング基礎'),
      event('20261010', '学内イベント'),
      'END:VCALENDAR',
    ].join('\r\n');

    final courses =
        GakujoCalendarExport.coursesFromOfficialScheduleExportText(ics);

    expect(
      [
        for (final course in courses)
          '${GakujoCalendarExport.displayTitleForCourse(course)}:'
              '${course.weekday}:${course.period}:${course.sourceDate!.day}',
      ],
      unorderedEquals([
        'プログラミング基礎:5:1:2',
        '知的財産概論:3:2:7',
        'プログラミング基礎:5:1:9',
      ]),
    );
  });

  test('a month-view calendar is read day by day', () async {
    final result = await Process.run(
      'node',
      ['test/support/gakujo_schedule_export_format_month_view_harness.cts', GakujoCalendarExport.extractionScript()],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final courses = ((jsonDecode(result.stdout as String)
            as Map<String, dynamic>)['courses'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      [
        for (final course in courses)
          '${course['sourceDate']} ${course['weekday']} ${course['period']} '
              '${course['title']} @ ${course['location']}',
      ],
      unorderedEquals([
        '2026-10-02 5 1 プログラミング基礎 @ A-101',
        '2026-10-06 2 4 基礎数理 @ B-353',
        '2026-10-07 3 2 知的財産概論 @ 備考欄参照',
      ]),
    );
  });

  test('the export fetch follows the progress page to the file', () async {
    final result = await Process.run(
      'node',
      [
        'test/support/gakujo_schedule_export_format_export_fetch_harness.cts',
        GakujoCalendarExport.officialScheduleExportFetchScript(
          startDate: '2026/10/02',
          endDate: '2026/12/01',
        ),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final payload = jsonDecode(result.stdout as String) as Map<String, dynamic>;

    expect(payload['status'], 'fetched');
    expect(payload['text'], startsWith('BEGIN:VCALENDAR'));
    expect(
      payload['requests'],
      [
        'POST /campusweb/campussquare.do',
        'GET /campusweb/campussquare.do?_flowExecutionKey=k2&_eventId=output',
      ],
    );
    expect(payload['body'], contains('startYmd=2026%2F10%2F02'));
    expect(payload['body'], contains('check2=true'));
    expect(payload['body'], isNot(contains('check1=true')));
  });

  test('the registration page lists each class with its classroom', () {
    String cell(String code, String weekday, String period, String text) =>
        '<div class="tblDivNml"><a href="" onclick="return '
        "InputCallA('$weekday','$period')\">追加</a><br> "
        '<a href="#" onclick="return '
        "CallDetail('2026','09','$code','$weekday','$period')\"> "
        '$code (T4) </a><br> $text<br> &nbsp;&nbsp; '
        '<input type="button" name="del" value="削除" disabled="disabled">'
        '</div>';
    final html = [
      '<table><tr><td>',
      cell('264T0507', '3', '1', 'プログラミング基礎Ⅱ&nbsp;工学部 計算機演習室&nbsp;2.0単位'),
      cell('264T0004', '3', '3', '技術者の心がまえ◆&nbsp;備考欄参照&nbsp;2.0単位'),
      cell('264G3531', '1', '6', '生成AI活用基礎&nbsp;　&nbsp;1.0単位'),
      '</td></tr></table>',
      // Rejected classes are listed without a CallDetail link.
      '<table><tr><td>260G2509 (T3,4)</td><td>健康スポーツ科学実習 I</td>'
          '<td>第1体育館</td><td>金2</td></tr></table>',
    ].join();

    final courses = GakujoCalendarExport.coursesFromRegistrationPage(html);

    expect(
      [
        for (final course in courses)
          '${course.courseCode} ${course.title} ${course.weekday} '
              '${course.period} [${course.location}]',
      ],
      [
        '264T0507 プログラミング基礎Ⅱ 3 1 [工学部 計算機演習室]',
        '264T0004 技術者の心がまえ 3 3 [備考欄参照]',
        '264G3531 生成AI活用基礎 1 6 []',
      ],
    );
  });

  test('classrooms from the schedule page fill the export gaps', () {
    const exported = [
      GakujoCalendarCourse(
        title: 'プログラミング基礎',
        officialTitle: 'プログラミング基礎',
        weekday: DateTime.friday,
        period: 1,
      ),
      GakujoCalendarCourse(
        title: 'プログラミング基礎',
        weekday: DateTime.tuesday,
        period: 1,
      ),
      GakujoCalendarCourse(
        title: '知的財産概論',
        weekday: DateTime.wednesday,
        period: 2,
        location: 'Zoom',
      ),
    ];
    const page = [
      GakujoCalendarCourse(
        title: 'プログラミング基礎',
        weekday: DateTime.friday,
        period: 1,
        location: 'A-101',
      ),
      GakujoCalendarCourse(
        title: '知的財産概論',
        weekday: DateTime.wednesday,
        period: 2,
        location: 'B-200',
      ),
    ];

    final courses = GakujoCalendarExport.withPageLocations(exported, page);

    expect(
        courses.map((course) => course.location), ['A-101', 'A-101', 'Zoom']);
  });
}
