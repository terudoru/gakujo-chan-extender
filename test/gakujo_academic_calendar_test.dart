import 'package:morebettergakujo_flutter/src/gakujo_academic_calendar.dart';
import 'package:test/test.dart';

void main() {
  test('termForDate returns the official 2026 second term', () {
    final term = GakujoAcademicCalendar.termForDate(DateTime(2026, 6, 29));

    expect(term?.academicYear, 2026);
    expect(term?.name, '第2ターム');
    expect(term?.start, DateTime(2026, 6, 10));
    expect(term?.end, DateTime(2026, 8, 5));
    expect(term?.noClassDates, contains(DateTime(2026, 7, 20)));
    expect(term?.noClassDates, contains(DateTime(2026, 8, 5)));
    expect(term?.sourceUrl, GakujoAcademicCalendar.calendarPageUrl);
  });

  test('termForDate handles the official fourth term across calendar years',
      () {
    final term = GakujoAcademicCalendar.termForDate(DateTime(2027, 1, 15));

    expect(term?.academicYear, 2026);
    expect(term?.name, '第4ターム');
    expect(term?.start, DateTime(2026, 12, 3));
    expect(term?.end, DateTime(2027, 2, 12));
    expect(term?.noClassDates, contains(DateTime(2027, 1, 15)));
    expect(term?.noClassDates, contains(DateTime(2027, 2, 11)));
  });

  test('built-in terms include weekends between no-class Friday and Monday', () {
    for (final term in GakujoAcademicCalendar.officialTerms) {
      for (final friday in term.noClassDates) {
        if (friday.weekday != DateTime.friday) {
          continue;
        }
        final monday = DateTime(friday.year, friday.month, friday.day + 3);
        if (!term.noClassDates.contains(monday)) {
          continue;
        }
        for (final offset in [1, 2]) {
          final weekend =
              DateTime(friday.year, friday.month, friday.day + offset);
          expect(
            term.noClassDates,
            contains(weekend),
            reason: '${term.academicYear} ${term.name}: $weekend',
          );
        }
      }
    }
  });

  test('termForDate returns null outside published terms', () {
    expect(GakujoAcademicCalendar.termForDate(DateTime(2026, 9, 1)), isNull);
  });

  test('academicYearFor follows the Japanese academic year', () {
    expect(GakujoAcademicCalendar.academicYearFor(DateTime(2026, 4, 1)), 2026);
    expect(GakujoAcademicCalendar.academicYearFor(DateTime(2027, 3, 31)), 2026);
  });
}
