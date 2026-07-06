import 'dart:convert';

class GakujoCalendarCourse {
  const GakujoCalendarCourse({
    required this.title,
    required this.weekday,
    required this.period,
    this.location = '',
    this.teacher = '',
    this.officialTitle = '',
    this.officialLocation = '',
    this.officialDescription = '',
    this.sourceDate,
    this.termHint = '',
    this.courseCode = '',
  });

  final String title;
  final int weekday;
  final int period;
  final String location;
  final String teacher;
  final String officialTitle;
  final String officialLocation;
  final String officialDescription;
  final DateTime? sourceDate;
  final String termHint;
  final String courseCode;

  GakujoCalendarCourse copyWith({
    String? title,
    int? weekday,
    int? period,
    String? location,
    String? teacher,
    String? officialTitle,
    String? officialLocation,
    String? officialDescription,
    Object? sourceDate = _unchanged,
    String? termHint,
    String? courseCode,
  }) {
    return GakujoCalendarCourse(
      title: title ?? this.title,
      weekday: weekday ?? this.weekday,
      period: period ?? this.period,
      location: location ?? this.location,
      teacher: teacher ?? this.teacher,
      officialTitle: officialTitle ?? this.officialTitle,
      officialLocation: officialLocation ?? this.officialLocation,
      officialDescription: officialDescription ?? this.officialDescription,
      sourceDate:
          sourceDate == _unchanged ? this.sourceDate : sourceDate as DateTime?,
      termHint: termHint ?? this.termHint,
      courseCode: courseCode ?? this.courseCode,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'weekday': weekday,
      'period': period,
      'location': location,
      'teacher': teacher,
      'officialTitle': officialTitle,
      'officialLocation': officialLocation,
      'officialDescription': officialDescription,
      if (sourceDate != null) 'sourceDate': _dateOnly(sourceDate!),
      'termHint': termHint,
      'courseCode': courseCode,
    };
  }

  factory GakujoCalendarCourse.fromJson(Map<dynamic, dynamic> json) {
    final sourceDate = _parseDateOnly(json['sourceDate']?.toString());
    final explicitWeekday = int.tryParse(json['weekday']?.toString() ?? '');
    return GakujoCalendarCourse(
      title: json['title']?.toString() ?? '',
      weekday: explicitWeekday ?? sourceDate?.weekday ?? 0,
      period: int.tryParse(json['period']?.toString() ?? '') ?? 0,
      location: json['location']?.toString() ?? '',
      teacher: json['teacher']?.toString() ?? '',
      officialTitle: json['officialTitle']?.toString() ?? '',
      officialLocation: json['officialLocation']?.toString() ?? '',
      officialDescription: json['officialDescription']?.toString() ?? '',
      sourceDate: sourceDate,
      termHint: json['termHint']?.toString() ?? '',
      courseCode: _normalizeCourseCode(json['courseCode']?.toString() ?? ''),
    );
  }

  static String _dateOnly(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
  }

  static DateTime? _parseDateOnly(String? raw) {
    final match = RegExp(r'^\s*(20[0-9]{2})[-/]([0-9]{1,2})[-/]([0-9]{1,2})')
        .firstMatch(raw ?? '');
    if (match == null) {
      return null;
    }
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  static String _normalizeCourseCode(String value) {
    const fullWidth = '０１２３４５６７８９ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ';
    const halfWidth = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final buffer = StringBuffer();
    for (final codeUnit in value.trim().toUpperCase().codeUnits) {
      final char = String.fromCharCode(codeUnit);
      final index = fullWidth.indexOf(char);
      buffer.write(index >= 0 ? halfWidth[index] : char);
    }
    return buffer.toString();
  }
}

const _unchanged = Object();

class GakujoPeriodTime {
  const GakujoPeriodTime({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });

  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
}

class GakujoCalendarTermRange {
  const GakujoCalendarTermRange({
    required this.start,
    required this.end,
    this.sourceText = '',
    this.noClassDates = const [],
  });

  final DateTime start;
  final DateTime end;
  final String sourceText;
  final List<DateTime> noClassDates;

  bool get isValid => !end.isBefore(start);
}

class GakujoCalendarExtraction {
  const GakujoCalendarExtraction({
    required this.courses,
    required this.termRange,
  });

  final List<GakujoCalendarCourse> courses;
  final GakujoCalendarTermRange? termRange;
}

class GakujoCalendarExport {
  const GakujoCalendarExport._();

  static const Map<int, GakujoPeriodTime> periodTimes = {
    1: GakujoPeriodTime(
      startHour: 8,
      startMinute: 45,
      endHour: 10,
      endMinute: 15,
    ),
    2: GakujoPeriodTime(
      startHour: 10,
      startMinute: 30,
      endHour: 12,
      endMinute: 0,
    ),
    3: GakujoPeriodTime(
      startHour: 13,
      startMinute: 0,
      endHour: 14,
      endMinute: 30,
    ),
    4: GakujoPeriodTime(
      startHour: 14,
      startMinute: 45,
      endHour: 16,
      endMinute: 15,
    ),
    5: GakujoPeriodTime(
      startHour: 16,
      startMinute: 30,
      endHour: 18,
      endMinute: 0,
    ),
    6: GakujoPeriodTime(
      startHour: 18,
      startMinute: 10,
      endHour: 19,
      endMinute: 40,
    ),
    7: GakujoPeriodTime(
      startHour: 19,
      startMinute: 45,
      endHour: 21,
      endMinute: 15,
    ),
  };

  static String displayTitleForCourse(GakujoCalendarCourse course) {
    final official = _normalizedDisplayText(course.officialTitle);
    return official.isNotEmpty
        ? official
        : _normalizedDisplayText(course.title);
  }

  static String displayLocationForCourse(GakujoCalendarCourse course) {
    final official = _normalizedDisplayText(course.officialLocation);
    return official.isNotEmpty
        ? official
        : _normalizedDisplayText(course.location);
  }

  static String descriptionForCourse({
    required GakujoCalendarCourse course,
    required GakujoPeriodTime periodTime,
    String termLabel = '',
  }) {
    final term = _normalizedDisplayText(termLabel);
    final official = _normalizedMultilineText(course.officialDescription);
    if (official.isNotEmpty) {
      return [
        official,
        if (term.isNotEmpty) 'ターム: $term',
      ].join('\n');
    }

    final lines = <String>[
      '${_weekdayLabel(course.weekday)}曜 ${course.period}限',
      '${_clockLabel(periodTime.startHour, periodTime.startMinute)} - '
          '${_clockLabel(periodTime.endHour, periodTime.endMinute)}',
    ];
    final location = displayLocationForCourse(course);
    if (location.isNotEmpty) {
      lines.add('教室: $location');
    }
    final teacher = _normalizedDisplayText(course.teacher);
    if (teacher.isNotEmpty) {
      lines.add('担当教員: $teacher');
    }
    if (term.isNotEmpty) {
      lines.add('ターム: $term');
    }
    return lines.join('\n');
  }

  static List<GakujoCalendarCourse> coursesFromJson(String raw) {
    return extractionFromJson(raw).courses;
  }

  static List<GakujoCalendarCourse> coursesFromOfficialGoogleCalendarUrls(
    Iterable<String> urls,
  ) {
    final rawCourses = <Map<String, Object?>>[];
    for (final url in urls.expand(_googleCalendarUrlsFromText)) {
      final course = _courseFromOfficialGoogleCalendarUrl(url);
      if (course == null) {
        continue;
      }
      rawCourses.add(course.toJson());
    }
    return _coursesFromDecoded(rawCourses);
  }

  static Iterable<String> _googleCalendarUrlsFromText(String raw) sync* {
    final normalized = raw
        .replaceAll('&amp;', '&')
        .replaceAll(r'\u0026', '&')
        .replaceAll('\\/', '/');
    final matches = RegExp(r'''https?:\/\/[^'"<>\s)]+''').allMatches(
      normalized,
    );
    var yielded = false;
    for (final match in matches) {
      final value = match.group(0);
      if (value == null) {
        continue;
      }
      yielded = true;
      yield value;
    }
    if (!yielded) {
      yield normalized;
    }
  }

  static List<GakujoCalendarCourse> filterCoursesForTerm({
    required List<GakujoCalendarCourse> courses,
    required GakujoCalendarTermRange termRange,
    String termName = '',
  }) {
    final coursesWithTermMetadata = courses.where(_hasTermMetadata).toList();
    if (coursesWithTermMetadata.isEmpty) {
      return courses;
    }

    final normalizedTermName = _normalizeTermHint(termName);
    final selectedTermCode = termCodeFromTermName(termName);
    final matched = <GakujoCalendarCourse>[
      for (final course in courses)
        // Keep a course that carries no term metadata: without a course code,
        // source date, or term hint there is nothing to place it in a
        // different term, so excluding it would silently drop real classes
        // (e.g. weekly-grid Friday cells that expose no date link).
        if (!_hasTermMetadata(course) ||
            _courseMatchesTerm(
              course,
              termRange,
              normalizedTermName: normalizedTermName,
              selectedTermCode: selectedTermCode,
            ))
          course,
    ];
    if (matched.isEmpty) {
      return const [];
    }
    return _dropMislocatedUndatedCourses(
      _mergeCourseSlots(
        _coursesFromDecoded(matched.map((course) => course.toJson()).toList()),
      ),
    );
  }

  /// Removes undated occurrences that look like a make-up class captured on the
  /// wrong weekday.
  ///
  /// The month/week calendar view shows real dated occurrences. When a public
  /// holiday falls on a class's normal weekday, that class is rescheduled onto
  /// another weekday for that one week (e.g. Monday's 日本国憲法 held on
  /// Wednesday 7/22). The scraper cannot always attach a date to such a cell,
  /// so the occurrence would otherwise be treated as a *weekly recurring* class
  /// on the wrong weekday. If the same title has a real dated occurrence on a
  /// different weekday — and none on this undated occurrence's weekday — treat
  /// it as a mislocated make-up and drop it. Titles that never appear dated
  /// (e.g. a class whose cells never expose a date link) are kept untouched.
  static List<GakujoCalendarCourse> _dropMislocatedUndatedCourses(
    List<GakujoCalendarCourse> courses,
  ) {
    final datedWeekdaysByTitle = <String, Set<int>>{};
    for (final course in courses) {
      if (course.sourceDate != null) {
        datedWeekdaysByTitle
            .putIfAbsent(displayTitleForCourse(course).trim(), () => <int>{})
            .add(course.weekday);
      }
    }
    return courses.where((course) {
      if (course.sourceDate != null) {
        return true;
      }
      final datedWeekdays =
          datedWeekdaysByTitle[displayTitleForCourse(course).trim()];
      if (datedWeekdays == null || datedWeekdays.contains(course.weekday)) {
        return true;
      }
      return false;
    }).toList();
  }

