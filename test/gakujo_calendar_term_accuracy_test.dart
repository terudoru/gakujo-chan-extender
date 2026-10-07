import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_academic_calendar.dart';
import 'package:morebettergakujo_flutter/src/gakujo_academic_calendar_resolver.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_service.dart';

void main() {
  group('term selection', () {
    final terms = GakujoAcademicCalendar.officialTerms;

    test('picks the term in progress', () {
      expect(
        GakujoAcademicCalendar.selectTerm(DateTime(2026, 10, 7), terms)?.name,
        '第3ターム',
      );
    });

    test('picks the next term during a break between terms', () {
      final summer =
          GakujoAcademicCalendar.selectTerm(DateTime(2026, 9, 1), terms);
      expect(summer?.academicYear, 2026);
      expect(summer?.name, '第3ターム');
      expect(
        GakujoAcademicCalendar.selectTerm(DateTime(2026, 12, 2), terms)?.name,
        '第4ターム',
      );
    });

    test('spring break plans the next academic year', () {
      final current =
          GakujoAcademicCalendar.selectTerm(DateTime(2027, 3, 1), terms);
      expect(current?.academicYear, 2027);
      expect(current?.name, '第1ターム');
      final named = GakujoAcademicCalendar.selectTerm(
        DateTime(2027, 3, 1),
        terms,
        termName: '第2ターム',
      );
      expect(named?.academicYear, 2027);
      expect(named?.start, DateTime(2027, 6, 10));
    });

    test('a named term stays in the running academic year', () {
      final first = GakujoAcademicCalendar.selectTerm(
        DateTime(2026, 10, 7),
        terms,
        termName: '第1ターム',
      );
      expect(first?.academicYear, 2026);
    });

    test('built-in 2027 terms follow the published 授業暦', () {
      final third =
          GakujoAcademicCalendar.selectTerm(DateTime(2027, 10, 4), terms);
      expect(third?.academicYear, 2027);
      expect(third?.start, DateTime(2027, 10, 4));
      expect(third?.end, DateTime(2027, 12, 1));
      final fourth =
          GakujoAcademicCalendar.selectTerm(DateTime(2028, 2, 14), terms);
      expect(fourth?.name, '第4ターム');
      expect(fourth?.noClassDates, contains(DateTime(2028, 1, 17)));
      expect(fourth?.noClassDates, isNot(contains(DateTime(2027, 12, 27))));
    });

    test('merged details keep the PDF swap and add built-in ones', () {
      final merged = GakujoAcademicCalendar.mergeWithBuiltInDetails(
        GakujoAcademicTerm(
          academicYear: 2026,
          name: '第1ターム',
          start: DateTime(2026, 4, 8),
          end: DateTime(2026, 6, 8),
          sourceUrl: 'https://example.com/schedule_2026.pdf',
          classDaySwaps: [
            GakujoClassDaySwap(date: DateTime(2026, 4, 27), weekday: 5),
          ],
        ),
      );
      expect(
        merged.classDaySwaps,
        containsAll([
          GakujoClassDaySwap(date: DateTime(2026, 4, 27), weekday: 5),
          GakujoClassDaySwap(date: DateTime(2026, 5, 7), weekday: 1),
        ]),
      );
      expect(merged.classDaySwaps, hasLength(3));
    });
  });

  group('official calendar PDF lookup', () {
    const html = '''
<h2 id="jugyoreki">授業暦・行事予定</h2>
<p><a href="https://www.niigata-u.ac.jp/wp-content/uploads/2025/08/schedule_2026.pdf" target="_blank">令和8年度（2026）新潟大学授業暦</a>（PDF：150KB）</p>
<p><a href="https://www.niigata-u.ac.jp/wp-content/uploads/2026/07/schedule_2027.pdf" target="_blank">令和9年度（2027）新潟大学授業暦</a>（PDF：289KB）</p>
''';

    test('ignores the upload directory year', () {
      expect(
        GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(html, 2025),
        isNull,
      );
      expect(
        GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(html, 2026)
            .toString(),
        endsWith('/2025/08/schedule_2026.pdf'),
      );
      expect(
        GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(html, 2027)
            .toString(),
        endsWith('/2026/07/schedule_2027.pdf'),
      );
    });

    test('prefers the labelled link even when it is listed later', () {
      const newestFirst = '''
<p><a href="/uploads/2026/07/a.pdf">令和9年度 授業暦</a></p>
<p><a href="/uploads/2025/08/b.pdf">令和8年度 授業暦</a></p>
''';
      expect(
        GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(
          newestFirst,
          2026,
        ).toString(),
        endsWith('/2025/08/b.pdf'),
      );
    });
  });

  group('official calendar PDF text', () {
    test('joins mixed literal and CID runs that share a baseline', () {
      // Digits come from a WinAnsi font as literal strings while kanji come
      // from an Identity-H font as hex glyph ids, as in the 2027 授業暦.
      final cmap = {
        0x0001: '第',
        0x0002: 'タ',
        0x0003: 'ー',
        0x0004: 'ム',
        0x0005: '月',
        0x0006: '日',
        0x0007: '～',
        0x0008: '１'
      };
      const content = '''
BT
/C2_0 1 Tf
7.32 0 0 7.32 400 300 Tm
<00010008000200030004>Tj
ET
BT
/TT0 1 Tf
7.32 0 0 7.32 400 280 Tm
(4)Tj
/C2_0 1 Tf
0.5 0 Td
<0005>Tj
/TT0 1 Tf
[(8)] TJ
/C2_0 1 Tf
<00060007>Tj
/TT0 1 Tf
(6)Tj
<0005>Tj
(8)Tj
<0006>Tj
ET
''';
      final lines = GakujoAcademicCalendarPdfParser.textLinesFromContentStream(
        content,
        cmap,
      );
      expect(lines, ['第１ターム', '4 月 8 日～ 6 月 8 日']);
    });

    test('reads spaced ranges, class-day swaps and class-held overrides', () {
      final terms = GakujoAcademicCalendarPdfParser.termsFromExtractedText(
        const GakujoPdfText(
          text: '''
第２ターム
6 月 10 日～ 8 月 5 日
第３ターム
10 月 4 日～ 12 月 1 日
第４ターム
12 月 3 日～ 2 月 14 日
第１ターム
4 月 8 日～ 6 月 8 日
2 3 4 5 6 7 8 5/7　水曜日授業振替 7 8 9
1 (2) (3) (4) 5 6/1　開学記念日
12/27～1/6冬期休業、ただし
26 27 28 29 30 31 12/27 月曜日授業開講
18 19 20 21 22 23 24 7/22　月曜日授業振替
''',
          actualTexts: [],
        ),
        academicYear: 2027,
        sourceUrl: 'https://example.com/schedule_2027.pdf',
      );

      expect(terms, hasLength(4));
      final first = terms[0];
      expect(first.start, DateTime(2027, 4, 8));
      expect(first.noClassDates, contains(DateTime(2027, 6, 1)));
      expect(first.classDaySwaps, [
        GakujoClassDaySwap(date: DateTime(2027, 5, 7), weekday: 3),
      ]);
      expect(terms[1].classDaySwaps, [
        GakujoClassDaySwap(date: DateTime(2027, 7, 22), weekday: 1),
      ]);
      final fourth = terms[3];
      expect(fourth.end, DateTime(2028, 2, 14));
      expect(fourth.noClassDates, contains(DateTime(2027, 12, 28)));
      expect(fourth.noClassDates, isNot(contains(DateTime(2027, 12, 27))));
      // 12/27 is a Monday holding Monday classes: no swap is needed.
      expect(fourth.classDaySwaps, isEmpty);
    });
  });

  group('授業振替日 in generated events', () {
    const monday = GakujoCalendarCourse(
      title: '月曜1限',
      weekday: DateTime.monday,
      period: 1,
    );
    const wednesday = GakujoCalendarCourse(
      title: '水曜2限',
      weekday: DateTime.wednesday,
      period: 2,
    );
    // 2026/04/27 (Mon) runs the Wednesday timetable.
    final swaps = [
      GakujoClassDaySwap(date: DateTime(2026, 4, 27), weekday: 3),
    ];

    test('native events move to the swapped timetable', () {
      final events = GakujoCalendarEventBuilder.buildEvents(
        courses: const [monday, wednesday],
        rangeStart: DateTime(2026, 4, 20),
        rangeEnd: DateTime(2026, 5, 1),
        classDaySwaps: swaps,
        uidNamespace: 'niigata-2026-第1ターム',
      );
      final mondayDates = events
          .where((event) => event.title == '月曜1限')
          .map((event) => event.start)
          .toList();
      final wednesdayDates = events
          .where((event) => event.title == '水曜2限')
          .map((event) => event.start)
          .toList();
      expect(mondayDates, [DateTime(2026, 4, 20, 8, 45)]);
      expect(wednesdayDates, [
        DateTime(2026, 4, 22, 10, 30),
        DateTime(2026, 4, 27, 10, 30),
        DateTime(2026, 4, 29, 10, 30),
      ]);
      expect(events.map((event) => event.id).toSet(), hasLength(4));
    });

    test('ICS excludes the displaced class and adds the swapped one', () {
      final ics = GakujoCalendarExport.buildIcs(
        courses: const [monday, wednesday],
        rangeStart: DateTime(2026, 4, 20),
        rangeEnd: DateTime(2026, 5, 1),
        classDaySwaps: swaps,
        uidNamespace: 'niigata-2026-第1ターム',
        generatedAt: DateTime.utc(2026, 4, 1),
      );
      final events = ics.split('BEGIN:VEVENT').skip(1).toList();
      final mondayEvent =
          events.singleWhere((event) => event.contains('SUMMARY:月曜1限'));
      expect(
        mondayEvent,
        contains('EXDATE;TZID=Asia/Tokyo:20260427T084500'),
      );
      final wednesdayEvents =
          events.where((event) => event.contains('SUMMARY:水曜2限')).toList();
      expect(wednesdayEvents, hasLength(2));
      final oneOff =
          wednesdayEvents.singleWhere((event) => !event.contains('RRULE:'));
      expect(oneOff, contains('DTSTART;TZID=Asia/Tokyo:20260427T103000'));
      final uids = RegExp(r'UID:(\S+)')
          .allMatches(ics)
          .map((match) => match.group(1))
          .toSet();
      expect(uids, hasLength(3));
    });
  });

  test('official Google courses combine every template link on the page', () {
    String link(String title, String dates) =>
        'https://calendar.google.com/calendar/render?action=TEMPLATE'
        '&text=${Uri.encodeComponent(title)}&dates=$dates';
    final firstLink = link('線形代数', '20261005T084500/20261005T101500');
    final pageCourses = [
      ...GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls([
        firstLink,
        link('物理学', '20261006T103000/20261006T120000'),
        link('英語', '20261007T130000/20261007T143000'),
      ]),
      const GakujoCalendarCourse(
        title: '時間割だけの授業',
        weekday: DateTime.thursday,
        period: 2,
      ),
    ];

    final courses = GakujoCalendarExport.officialGoogleCourses(
      pageCourses: pageCourses,
      urls: [firstLink],
    );

    expect(
      courses.map((course) => course.title),
      ['線形代数', '物理学', '英語'],
    );
  });
}
