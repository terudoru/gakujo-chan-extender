import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_academic_calendar.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  String day(DateTime d) => '${d.month}/${d.day}';

  test('a typed-in period gets the official holidays and swaps inside it', () {
    final range = gakujoManualTermRangeWithOfficialDays(
      GakujoCalendarTermRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
      ),
      GakujoAcademicCalendar.officialTerms,
    );

    // 10/1 is a make-up day before 第3ターム starts; 10/12 is a holiday.
    expect(range.noClassDates.map(day), containsAll(['10/1', '10/12']));
    expect(range.noClassDates.map(day), isNot(contains('11/3')));
    expect(
      [
        for (final swap in range.classDaySwaps)
          '${day(swap.date)}:${swap.weekday}'
      ],
      ['10/13:1'],
    );
  });

  test('a period in a year the calendar does not cover is left as typed', () {
    final range = gakujoManualTermRangeWithOfficialDays(
      GakujoCalendarTermRange(
        start: DateTime(2040, 10, 1),
        end: DateTime(2040, 10, 31),
      ),
      GakujoAcademicCalendar.officialTerms,
    );

    expect(range.noClassDates, isEmpty);
    expect(range.classDaySwaps, isEmpty);
  });
}