  static int? termCodeFromTermName(String termName) {
    final normalized = _normalizeTermHint(termName);
    final match = RegExp(r'第([1-4])ターム').firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1) ?? '');
  }

  static int? termCodeFromCourseCode(String courseCode) {
    final normalized = GakujoCalendarCourse._normalizeCourseCode(courseCode);
    final match = RegExp(r'\b([0-9]{2})([0-4])([A-Z][A-Z0-9]{3,})\b')
        .firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(2) ?? '');
  }

  static String courseCodeFromText(String value) {
    final normalized = GakujoCalendarCourse._normalizeCourseCode(value);
    final match = RegExp(
            r'(?:^|[^A-Z0-9])([0-9]{2}[0-4][A-Z][A-Z0-9]{3,})(?=$|[^A-Z0-9])')
        .firstMatch(normalized);
    return match?.group(1) ?? '';
  }

  static bool hasAmbiguousTermCode(GakujoCalendarCourse course) {
    return termCodeFromCourseCode(course.courseCode) == 0;
  }

  static String courseIdentityKey(GakujoCalendarCourse course) {
    return [
      course.courseCode.trim(),
      displayTitleForCourse(course).trim(),
      course.weekday,
      course.period,
      displayLocationForCourse(course).trim(),
    ].join('\u{1f}');
  }

  static List<GakujoCalendarCourse> coursesFromOfficialScheduleExportText(
    String raw,
  ) {
    var text = raw;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<dynamic, dynamic>) {
        text = decoded['text']?.toString() ?? '';
      }
    } on FormatException {
      // Treat raw as the exported text.
    }
    if (!text.contains('BEGIN:VCALENDAR') || !text.contains('BEGIN:VEVENT')) {
      return const [];
    }

    final rawCourses = <Map<String, Object?>>[];
    for (final event in _icalendarEvents(text)) {
      final title = _unescapeIcalendarText(event['SUMMARY'] ?? '');
      final location = _unescapeIcalendarText(event['LOCATION'] ?? '');
      final description = _unescapeIcalendarText(event['DESCRIPTION'] ?? '');
      final start = _dateTimeFromIcalendarValue(event['DTSTART'] ?? '');
      if (start == null) {
        continue;
      }
      final period = _periodFromStartTime(start);
      if (period == 0) {
        continue;
      }
      rawCourses.add({
        'title': title,
        'weekday': start.weekday,
        'period': period,
        'location': location,
        'teacher': '',
        'officialTitle': title,
        'officialLocation': location,
        'officialDescription': description,
        'sourceDate': GakujoCalendarCourse._dateOnly(start),
        'courseCode': courseCodeFromText('$title $location $description'),
      });
    }
    return _coursesFromDecoded(rawCourses);
  }

  static GakujoCalendarExtraction extractionFromJson(
    String raw, {
    DateTime? referenceDate,
  }) {
    final decoded = jsonDecode(raw);
    Object? rawCourses = decoded;
    String termRangeText = '';
    if (decoded is Map<dynamic, dynamic>) {
      rawCourses = decoded['courses'];
      termRangeText = [
        decoded['termRangeText']?.toString() ?? '',
        decoded['pageText']?.toString() ?? '',
      ].where((text) => text.trim().isNotEmpty).join('\n');
    }
    final courses = _coursesFromDecoded(rawCourses);
    return GakujoCalendarExtraction(
      courses: courses,
      termRange: termRangeFromText(
        termRangeText,
        referenceDate: referenceDate,
      ),
    );
  }

  static List<GakujoCalendarCourse> _coursesFromDecoded(Object? decoded) {
    if (decoded is! List<dynamic>) {
      return const [];
    }
    final seen = <String, int>{};
    final courses = <GakujoCalendarCourse>[];
    for (final item in decoded.whereType<Map<dynamic, dynamic>>()) {
      final course = GakujoCalendarCourse.fromJson(item);
      if (!_isUsefulCourse(course)) {
        continue;
      }
      final key = [
        course.title.trim(),
        course.weekday,
        course.period,
        course.location.trim(),
        course.sourceDate == null
            ? ''
            : GakujoCalendarCourse._dateOnly(course.sourceDate!),
        course.termHint.trim(),
        course.courseCode.trim(),
      ].join('\u{1f}');
      final existingIndex = seen[key];
      if (existingIndex == null) {
        seen[key] = courses.length;
        courses.add(course);
      } else {
        courses[existingIndex] = _mergeCourse(courses[existingIndex], course);
      }
    }
    final mergedCourses = _mergeOfficialSameSlotCourses(courses);
    mergedCourses.sort((a, b) {
      final weekday = a.weekday.compareTo(b.weekday);
      if (weekday != 0) {
        return weekday;
      }
      final period = a.period.compareTo(b.period);
      if (period != 0) {
        return period;
      }
      return a.title.compareTo(b.title);
    });
    return mergedCourses;
  }

  static bool _hasTermMetadata(GakujoCalendarCourse course) {
    return course.courseCode.trim().isNotEmpty ||
        course.sourceDate != null ||
        course.termHint.trim().isNotEmpty;
  }

  static List<GakujoCalendarCourse> _mergeCourseSlots(
    List<GakujoCalendarCourse> courses,
  ) {
    final seen = <String, int>{};
    final merged = <GakujoCalendarCourse>[];
    for (final course in courses) {
      final key = [
        course.title.trim(),
        course.weekday,
        course.period,
        course.courseCode.trim(),
      ].join('\u{1f}');
      final index = seen[key];
      if (index == null) {
        seen[key] = merged.length;
        merged.add(course);
      } else {
        merged[index] = _mergeCourse(merged[index], course);
      }
    }
    return merged;
  }

  static String _termHintFromText(String value) {
    final match = RegExp(r'第\s*([1-4１-４])\s*ターム').firstMatch(value);
    return match?.group(0)?.replaceAll(RegExp(r'\s+'), '') ?? '';
  }

  static String _termHintFromCourseCode(String courseCode) {
    final termCode = termCodeFromCourseCode(courseCode);
    if (termCode == null || termCode < 1 || termCode > 4) {
      return '';
    }
    return '第$termCodeターム';
  }

  static bool _courseMatchesTerm(
    GakujoCalendarCourse course,
    GakujoCalendarTermRange termRange, {
    required String normalizedTermName,
    required int? selectedTermCode,
  }) {
    final codeTerm = termCodeFromCourseCode(course.courseCode);
    if (codeTerm != null) {
      if (codeTerm >= 1 && codeTerm <= 4) {
        return selectedTermCode == null || selectedTermCode == codeTerm;
      }
      if (codeTerm == 0) {
        return selectedTermCode != null &&
            _selectedTermCodesFromHint(course.termHint).contains(
              selectedTermCode,
            );
      }
    }
    final sourceDate = course.sourceDate;
    if (sourceDate != null &&
        !_dateOnly(sourceDate).isBefore(_dateOnly(termRange.start)) &&
        !_dateOnly(sourceDate).isAfter(_dateOnly(termRange.end))) {
      return true;
    }
    if (normalizedTermName.isEmpty) {
      return false;
    }
    final hint = _normalizeTermHint(course.termHint);
    return hint.isNotEmpty && hint.contains(normalizedTermName);
  }

  static Set<int> _selectedTermCodesFromHint(String value) {
    final normalized = _normalizeTermHint(value);
    final terms = <int>{};
    for (final match in RegExp(r'第([1-4])ターム').allMatches(normalized)) {
      final term = int.tryParse(match.group(1) ?? '');
      if (term != null) {
        terms.add(term);
      }
    }
    return terms;
  }

  static String _normalizeTermHint(String value) {
    return value
        .replaceAll('１', '1')
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('４', '4')
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static List<Map<String, String>> _icalendarEvents(String text) {
    final lines = _unfoldIcalendarLines(text);
    final events = <Map<String, String>>[];
    Map<String, String>? current;
    for (final line in lines) {
      if (line == 'BEGIN:VEVENT') {
        current = <String, String>{};
        continue;
      }
      if (line == 'END:VEVENT') {
        if (current != null) {
          events.add(current);
        }
        current = null;
        continue;
      }
      if (current == null) {
        continue;
      }
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final name = line.substring(0, separator).split(';').first.toUpperCase();
      final value = line.substring(separator + 1);
      current[name] = value;
    }
    return events;
  }

  static List<String> _unfoldIcalendarLines(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = <String>[];
    for (final rawLine in normalized.split('\n')) {
      if ((rawLine.startsWith(' ') || rawLine.startsWith('\t')) &&
          lines.isNotEmpty) {
        lines[lines.length - 1] += rawLine.substring(1);
      } else {
        lines.add(rawLine);
      }
    }
    return lines;
  }

  static String _unescapeIcalendarText(String value) {
    return value
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', '\\')
        .trim();
  }

  static DateTime? _dateTimeFromIcalendarValue(String value) {
    final match = RegExp(
      r'([0-9]{4})([0-9]{2})([0-9]{2})T?([0-9]{2})([0-9]{2})([0-9]{2})?(Z)?',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.tryParse(match.group(6) ?? '') ?? 0;
    if (match.group(7) == 'Z') {
      return DateTime.utc(year, month, day, hour, minute, second)
          .add(const Duration(hours: 9));
    }
    return DateTime(year, month, day, hour, minute, second);
  }

  static int _periodFromStartTime(DateTime start) {
    for (final entry in periodTimes.entries) {
      final time = entry.value;
      if (time.startHour == start.hour && time.startMinute == start.minute) {
        return entry.key;
      }
    }
    return 0;
  }

  static GakujoCalendarCourse _mergeCourse(
    GakujoCalendarCourse existing,
    GakujoCalendarCourse incoming,
  ) {
    String choose(String current, String next) {
      return current.trim().isNotEmpty ? current : next;
    }

    return existing.copyWith(
      location: choose(existing.location, incoming.location),
      teacher: choose(existing.teacher, incoming.teacher),
      officialTitle: choose(existing.officialTitle, incoming.officialTitle),
      officialLocation: choose(
        existing.officialLocation,
        incoming.officialLocation,
      ),
      officialDescription: choose(
        existing.officialDescription,
        incoming.officialDescription,
      ),
      sourceDate: existing.sourceDate ?? incoming.sourceDate,
      termHint: choose(existing.termHint, incoming.termHint),
      courseCode: choose(existing.courseCode, incoming.courseCode),
    );
  }

  static List<GakujoCalendarCourse> _mergeOfficialSameSlotCourses(
    List<GakujoCalendarCourse> courses,
  ) {
    if (courses.length < 2) {
      return courses;
    }

    final merged = List<GakujoCalendarCourse>.of(courses);
    final removeIndexes = <int>{};
    for (var officialIndex = 0;
        officialIndex < merged.length;
        officialIndex++) {
      if (removeIndexes.contains(officialIndex)) {
        continue;
      }
      final officialCourse = merged[officialIndex];
      if (!_hasOfficialCalendarData(officialCourse)) {
        continue;
      }

      final sameSlotBaseIndexes = <int>[];
      for (var baseIndex = 0; baseIndex < merged.length; baseIndex++) {
        if (baseIndex == officialIndex || removeIndexes.contains(baseIndex)) {
          continue;
        }
        final baseCourse = merged[baseIndex];
        if (_hasOfficialCalendarData(baseCourse) ||
            baseCourse.weekday != officialCourse.weekday ||
            baseCourse.period != officialCourse.period ||
            !_canMergePotentialSameTerm(baseCourse, officialCourse)) {
          continue;
        }
        sameSlotBaseIndexes.add(baseIndex);
      }
      if (sameSlotBaseIndexes.isEmpty) {
        continue;
      }

      final officialTitle = displayTitleForCourse(officialCourse);
      final titleMatches = sameSlotBaseIndexes
          .where(
            (index) => _titleLooksSame(
              merged[index].title,
              officialTitle,
            ),
          )
          .toList();
      final int? targetIndex;
      if (titleMatches.length == 1) {
        targetIndex = titleMatches.single;
      } else if (sameSlotBaseIndexes.length == 1 &&
          _canMergeSingleSameSlotFallback(
            merged[sameSlotBaseIndexes.single],
            officialCourse,
          )) {
        targetIndex = sameSlotBaseIndexes.single;
      } else {
        targetIndex = null;
      }
      if (targetIndex == null) {
        continue;
      }

      merged[targetIndex] = _mergeCourse(merged[targetIndex], officialCourse);
      removeIndexes.add(officialIndex);
    }

    if (removeIndexes.isEmpty) {
      return merged;
    }
    return [
      for (var index = 0; index < merged.length; index++)
        if (!removeIndexes.contains(index)) merged[index],
    ];
  }

  static bool _hasOfficialCalendarData(GakujoCalendarCourse course) {
    return course.officialTitle.trim().isNotEmpty ||
        course.officialLocation.trim().isNotEmpty ||
        course.officialDescription.trim().isNotEmpty;
  }

  static bool _canMergePotentialSameTerm(
    GakujoCalendarCourse left,
    GakujoCalendarCourse right,
  ) {
    final leftCode = termCodeFromCourseCode(left.courseCode);
    final rightCode = termCodeFromCourseCode(right.courseCode);
    if (leftCode != null &&
        rightCode != null &&
        leftCode >= 1 &&
        rightCode >= 1 &&
        leftCode <= 4 &&
        rightCode <= 4 &&
        leftCode != rightCode) {
      return false;
    }
    final leftHintTerms = _selectedTermCodesFromHint(left.termHint);
    final rightHintTerms = _selectedTermCodesFromHint(right.termHint);
    if (leftCode != null &&
        leftCode >= 1 &&
        leftCode <= 4 &&
        rightHintTerms.isNotEmpty &&
        !rightHintTerms.contains(leftCode)) {
      return false;
    }
    if (leftCode != null &&
        leftCode >= 1 &&
        leftCode <= 4 &&
        rightCode == null &&
        rightHintTerms.isEmpty) {
      return false;
    }
    if (rightCode != null &&
        rightCode >= 1 &&
        rightCode <= 4 &&
        leftHintTerms.isNotEmpty &&
        !leftHintTerms.contains(rightCode)) {
      return false;
    }
    if (rightCode != null &&
        rightCode >= 1 &&
        rightCode <= 4 &&
        leftCode == null &&
        leftHintTerms.isEmpty) {
      return false;
    }
    final leftDate = left.sourceDate;
    final rightDate = right.sourceDate;
    if (leftDate != null &&
        rightDate != null &&
        !_dateOnly(leftDate).isAtSameMomentAs(_dateOnly(rightDate))) {
      return false;
    }
    return true;
  }

  static bool _canMergeSingleSameSlotFallback(
    GakujoCalendarCourse baseCourse,
    GakujoCalendarCourse officialCourse,
  ) {
    return baseCourse.courseCode.trim().isEmpty ||
        officialCourse.courseCode.trim().isNotEmpty;
  }

  static bool _titleLooksSame(String a, String b) {
    final left = _normalizedTitleForMatch(a);
    final right = _normalizedTitleForMatch(b);
    return left.isNotEmpty &&
        right.isNotEmpty &&
        (left == right || left.contains(right) || right.contains(left));
  }

  static String _normalizedTitleForMatch(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  static GakujoCalendarCourse? _courseFromOfficialGoogleCalendarUrl(
    String rawUrl,
  ) {
    final normalized =
        rawUrl.replaceAll('&amp;', '&').replaceAll(r'\u0026', '&').trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return null;
    }

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (!((host.contains('google.') || host == 'calendar.google.com') &&
        path.contains('/calendar'))) {
      return null;
    }

    String firstQueryValue(String name) {
      final values = uri.queryParametersAll[name] ?? const <String>[];
      for (final value in values) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      return '';
    }

    final title = firstQueryValue('text').isNotEmpty
        ? firstQueryValue('text')
        : firstQueryValue('title');
    final location = firstQueryValue('location');
    final details = firstQueryValue('details');
    final courseCode = courseCodeFromText('$title $location $details');
    final dates = firstQueryValue('dates');
    final start = _googleCalendarStartDate(dates.split('/').first);
    if (title.isEmpty || start == null) {
      return null;
    }
    final weekday = start.weekday;
    final period = _periodFromClock(start.hour, start.minute);
    if (period == 0) {
      return null;
    }

    return GakujoCalendarCourse(
      title: title,
      weekday: weekday,
      period: period,
      location: location,
      officialTitle: title,
      officialLocation: location,
      officialDescription: details,
      sourceDate: DateTime(start.year, start.month, start.day),
      termHint: _termHintFromCourseCode(courseCode).isNotEmpty
          ? _termHintFromCourseCode(courseCode)
          : _termHintFromText('$title $details'),
      courseCode: courseCode,
    );
  }

  static DateTime? _googleCalendarStartDate(String rawStart) {
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(?:T?(\d{2})(\d{2})(\d{2})?)?(Z)?',
    ).firstMatch(rawStart.trim());
    if (match == null) {
      return null;
    }
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    final hour = int.tryParse(match.group(4) ?? '0');
    final minute = int.tryParse(match.group(5) ?? '0');
    final second = int.tryParse(match.group(6) ?? '0');
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }
    if (match.group(7) == 'Z') {
      return DateTime.utc(year, month, day, hour, minute, second).add(
        const Duration(hours: 9),
      );
    }
    return DateTime(year, month, day, hour, minute, second);
  }

  static int _periodFromClock(int hour, int minute) {
    final minutes = hour * 60 + minute;
    const starts = {
      525: 1,
      630: 2,
      780: 3,
      885: 4,
      990: 5,
      1090: 6,
      1185: 7,
    };
    return starts[minutes] ?? 0;
  }

  static GakujoCalendarTermRange? termRangeFromText(
    String text, {
    DateTime? referenceDate,
  }) {
    final reference = referenceDate ?? DateTime.now();
    final normalized = text
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('〜', '～')
        .replaceAll('~', '～')
        .replaceAll('－', '～')
        .replaceAll('ー', '～')
        .replaceAll('―', '～')
        .replaceAll('から', '～');
    final relevantLines = normalized
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .where((line) {
      return RegExp(r'(ターム|学期|授業期間|開講期間|履修期間|授業日程|期間)').hasMatch(line);
    }).toList();
    final candidates = relevantLines.isEmpty
        ? normalized.split(RegExp(r'[\r\n]+')).toList()
        : relevantLines;
    for (final line in candidates) {
      final range = _termRangeFromLine(line, reference);
      if (range != null) {
        return range;
      }
    }
    return null;
  }

  static String buildIcs({
    required List<GakujoCalendarCourse> courses,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    List<DateTime> noClassDates = const [],
    String uidNamespace = 'manual',
    String termLabel = '',
    DateTime? generatedAt,
  }) {
    final stamp = _utcTimestamp(generatedAt?.toUtc() ?? DateTime.now().toUtc());
    final until = _utcTimestamp(
      DateTime(
        rangeEnd.year,
        rangeEnd.month,
        rangeEnd.day,
        23,
        59,
        59,
      ).toUtc(),
    );
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//More Better Gakujo//Calendar Export//JA',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:More Better Gakujo 授業',
      'X-WR-TIMEZONE:Asia/Tokyo',
    ];

    for (final course in courses.where(_isUsefulCourse)) {
      final time = periodTimes[course.period];
      if (time == null) {
        continue;
      }
      final firstDate = _firstDateOnOrAfter(rangeStart, course.weekday);
      if (firstDate.isAfter(rangeEnd)) {
        continue;
      }
      final start = DateTime(
        firstDate.year,
        firstDate.month,
        firstDate.day,
        time.startHour,
        time.startMinute,
      );
      final end = DateTime(
        firstDate.year,
        firstDate.month,
        firstDate.day,
        time.endHour,
        time.endMinute,
      );
      final uid = _eventUid(course, uidNamespace);
      final exDates = _exDatesForCourse(
        course: course,
        periodTime: time,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        noClassDates: noClassDates,
      );
      lines.addAll([
        'BEGIN:VEVENT',
        'UID:$uid',
        'DTSTAMP:$stamp',
        'LAST-MODIFIED:$stamp',
        'SEQUENCE:0',
        'SUMMARY:${_escape(displayTitleForCourse(course))}',
        'DTSTART;TZID=Asia/Tokyo:${_localTimestamp(start)}',
        'DTEND;TZID=Asia/Tokyo:${_localTimestamp(end)}',
        'RRULE:FREQ=WEEKLY;UNTIL=$until',
        if (exDates.isNotEmpty)
          'EXDATE;TZID=Asia/Tokyo:${exDates.map(_localTimestamp).join(',')}',
        if (displayLocationForCourse(course).isNotEmpty)
          'LOCATION:${_escape(displayLocationForCourse(course))}',
        'DESCRIPTION:${_escape(
          descriptionForCourse(
            course: course,
            periodTime: time,
            termLabel: termLabel,
          ),
        )}',
        'END:VEVENT',
      ]);
    }

    lines.add('END:VCALENDAR');
    return _foldLines(lines).join('\r\n');
  }

  static String extractionScript() {
    return r'''
(function() {
  var results = [];
  var seen = {};
  function rawTextOf(node) {
    return (node && (node.innerText || node.textContent) || '')
      .replace(/\r\n?/g, '\n')
      .replace(/\u00a0/g, ' ')
      .trim();
  }
  function textOf(node) {
    return rawTextOf(node)
      .replace(/\s+/g, ' ')
      .trim();
  }
  function addCourse(course) {
    if (!course || !course.title || !course.weekday || !course.period) {
      return;
    }
    var key = [
      course.title,
      course.weekday,
      course.period,
      course.location || '',
      course.sourceDate || '',
      course.termHint || '',
      course.courseCode || ''
    ].join('\u001f');
    if (seen[key]) {
      for (var i = 0; i < results.length; i += 1) {
        var existing = results[i];
        var existingKey = [
          existing.title,
          existing.weekday,
          existing.period,
          existing.location || '',
          existing.sourceDate || '',
          existing.termHint || '',
          existing.courseCode || ''
        ].join('\u001f');
        if (existingKey === key) {
          existing.teacher = existing.teacher || course.teacher || '';
          existing.officialTitle = existing.officialTitle ||
            course.officialTitle || '';
          existing.officialLocation = existing.officialLocation ||
            course.officialLocation || '';
          existing.officialDescription = existing.officialDescription ||
            course.officialDescription || '';
          existing.sourceDate = existing.sourceDate || course.sourceDate || '';
          existing.termHint = existing.termHint || course.termHint || '';
          existing.courseCode = existing.courseCode || course.courseCode || '';
          if (!existing.location && course.location) {
            existing.location = course.location;
          }
          return;
        }
      }
      return;
    }
    seen[key] = true;
    results.push(course);
  }
  function normalizeTitle(text) {
    return String(text || '').replace(/\s+/g, '').toLowerCase();
  }
  function titleLooksSame(a, b) {
    var left = normalizeTitle(a);
    var right = normalizeTitle(b);
    return left && right && (left === right ||
      left.indexOf(right) >= 0 || right.indexOf(left) >= 0);
  }
  function titleLooksUseful(title) {
    var normalized = String(title || '').replace(/\s+/g, ' ').trim();
    var compact = normalized.replace(/\s+/g, '');
    if (!compact ||
        /^[0-9]+$/.test(compact) ||
        /^[0-9]{4}[\/年-][0-9]{1,2}[\/月-][0-9]{1,2}日?/.test(compact) ||
        /^(mon|tue|wed|thu|fri|sat|sun)$/i.test(compact) ||
        /^[月火水木金土日]$/.test(compact) ||
        /^(myスケジュール|リンク|新着情報|home)$/i.test(compact)) {
      return false;
    }
    return /[A-Za-zＡ-Ｚａ-ｚ一-龯ぁ-んァ-ヶ]/.test(compact);
  }
  function weekdayFromLabel(label) {
    var value = String(label || '').toLowerCase();
    if (/mon|月/.test(value)) return 1;
    if (/tue|火/.test(value)) return 2;
    if (/wed|水/.test(value)) return 3;
    if (/thu|木/.test(value)) return 4;
    if (/fri|金/.test(value)) return 5;
    if (/sat|土/.test(value)) return 6;
    if (/sun|日/.test(value)) return 7;
    return 0;
  }
  function weekdayFromDateLine(line) {
    var text = String(line || '');
    var labelMatch = text.match(/\(([^)]+)\)/);
    var labelWeekday = weekdayFromLabel(labelMatch && labelMatch[1]);
    if (labelWeekday) {
      return labelWeekday;
    }
    var dateMatch = text.match(/(20[0-9]{2})[\/年-]([0-9]{1,2})[\/月-]([0-9]{1,2})日?/);
    if (!dateMatch) {
      return 0;
    }
    var date = new Date(
      Number(dateMatch[1]),
      Number(dateMatch[2]) - 1,
      Number(dateMatch[3])
    );
    var day = date.getDay();
    return day === 0 ? 7 : day;
  }
  function sourceDateFromLine(line) {
    var match = String(line || '').match(/(20[0-9]{2})[\/年-]([0-9]{1,2})[\/月-]([0-9]{1,2})日?/);
    if (!match) {
      return '';
    }
    function pad(value) {
      return String(value).padStart(2, '0');
    }
    return match[1] + '-' + pad(match[2]) + '-' + pad(match[3]);
  }
  function sourceDateFromNode(node) {
    if (!node) {
      return '';
    }
    var direct = sourceDateFromLine(rawTextOf(node));
    if (direct) {
      return direct;
    }
    var candidates = Array.prototype.slice.call(
      node.querySelectorAll && node.querySelectorAll('[onclick],[href]') || []
    );
    candidates.unshift(node);
    for (var i = 0; i < candidates.length; i += 1) {
      var candidate = candidates[i];
      var text = [
        candidate.getAttribute && candidate.getAttribute('onclick') || '',
        candidate.getAttribute && candidate.getAttribute('href') || ''
      ].join(' ');
      var match = text.match(/(20[0-9]{2})[_\/-]([0-9]{1,2})[_\/-]([0-9]{1,2})/);
      if (match) {
        function pad(value) {
          return String(value).padStart(2, '0');
        }
        return match[1] + '-' + pad(match[2]) + '-' + pad(match[3]);
      }
    }
    return '';
  }
  function termHintFromText(text) {
    var match = String(text || '').match(/第\s*([1-4１-４])\s*ターム/);
    return match ? match[0].replace(/\s+/g, '') : '';
  }
  function termCodesFromHint(text) {
    var normalized = String(text || '')
      .replace(/[１-４]/g, function(ch) {
        return String('１２３４'.indexOf(ch) + 1);
      });
    var terms = {};
    var match;
    var pattern = /第\s*([1-4])\s*ターム/g;
    while ((match = pattern.exec(normalized)) !== null) {
      terms[Number(match[1])] = true;
    }
    return terms;
  }
  function normalizeCourseCode(text) {
    var full = '０１２３４５６７８９ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ';
    var half = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return String(text || '').toUpperCase().replace(/[０-９Ａ-Ｚ]/g, function(ch) {
      var index = full.indexOf(ch);
      return index >= 0 ? half.charAt(index) : ch;
    });
  }
  function courseCodeFromText(text) {
    var value = normalizeCourseCode(text);
    var match = value.match(/(?:^|[^A-Z0-9])([0-9]{2}[0-4][A-Z][A-Z0-9]{3,})(?=$|[^A-Z0-9])/);
    return match ? match[1] : '';
  }
  function termCodeFromCourseCode(code) {
    var normalized = normalizeCourseCode(code);
    var match = normalized.match(/^([0-9]{2})([0-4])([A-Z][A-Z0-9]{3,})$/);
    return match ? Number(match[2]) : null;
  }
  function termHintFromCourseCode(code) {
    var termCode = termCodeFromCourseCode(code);
    return termCode && termCode >= 1 && termCode <= 4
      ? '第' + termCode + 'ターム'
      : '';
  }
  function splitTitleAndLocation(raw) {
    var value = String(raw || '').replace(/\s+/g, ' ').trim();
    var courseCode = courseCodeFromText(value);
    if (courseCode) {
      value = normalizeCourseCode(value)
        .replace(courseCode, ' ')
        .replace(/\s+/g, ' ')
        .trim();
    }
    var parts = value.split(/\s*[@＠]\s*/);
    return {
      title: (parts.shift() || '').trim(),
      location: parts.join(' @ ').trim(),
      courseCode: courseCode
    };
  }
  function addDailyLineCourse(
    weekday,
    period,
    rawTitleAndLocation,
    sourceDate,
    termHint
  ) {
    var split = splitTitleAndLocation(rawTitleAndLocation);
    if (!weekday || !period || !titleLooksUseful(split.title)) {
      return;
    }
    addCourse({
      title: split.title,
      weekday: weekday,
      period: period,
      location: split.location,
      teacher: '',
      sourceDate: sourceDate || '',
      termHint: termHint ||
        termHintFromCourseCode(split.courseCode) ||
        termHintFromText(rawTitleAndLocation),
      courseCode: split.courseCode || courseCodeFromText(rawTitleAndLocation)
    });
  }
  function periodFromTimeText(text) {
    var value = String(text || '').replace(/\s+/g, '');
    var match = value.match(/([0-9]{1,2})[:：]([0-9]{2})\s*[~〜～\-−ー]\s*([0-9]{1,2})[:：]([0-9]{2})/);
    if (!match) {
      return 0;
    }
    var start = Number(match[1]) * 60 + Number(match[2]);
    var starts = {
      525: 1,
      630: 2,
      780: 3,
      885: 4,
      990: 5,
      1090: 6,
      1185: 7
    };
    return starts[start] || 0;
  }
  function cleanCourseText(text) {
    return String(text || '')
      .replace(/\b[0-9]{1,2}[:：][0-9]{2}\s*[~〜～\-−ー]\s*[0-9]{1,2}[:：][0-9]{2}\b/g, ' ')
      .replace(/^\s*[0-9]{1,2}\s*$/, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }
  function cleanTimetableCellText(text, courseCode) {
    var value = normalizeCourseCode(text)
      .replace(courseCode, ' ')
      .replace(/\(\s*T\s*[0-9,，、]+\s*\)/gi, ' ')
      .replace(/第\s*[1-4１-４]\s*ターム/g, ' ')
      .replace(/備考欄参照\s*\/?\s*See\s*remarks/gi, ' ')
      .replace(/[0-9]+(?:\.[0-9]+)?\s*単位/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    return value;
  }
  function splitTimetableTitleAndLocation(text) {
    var value = String(text || '').replace(/\s+/g, ' ').trim();
    var location = '';
    var locationMatch = value.match(
      /\s((?:総合教育研究棟|工学部|農学部|人文学部|教育学部|理学部|医学部|歯学部|図書館|未定)\s*[A-ZＡ-Ｚ]?-?[0-9０-９A-ZＡ-Ｚ,\- 　]*)$/i
    );
    if (!locationMatch) {
      locationMatch = value.match(
        /\s([A-ZＡ-Ｚ]-?[0-9０-９]{2,}[A-ZＡ-Ｚ,\- 　]*)$/i
      );
    }
    if (locationMatch) {
      location = locationMatch[1].trim();
      value = value.substring(0, locationMatch.index).trim();
    }
    return {
      title: value,
      location: location
    };
  }
  function addTimetableGridCellCourse(weekday, period, raw) {
    if (!weekday || !period) {
      return;
    }
    var rawText = String(raw || '');
    var code = courseCodeFromText(rawText);
    if (!code) {
      return;
    }
    var cleaned = cleanTimetableCellText(rawText, code);
    var split = splitTimetableTitleAndLocation(cleaned);
    if (!titleLooksUseful(split.title)) {
      return;
    }
    addCourse({
      title: split.title,
      weekday: weekday,
      period: period,
      location: split.location,
      teacher: '',
      sourceDate: '',
      termHint: termHintFromCourseCode(code) || termHintFromText(rawText),
      courseCode: code
    });
  }
  function parseScheduleTextWithWeekday(weekday, raw, sourceDate, termHint) {
    if (!weekday) {
      return;
    }
    var text = String(raw || '').replace(/\r\n?/g, '\n');
    var dateHint = sourceDate || sourceDateFromLine(text);
    var termHintValue = termHint || termHintFromText(text);
    var periodPattern = /(?:^|[\n\s　])([1-7])\s*限\s*[:：]\s*([\s\S]*?)(?=(?:[\n\s　][1-7]\s*限\s*[:：])|$)/g;
    var match;
    var foundPeriod = false;
    while ((match = periodPattern.exec(text)) !== null) {
      foundPeriod = true;
      addDailyLineCourse(
        weekday,
        Number(match[1]),
        cleanCourseText(match[2]),
        dateHint,
        termHintValue
      );
    }
    if (foundPeriod) {
      return;
    }

    var period = periodFromTimeText(text);
    if (!period) {
      return;
    }
    var lines = text.split(/\n+/)
      .map(function(line) {
        return cleanCourseText(line);
      })
      .filter(function(line) {
        return titleLooksUseful(line) &&
          !/[0-9]{1,2}[:：][0-9]{2}/.test(line);
      });
    if (lines.length) {
      addDailyLineCourse(
        weekday,
        period,
        lines.join(' '),
        dateHint,
        termHintValue
      );
    }
  }
  function parseDailySummaryCell(weekday, raw, sourceDate) {
    // The weekday is already known from the column header, so parse the cell
    // even when no per-cell date is available. Previously requiring a
    // sourceDate here dropped every day-column whose cell carried no embedded
    // date, so typically only the single column that happened to hold a date
    // (e.g. "today") produced courses -- leaving only one weekday on the
    // calendar.
    if (!weekday) {
      return;
    }
    var text = String(raw || '').replace(/\r\n?/g, '\n');
    var pattern = /(?:^|[\s\n　])([1-7])\s*限\s*[:：]\s*([\s\S]*?)(?=(?:[\s\n　][1-7]\s*限\s*[:：])|(?:[\s\n　]*\[[^\]]+\])|$)/g;
    var match;
    while ((match = pattern.exec(text)) !== null) {
      addDailyLineCourse(
        weekday,
        Number(match[1]),
        cleanCourseText(match[2]),
        sourceDate,
        termHintFromText(text)
      );
    }
  }
  function columnWeekdayMapFromRow(row) {
    var cells = Array.prototype.slice.call(row.children || []);
    var map = {};
    var found = 0;
    for (var i = 0; i < cells.length; i += 1) {
      var weekday = weekdayFromLabel(textOf(cells[i]));
      if (weekday) {
        map[i] = weekday;
        found += 1;
      }
    }
    return found >= 3 ? map : null;
  }
  function columnDateMapFromRow(row) {
    // Weekly-view headers usually pair each weekday with its date (e.g.
    // "月 6/29"); capture those so every day-column has a date for term
    // filtering, not just the columns whose body cell embeds one.
    var cells = Array.prototype.slice.call(row.children || []);
    var map = {};
    for (var i = 0; i < cells.length; i += 1) {
      var date = sourceDateFromLine(textOf(cells[i]));
      if (date) {
        map[i] = date;
      }
    }
    return map;
  }
  function headerMapFromRow(row) {
    var cells = Array.prototype.slice.call(row.children || []);
    var map = {};
    var hits = 0;
    for (var i = 0; i < cells.length; i += 1) {
      var text = textOf(cells[i]);
      if (/開講番号|講義番号|科目番号/.test(text)) {
        map.code = i;
        hits += 1;
      } else if (/科目名|授業科目|講義名/.test(text)) {
        map.title = i;
        hits += 1;
      } else if (/曜日/.test(text)) {
        map.weekday = i;
        hits += 1;
      } else if (/時限|時限目|校時|時間/.test(text)) {
        map.period = i;
        hits += 1;
      } else if (/教室|場所|講義室/.test(text)) {
        map.location = i;
      } else if (/担当|教員/.test(text)) {
        map.teacher = i;
      }
    }
    return hits >= 2 && map.code !== undefined ? map : null;
  }
  function exactWeekdayFromCell(text) {
    var value = String(text || '').replace(/\s+/g, '').toLowerCase();
    if (/^(mon|月|月曜|月曜日)$/.test(value)) return 1;
    if (/^(tue|火|火曜|火曜日)$/.test(value)) return 2;
    if (/^(wed|水|水曜|水曜日)$/.test(value)) return 3;
    if (/^(thu|木|木曜|木曜日)$/.test(value)) return 4;
    if (/^(fri|金|金曜|金曜日)$/.test(value)) return 5;
    if (/^(sat|土|土曜|土曜日)$/.test(value)) return 6;
    if (/^(sun|日|日曜|日曜日)$/.test(value)) return 7;
    return weekdayFromDateLine(text);
  }
  function periodFromCell(text) {
    var value = String(text || '').replace(/\s+/g, '');
    var match = value.match(/^([1-7])(?:限|時限|時限目|校時)?$/);
    if (match) {
      return Number(match[1]);
    }
    match = value.match(/([1-7])(?:限|時限|時限目|校時)/);
    if (match) {
      return Number(match[1]);
    }
    return periodFromTimeText(value);
  }
  function periodFromRowHeaderCell(text) {
    var value = String(text || '').replace(/\s+/g, '');
    var match = value.match(/^([1-7])(?:限|時限|時限目|校時)$/);
    return match ? Number(match[1]) : 0;
  }
  function cellAt(cells, index) {
    if (index === undefined || index < 0 || index >= cells.length) {
      return '';
    }
    return textOf(cells[index]);
  }
  function scanCourseRows(doc) {
    var tables = Array.prototype.slice.call(doc.querySelectorAll('table'));
    for (var t = 0; t < tables.length; t += 1) {
      var rows = Array.prototype.slice.call(tables[t].querySelectorAll('tr'));
      var headerMap = null;
      for (var r = 0; r < rows.length; r += 1) {
        var row = rows[r];
        var maybeHeader = headerMapFromRow(row);
        if (maybeHeader) {
          headerMap = maybeHeader;
          continue;
        }
        var cells = Array.prototype.slice.call(row.children || []);
        if (!cells.length) {
          continue;
        }
        var rowText = rawTextOf(row);
        var code = headerMap ?
          (courseCodeFromText(cellAt(cells, headerMap.code)) || courseCodeFromText(rowText)) :
          courseCodeFromText(rowText);
        if (!code) {
          continue;
        }
        var title = headerMap ? cellAt(cells, headerMap.title) : '';
        if (!title) {
          for (var c = 0; c < cells.length; c += 1) {
            var candidate = textOf(cells[c]);
            if (candidate.indexOf(code) >= 0) {
              continue;
            }
            if (titleLooksUseful(candidate) &&
                !exactWeekdayFromCell(candidate) &&
                !periodFromCell(candidate)) {
              title = candidate;
              break;
            }
          }
        }
        var weekday = headerMap ? exactWeekdayFromCell(cellAt(cells, headerMap.weekday)) : 0;
        var period = headerMap ? periodFromCell(cellAt(cells, headerMap.period)) : 0;
        if (!weekday || !period) {
          for (var p = 0; p < cells.length; p += 1) {
            var cellText = textOf(cells[p]);
            weekday = weekday || exactWeekdayFromCell(cellText);
            period = period || periodFromCell(cellText);
          }
        }
        if (!weekday || !period || !titleLooksUseful(title)) {
          continue;
        }
        addCourse({
          title: splitTitleAndLocation(title).title,
          weekday: weekday,
          period: period,
          location: headerMap ? cellAt(cells, headerMap.location) : '',
          teacher: headerMap ? cellAt(cells, headerMap.teacher) : '',
          sourceDate: sourceDateFromLine(rowText),
          termHint: termHintFromCourseCode(code) || termHintFromText(rowText),
          courseCode: code
        });
      }
    }
  }
  function scanScheduleTables(doc) {
    var tables = Array.prototype.slice.call(doc.querySelectorAll('table'));
    for (var t = 0; t < tables.length; t += 1) {
      var table = tables[t];
      var rows = Array.prototype.slice.call(table.querySelectorAll('tr'));
      var columnWeekdays = null;
      var columnDates = null;
      for (var r = 0; r < rows.length; r += 1) {
        var row = rows[r];
        var rowMap = columnWeekdayMapFromRow(row);
        if (rowMap) {
          columnWeekdays = rowMap;
          columnDates = columnDateMapFromRow(row);
          continue;
        }
        var cells = Array.prototype.slice.call(row.children || []);
        if (!columnWeekdays) {
          continue;
        }
        var rowPeriod = cells.length ? periodFromRowHeaderCell(textOf(cells[0])) : 0;
        if (!rowPeriod) {
          for (var sc = 0; sc < cells.length; sc += 1) {
            if (!columnWeekdays[sc]) {
              continue;
            }
            parseDailySummaryCell(
              columnWeekdays[sc],
              rawTextOf(cells[sc]),
              sourceDateFromNode(cells[sc]) ||
                (columnDates && columnDates[sc]) || ''
            );
          }
          continue;
        }
        for (var c = 0; c < cells.length; c += 1) {
          var cellText = rawTextOf(cells[c]);
          if (rowPeriod && columnWeekdays[c] && courseCodeFromText(cellText)) {
            addTimetableGridCellCourse(columnWeekdays[c], rowPeriod, cellText);
            continue;
          }
        }
      }
    }
  }
  function hasOfficialFields(course) {
    return !!(course && (
      course.officialTitle ||
      course.officialLocation ||
      course.officialDescription
    ));
  }
  function mergeOfficialEventIntoCourse(course, event) {
    course.officialTitle = event.officialTitle || course.officialTitle || '';
    course.officialLocation =
      event.officialLocation || course.officialLocation || '';
    course.officialDescription =
      event.officialDescription || course.officialDescription || '';
    course.sourceDate = event.sourceDate || course.sourceDate || '';
    course.termHint = event.termHint || course.termHint || '';
    course.courseCode = course.courseCode || event.courseCode || '';
    if (!course.location && event.location) {
      course.location = event.location;
    }
  }
  function canMergePotentialSameTerm(course, event) {
    var courseTerm = termCodeFromCourseCode(course && course.courseCode || '');
    var eventTerm = termCodeFromCourseCode(event && event.courseCode || '');
    if (courseTerm !== null && eventTerm !== null &&
        courseTerm >= 1 && courseTerm <= 4 &&
        eventTerm >= 1 && eventTerm <= 4 &&
        courseTerm !== eventTerm) {
      return false;
    }
    var courseHintTerms = termCodesFromHint(course && course.termHint || '');
    var eventHintTerms = termCodesFromHint(event && event.termHint || '');
    if (courseTerm !== null && courseTerm >= 1 && courseTerm <= 4 &&
        Object.keys(eventHintTerms).length &&
        !eventHintTerms[courseTerm]) {
      return false;
    }
    if (courseTerm !== null && courseTerm >= 1 && courseTerm <= 4 &&
        eventTerm === null && !Object.keys(eventHintTerms).length) {
      return false;
    }
    if (eventTerm !== null && eventTerm >= 1 && eventTerm <= 4 &&
        Object.keys(courseHintTerms).length &&
        !courseHintTerms[eventTerm]) {
      return false;
    }
    if (eventTerm !== null && eventTerm >= 1 && eventTerm <= 4 &&
        courseTerm === null && !Object.keys(courseHintTerms).length) {
      return false;
    }
    if (course && event && course.sourceDate && event.sourceDate &&
        course.sourceDate !== event.sourceDate) {
      return false;
    }
    return true;
  }
  function sameSlotCourses(event) {
    return results.filter(function(course) {
      return course.weekday === event.weekday &&
        course.period === event.period &&
        canMergePotentialSameTerm(course, event);
    });
  }
  function googleStartDate(start) {
    var match = String(start || '')
      .match(/^(\d{4})(\d{2})(\d{2})(?:T?(\d{2})(\d{2})(\d{2})?)?(Z)?/);
    if (!match) {
      return null;
    }
    var year = Number(match[1]);
    var month = Number(match[2]) - 1;
    var day = Number(match[3]);
    var hour = Number(match[4] || 0);
    var minute = Number(match[5] || 0);
    var second = Number(match[6] || 0);
    if (match[7] === 'Z') {
      var jstDate = new Date(
        Date.UTC(year, month, day, hour, minute, second) +
          9 * 60 * 60 * 1000
      );
      var utcDay = jstDate.getUTCDay();
      return {
        hour: jstDate.getUTCHours(),
        minute: jstDate.getUTCMinutes(),
        weekday: utcDay === 0 ? 7 : utcDay,
        sourceDate: [
          jstDate.getUTCFullYear(),
          String(jstDate.getUTCMonth() + 1).padStart(2, '0'),
          String(jstDate.getUTCDate()).padStart(2, '0')
        ].join('-')
      };
    }
    var localDate = new Date(year, month, day, hour, minute, second);
    var localDay = localDate.getDay();
    return {
      hour: localDate.getHours(),
      minute: localDate.getMinutes(),
      weekday: localDay === 0 ? 7 : localDay,
      sourceDate: [
        localDate.getFullYear(),
        String(localDate.getMonth() + 1).padStart(2, '0'),
        String(localDate.getDate()).padStart(2, '0')
      ].join('-')
    };
  }
  function googlePeriodFromStart(start) {
    var date = googleStartDate(start);
    if (!date) {
      return 0;
    }
    var minutes = date.hour * 60 + date.minute;
    var starts = {
      525: 1,
      630: 2,
      780: 3,
      885: 4,
      990: 5,
      1090: 6,
      1185: 7
    };
    return starts[minutes] || 0;
  }
  function googleWeekdayFromStart(start) {
    var date = googleStartDate(start);
    if (!date) {
      return 0;
    }
    return date.weekday;
  }
  function extractGoogleUrls(raw, baseUrl) {
    var values = [];
    var text = String(raw || '')
      .replace(/&amp;/g, '&')
      .replace(/\\u0026/g, '&');
    var matches = text.match(/https?:\/\/[^'"<>\s)]+/g) || [];
    if (/calendar/i.test(text) && /^https?:\/\//i.test(text)) {
      matches.push(text);
    }
    for (var i = 0; i < matches.length; i += 1) {
      try {
        var url = new URL(matches[i], baseUrl);
        var host = url.hostname.toLowerCase();
        var path = url.pathname.toLowerCase();
        if ((host.indexOf('google.') >= 0 ||
             host === 'calendar.google.com') &&
            path.indexOf('/calendar') >= 0 &&
            (url.searchParams.has('text') ||
             url.searchParams.has('details') ||
             url.searchParams.has('dates'))) {
          values.push(url);
        }
      } catch (e) {}
    }
    return values;
  }
  function officialEventFromUrl(url) {
    var title = (url.searchParams.get('text') ||
      url.searchParams.get('title') || '').trim();
    var location = (url.searchParams.get('location') || '').trim();
    var details = (url.searchParams.get('details') || '').trim();
    var dates = (url.searchParams.get('dates') || '').split('/')[0] || '';
    var courseCode = courseCodeFromText(title + ' ' + details + ' ' + location);
    var weekday = googleWeekdayFromStart(dates);
    var period = googlePeriodFromStart(dates);
    var startDate = googleStartDate(dates);
    if (!title || !weekday || !period) {
      return null;
    }
    return {
      title: title,
      weekday: weekday,
      period: period,
      location: location,
      teacher: '',
      officialTitle: title,
      officialLocation: location,
      officialDescription: details,
      sourceDate: startDate && startDate.sourceDate || '',
      termHint: termHintFromCourseCode(courseCode) ||
        termHintFromText(title + ' ' + details),
      courseCode: courseCode
    };
  }
  function attachOfficialEvent(event) {
    if (!event) {
      return;
    }
    var matchingCourses = sameSlotCourses(event);
    for (var i = 0; i < matchingCourses.length; i += 1) {
      var course = matchingCourses[i];
      if (titleLooksSame(course.title, event.title)) {
        mergeOfficialEventIntoCourse(course, event);
        return;
      }
    }
    if (matchingCourses.length === 1 &&
        !hasOfficialFields(matchingCourses[0]) &&
        (!matchingCourses[0].courseCode || event.courseCode)) {
      mergeOfficialEventIntoCourse(matchingCourses[0], event);
      return;
    }
    addCourse(event);
  }
  function scanOfficialGoogleCalendarLinks(doc) {
    var nodes = Array.prototype.slice.call(
      doc.querySelectorAll('a,button,input,[onclick],[data-url],[data-href]')
    );
    var seenUrls = {};
    for (var n = 0; n < nodes.length; n += 1) {
      var node = nodes[n];
      var sources = [
        node.getAttribute && node.getAttribute('href') || '',
        node.getAttribute && node.getAttribute('onclick') || '',
        node.value || ''
      ];
      var attrs = node.attributes || [];
      for (var a = 0; a < attrs.length; a += 1) {
        if (/^data-/i.test(attrs[a].name)) {
          sources.push(attrs[a].value || '');
        }
      }
      for (var s = 0; s < sources.length; s += 1) {
        var urls = extractGoogleUrls(sources[s], doc.location.href);
        for (var u = 0; u < urls.length; u += 1) {
          var href = urls[u].href;
          if (seenUrls[href]) {
            continue;
          }
          seenUrls[href] = true;
          attachOfficialEvent(officialEventFromUrl(urls[u]));
        }
      }
    }
  }
  function collect(win) {
    try {
      if (!win || !win.document) {
        return;
      }
      var beforeStructuredRows = results.length;
      scanCourseRows(win.document);
      var addedStructuredRows = results.slice(beforeStructuredRows).some(function(course) {
        return !!course.courseCode;
      });
      if (!addedStructuredRows) {
        scanScheduleTables(win.document);
      }
      scanOfficialGoogleCalendarLinks(win.document);
      for (var i = 0; i < win.frames.length; i += 1) {
        collect(win.frames[i]);
      }
    } catch (e) {}
  }
  function allPageText() {
    var texts = [];
    function collectText(win) {
      try {
        if (!win || !win.document || !win.document.body) {
          return;
        }
        texts.push(textOf(win.document.body));
        for (var i = 0; i < win.frames.length; i += 1) {
          collectText(win.frames[i]);
        }
      } catch (e) {}
    }
    collectText(window);
    return texts.join('\n');
  }
  function termRangeTextFrom(pageText) {
    var lines = String(pageText || '').split(/\n+/);
    var picked = [];
    for (var i = 0; i < lines.length; i += 1) {
      var line = lines[i].replace(/\s+/g, ' ').trim();
      if (!line) {
        continue;
      }
      if (/(ターム|学期|授業期間|開講期間|履修期間|授業日程|期間)/.test(line) &&
          /([0-9]{4}[年\/-])?[0-9]{1,2}[月\/-][0-9]{1,2}日?/.test(line)) {
        picked.push(line);
      }
      if (picked.length >= 12) {
        break;
      }
    }
    return picked.join('\n');
  }
  collect(window);
  if (results.some(function(course) { return !!course.courseCode; })) {
    results = results.filter(function(course) {
      return !!course.courseCode || hasOfficialFields(course);
    });
  }
  var pageText = allPageText();
  return JSON.stringify({
    courses: results,
    termRangeText: termRangeTextFrom(pageText),
    pageText: pageText
  });
})()
''';
  }

  static String officialGoogleScheduleIntegrationScript({
    required bool activate,
  }) {
    final activateLiteral = activate ? 'true' : 'false';
    return '''
(function() {
  var shouldActivate = $activateLiteral;
  function textOf(node) {
    if (!node) {
      return '';
    }
    return [
      node.innerText || node.textContent || '',
      node.value || '',
      node.name || '',
      node.id || '',
      node.className || '',
      node.title || '',
      node.alt || '',
      node.getAttribute && node.getAttribute('aria-label') || '',
      node.getAttribute && node.getAttribute('href') || '',
      node.getAttribute && node.getAttribute('onclick') || '',
      node.getAttribute && node.getAttribute('src') || '',
      node.getAttribute && node.getAttribute('data-url') || '',
      node.getAttribute && node.getAttribute('data-href') || '',
      node.getAttribute && node.getAttribute('formaction') || '',
      node.getAttribute && node.getAttribute('action') || ''
    ].join(' ').replace(/\\s+/g, ' ').trim();
  }
  function normalize(text) {
    return String(text || '').replace(/\\s+/g, '').toLowerCase();
  }
  function isGoogleScheduleLabel(text) {
    var value = normalize(text);
    return value.indexOf('googleスケジュール連携') >= 0 ||
        value.indexOf('googleカレンダー連携') >= 0 ||
        value.indexOf('googlecalendar') >= 0 ||
        value.indexOf('googleカレンダー') >= 0;
  }
  function isGoogleScheduleExportControl(node) {
    var value = normalize([
      node && node.value || '',
      node && node.name || '',
      node && node.id || '',
      node && node.className || '',
      node && node.getAttribute && node.getAttribute('onclick') || '',
      node && node.getAttribute && node.getAttribute('aria-label') || '',
      node && node.getAttribute && node.getAttribute('title') || ''
    ].join(' '));
    if (value.indexOf('インポート') >= 0 ||
        value.indexOf('import') >= 0 ||
        value.indexOf('自分のスケジュール') >= 0 ||
        value.indexOf('教職員') >= 0) {
      return false;
    }
    return value.indexOf('エクスポート') >= 0 ||
        value.indexOf('export') >= 0 ||
        value.indexOf('doexport') >= 0;
  }
  function actionableFor(node) {
    if (!node) {
      return null;
    }
    function isActionable(candidate) {
      if (!candidate || !candidate.tagName) {
        return false;
      }
      var tag = String(candidate.tagName || '').toLowerCase();
      if (tag === 'a' || tag === 'button') {
        return true;
      }
      if (tag === 'input') {
        var type = String(candidate.getAttribute('type') || '').toLowerCase();
        return !type ||
          type === 'button' ||
          type === 'submit' ||
          type === 'image';
      }
      return !!(
        candidate.getAttribute &&
        (candidate.getAttribute('onclick') ||
         candidate.getAttribute('data-url') ||
         candidate.getAttribute('data-href') ||
         candidate.getAttribute('formaction'))
      );
    }
    if (node.closest) {
      var candidate = node.closest(
        'a,button,input,[onclick],[data-url],[data-href],[formaction]'
      );
      return isActionable(candidate) ? candidate : null;
    }
    return isActionable(node) ? node : null;
  }
  function hrefOf(doc, node) {
    var href = node && node.getAttribute && node.getAttribute('href');
    if (!href || /^javascript:/i.test(href)) {
      return '';
    }
    try {
      return new URL(href, doc.location.href).href;
    } catch (e) {
      return href;
    }
  }
  function googleCalendarUrlOf(doc, raw) {
    var text = String(raw || '')
      .replace(/&amp;/g, '&')
      .replace(/\\u0026/g, '&');
    var matches = text.match(/https?:\\/\\/[^'"<>\\s)]+/g) || [];
    if (/calendar/i.test(text) && /^https?:\\/\\//i.test(text)) {
      matches.push(text);
    }
    for (var i = 0; i < matches.length; i += 1) {
      try {
        var url = new URL(matches[i], doc.location.href);
        var host = url.hostname.toLowerCase();
        var path = url.pathname.toLowerCase();
        if ((host.indexOf('google.') >= 0 ||
             host === 'calendar.google.com') &&
            path.indexOf('/calendar') >= 0 &&
            (url.searchParams.has('text') ||
             url.searchParams.has('details') ||
             url.searchParams.has('dates'))) {
          return url.href;
        }
      } catch (e) {}
    }
    return '';
  }
  function sourcesOf(node) {
    var values = [
      textOf(node),
      node && node.getAttribute && node.getAttribute('href') || '',
      node && node.getAttribute && node.getAttribute('onclick') || '',
      node && node.getAttribute && node.getAttribute('formaction') || '',
      node && node.getAttribute && node.getAttribute('action') || '',
      node && node.value || ''
    ];
    var attrs = node && node.attributes || [];
    for (var i = 0; i < attrs.length; i += 1) {
      if (/^data-/i.test(attrs[i].name)) {
        values.push(attrs[i].value || '');
      }
    }
    return values;
  }
  function directGoogleCalendarUrl(doc, node, parent) {
    var sources = sourcesOf(node).concat(sourcesOf(parent));
    for (var i = 0; i < sources.length; i += 1) {
      var url = googleCalendarUrlOf(doc, sources[i]);
      if (url) {
        return url;
      }
    }
    return '';
  }
  function googleScheduleExportControl(node) {
    var root = node && node.closest && node.closest('form,table,div');
    if (!root || !isGoogleScheduleLabel(textOf(root))) {
      return null;
    }
    var controls = Array.prototype.slice.call(
      root.querySelectorAll('a,button,input,[onclick],[data-url],[data-href]')
    );
    for (var i = 0; i < controls.length; i += 1) {
      if (isGoogleScheduleExportControl(controls[i])) {
        return controls[i];
      }
    }
    return null;
  }
  function diagnosticsFor(doc) {
    var nodes = Array.prototype.slice.call(
      doc.querySelectorAll('a,button,input,img,form,[onclick],[data-url],[data-href]')
    );
    var googleLabelCount = 0;
    var directCalendarUrlCount = 0;
    var sampleLabels = [];
    var googleControlSamples = [];
    function controlSample(node) {
      var attrs = [
        node.getAttribute && node.getAttribute('type') || '',
        node.value || '',
        node.name || '',
        node.id || '',
        node.className || '',
        node.getAttribute && node.getAttribute('onclick') || '',
        node.getAttribute && node.getAttribute('href') || '',
        node.getAttribute && node.getAttribute('src') || '',
        node.getAttribute && node.getAttribute('alt') || '',
        node.getAttribute && node.getAttribute('title') || ''
      ].join(' ').replace(/[\\r\\n]+/g, ' ').replace(/\\s+/g, ' ').trim();
      return String(node.tagName || '').toLowerCase() + ':' + attrs.slice(0, 120);
    }
    for (var i = 0; i < nodes.length; i += 1) {
      var node = nodes[i];
      var label = textOf(node);
      if (isGoogleScheduleLabel(label)) {
        googleLabelCount += 1;
        var root = node.closest && node.closest('form,table,div') || node;
        var controls = Array.prototype.slice.call(
          root.querySelectorAll('a,button,input,img,[onclick],[data-url],[data-href]')
        );
        for (var c = 0; c < controls.length && googleControlSamples.length < 24; c += 1) {
          googleControlSamples.push(controlSample(controls[c]));
        }
      }
      if (directGoogleCalendarUrl(doc, node, actionableFor(node))) {
        directCalendarUrlCount += 1;
      }
      if (sampleLabels.length < 16) {
        var compact = label.replace(/[\\r\\n]+/g, ' ').trim();
        if (compact) {
          sampleLabels.push(
            String(node.tagName || '').toLowerCase() +
            ':' + compact.slice(0, 80)
          );
        }
      }
    }
    return {
      url: String(doc.location.href || '').split('?')[0],
      title: doc.title || '',
      nodeCount: nodes.length,
      googleLabelCount: googleLabelCount,
      directCalendarUrlCount: directCalendarUrlCount,
      googleControls: googleControlSamples,
      samples: sampleLabels
    };
  }
  function inspectDocument(doc) {
    var candidates = Array.prototype.slice.call(
      doc.querySelectorAll('a,button,input,img,span,div,td,li,form,[onclick],[data-url],[data-href]')
    );
    for (var i = 0; i < candidates.length; i += 1) {
      var node = candidates[i];
      var label = textOf(node);
      var parent = actionableFor(node);
      var combined = [label, textOf(parent)].join(' ');
      var directUrl = directGoogleCalendarUrl(doc, node, parent);
      if (directUrl) {
        return {
          status: shouldActivate ? 'url' : 'available',
          label: label || textOf(parent),
          url: directUrl,
          diagnostics: diagnosticsFor(doc)
        };
      }
      if (!isGoogleScheduleLabel(combined)) {
        continue;
      }
      var googleExportControl = googleScheduleExportControl(node);
      if (!parent && googleExportControl) {
        parent = googleExportControl;
        label = 'Googleスケジュール連携: ' + textOf(googleExportControl);
      }
      var href = hrefOf(doc, parent);
      if (!parent) {
        continue;
      }
      if (shouldActivate) {
        if (href) {
          return {
            status: 'url',
            label: label || textOf(parent),
            url: href,
            diagnostics: diagnosticsFor(doc)
          };
        }
        if (parent && parent.click) {
          parent.click();
          return {
            status: 'clicked',
            label: label || textOf(parent),
            url: '',
            diagnostics: diagnosticsFor(doc)
          };
        }
      }
      return {
        status: href ? 'available' : 'clickable',
        label: label || textOf(parent),
        url: href,
        diagnostics: diagnosticsFor(doc)
      };
    }
    return null;
  }
  function collect(win) {
    try {
      if (!win || !win.document) {
        return null;
      }
      var found = inspectDocument(win.document);
      if (found) {
        return found;
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        found = collect(win.frames[i]);
        if (found) {
          return found;
        }
      }
    } catch (e) {}
    return null;
  }
  function allDiagnostics() {
    var values = [];
    function collectDiagnostics(win) {
      try {
        if (!win || !win.document) {
          return;
        }
        values.push(diagnosticsFor(win.document));
        for (var i = 0; i < win.frames.length; i += 1) {
          collectDiagnostics(win.frames[i]);
        }
      } catch (e) {}
    }
    collectDiagnostics(window);
    return values;
  }
  return JSON.stringify(collect(window) || {
    status: 'not_found',
    label: '',
    url: '',
    diagnostics: {
      documents: allDiagnostics()
    }
  });
})()
''';
  }

  static String officialScheduleExportExecutionScript({
    required bool activate,
    String startDate = '',
    String endDate = '',
  }) {
    final activateLiteral = activate ? 'true' : 'false';
    final startDateLiteral = jsonEncode(startDate);
    final endDateLiteral = jsonEncode(endDate);
    return '''
(function() {
  var shouldActivate = $activateLiteral;
  var startDate = $startDateLiteral;
  var endDate = $endDateLiteral;
  function textOf(node) {
    if (!node) {
      return '';
    }
    return [
      node.innerText || node.textContent || '',
      node.value || '',
      node.name || '',
      node.id || '',
      node.className || '',
      node.getAttribute && node.getAttribute('onclick') || '',
      node.getAttribute && node.getAttribute('href') || '',
      node.getAttribute && node.getAttribute('title') || ''
    ].join(' ').replace(/\\s+/g, ' ').trim();
  }
  function normalize(text) {
    return String(text || '').replace(/\\s+/g, '').toLowerCase();
  }
  function isExportForm(form) {
    var value = normalize(textOf(form));
    return value.indexOf('scheduleexportform') >= 0 ||
      (value.indexOf('カテゴリ') >= 0 &&
       value.indexOf('対象期間') >= 0 &&
       value.indexOf('時間割コマ情報') >= 0);
  }
  function visibleDateInputs(form) {
    return Array.prototype.slice.call(
      form.querySelectorAll('input')
    ).filter(function(input) {
      var type = String(input.getAttribute('type') || 'text').toLowerCase();
      if (type === 'hidden' ||
          type === 'button' ||
          type === 'submit' ||
          type === 'checkbox' ||
          type === 'radio' ||
          type === 'image') {
        return false;
      }
      return true;
    });
  }
  function setDateValue(input, value) {
    if (!input || !value) {
      return;
    }
    input.value = value;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function configureCategories(form) {
    var checkboxes = Array.prototype.slice.call(
      form.querySelectorAll('input[type="checkbox"]')
    );
    for (var i = 0; i < checkboxes.length; i += 1) {
      var checkbox = checkboxes[i];
      checkbox.checked = checkbox.name === 'check2' ||
        checkbox.id === 'check21';
      checkbox.dispatchEvent(new Event('input', { bubbles: true }));
      checkbox.dispatchEvent(new Event('change', { bubbles: true }));
    }
  }
  function exportButton(form) {
    var controls = Array.prototype.slice.call(
      form.querySelectorAll('button,input,a,[onclick]')
    );
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = normalize(textOf(control));
      var type = String(control.getAttribute && control.getAttribute('type') || '').toLowerCase();
      if (type === 'hidden') {
        continue;
      }
      if (label.indexOf('クリア') >= 0 ||
          label.indexOf('戻る') >= 0 ||
          label.indexOf('back') >= 0 ||
          label.indexOf('clear') >= 0) {
        continue;
      }
      if (label.indexOf('エクスポート実行') >= 0 ||
          label.indexOf('executeexport') >= 0 ||
          label.indexOf('エクスポート') >= 0) {
        return control;
      }
    }
    return null;
  }
  function diagnosticsFor(doc, form) {
    var controls = Array.prototype.slice.call(
      form.querySelectorAll('button,input,a,[onclick]')
    );
    return {
      url: String(doc.location.href || '').split('?')[0],
      title: doc.title || '',
      formTextLength: textOf(form).length,
      controls: controls.slice(0, 32).map(function(control) {
        return String(control.tagName || '').toLowerCase() + ':' +
          textOf(control).slice(0, 120);
      })
    };
  }
  function inspectDocument(doc) {
    var forms = Array.prototype.slice.call(doc.querySelectorAll('form'));
    var missingCandidate = null;
    for (var f = 0; f < forms.length; f += 1) {
      var form = forms[f];
      if (!isExportForm(form)) {
        continue;
      }
      var dates = visibleDateInputs(form);
      setDateValue(dates[0], startDate);
      setDateValue(dates[1], endDate);
      configureCategories(form);
      var eventId = form.querySelector('input[name="_eventId"]');
      if (eventId && !eventId.value) {
        eventId.value = 'executeExport';
      }
      var button = exportButton(form);
      if (!button) {
        missingCandidate = missingCandidate || {
          status: 'not_found',
          label: '',
          url: '',
          diagnostics: diagnosticsFor(doc, form)
        };
        continue;
      }
      if (shouldActivate) {
        button.click();
        return {
          status: 'clicked',
          label: textOf(button),
          url: '',
          diagnostics: diagnosticsFor(doc, form)
        };
      }
      return {
        status: 'clickable',
        label: textOf(button),
        url: '',
        diagnostics: diagnosticsFor(doc, form)
      };
    }
    return missingCandidate;
  }
  function collect(win) {
    try {
      if (!win || !win.document) {
        return null;
      }
      var found = inspectDocument(win.document);
      if (found) {
        return found;
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        found = collect(win.frames[i]);
        if (found) {
          return found;
        }
      }
    } catch (e) {}
    return null;
  }
  function formCounts() {
    var values = [];
    function collectCounts(win) {
      try {
        if (!win || !win.document) {
          return;
        }
        values.push({
          url: String(win.document.location.href || '').split('?')[0],
          title: win.document.title || '',
          formCount: win.document.querySelectorAll('form').length
        });
        for (var i = 0; i < win.frames.length; i += 1) {
          collectCounts(win.frames[i]);
        }
      } catch (e) {}
    }
    collectCounts(window);
    return values;
  }
  return JSON.stringify(collect(window) || {
    status: 'not_found',
    label: '',
    url: '',
    diagnostics: {
      documents: formCounts()
    }
  });
})()
''';
  }

  static String officialScheduleExportFetchScript({
    String startDate = '',
    String endDate = '',
  }) {
    final startDateLiteral = jsonEncode(startDate);
    final endDateLiteral = jsonEncode(endDate);
    return '''
(function() {
  var startDate = $startDateLiteral;
  var endDate = $endDateLiteral;
  function textOf(node) {
    if (!node) {
      return '';
    }
    return [
      node.innerText || node.textContent || '',
      node.value || '',
      node.name || '',
      node.id || '',
      node.className || '',
      node.getAttribute && node.getAttribute('onclick') || '',
      node.getAttribute && node.getAttribute('href') || '',
      node.getAttribute && node.getAttribute('title') || ''
    ].join(' ').replace(/\\s+/g, ' ').trim();
  }
  function normalize(text) {
    return String(text || '').replace(/\\s+/g, '').toLowerCase();
  }
  function isExportForm(form) {
    var value = normalize(textOf(form));
    return value.indexOf('scheduleexportform') >= 0 ||
      (value.indexOf('カテゴリ') >= 0 &&
       value.indexOf('対象期間') >= 0 &&
       value.indexOf('時間割コマ情報') >= 0);
  }
  function visibleDateInputs(form) {
    return Array.prototype.slice.call(
      form.querySelectorAll('input')
    ).filter(function(input) {
      var type = String(input.getAttribute('type') || 'text').toLowerCase();
      return type !== 'hidden' &&
        type !== 'button' &&
        type !== 'submit' &&
        type !== 'checkbox' &&
        type !== 'radio' &&
        type !== 'image';
    });
  }
  function setDateValue(input, value) {
    if (!input || !value) {
      return;
    }
    input.value = value;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function configureCategories(form) {
    var checkboxes = Array.prototype.slice.call(
      form.querySelectorAll('input[type="checkbox"]')
    );
    for (var i = 0; i < checkboxes.length; i += 1) {
      var checkbox = checkboxes[i];
      checkbox.checked = checkbox.name === 'check2' ||
        checkbox.id === 'check21';
    }
  }
  function configureForm(form) {
    var dates = visibleDateInputs(form);
    setDateValue(dates[0], startDate);
    setDateValue(dates[1], endDate);
    configureCategories(form);
    var eventId = form.querySelector('input[name="_eventId"]');
    if (eventId) {
      eventId.value = 'executeExport';
    }
  }
  function diagnosticsFor(doc, form) {
    return {
      url: String(doc.location.href || '').split('?')[0],
      title: doc.title || '',
      formTextLength: textOf(form).length,
      controls: Array.prototype.slice.call(
        form.querySelectorAll('button,input,a,[onclick]')
      ).slice(0, 32).map(function(control) {
        return String(control.tagName || '').toLowerCase() + ':' +
          textOf(control).slice(0, 120);
      })
    };
  }
  function requestForm(doc, form) {
    configureForm(form);
    var method = String(form.method || 'POST').toUpperCase();
    var action = form.action || doc.location.href;
    var data = new URLSearchParams(new FormData(form)).toString();
    var url = new URL(action, doc.location.href);
    var body = null;
    if (method === 'GET') {
      url.search += (url.search ? '&' : '?') + data;
    } else {
      body = data;
    }
    var xhr = new XMLHttpRequest();
    xhr.open(method, url.href, false);
    if (method !== 'GET') {
      xhr.setRequestHeader(
        'Content-Type',
        'application/x-www-form-urlencoded; charset=UTF-8'
      );
    }
    xhr.send(body);
    return {
      status: xhr.status >= 200 && xhr.status < 400 ? 'fetched' : 'http_error',
      httpStatus: xhr.status,
      url: xhr.responseURL || url.href,
      contentType: xhr.getResponseHeader('Content-Type') || '',
      text: xhr.responseText || '',
      diagnostics: diagnosticsFor(doc, form)
    };
  }
  function inspectDocument(doc) {
    var forms = Array.prototype.slice.call(doc.querySelectorAll('form'));
    for (var f = 0; f < forms.length; f += 1) {
      var form = forms[f];
      if (!isExportForm(form)) {
        continue;
      }
      var hasExecute = !!form.querySelector('input[name="_eventId"]');
      var controls = textOf(form);
      if (!hasExecute && controls.indexOf('エクスポート実行') < 0) {
        continue;
      }
      return requestForm(doc, form);
    }
    return null;
  }
  function collect(win) {
    try {
      if (!win || !win.document) {
        return null;
      }
      var found = inspectDocument(win.document);
      if (found) {
        return found;
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        found = collect(win.frames[i]);
        if (found) {
          return found;
        }
      }
    } catch (e) {
      return {
        status: 'exception',
        httpStatus: 0,
        url: '',
        contentType: '',
        text: String(e && e.message || e),
        diagnostics: {}
      };
    }
    return null;
  }
  return JSON.stringify(collect(window) || {
    status: 'not_found',
    httpStatus: 0,
    url: '',
    contentType: '',
    text: '',
    diagnostics: {}
  });
})()
''';
  }

  static String scheduleMonthNavigationScript({
    required int year,
    required int month,
  }) {
    return '''
(function() {
  var targetYear = $year;
  var targetMonth = $month;
  function textOf(node) {
    if (!node) {
      return '';
    }
    return [
      node.innerText || node.textContent || '',
      node.value || '',
      node.getAttribute && node.getAttribute('title') || '',
      node.getAttribute && node.getAttribute('onclick') || '',
      node.getAttribute && node.getAttribute('href') || ''
    ].join(' ').replace(/\\s+/g, ' ').trim();
  }
  function monthInDocument(doc) {
    var text = textOf(doc.body || doc);
    var match = text.match(/(20[0-9]{2})\\s*年\\s*([0-9]{1,2})\\s*月/);
    if (!match) {
      return null;
    }
    return { year: Number(match[1]), month: Number(match[2]) };
  }
  function clickControl(doc, direction) {
    var view = doc.defaultView || window;
    try {
      if (direction > 0 && typeof view.loadNextMonth === 'function') {
        view.loadNextMonth();
        return true;
      }
      if (direction < 0 && typeof view.loadBeforeMonth === 'function') {
        view.loadBeforeMonth();
        return true;
      }
    } catch (e) {}
    var controls = Array.prototype.slice.call(
      doc.querySelectorAll('a,button,input,[onclick]')
    );
    var fallback = null;
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = textOf(control).toLowerCase();
      var onclick = String(
        control.getAttribute && control.getAttribute('onclick') || ''
      ).toLowerCase();
      if (direction > 0) {
        if (onclick.indexOf('loadnextmonth') >= 0 ||
            label.indexOf('loadnextmonth') >= 0) {
          control.click();
          return true;
        }
        if (!fallback &&
            (label.indexOf('next') >= 0 ||
            label.indexOf('次') >= 0)) {
          fallback = control;
        }
      } else if (direction < 0) {
        if (onclick.indexOf('loadbeforemonth') >= 0 ||
            label.indexOf('loadbeforemonth') >= 0) {
          control.click();
          return true;
        }
        if (!fallback &&
            (label.indexOf('prev') >= 0 ||
            label.indexOf('前') >= 0)) {
          fallback = control;
        }
      }
    }
    if (fallback) {
      fallback.click();
      return true;
    }
    return false;
  }
  function inspect(win) {
    try {
      if (!win || !win.document) {
        return null;
      }
      var current = monthInDocument(win.document);
      if (current) {
        var diff = (targetYear - current.year) * 12 +
          (targetMonth - current.month);
        if (diff === 0) {
          return {
            status: 'ready',
            year: current.year,
            month: current.month
          };
        }
        if (clickControl(win.document, diff > 0 ? 1 : -1)) {
          return {
            status: 'clicked',
            year: current.year,
            month: current.month,
            direction: diff > 0 ? 'next' : 'prev'
          };
        }
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        var found = inspect(win.frames[i]);
        if (found) {
          return found;
        }
      }
    } catch (e) {}
    return null;
  }
  return JSON.stringify(inspect(window) || {
    status: 'not_found',
    year: 0,
    month: 0
  });
})()
''';
  }

  static String scheduleMonthViewActivationScript() {
    return r'''
(function() {
  function textOf(node) {
    if (!node) {
      return '';
    }
    return [
      node.innerText || node.textContent || '',
      node.value || '',
      node.getAttribute && node.getAttribute('title') || '',
      node.getAttribute && node.getAttribute('onclick') || '',
      node.getAttribute && node.getAttribute('href') || ''
    ].join(' ').replace(/\s+/g, ' ').trim();
  }
  function inspect(doc) {
    var controls = Array.prototype.slice.call(
      doc.querySelectorAll('a,button,input,[onclick]')
    );
    var monthControl = null;
    var monthLabel = '';
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = textOf(control);
      var normalized = label.toLowerCase();
      if (normalized.indexOf('changecalunitweek') >= 0 ||
          label.indexOf('週単位') >= 0) {
        return {
          status: 'ready',
          label: label,
          url: doc.location && doc.location.href || ''
        };
      }
      if (!monthControl &&
          (normalized.indexOf('changecalunitmonth') >= 0 ||
              label.indexOf('月単位') >= 0)) {
        monthControl = control;
        monthLabel = label;
      }
    }
    if (!monthControl) {
      return null;
    }
    try {
      monthControl.click();
      return {
        status: 'clicked',
        label: monthLabel,
        url: doc.location && doc.location.href || ''
      };
    } catch (e) {
      return {
        status: 'exception',
        label: monthLabel,
        url: doc.location && doc.location.href || '',
        message: String(e && e.message || e)
      };
    }
  }
  function collect(win) {
    try {
      var found = inspect(win.document);
      if (found) {
        return found;
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        found = collect(win.frames[i]);
        if (found) {
          return found;
        }
      }
    } catch (e) {}
    return null;
  }
  return JSON.stringify(collect(window) || {
    status: 'not_found',
    label: '',
    url: ''
  });
})()
''';
  }

  static String scheduleDaySelectionScript({
    required DateTime date,
  }) {
    final dateLiteral = jsonEncode(
      '${date.year.toString().padLeft(4, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}',
    );
    return '''
(function() {
  var targetDate = $dateLiteral;
  var parts = targetDate.split('/');
  var targetYear = Number(parts[0]);
  var targetMonth = Number(parts[1]);
  var targetDay = Number(parts[2]);
  function textOf(node) {
    if (!node) {
      return '';
    }
    return [
      node.innerText || node.textContent || '',
      node.value || '',
      node.getAttribute && node.getAttribute('title') || '',
      node.getAttribute && node.getAttribute('onclick') || '',
      node.getAttribute && node.getAttribute('href') || ''
    ].join(' ').replace(/\\s+/g, ' ').trim();
  }
  function documentMonthMatches(doc) {
    var text = textOf(doc.body || doc);
    var match = text.match(/(20[0-9]{2})\\s*年\\s*([0-9]{1,2})\\s*月/);
    return !!match &&
      Number(match[1]) === targetYear &&
      Number(match[2]) === targetMonth;
  }
  function clickDay(doc) {
    if (!documentMonthMatches(doc)) {
      return null;
    }
    var view = doc.defaultView || window;
    var controls = Array.prototype.slice.call(
      doc.querySelectorAll('a,button,input,[onclick]')
    );
    for (var i = 0; i < controls.length; i += 1) {
      var control = controls[i];
      var label = textOf(control);
      var compact = label.replace(/\\s+/g, '');
      var onclick = String(
        control.getAttribute && control.getAttribute('onclick') || ''
      );
      var href = String(
        control.getAttribute && control.getAttribute('href') || ''
      );
      var datePattern = new RegExp(
        targetYear + '[^0-9]+' + targetMonth + '[^0-9]+' + targetDay + '(?![0-9])'
      );
      if (compact === String(targetDay)) {
        control.click();
        return {
          status: 'clicked',
          label: label,
          date: targetDate
        };
      }
      if (datePattern.test(onclick) || datePattern.test(href)) {
        control.click();
        return {
          status: 'clicked',
          label: label || onclick || href,
          date: targetDate
        };
      }
      var dayOnlyPattern = new RegExp(
        '(?:^|[^0-9])' + targetDay + '(?:[^0-9]|\\\$)'
      );
      if (onclick.toLowerCase().indexOf('myschlistreload') >= 0 &&
          dayOnlyPattern.test(onclick + ' ' + href) &&
          compact.indexOf(String(targetDay)) >= 0) {
        control.click();
        return {
          status: 'clicked',
          label: label || onclick || href,
          date: targetDate
        };
      }
    }
    return null;
  }
  function inspect(win) {
    try {
      if (!win || !win.document) {
        return null;
      }
      var found = clickDay(win.document);
      if (found) {
        return found;
      }
      for (var i = 0; i < win.frames.length; i += 1) {
        found = inspect(win.frames[i]);
        if (found) {
          return found;
        }
      }
    } catch (e) {}
    return null;
  }
  return JSON.stringify(inspect(window) || {
    status: 'not_found',
    date: targetDate,
    label: ''
  });
})()
''';
  }

  static bool _isUsefulCourse(GakujoCalendarCourse course) {
    return _looksLikeCourseTitle(displayTitleForCourse(course)) &&
        course.weekday >= 1 &&
        course.weekday <= 7 &&
        periodTimes.containsKey(course.period);
  }

  static bool _looksLikeCourseTitle(String value) {
    final title = _normalizedDisplayText(value);
    final compact = title.replaceAll(RegExp(r'\s+'), '');
    if (_looksLikeAggregatedScheduleText(title)) {
      return false;
    }
    if (compact.isEmpty ||
        RegExp(r'^[0-9]+$').hasMatch(compact) ||
        RegExp(r'^[0-9]{4}[/-][0-9]{1,2}[/-][0-9]{1,2}').hasMatch(compact) ||
        RegExp(r'^(mon|tue|wed|thu|fri|sat|sun)$', caseSensitive: false)
            .hasMatch(compact) ||
        RegExp(r'^[月火水木金土日]$').hasMatch(compact)) {
      return false;
    }
    if (RegExp(
      r'^(myスケジュール|リンク|新着情報|home)$',
      caseSensitive: false,
    ).hasMatch(compact)) {
      return false;
    }
    return RegExp(r'[A-Za-zＡ-Ｚａ-ｚ一-龯ぁ-んァ-ヶ]').hasMatch(compact);
  }

  static bool _looksLikeAggregatedScheduleText(String value) {
    final normalized = _normalizedDisplayText(value);
    final periodMarkerCount =
        RegExp(r'[1-7]\s*限\s*[:：]').allMatches(normalized).length;
    if (periodMarkerCount >= 2) {
      return true;
    }
    if (RegExp(r'^\d{1,2}\s+[1-7]\s*限\s*[:：]').hasMatch(normalized)) {
      return true;
    }
    if (RegExp(r'\[(?:小テスト|レポート|授業アンケート|アンケート)\]').hasMatch(
      normalized,
    )) {
      return true;
    }
    if (normalized.contains('【') && normalized.contains('まで】')) {
      return true;
    }
    return false;
  }

  static String _normalizedDisplayText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalizedMultilineText(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  static String _weekdayLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return '月';
      case DateTime.tuesday:
        return '火';
      case DateTime.wednesday:
        return '水';
      case DateTime.thursday:
        return '木';
      case DateTime.friday:
        return '金';
      case DateTime.saturday:
        return '土';
      case DateTime.sunday:
        return '日';
      default:
        return '';
    }
  }

  static String _clockLabel(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static GakujoCalendarTermRange? _termRangeFromLine(
    String line,
    DateTime reference,
  ) {
    final fullDateRange = RegExp(
      r'((?:20)?[0-9]{2})[年/-]([0-9]{1,2})[月/-]([0-9]{1,2})日?(?:\([^)]*\))?\s*[～-]\s*(?:(?:((?:20)?[0-9]{2})[年/-])?([0-9]{1,2})[月/-]([0-9]{1,2})日?)',
    ).firstMatch(line);
    if (fullDateRange != null) {
      final startYear = _normalizedYear(fullDateRange.group(1));
      final startMonth = int.tryParse(fullDateRange.group(2) ?? '');
      final startDay = int.tryParse(fullDateRange.group(3) ?? '');
      final endYear = _normalizedYear(fullDateRange.group(4)) ?? startYear;
      final endMonth = int.tryParse(fullDateRange.group(5) ?? '');
      final endDay = int.tryParse(fullDateRange.group(6) ?? '');
      if (startYear != null &&
          startMonth != null &&
          startDay != null &&
          endYear != null &&
          endMonth != null &&
          endDay != null) {
        return _termRange(
          DateTime(startYear, startMonth, startDay),
          DateTime(endYear, endMonth, endDay),
          line,
        );
      }
    }

    final monthDayRange = RegExp(
      r'([0-9]{1,2})月([0-9]{1,2})日?(?:\([^)]*\))?\s*～\s*([0-9]{1,2})月([0-9]{1,2})日?',
    ).firstMatch(line);
    if (monthDayRange == null) {
      return null;
    }
    final startMonth = int.tryParse(monthDayRange.group(1) ?? '');
    final startDay = int.tryParse(monthDayRange.group(2) ?? '');
    final endMonth = int.tryParse(monthDayRange.group(3) ?? '');
    final endDay = int.tryParse(monthDayRange.group(4) ?? '');
    if (startMonth == null ||
        startDay == null ||
        endMonth == null ||
        endDay == null) {
      return null;
    }
    final startYear = reference.month <= 3 && startMonth >= 4
        ? reference.year - 1
        : reference.year;
    return _termRange(
      DateTime(startYear, startMonth, startDay),
      DateTime(startYear, endMonth, endDay),
      line,
    );
  }

  static int? _normalizedYear(String? raw) {
    final year = int.tryParse(raw ?? '');
    if (year == null) {
      return null;
    }
    return year < 100 ? year + 2000 : year;
  }

  static GakujoCalendarTermRange _termRange(
    DateTime start,
    DateTime end,
    String sourceText,
  ) {
    final normalizedEnd =
        end.isBefore(start) ? DateTime(end.year + 1, end.month, end.day) : end;
    return GakujoCalendarTermRange(
      start: start,
      end: normalizedEnd,
      sourceText: sourceText.trim(),
      noClassDates: const [],
    );
  }

  static List<DateTime> _exDatesForCourse({
    required GakujoCalendarCourse course,
    required GakujoPeriodTime periodTime,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required List<DateTime> noClassDates,
  }) {
    final seen = <String>{};
    final dates = <DateTime>[];
    for (final date in noClassDates) {
      final day = DateTime(date.year, date.month, date.day);
      if (day.weekday != course.weekday ||
          day.isBefore(rangeStart) ||
          day.isAfter(rangeEnd)) {
        continue;
      }
      final dateTime = DateTime(
        day.year,
        day.month,
        day.day,
        periodTime.startHour,
        periodTime.startMinute,
      );
      if (seen.add(_localTimestamp(dateTime))) {
        dates.add(dateTime);
      }
    }
    dates.sort();
    return dates;
  }

  static DateTime _firstDateOnOrAfter(DateTime start, int weekday) {
    final date = DateTime(start.year, start.month, start.day);
    final delta = (weekday - date.weekday) % DateTime.daysPerWeek;
    return date.add(Duration(days: delta));
  }

  static String _eventUid(GakujoCalendarCourse course, String uidNamespace) {
    final source = [
      uidNamespace,
      _normalizedUidPart(displayTitleForCourse(course)),
      course.weekday,
      course.period,
      _normalizedUidPart(displayLocationForCourse(course)),
    ].join('|');
    final encoded = base64Url.encode(utf8.encode(source)).replaceAll('=', '');
    return '$encoded@morebettergakujo.local';
  }

  static String _normalizedUidPart(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _escape(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll('\n', r'\n')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,');
  }

  static String _localTimestamp(DateTime value) {
    return '${_digits(value.year, 4)}${_digits(value.month, 2)}'
        '${_digits(value.day, 2)}T${_digits(value.hour, 2)}'
        '${_digits(value.minute, 2)}${_digits(value.second, 2)}';
  }

  static String _utcTimestamp(DateTime value) {
    return '${_localTimestamp(value.toUtc())}Z';
  }

  static String _digits(int value, int width) {
    return value.toString().padLeft(width, '0');
  }

  static List<String> _foldLines(List<String> lines) {
    // RFC 5545 folds at 75 octets, and a continuation line begins with a
    // single leading space that counts toward that budget. Fold on whole
    // runes (never in the middle of a UTF-16 surrogate pair) so astral-plane
    // characters such as emoji survive intact.
    const maxOctets = 75;
    final folded = <String>[];
    for (final line in lines) {
      if (utf8.encode(line).length <= maxOctets) {
        folded.add(line);
        continue;
      }
      var current = StringBuffer();
      var octets = 0;
      var continuation = false;
      for (final rune in line.runes) {
        final char = String.fromCharCode(rune);
        final charOctets = utf8.encode(char).length;
        final limit = continuation ? maxOctets - 1 : maxOctets;
        if (octets > 0 && octets + charOctets > limit) {
          folded.add(continuation ? ' $current' : current.toString());
          current = StringBuffer();
          octets = 0;
          continuation = true;
        }
        current.write(char);
        octets += charOctets;
      }
      folded.add(continuation ? ' $current' : current.toString());
    }
    return folded;
  }
}
