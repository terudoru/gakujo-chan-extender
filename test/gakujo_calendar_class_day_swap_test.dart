import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_academic_calendar.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_service.dart';

/// 2026年度 第3ターム as published: 10/13 (Tue) runs the Monday timetable and
/// 11/6 (Fri) runs the Tuesday timetable.
final _term3 = GakujoCalendarTermRange(
  start: DateTime(2026, 10, 2),
  end: DateTime(2026, 12, 1),
  sourceText: '2026年度 第3ターム',
  noClassDates: [
    DateTime(2026, 10, 12),
    DateTime(2026, 11, 3),
    DateTime(2026, 11, 23),
    DateTime(2026, 11, 25),
    DateTime(2026, 11, 26),
    DateTime(2026, 11, 27),
    DateTime(2026, 11, 30),
    DateTime(2026, 12, 1),
  ],
  classDaySwaps: [
    GakujoClassDaySwap(date: DateTime(2026, 10, 13), weekday: DateTime.monday),
    GakujoClassDaySwap(date: DateTime(2026, 11, 6), weekday: DateTime.tuesday),
  ],
);

String _event(String uid, String date, String title) => [
      'BEGIN:VEVENT',
      'UID:$uid',
      'DTSTART;TZID=Asia/Tokyo:${date}T084500',
      'DTEND;TZID=Asia/Tokyo:${date}T101500',
      'SUMMARY:$title',
      'END:VEVENT',
    ].join('\r\n');

