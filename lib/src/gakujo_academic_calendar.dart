class GakujoAcademicTerm {
  const GakujoAcademicTerm({
    required this.academicYear,
    required this.name,
    required this.start,
    required this.end,
    required this.sourceUrl,
    this.noClassDates = const [],
  });

  final int academicYear;
  final String name;
  final DateTime start;
  final DateTime end;
  final String sourceUrl;
  final List<DateTime> noClassDates;

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

class GakujoAcademicCalendar {
  const GakujoAcademicCalendar._();

  static const calendarPageUrl =
      'https://www.niigata-u.ac.jp/campus/life/schedule/calendar/';

  static final List<GakujoAcademicTerm> officialTerms = [
    GakujoAcademicTerm(
      academicYear: 2026,
      name: '第1ターム',
      start: DateTime(2026, 4, 8),
      end: DateTime(2026, 6, 8),
      sourceUrl: calendarPageUrl,
      noClassDates: [
        DateTime(2026, 4, 29),
        DateTime(2026, 5, 4),
        DateTime(2026, 5, 5),
        DateTime(2026, 5, 6),
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 2),
        DateTime(2026, 6, 3),
        DateTime(2026, 6, 4),
        DateTime(2026, 6, 5),
        DateTime(2026, 6, 8),
      ],
    ),
    GakujoAcademicTerm(
      academicYear: 2026,
      name: '第2ターム',
      start: DateTime(2026, 6, 10),
      end: DateTime(2026, 8, 5),
      sourceUrl: calendarPageUrl,
      noClassDates: [
        DateTime(2026, 7, 20),
        DateTime(2026, 7, 30),
        DateTime(2026, 7, 31),
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 4),
        DateTime(2026, 8, 5),
      ],
    ),
    GakujoAcademicTerm(
      academicYear: 2026,
      name: '第3ターム',
      start: DateTime(2026, 10, 2),
      end: DateTime(2026, 12, 1),
      sourceUrl: calendarPageUrl,
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
    ),
    GakujoAcademicTerm(
      academicYear: 2026,
      name: '第4ターム',
      start: DateTime(2026, 12, 3),
      end: DateTime(2027, 2, 12),
      sourceUrl: calendarPageUrl,
      noClassDates: [
        DateTime(2026, 12, 28),
        DateTime(2026, 12, 29),
        DateTime(2026, 12, 30),
        DateTime(2026, 12, 31),
        DateTime(2027, 1, 1),
        DateTime(2027, 1, 4),
        DateTime(2027, 1, 5),
        DateTime(2027, 1, 6),
        DateTime(2027, 1, 11),
        DateTime(2027, 1, 15),
        DateTime(2027, 1, 18),
        DateTime(2027, 2, 4),
        DateTime(2027, 2, 8),
        DateTime(2027, 2, 9),
        DateTime(2027, 2, 10),
        DateTime(2027, 2, 11),
        DateTime(2027, 2, 12),
      ],
    ),
  ];

  static GakujoAcademicTerm? termForDate(DateTime date) {
    return termForDateIn(date, officialTerms);
  }

  static GakujoAcademicTerm? termForDateIn(
    DateTime date,
    List<GakujoAcademicTerm> terms,
  ) {
    for (final term in terms) {
      if (term.contains(date)) {
        return term;
      }
    }
    return null;
  }

  static int academicYearFor(DateTime date) {
    return date.month >= 4 ? date.year : date.year - 1;
  }

  static GakujoAcademicTerm mergeWithBuiltInDetails(
    GakujoAcademicTerm term,
  ) {
    GakujoAcademicTerm? builtIn;
    for (final candidate in officialTerms) {
      if (candidate.academicYear == term.academicYear &&
          candidate.name == term.name) {
        builtIn = candidate;
        break;
      }
    }
    if (builtIn == null) {
      return term;
    }
    final noClassDates = {
      for (final date in term.noClassDates) _dateKey(date): date,
      for (final date in builtIn.noClassDates) _dateKey(date): date,
    }.values.toList()
      ..sort();
    return GakujoAcademicTerm(
      academicYear: term.academicYear,
      name: term.name,
      start: term.start,
      end: term.end,
      sourceUrl: term.sourceUrl,
      noClassDates: noClassDates,
    );
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }
}
