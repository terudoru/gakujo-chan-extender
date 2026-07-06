import 'package:morebettergakujo_flutter/src/gakujo_calendar_export.dart';
import 'package:test/test.dart';

void main() {
  test('coursesFromJson normalizes and sorts useful courses', () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {"title":"人工知能入門","weekday":3,"period":4,"location":"F-271"},
  {"title":"","weekday":3,"period":4},
  {"title":"日本国憲法","weekday":1,"period":1,"location":"E-260"},
  {"title":"日本国憲法","weekday":1,"period":1,"location":"E-260"}
]
''');

    expect(courses, hasLength(2));
    expect(courses.first.title, '日本国憲法');
    expect(courses.last.title, '人工知能入門');
  });

  test('coursesFromJson rejects calendar grid noise as courses', () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {"title":"1","weekday":1,"period":1},
  {"title":"2026/06/30","weekday":2,"period":1},
  {"title":"Tue","weekday":2,"period":1},
  {"title":"物理学基礎BⅠ","weekday":2,"period":1,"location":"F-271"}
]
''');

    expect(courses, hasLength(1));
    expect(courses.single.title, '物理学基礎BⅠ');
  });

  test('coursesFromJson rejects aggregated sidebar schedule summaries', () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title":"29 1限:日本国憲法@総合教育研究棟 E-260 2限:日本国憲法@総合教育研究棟 E-260 [小テスト][262G7070 日本国憲法]小テスト4【2026/06/29まで】",
    "weekday":1,
    "period":1,
    "courseCode":"262G7070"
  },
  {
    "title":"2 2限:コンピュータ基礎@未定 3限:協創経営概論@工学部 101 4限:協創経営概論@工学部 101 5限:人工知能入門@総合教育研究棟 E-260",
    "weekday":4,
    "period":1,
    "courseCode":"260T0505"
  },
  {
    "title":"日本国憲法",
    "weekday":1,
    "period":1,
    "location":"総合教育研究棟 E-260",
    "courseCode":"262G7070"
  }
]
''');

    expect(courses, hasLength(1));
    expect(courses.single.title, '日本国憲法');
  });

  test('filterCoursesForTerm keeps only courses inside selected term', () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title":"第1ターム科目",
    "weekday":1,
    "period":1,
    "sourceDate":"2026-05-11"
  },
  {
    "title":"第2ターム科目",
    "weekday":2,
    "period":2,
    "sourceDate":"2026-06-23"
  }
]
''');

    final filtered = GakujoCalendarExport.filterCoursesForTerm(
      courses: courses,
      termRange: GakujoCalendarTermRange(
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 8, 5),
      ),
      termName: '第2ターム',
    );

    expect(filtered, hasLength(1));
    expect(filtered.single.title, '第2ターム科目');
  });

  test('filterCoursesForTerm keeps courses that carry no term metadata', () {
    // A weekly-grid Friday cell can be extracted with no course code, source
    // date, or term hint. It must survive term filtering rather than being
    // dropped just because sibling courses do carry metadata.
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title":"月曜の授業",
    "weekday":1,
    "period":1,
    "sourceDate":"2026-06-23"
  },
  {
    "title":"金曜の授業",
    "weekday":5,
    "period":1
  }
]
''');

    final filtered = GakujoCalendarExport.filterCoursesForTerm(
      courses: courses,
      termRange: GakujoCalendarTermRange(
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 8, 5),
      ),
      termName: '第2ターム',
    );

    final titles = filtered.map((course) => course.title).toList();
    expect(titles, containsAll(<String>['月曜の授業', '金曜の授業']));
  });

  test('filterCoursesForTerm drops make-up occurrences on the wrong weekday',
      () {
    // 日本国憲法 is a Monday class; a public holiday moved it to Wednesday for
    // one week and that make-up cell has no date. 物理学基礎BⅠ is a genuine
    // undated Friday class with no dated twin.
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {"title":"日本国憲法","weekday":1,"period":1,"sourceDate":"2026-06-29"},
  {"title":"日本国憲法","weekday":3,"period":1},
  {"title":"物理学基礎BⅠ","weekday":5,"period":1}
]
''');

    final filtered = GakujoCalendarExport.filterCoursesForTerm(
      courses: courses,
      termRange: GakujoCalendarTermRange(
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 8, 5),
      ),
      termName: '第2ターム',
    );

    final byWeekday = {
      for (final course in filtered) course.weekday: course.title,
    };
    expect(byWeekday[DateTime.monday], '日本国憲法');
    expect(byWeekday[DateTime.friday], '物理学基礎BⅠ');
    expect(byWeekday.containsKey(DateTime.wednesday), isFalse);
  });

  test('coursesFromJson keeps explicit weekday when source date is different',
      () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title":"水曜欄の授業",
    "weekday":3,
    "period":2,
    "sourceDate":"2026-06-23"
  }
]
''');

    expect(courses.single.weekday, DateTime.wednesday);
  });

  test('filterCoursesForTerm uses course number term digit first', () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title":"第1ターム科目",
    "weekday":1,
    "period":1,
    "courseCode":"261T0001",
    "sourceDate":"2026-06-23"
  },
  {
    "title":"第2ターム科目",
    "weekday":2,
    "period":2,
    "courseCode":"262G5023"
  },
  {
    "title":"通年扱い未選択",
    "weekday":3,
    "period":3,
    "courseCode":"260G3010"
  },
  {
    "title":"通年扱い選択済み",
    "weekday":4,
    "period":4,
    "courseCode":"260G3011",
    "termHint":"第2ターム 第3ターム"
  }
]
''');

    final filtered = GakujoCalendarExport.filterCoursesForTerm(
      courses: courses,
      termRange: GakujoCalendarTermRange(
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 8, 5),
      ),
      termName: '第2ターム',
    );

    expect(
      filtered.map((course) => course.title),
      ['第2ターム科目', '通年扱い選択済み'],
    );
  });

  test('filterCoursesForTerm keeps the selected term timetable slots', () {
    final courses = GakujoCalendarExport.filterCoursesForTerm(
      courses: GakujoCalendarExport.coursesFromJson('''
[
  {"title":"エンジニアのためのデータサイエンス入門","weekday":1,"period":1,"courseCode":"261G3009"},
  {"title":"エンジニアのためのデータサイエンス入門","weekday":1,"period":2,"courseCode":"261G3009"},
  {"title":"総合技術科学演習","weekday":1,"period":3,"courseCode":"261T0002"},
  {"title":"総合技術科学演習","weekday":1,"period":4,"courseCode":"261T0002"},
  {"title":"アントレプレナーシップ","weekday":2,"period":3,"courseCode":"261T0504"},
  {"title":"基礎数理Ａ I","weekday":2,"period":4,"courseCode":"262G6013"},
  {"title":"半導体産業概論","weekday":2,"period":5,"courseCode":"262T0055"},
  {"title":"ドイツ語圏グローバル理解 3","weekday":3,"period":2,"courseCode":"261G1005"},
  {"title":"ロシア語圏グローバル理解 1","weekday":3,"period":2,"courseCode":"262G1020"},
  {"title":"エンジニアのためのデータサイエンス入門","weekday":3,"period":3,"courseCode":"261G4258"},
  {"title":"基礎数理Ａ I","weekday":3,"period":4,"courseCode":"261G4258"},
  {"title":"ウェアラブルデザイン","weekday":3,"period":5,"courseCode":"262G3213"},
  {"title":"コンピュータ基礎","weekday":4,"period":2,"courseCode":"260T0505","termHint":"第1ターム 第2ターム"},
  {"title":"協創経営概論","weekday":4,"period":3,"courseCode":"262T0502"},
  {"title":"協創経営概論","weekday":4,"period":4,"courseCode":"262T0502"},
  {"title":"人工知能入門","weekday":4,"period":5,"courseCode":"260G3010","termHint":"第1ターム 第2ターム"},
  {"title":"物理学基礎BⅠ","weekday":2,"period":1,"courseCode":"262G5023"},
  {"title":"物理学基礎BⅠ","weekday":5,"period":1,"courseCode":"262G5023"},
  {"title":"日本国憲法","weekday":1,"period":1,"courseCode":"262G7070"},
  {"title":"日本国憲法","weekday":1,"period":2,"courseCode":"262G7070"},
  {"title":"人間支援感性科学概論","weekday":1,"period":3,"courseCode":"262T0501"},
  {"title":"人間支援感性科学概論","weekday":1,"period":4,"courseCode":"262T0501"},
  {"title":"基礎数理Ａ I","weekday":5,"period":4,"courseCode":"262G6013"}
]
'''),
      termRange: GakujoCalendarTermRange(
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 8, 5),
      ),
      termName: '第2ターム',
    );

    expect(
      courses.map((course) => '${course.weekday}-${course.period}').toSet(),
      {
        '1-1',
        '1-2',
        '1-3',
        '1-4',
        '2-1',
        '2-4',
        '2-5',
        '3-2',
        '3-5',
        '4-2',
        '4-3',
        '4-4',
        '4-5',
        '5-1',
        '5-4',
      },
    );
    expect(courses.any((course) => course.weekday == DateTime.saturday), false);
    expect(courses.any((course) => course.weekday == DateTime.sunday), false);
    expect(
      courses.where((course) => course.title == '総合技術科学演習'),
      isEmpty,
    );
  });

  test('filterCoursesForTerm does not keep zero-term codes by date alone', () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title":"通年扱い未確認",
    "weekday":2,
    "period":1,
    "courseCode":"260G3010",
    "sourceDate":"2026-06-23"
  }
]
''');

    final filtered = GakujoCalendarExport.filterCoursesForTerm(
      courses: courses,
      termRange: GakujoCalendarTermRange(
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 8, 5),
      ),
      termName: '第2ターム',
    );

    expect(filtered, isEmpty);
  });

  test('filterCoursesForTerm merges same course with missing location', () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title":"ロシア語圏グローバル理解 1",
    "weekday":3,
    "period":1,
    "courseCode":"262G1020",
    "location":"",
    "termHint":"第2ターム"
  },
  {
    "title":"ロシア語圏グローバル理解 1",
    "weekday":3,
    "period":1,
    "courseCode":"262G1020",
    "location":"総合教育研究棟 F-271",
    "termHint":"第2ターム"
  }
]
''');

    final filtered = GakujoCalendarExport.filterCoursesForTerm(
      courses: courses,
      termRange: GakujoCalendarTermRange(
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 8, 5),
      ),
      termName: '第2ターム',
    );

    expect(filtered, hasLength(1));
    expect(filtered.single.location, '総合教育研究棟 F-271');
  });

  test('extractionFromJson reads courses and a term range from page text', () {
    final extraction = GakujoCalendarExport.extractionFromJson(
      '''
{
  "courses": [
    {"title":"日本国憲法","weekday":1,"period":1,"location":"E-260"}
  ],
  "termRangeText": "第2ターム 授業期間 2026年6月11日～2026年8月8日"
}
''',
      referenceDate: DateTime(2026, 6, 29),
    );

    expect(extraction.courses, hasLength(1));
    expect(extraction.termRange?.start, DateTime(2026, 6, 11));
    expect(extraction.termRange?.end, DateTime(2026, 8, 8));
  });

  test('coursesFromJson merges single same-slot official Google fields', () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title": "AI入門",
    "weekday": 3,
    "period": 4,
    "location": ""
  },
  {
    "title": "人工知能入門（Gコード）",
    "weekday": 3,
    "period": 4,
    "location": "工学部 101",
    "officialTitle": "人工知能入門（Gコード）",
    "officialLocation": "工学部 101",
    "officialDescription": "Googleスケジュール連携の説明"
  }
]
''');

    expect(courses, hasLength(1));
    expect(courses.single.title, 'AI入門');
    expect(
      GakujoCalendarExport.displayTitleForCourse(courses.single),
      '人工知能入門（Gコード）',
    );
    expect(
      GakujoCalendarExport.displayLocationForCourse(courses.single),
      '工学部 101',
    );
    expect(courses.single.officialDescription, 'Googleスケジュール連携の説明');
  });

  test(
      'coursesFromJson does not slot-merge no-code official data into coded course',
      () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title": "第2タームの授業",
    "weekday": 2,
    "period": 1,
    "courseCode": "262G5023"
  },
  {
    "title": "第1タームの別授業",
    "weekday": 2,
    "period": 1,
    "officialTitle": "第1タームの別授業",
    "officialLocation": "F-271",
    "sourceDate": "2026-05-12"
  }
]
''');

    expect(courses, hasLength(2));
    expect(
      courses.map(GakujoCalendarExport.displayTitleForCourse),
      unorderedEquals(['第2タームの授業', '第1タームの別授業']),
    );
  });

  test(
      'coursesFromJson does not merge term-unknown official data into coded course',
      () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title": "同名授業",
    "weekday": 2,
    "period": 1,
    "courseCode": "261T0001"
  },
  {
    "title": "同名授業",
    "weekday": 2,
    "period": 1,
    "officialTitle": "同名授業",
    "officialLocation": "F-271",
    "sourceDate": "2026-06-23"
  }
]
''');

    expect(courses, hasLength(2));
  });

  test('coursesFromJson does not merge official term text against course code',
      () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title": "同名授業",
    "weekday": 2,
    "period": 1,
    "courseCode": "262G5023"
  },
  {
    "title": "同名授業",
    "weekday": 2,
    "period": 1,
    "officialTitle": "同名授業",
    "officialLocation": "F-271",
    "termHint": "第1ターム"
  }
]
''');

    expect(courses, hasLength(2));
  });

  test('coursesFromJson keeps competing same-slot official courses separate',
      () {
    final courses = GakujoCalendarExport.coursesFromJson('''
[
  {
    "title": "集中講義A",
    "weekday": 5,
    "period": 3,
    "officialTitle": "集中講義A"
  },
  {
    "title": "集中講義B",
    "weekday": 5,
    "period": 3,
    "officialTitle": "集中講義B"
  }
]
''');

    expect(courses, hasLength(2));
    expect(
      courses.map(GakujoCalendarExport.displayTitleForCourse),
      ['集中講義A', '集中講義B'],
    );
  });

  test('termRangeFromText reads month-day ranges using the selected year', () {
    final range = GakujoCalendarExport.termRangeFromText(
      '第1ターム 授業期間 4月8日（水）～6月10日（水）',
      referenceDate: DateTime(2026, 4, 20),
    );

    expect(range?.start, DateTime(2026, 4, 8));
    expect(range?.end, DateTime(2026, 6, 10));
  });

  test('termRangeFromText reads hyphenated full-date ranges', () {
    final range = GakujoCalendarExport.termRangeFromText(
      '第2ターム 授業期間 2026-06-11 - 2026-08-08',
      referenceDate: DateTime(2026, 6, 29),
    );

    expect(range?.start, DateTime(2026, 6, 11));
    expect(range?.end, DateTime(2026, 8, 8));
  });

  test('termRangeFromText handles fourth term month-day ranges in January', () {
    final range = GakujoCalendarExport.termRangeFromText(
      '第4ターム 授業期間 12月3日（木）～2月12日（金）',
      referenceDate: DateTime(2027, 1, 15),
    );

    expect(range?.start, DateTime(2026, 12, 3));
    expect(range?.end, DateTime(2027, 2, 12));
  });

  test('buildIcs exports weekly recurring classes in Asia Tokyo time', () {
    final ics = GakujoCalendarExport.buildIcs(
      courses: const [
        GakujoCalendarCourse(
          title: '日本国憲法',
          weekday: DateTime.monday,
          period: 1,
          location: '総合教育研究棟 E-260',
          teacher: '山田 太郎',
        ),
      ],
      rangeStart: DateTime(2026, 6, 29),
      rangeEnd: DateTime(2026, 8, 8),
      termLabel: '2026年度 第2ターム',
      generatedAt: DateTime.utc(2026, 6, 29),
    );
    final unfolded = ics.replaceAll('\r\n ', '');

    expect(ics, contains('BEGIN:VCALENDAR'));
    expect(ics, contains('SUMMARY:日本国憲法'));
    expect(ics, contains('DTSTART;TZID=Asia/Tokyo:20260629T084500'));
    expect(ics, contains('DTEND;TZID=Asia/Tokyo:20260629T101500'));
    expect(ics, contains('RRULE:FREQ=WEEKLY;UNTIL='));
    expect(ics, contains('LOCATION:総合教育研究棟 E-260'));
    expect(unfolded, contains(r'DESCRIPTION:月曜 1限\n08:45 - 10:15'));
    expect(unfolded, contains(r'教室: 総合教育研究棟 E-260'));
    expect(unfolded, contains(r'担当教員: 山田 太郎'));
    expect(unfolded, contains(r'ターム: 2026年度 第2ターム'));
  });

  test('buildIcs folds long lines without splitting surrogate pairs', () {
    // A long title with emoji scattered across UTF-8 fold boundaries: each
    // emoji is a UTF-16 surrogate pair that must never be split by folding.
    final emojiTitle = '基礎ゼミナール😀' * 8;
    final ics = GakujoCalendarExport.buildIcs(
      courses: [
        GakujoCalendarCourse(
          title: emojiTitle,
          weekday: DateTime.monday,
          period: 1,
        ),
      ],
      rangeStart: DateTime(2026, 6, 29),
      rangeEnd: DateTime(2026, 7, 6),
      termLabel: '2026年度 第2ターム',
      generatedAt: DateTime.utc(2026, 6, 29),
    );

    // The event must exist and the title must fold across multiple lines.
    expect(ics, contains('BEGIN:VEVENT'));
    expect(ics, contains('\r\n '));
    // No physical line may carry an unpaired UTF-16 surrogate, which would
    // corrupt the UTF-8 encoded .ics output.
    for (final line in ics.split('\r\n')) {
      expect(_hasUnpairedSurrogate(line), isFalse, reason: 'line: $line');
    }
    final unfolded = ics.replaceAll('\r\n ', '');
    expect(unfolded, contains('SUMMARY:$emojiTitle'));
  });

  test('buildIcs prefers official Google schedule display fields', () {
    final ics = GakujoCalendarExport.buildIcs(
      courses: const [
        GakujoCalendarCourse(
          title: '人工知能入門',
          weekday: DateTime.wednesday,
          period: 4,
          location: '',
          officialTitle: '人工知能入門（Gコード）',
          officialLocation: '工学部 101',
          officialDescription: '学務Google連携の説明\n担当: 山田 太郎',
        ),
      ],
      rangeStart: DateTime(2026, 6, 29),
      rangeEnd: DateTime(2026, 7, 31),
      termLabel: '2026年度 第2ターム',
      generatedAt: DateTime.utc(2026, 6, 29),
    );
    final unfolded = ics.replaceAll('\r\n ', '');

    expect(ics, contains('SUMMARY:人工知能入門（Gコード）'));
    expect(ics, contains('LOCATION:工学部 101'));
    expect(unfolded, contains(r'DESCRIPTION:学務Google連携の説明\n担当: 山田 太郎'));
    expect(unfolded, contains(r'ターム: 2026年度 第2ターム'));
  });

  test('buildIcs supports seventh period classes', () {
    final ics = GakujoCalendarExport.buildIcs(
      courses: const [
        GakujoCalendarCourse(
          title: '夜間講義',
          weekday: DateTime.friday,
          period: 7,
        ),
      ],
      rangeStart: DateTime(2026, 6, 29),
      rangeEnd: DateTime(2026, 7, 31),
      generatedAt: DateTime.utc(2026, 6, 29),
    );

    expect(ics, contains('DTSTART;TZID=Asia/Tokyo:20260703T194500'));
    expect(ics, contains('DTEND;TZID=Asia/Tokyo:20260703T211500'));
  });

  test('buildIcs excludes no-class days for each course weekday', () {
    final ics = GakujoCalendarExport.buildIcs(
      courses: const [
        GakujoCalendarCourse(
          title: '月曜講義',
          weekday: DateTime.monday,
          period: 2,
        ),
        GakujoCalendarCourse(
          title: '水曜講義',
          weekday: DateTime.wednesday,
          period: 3,
        ),
      ],
      rangeStart: DateTime(2026, 6, 10),
      rangeEnd: DateTime(2026, 8, 5),
      noClassDates: [
        DateTime(2026, 7, 20),
        DateTime(2026, 8, 5),
      ],
      generatedAt: DateTime.utc(2026, 6, 29),
    );

    expect(ics, contains('EXDATE;TZID=Asia/Tokyo:20260720T103000'));
    expect(ics, contains('EXDATE;TZID=Asia/Tokyo:20260805T130000'));
    expect(ics, isNot(contains('20260720T130000')));
    expect(ics, isNot(contains('20260805T103000')));
  });

  test('buildIcs keeps event UIDs stable across range date adjustments', () {
    final first = GakujoCalendarExport.buildIcs(
      courses: const [
        GakujoCalendarCourse(
          title: '日本国憲法',
          weekday: DateTime.monday,
          period: 1,
          location: '総合教育研究棟 E-260',
        ),
      ],
      rangeStart: DateTime(2026, 6, 11),
      rangeEnd: DateTime(2026, 8, 8),
      uidNamespace: 'niigata-2026-第2ターム',
      generatedAt: DateTime.utc(2026, 6, 29),
    );
    final updated = GakujoCalendarExport.buildIcs(
      courses: const [
        GakujoCalendarCourse(
          title: '日本国憲法',
          weekday: DateTime.monday,
          period: 1,
          location: '総合教育研究棟 E-260',
        ),
      ],
      rangeStart: DateTime(2026, 6, 12),
      rangeEnd: DateTime(2026, 8, 7),
      uidNamespace: 'niigata-2026-第2ターム',
      generatedAt: DateTime.utc(2026, 6, 30),
    );

    expect(_uidsFromIcs(updated), _uidsFromIcs(first));
    expect(first, contains('DTSTART;TZID=Asia/Tokyo:20260615T084500'));
    expect(updated, contains('DTSTART;TZID=Asia/Tokyo:20260615T084500'));
  });

  test('buildIcs separates UIDs between academic terms', () {
    final firstTerm = GakujoCalendarExport.buildIcs(
      courses: const [
        GakujoCalendarCourse(
          title: '日本国憲法',
          weekday: DateTime.monday,
          period: 1,
        ),
      ],
      rangeStart: DateTime(2026, 4, 8),
      rangeEnd: DateTime(2026, 6, 10),
      uidNamespace: 'niigata-2026-第1ターム',
      generatedAt: DateTime.utc(2026, 6, 29),
    );
    final secondTerm = GakujoCalendarExport.buildIcs(
      courses: const [
        GakujoCalendarCourse(
          title: '日本国憲法',
          weekday: DateTime.monday,
          period: 1,
        ),
      ],
      rangeStart: DateTime(2026, 6, 11),
      rangeEnd: DateTime(2026, 8, 8),
      uidNamespace: 'niigata-2026-第2ターム',
      generatedAt: DateTime.utc(2026, 6, 29),
    );

    expect(_uidsFromIcs(firstTerm), isNot(_uidsFromIcs(secondTerm)));
  });

  test('buildIcs escapes iCalendar text fields', () {
    final ics = GakujoCalendarExport.buildIcs(
      courses: const [
        GakujoCalendarCourse(
          title: r'情報,リテラシー\演習',
          weekday: DateTime.tuesday,
          period: 2,
          location: 'A;101',
        ),
      ],
      rangeStart: DateTime(2026, 6, 29),
      rangeEnd: DateTime(2026, 7, 31),
      generatedAt: DateTime.utc(2026, 6, 29),
    );

    expect(ics, contains(r'SUMMARY:情報\,リテラシー\\演習'));
    expect(ics, contains(r'LOCATION:A\;101'));
  });

  test('extractionScript uses official links and strict page schedule lines',
      () {
    final script = GakujoCalendarExport.extractionScript();

    expect(script, contains('querySelectorAll'));
    expect(script, contains('function rawTextOf'));
    expect(script, contains('scanOfficialGoogleCalendarLinks'));
    expect(script, contains('scanScheduleTables'));
    expect(script, contains('columnWeekdayMapFromRow'));
    expect(script, contains('addTimetableGridCellCourse'));
    expect(script, contains('cleanTimetableCellText'));
    expect(script, contains('parseDailySummaryCell'));
    expect(script, contains('sourceDateFromNode'));
    expect(script, contains('parseScheduleTextWithWeekday'));
    expect(script, contains('function googleStartDate'));
    expect(script, contains('function sameSlotCourses'));
    expect(script, contains('function canMergePotentialSameTerm'));
    expect(script, contains('addedStructuredRows'));
    expect(script, contains('mergeOfficialEventIntoCourse'));
    expect(script, contains('officialTitle'));
    expect(script, contains('titleLooksUseful'));
    expect(script, contains('termRangeText'));
    expect(script, contains('JSON.stringify({'));
    expect(script, isNot(contains('function scanUnsafeTable')));
    expect(script, isNot(contains('function splitCourse')));
    expect(script, isNot(contains('scanDailyScheduleLines')));
    expect(
      script,
      isNot(contains('if (courseCodeFromText(tableText))')),
    );
  });

  test('scheduleMonthViewActivationScript switches week view to month view',
      () {
    final script = GakujoCalendarExport.scheduleMonthViewActivationScript();

    expect(script, contains('changecalunitmonth'));
    expect(script, contains('changecalunitweek'));
    expect(script, contains('月単位'));
    expect(script, contains('週単位'));
    expect(script, contains('JSON.stringify'));
  });

  test('coursesFromOfficialGoogleCalendarUrls parses Google template URLs', () {
    final url = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': '物理学基礎BⅠ',
      'dates': '20260623T084500/20260623T101500',
      'location': '総合教育研究棟 F-271',
      'details': '学務の説明',
    }).toString();

    final courses =
        GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls([url]);

    expect(courses, hasLength(1));
    expect(courses.single.weekday, DateTime.tuesday);
    expect(courses.single.period, 1);
    expect(
      GakujoCalendarExport.displayTitleForCourse(courses.single),
      '物理学基礎BⅠ',
    );
    expect(
      GakujoCalendarExport.displayLocationForCourse(courses.single),
      '総合教育研究棟 F-271',
    );
    expect(courses.single.officialDescription, '学務の説明');
    expect(courses.single.sourceDate, DateTime(2026, 6, 23));
  });

  test('course code parser reads the third digit as term', () {
    expect(
        GakujoCalendarExport.courseCodeFromText('科目名 261T0001 情報'), '261T0001');
    expect(GakujoCalendarExport.termCodeFromCourseCode('262G5023'), 2);
    expect(GakujoCalendarExport.termCodeFromCourseCode('260G3010'), 0);
  });

  test('coursesFromOfficialGoogleCalendarUrls converts UTC dates to JST', () {
    final url = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': '日本国憲法',
      'dates': '20260621T234500Z/20260622T011500Z',
    }).toString();

    final courses =
        GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls([url]);

    expect(courses, hasLength(1));
    expect(courses.single.weekday, DateTime.monday);
    expect(courses.single.period, 1);
  });

  test('coursesFromOfficialGoogleCalendarUrls extracts urls from html text',
      () {
    final url = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': '物理学基礎BⅠ',
      'dates': '20260623T084500/20260623T101500',
      'location': '総合教育研究棟 F-271',
    }).toString();

    final courses = GakujoCalendarExport.coursesFromOfficialGoogleCalendarUrls([
      '<a href="${url.replaceAll('&', '&amp;')}">Google</a>',
    ]);

    expect(courses, hasLength(1));
    expect(courses.single.weekday, DateTime.tuesday);
    expect(courses.single.period, 1);
    expect(
      GakujoCalendarExport.displayTitleForCourse(courses.single),
      '物理学基礎BⅠ',
    );
  });

  test('coursesFromOfficialScheduleExportText parses iCalendar events', () {
    final courses = GakujoCalendarExport.coursesFromOfficialScheduleExportText(
      '''
BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:日本国憲法
DTSTART;TZID=Asia/Tokyo:20260622T084500
DTEND;TZID=Asia/Tokyo:20260622T101500
LOCATION:総合教育研究棟 E-260
DESCRIPTION:Google schedule details
END:VEVENT
BEGIN:VEVENT
SUMMARY:物理学基礎BⅠ
DTSTART;TZID=Asia/Tokyo:20260623T084500
DTEND;TZID=Asia/Tokyo:20260623T101500
LOCATION:総合教育研究棟 F-271
END:VEVENT
END:VCALENDAR
''',
    );

    expect(courses, hasLength(2));
    expect(courses.map((course) => course.weekday), [
      DateTime.monday,
      DateTime.tuesday,
    ]);
    expect(
      courses.map(GakujoCalendarExport.displayTitleForCourse),
      ['日本国憲法', '物理学基礎BⅠ'],
    );
  });

  test('official Google schedule integration script detects campus action', () {
    final inspectScript =
        GakujoCalendarExport.officialGoogleScheduleIntegrationScript(
      activate: false,
    );
    final activateScript =
        GakujoCalendarExport.officialGoogleScheduleIntegrationScript(
      activate: true,
    );

    expect(inspectScript, contains('googleスケジュール連携'));
    expect(inspectScript, contains("'available'"));
    expect(inspectScript, contains("'clickable'"));
    expect(inspectScript, contains('querySelectorAll'));
    expect(activateScript, contains('parent.click()'));
    expect(activateScript, contains("status: 'clicked'"));
  });

  test('official schedule export execution script targets export form', () {
    final script = GakujoCalendarExport.officialScheduleExportExecutionScript(
      activate: true,
      startDate: '2026/06/11',
      endDate: '2026/08/08',
    );

    expect(script, contains('scheduleexportform'));
    expect(script, contains('executeExport'));
    expect(script, contains('エクスポート実行'));
    expect(script, contains('2026/06/11'));
    expect(script, contains('button.click()'));
    expect(script, contains('missingCandidate'));
    expect(script, contains('continue;'));
  });

  test('official schedule export fetch script posts timetable category only',
      () {
    final script = GakujoCalendarExport.officialScheduleExportFetchScript(
      startDate: '2026/06/11',
      endDate: '2026/08/08',
    );

    expect(script, contains('XMLHttpRequest'));
    expect(script, contains("checkbox.name === 'check2'"));
    expect(script, contains('executeExport'));
    expect(script, contains('2026/06/11'));
    expect(script, contains('responseText'));
  });

  test('schedule day visit scripts target month navigation and date links', () {
    final monthScript = GakujoCalendarExport.scheduleMonthNavigationScript(
      year: 2026,
      month: 6,
    );
    final dayScript = GakujoCalendarExport.scheduleDaySelectionScript(
      date: DateTime(2026, 6, 23),
    );

    expect(monthScript, contains('loadnextmonth'));
    expect(monthScript, contains('loadbeforemonth'));
    expect(monthScript, contains("label.indexOf('次') >= 0))"));
    expect(monthScript, contains("label.indexOf('前') >= 0))"));
    expect(monthScript, contains('targetYear = 2026'));
    expect(monthScript, contains('targetMonth = 6'));
    expect(dayScript, contains('2026/06/23'));
    expect(dayScript, contains("status: 'clicked'"));
  });
}

List<String> _uidsFromIcs(String ics) {
  return RegExp(r'^UID:(.+)$', multiLine: true)
      .allMatches(ics)
      .map((match) => match.group(1)!)
      .toList();
}

bool _hasUnpairedSurrogate(String value) {
  final units = value.codeUnits;
  for (var i = 0; i < units.length; i += 1) {
    final unit = units[i];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      final next = i + 1 < units.length ? units[i + 1] : 0;
      if (next < 0xDC00 || next > 0xDFFF) {
        return true;
      }
      i += 1;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return true;
    }
  }
  return false;
}