void main() {
  // Gakujo's schedule export lists each meeting as its own dated event.
  final feed = [
    'BEGIN:VCALENDAR',
    _event('a1', '20261005', '線形代数'),
    _event('a2', '20261013', '線形代数'), // Monday class on the swap day
    _event('a3', '20261019', '線形代数'),
    _event('b1', '20261006', '英語'),
    _event('b3', '20261020', '英語'),
    _event('b2', '20261106', '英語'), // Tuesday class on the swap day
    _event('c1', '20261007', '物理学'),
    _event('c3', '20261014', '物理学'),
    // An exam listed on an exam day, at a different period's start time.
    [
      'BEGIN:VEVENT',
      'UID:c2',
      'DTSTART;TZID=Asia/Tokyo:20261125T103000',
      'DTEND;TZID=Asia/Tokyo:20261125T120000',
      'SUMMARY:物理学',
      'END:VEVENT',
    ].join('\r\n'),
    'END:VCALENDAR',
  ].join('\r\n');

  List<GakujoCalendarCourse> importedCourses() {
    final parsed =
        GakujoCalendarExport.coursesFromOfficialScheduleExportText(feed);
    return GakujoCalendarExport.filterCoursesForTerm(
      courses: GakujoCalendarExport.applyClassDaySwaps(
        parsed,
        _term3.classDaySwaps,
        noClassDates: _term3.noClassDates,
      ),
      termRange: _term3,
      termName: '第3ターム',
    );
  }

  test('a class met on a swap day keeps its real weekday', () {
    final courses = importedCourses();

    final weekly = [
      for (final course in courses)
        if (course.recursWeekly)
          '${course.title}:${course.weekday}:${course.period}',
    ];
    expect(weekly, unorderedEquals(['線形代数:1:1', '英語:2:1', '物理学:3:1']));
  });

  test('a meeting on an exam day does not start a weekly series', () {
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: importedCourses(),
      rangeStart: _term3.start,
      rangeEnd: _term3.end,
      noClassDates: _term3.noClassDates,
      classDaySwaps: _term3.classDaySwaps,
      uidNamespace: 'test',
      termLabel: 'test',
    );
    final secondPeriod = [
      for (final e in events)
        if (e.title.contains('物理学') && e.start.hour == 10)
          '${e.start.month}/${e.start.day}',
    ];
    // The exam stays a single meeting instead of a weekly Wednesday 2限 copy.
    expect(secondPeriod, ['11/25']);
  });

  test('no extra weekly series appears on the swap weekday', () {
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: importedCourses(),
      rangeStart: _term3.start,
      rangeEnd: _term3.end,
      noClassDates: _term3.noClassDates,
      classDaySwaps: _term3.classDaySwaps,
      uidNamespace: 'test',
      termLabel: 'test',
    );
    String day(DateTime d) => '${d.month}/${d.day}';

    final monday = [
      for (final e in events)
        if (e.title.contains('線形代数')) day(e.start),
    ];
    final tuesday = [
      for (final e in events)
        if (e.title.contains('英語')) day(e.start),
    ];
    expect(monday, [
      '10/5', '10/13', '10/19', '10/26', '11/2', '11/9', '11/16', //
    ]);
    expect(tuesday, [
      '10/6', '10/20', '10/27', '11/6', '11/10', '11/17', '11/24', //
    ]);
  });

  test('an exam-day meeting is not doubled when no-class days are off', () {
    final courses = GakujoCalendarExport.applyClassDaySwaps(
      GakujoCalendarExport.coursesFromOfficialScheduleExportText(
        [
          'BEGIN:VCALENDAR',
          _event('w1', '20261118', '物理学'),
          _event('w2', '20261125', '物理学'), // listed on an exam day
          'END:VCALENDAR',
        ].join('\r\n'),
      ),
      _term3.classDaySwaps,
      noClassDates: _term3.noClassDates,
    );
    String day(DateTime d) => '${d.month}/${d.day}';

    // The user chose not to apply holidays and exam days.
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: courses,
      rangeStart: _term3.start,
      rangeEnd: _term3.end,
      uidNamespace: 'test',
      termLabel: 'test',
    );
    expect(
      [for (final e in events) day(e.start)].where((d) => d == '11/25'),
      ['11/25'],
    );

    final ics = GakujoCalendarExport.buildIcs(
      courses: courses,
      rangeStart: _term3.start,
      rangeEnd: _term3.end,
      uidNamespace: 'test',
    );
    expect(RegExp('BEGIN:VEVENT').allMatches(ics), hasLength(1));
    expect(ics, contains('RRULE'));
  });

  test('courses without a date or swap are left alone', () {
    const weekly = GakujoCalendarCourse(title: 'x', weekday: 3, period: 2);
    expect(
      GakujoCalendarExport.applyClassDaySwaps([weekly], _term3.classDaySwaps),
      [weekly],
    );
  });

  test('a cancelled swap-day meeting is absent from direct sync and ICS', () {
    final courses = GakujoCalendarExport.applyClassChanges(
      importedCourses(),
      [
        GakujoClassChange.fromJson({
          'kind': 'kyuko-kyuko',
          'date': '2026-10-13',
          'period': '1',
          'course': '線形代数',
        })!,
      ],
    );
    final events = GakujoCalendarEventBuilder.buildEvents(
      courses: courses,
      rangeStart: _term3.start,
      rangeEnd: _term3.end,
      noClassDates: _term3.noClassDates,
      classDaySwaps: _term3.classDaySwaps,
    );
    final mondayDates = events
        .where((event) => event.title == '線形代数')
        .map((event) => '${event.start.month}/${event.start.day}');
    expect(mondayDates, isNot(contains('10/13')));
    expect(mondayDates, contains('10/19'));

    final ics = GakujoCalendarExport.buildIcs(
      courses: courses,
      rangeStart: _term3.start,
      rangeEnd: _term3.end,
      noClassDates: _term3.noClassDates,
      classDaySwaps: _term3.classDaySwaps,
    );
    expect(ics, isNot(contains('DTSTART;TZID=Asia/Tokyo:20261013T084500')));
    expect(ics, contains('DTSTART;TZID=Asia/Tokyo:20261106T084500'));
  });

  test('the iCalendar export matches the device calendar events', () {
    final ics = GakujoCalendarExport.buildIcs(
      courses: importedCourses(),
      rangeStart: _term3.start,
      rangeEnd: _term3.end,
      noClassDates: _term3.noClassDates,
      classDaySwaps: _term3.classDaySwaps,
      uidNamespace: 'test',
    );
    final starts = RegExp(r'DTSTART;TZID=Asia/Tokyo:(\d{8}T\d{4})')
        .allMatches(ics)
        .map((m) => m.group(1))
        .toList();

    // Weekly series start on their real weekdays only.
    expect(starts, contains('20261005T0845')); // 線形代数 (Mon)
    expect(starts, contains('20261006T0845')); // 英語 (Tue)
    expect(starts, contains('20261007T0845')); // 物理学 (Wed)
    // Swap-day meetings and the exam stay as single events.
    expect(starts, contains('20261013T0845'));
    expect(starts, contains('20261106T0845'));
    expect(starts, contains('20261125T1030'));
    // No weekly copy on the swap weekdays.
    expect(starts.where((s) => s == '20261009T0845'), isEmpty);
    expect(RegExp('RRULE').allMatches(ics), hasLength(3));
  });
}
