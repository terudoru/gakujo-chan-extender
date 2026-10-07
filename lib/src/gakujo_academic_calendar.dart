/// A 授業振替日: on [date] the timetable of [weekday] is held instead of the
/// date's own weekday.
class GakujoClassDaySwap {
  const GakujoClassDaySwap({required this.date, required this.weekday});

  final DateTime date;
  final int weekday;

  @override
  bool operator ==(Object other) =>
      other is GakujoClassDaySwap &&
      other.weekday == weekday &&
      other.date.year == date.year &&
      other.date.month == date.month &&
      other.date.day == date.day;

  @override
  int get hashCode => Object.hash(date.year, date.month, date.day, weekday);

  @override
  String toString() =>
      'GakujoClassDaySwap(${date.year}-${date.month}-${date.day}, $weekday)';
}

class GakujoAcademicTerm {
  const GakujoAcademicTerm({
    required this.academicYear,
    required this.name,
    required this.start,
    required this.end,
    required this.sourceUrl,
    this.noClassDates = const [],
    this.classDaySwaps = const [],
  });

  final int academicYear;
  final String name;
  final DateTime start;
  final DateTime end;
  final String sourceUrl;
  final List<DateTime> noClassDates;
  final List<GakujoClassDaySwap> classDaySwaps;

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
      classDaySwaps: [
        GakujoClassDaySwap(date: DateTime(2026, 4, 27), weekday: 3),
        GakujoClassDaySwap(date: DateTime(2026, 5, 7), weekday: 1),
        GakujoClassDaySwap(date: DateTime(2026, 5, 8), weekday: 2),
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
      classDaySwaps: [
        GakujoClassDaySwap(date: DateTime(2026, 7, 22), weekday: 1),
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
      classDaySwaps: [
        GakujoClassDaySwap(date: DateTime(2026, 10, 13), weekday: 1),
        GakujoClassDaySwap(date: DateTime(2026, 11, 6), weekday: 2),
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
      classDaySwaps: [
        GakujoClassDaySwap(date: DateTime(2027, 1, 14), weekday: 1),
        GakujoClassDaySwap(date: DateTime(2027, 1, 22), weekday: 1),
      ],
    ),
    // 令和9年度（2027）新潟大学授業暦
    // https://www.niigata-u.ac.jp/wp-content/uploads/2026/07/schedule_2027.pdf
    GakujoAcademicTerm(
      academicYear: 2027,
      name: '第1ターム',
      start: DateTime(2027, 4, 8),
      end: DateTime(2027, 6, 8),
      sourceUrl: calendarPageUrl,
      noClassDates: [
        DateTime(2027, 4, 29),
        DateTime(2027, 5, 3),
        DateTime(2027, 5, 4),
        DateTime(2027, 5, 5),
        DateTime(2027, 6, 1),
        DateTime(2027, 6, 2),
        DateTime(2027, 6, 3),
        DateTime(2027, 6, 4),
        DateTime(2027, 6, 7),
        DateTime(2027, 6, 8),
      ],
      classDaySwaps: [
        GakujoClassDaySwap(date: DateTime(2027, 5, 7), weekday: 3),
      ],
    ),
    GakujoAcademicTerm(
      academicYear: 2027,
      name: '第2ターム',
      start: DateTime(2027, 6, 10),
      end: DateTime(2027, 8, 5),
      sourceUrl: calendarPageUrl,
      noClassDates: [
        DateTime(2027, 7, 19),
        DateTime(2027, 7, 30),
        DateTime(2027, 8, 2),
        DateTime(2027, 8, 3),
        DateTime(2027, 8, 4),
        DateTime(2027, 8, 5),
      ],
      classDaySwaps: [
        GakujoClassDaySwap(date: DateTime(2027, 7, 22), weekday: 1),
      ],
    ),
    GakujoAcademicTerm(
      academicYear: 2027,
      name: '第3ターム',
      start: DateTime(2027, 10, 4),
      end: DateTime(2027, 12, 1),
      sourceUrl: calendarPageUrl,
      noClassDates: [
        DateTime(2027, 10, 11),
        DateTime(2027, 11, 3),
        DateTime(2027, 11, 23),
        DateTime(2027, 11, 25),
        DateTime(2027, 11, 26),
        DateTime(2027, 11, 29),
        DateTime(2027, 11, 30),
        DateTime(2027, 12, 1),
      ],
    ),
    GakujoAcademicTerm(
      academicYear: 2027,
      name: '第4ターム',
      start: DateTime(2027, 12, 3),
      end: DateTime(2028, 2, 14),
      sourceUrl: calendarPageUrl,
      noClassDates: [
        DateTime(2027, 12, 28),
        DateTime(2027, 12, 29),
        DateTime(2027, 12, 30),
        DateTime(2027, 12, 31),
        DateTime(2028, 1, 3),
        DateTime(2028, 1, 4),
        DateTime(2028, 1, 5),
        DateTime(2028, 1, 6),
        DateTime(2028, 1, 10),
        DateTime(2028, 1, 14),
        DateTime(2028, 1, 17),
        DateTime(2028, 2, 4),
        DateTime(2028, 2, 8),
        DateTime(2028, 2, 9),
        DateTime(2028, 2, 10),
        DateTime(2028, 2, 11),
        DateTime(2028, 2, 14),
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

  /// Academic year whose terms should be synced on [date]. Once the last term
  /// of the current academic year has ended (spring break), students prepare
  /// the next year's timetable, so the following year is used.
  static int planningAcademicYearFor(
    DateTime date,
    List<GakujoAcademicTerm> terms,
  ) {
    final day = DateTime(date.year, date.month, date.day);
    final academicYear = academicYearFor(day);
    final currentYearTerms =
        terms.where((term) => term.academicYear == academicYear);
    if (currentYearTerms.isNotEmpty &&
        currentYearTerms.every((term) => term.end.isBefore(day))) {
      return academicYear + 1;
    }
    return academicYear;
  }

  /// Picks the term to sync on [date]. Without [termName] this is the term in
  /// progress, or the next one when [date] falls in a break between terms.
  static GakujoAcademicTerm? selectTerm(
    DateTime date,
    List<GakujoAcademicTerm> terms, {
    String? termName,
  }) {
    final day = DateTime(date.year, date.month, date.day);
    final academicYear = planningAcademicYearFor(day, terms);
    final candidates = terms
        .where((term) => term.academicYear == academicYear)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (termName != null) {
      for (final term in candidates) {
        if (term.name == termName) {
          return term;
        }
      }
      return null;
    }
    final current = termForDateIn(day, candidates);
    if (current != null) {
      return current;
    }
    for (final term in candidates) {
      if (term.start.isAfter(day)) {
        return term;
      }
    }
    return null;
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
    final classDaySwaps = {
      for (final swap in builtIn.classDaySwaps) _dateKey(swap.date): swap,
      // The published PDF wins over the embedded copy for the same date.
      for (final swap in term.classDaySwaps) _dateKey(swap.date): swap,
    }.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return GakujoAcademicTerm(
      academicYear: term.academicYear,
      name: term.name,
      start: term.start,
      end: term.end,
      sourceUrl: term.sourceUrl,
      noClassDates: noClassDates,
      classDaySwaps: classDaySwaps,
    );
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }
}
