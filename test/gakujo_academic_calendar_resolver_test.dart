import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:morebettergakujo_flutter/src/course_planner_balance_pdf.dart';
import 'package:morebettergakujo_flutter/src/course_planner_handoff.dart';
import 'package:morebettergakujo_flutter/src/gakujo_academic_calendar.dart';
import 'package:morebettergakujo_flutter/src/gakujo_academic_calendar_resolver.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

void main() {
  test('the credit PDF projects only the official earned-credit columns', () async {
    String cell(String text, int x, int y) =>
        'BT 1 0 0 1 $x $y Tm /CID 11 Tf <${text.codeUnits.map(_hex).join()}> Tj ET';
    final contents = [
      cell('履修科目確認表', 250, 780),
      cell('区分', 336, 752),
      cell('履修単位', 423, 752),
      cell('既修得単位', 497, 752),
      cell('昼間', 414, 736),
      cell('夜間', 454, 736),
      cell('昼間', 494, 736),
      cell('夜間', 534, 736),
      cell('別表の科目名', 84, 715),
      cell('大学独自の区分', 292, 715),
      cell('90', 414, 715),
      cell('88', 454, 715),
      cell('４．５', 489, 715),
      cell('1.5', 529, 715),
      cell('認定分', 292, 697),
      cell('77', 414, 697),
      cell('＊2.5', 523, 697),
      cell('学生氏名', 292, 677),
      cell('99', 494, 677),
    ];
    final bytes = _calendarPdf([contents.join('\n')]);
    final report = readCoursePlannerBalancePdf(bytes);
    expect(report, {
      'v': 1, 'kind': 'balances',
      'tables': [
        {'heading': '履修科目確認表', 'rows': [
          ['科目区分', '既修得単位(昼間)', '既修得単位(夜間)'],
          ['大学独自の区分', '4.5', '1.5'],
          ['認定分', '', '*2.5'],
        ]},
      ],
    });
    const kind = CoursePlannerImportKind.balances;
    final token = encodeCoursePlannerHandoff(report, kind)!;
    expect(hasCoursePlannerSplitBalances(token), isTrue);
    final (packets, _, complete) = await fetchCoursePlannerCapture(
      _ReportView(jsonEncode({
        'v': 1, 'packets': <String, dynamic>{}, 'timetable': [],
        'complete': true, 'balancePdf': base64Encode(bytes),
      })),
      () => true,
    );
    expect(packets, [(kind, token)]);
    expect(complete, isTrue);
    expect(readCoursePlannerBalancePdf(_calendarPdf([contents.skip(1).join('\n')])), isNull);
    final wrongGroup = [...contents]..[3] = cell('他の単位数', 497, 752);
    expect(readCoursePlannerBalancePdf(_calendarPdf([wrongGroup.join('\n')])), isNull);
  });

  final exceedsLimits = isA<FormatException>().having(
    (error) => error.message,
    'message',
    'Calendar PDF exceeds processing limits',
  );

  test('calendar PDF rejects oversized operand sequences', () {
    expect(
      () => _parsePdf(_calendarPdf(['BT ${'1 ' * 4097}Tj ET'])),
      throwsA(exceedsLimits),
    );
  });

  test('reads only pages headed with the requested academic year', () async {
    const ranges = [
      '第１ターム 4月8日～6月8日',
      '第２ターム 6月10日～8月5日',
      '第３ターム 10月2日～12月1日',
      '第４ターム 12月3日～2月12日',
    ];
    final bytes = _calendarPdf([
      _pageContent(['令和８年度 新潟大学授業暦', '4/27 水曜授業振替', ...ranges]),
      _pageContent(['令和７年度 新潟大学授業暦', '5/1 月曜授業振替', ...ranges]),
      _pageContent(['2025年度（2025）新潟大学授業暦', '5/7 火曜授業振替']),
      _pageContent(['5/2 木曜授業振替']),
    ]);
    final resolver = GakujoAcademicCalendarResolver(
      fetchHtml: (_) async => '<a href="/2025.pdf">2025年度</a>',
      fetchBytes: (_) async => bytes,
    );
    final terms = await resolver.fetchTermsForAcademicYear(2025);
    expect(terms, hasLength(4));
    expect(terms.last.end, DateTime(2026, 2, 12));
    expect(terms.first.classDaySwaps, [
      GakujoClassDaySwap(date: DateTime(2025, 5, 1), weekday: DateTime.monday),
      GakujoClassDaySwap(date: DateTime(2025, 5, 7), weekday: DateTime.tuesday),
    ]);
    expect(_parsePdf(bytes, academicYear: 2027), isEmpty);
  });

  test('uses ActualText fallback only from the selected page', () {
    const dates = [6, 10, 8, 5, 10, 2, 12, 1, 12, 3, 2, 12, 4, 8, 6, 8];
    final markedDates = [
      for (final value in dates) '/Span << /ActualText ($value) >> BDC EMC',
    ].join('\n');
    final bytes = _calendarPdf([
      _pageContent(['令和７年度 新潟大学授業暦']),
      '${_pageContent(['令和８年度 新潟大学授業暦'])}\n$markedDates',
    ]);
    final terms = _parsePdf(bytes);
    expect(terms, hasLength(4));
    expect(terms.first.start, DateTime(2026, 4, 8));
    expect(_parsePdf(bytes, academicYear: 2025), isEmpty);
  });
  test('rejects untrusted calendar PDF destinations', () {
    for (final url in [
      'https://untrusted.example/2026.pdf',
      '//untrusted.example/2026.pdf',
      'http://www.niigata-u.ac.jp/2026.pdf',
      'https://www.niigata-u.ac.jp.untrusted.example/2026.pdf',
    ]) {
      expect(GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(
        '<a href="$url">2026</a>', 2026), isNull, reason: url);
    }
  });

  test('rejects oversized PDF and unbounded character map ranges', () {
    expect(
      () => _parsePdf(Uint8List(GakujoAcademicCalendarResolver.maxResponseBytes + 1)),
      throwsA(exceedsLimits),
    );
    final cmap = _compressed(
      ascii.encode('beginbfrange\n<0000> % comment\n<FFFFFF> <0001>\nendbfrange'),
    );
    expect(() => _parsePdf(_calendarPdf([], extra: [cmap])), throwsA(exceedsLimits));
  });

  test('counts cumulative expansion of unreferenced compressed streams', () {
    final stream = _compressed(Uint8List(33 * 1024 * 1024));
    final bytes = _calendarPdf([], extra: [stream, stream]);
    expect(() => _parsePdf(bytes), throwsA(exceedsLimits));
  });
  test('findPdfUrlForAcademicYear finds the matching official PDF link', () {
    final uri = GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(
      '''
<p><a href="https://www.niigata-u.ac.jp/wp-content/uploads/2025/01/schedule_2025.pdf">令和7年度（2025）新潟大学授業暦</a></p>
<p><a href="https://www.niigata-u.ac.jp/wp-content/uploads/2025/08/schedule_2026.pdf">令和8年度（2026）新潟大学授業暦</a></p>
''',
      2026,
    );

    expect(uri.toString(), endsWith('/schedule_2026.pdf'));
  });

  test('findPdfUrlForAcademicYear accepts PDF URLs with query strings', () {
    final uri = GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(
      '''
<p><a href="/wp-content/uploads/2026/schedule_2026.pdf?ver=1">令和8年度（2026）新潟大学授業暦</a></p>
''',
      2026,
    );

    expect(uri.toString(), endsWith('/schedule_2026.pdf?ver=1'));
  });

  test('rejects a different academic year despite calendar-year mentions', () {
    for (final label in [
      '令和8年度（2026）新潟大学授業暦（2027年3月まで）',
      '令和8年度 新潟大学授業暦（2027年3月まで）',
      '2026年度 新潟大学授業暦（2027年3月まで）',
      '授業年度（2026）新潟大学授業暦（2027年3月まで）',
    ]) {
      expect(
        GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(
          '<a href="/uploads/schedule_2027.pdf">$label</a>',
          2027,
        ),
        isNull,
        reason: label,
      );
    }
  });

  test('rejects a different labelled academic year despite nearby text', () {
    expect(
      GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(
        '''
<h2>2028年度</h2>
<a href="/uploads/calendar.pdf">令和9年度（2027）新潟大学授業暦</a>
''',
        2028,
      ),
      isNull,
    );
  });

  test('accepts a label that also names the requested academic year', () {
    for (final label in [
      '令和8年度（2026）・令和9年度（2027）新潟大学授業暦',
      '2026年度・2027年度 新潟大学授業暦',
      '令和8年度（2027）新潟大学授業暦',
    ]) {
      expect(
        GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(
          '<a href="/uploads/calendar.pdf">$label</a>',
          2027,
        ).toString(),
        endsWith('/uploads/calendar.pdf'),
        reason: label,
      );
    }
  });

  test('uses nearby text when the link label names no academic year', () {
    expect(
      GakujoAcademicCalendarResolver.findPdfUrlForAcademicYear(
        '''
<h2>2028年度</h2>
<a href="/uploads/calendar.pdf">新潟大学授業暦</a>
''',
        2028,
      ).toString(),
      endsWith('/uploads/calendar.pdf'),
    );
  });

  test('termsFromExtractedText reads term ranges from PDF ActualText order',
      () {
    final terms = GakujoAcademicCalendarPdfParser.termsFromExtractedText(
      const GakujoPdfText(
        text: '6/1 開学記念日\n8/11～9/30 夏期休業',
        actualTexts: [
          '6',
          '10',
          '8',
          '5',
          '10',
          '2',
          '12',
          '1',
          '12',
          '3',
          '2',
          '12',
          '4',
          '8',
          '6',
          '8',
        ],
      ),
      academicYear: 2026,
      sourceUrl: 'https://example.com/schedule_2026.pdf',
    );

    expect(terms, hasLength(4));
    expect(terms[0].name, '第1ターム');
    expect(terms[0].start, DateTime(2026, 4, 8));
    expect(terms[0].end, DateTime(2026, 6, 8));
    expect(terms[1].name, '第2ターム');
    expect(terms[1].start, DateTime(2026, 6, 10));
    expect(terms[1].end, DateTime(2026, 8, 5));
    expect(terms[0].noClassDates, contains(DateTime(2026, 6, 1)));
  });

  test('termsFromExtractedText places a Jan-Mar term in the next calendar year',
      () {
    final terms = GakujoAcademicCalendarPdfParser.termsFromExtractedText(
      const GakujoPdfText(
        text: '',
        actualTexts: [
          // term 2
          '6', '10', '8', '5',
          // term 3
          '10', '2', '12', '1',
          // term 4 begins in January of the following calendar year
          '1', '8', '3', '20',
          // term 1
          '4', '8', '6', '8',
        ],
      ),
      academicYear: 2026,
      sourceUrl: 'https://example.com/schedule_2026.pdf',
    );

    final fourth = terms.singleWhere((term) => term.name == '第4ターム');
    expect(fourth.start, DateTime(2027, 1, 8));
    expect(fourth.end, DateTime(2027, 3, 20));
  });

  test('termsFromExtractedText falls back when ActualText has invalid dates',
      () {
    final terms = GakujoAcademicCalendarPdfParser.termsFromExtractedText(
      const GakujoPdfText(
        text: '''
第１ターム 4月8日～6月8日
第２ターム 6月10日～8月5日
第３ターム 10月2日～12月1日
第４ターム 12月3日～2月12日
''',
        actualTexts: [
          '99',
          '99',
          '8',
          '5',
          '10',
          '2',
          '12',
          '1',
          '12',
          '3',
          '2',
          '31',
          '4',
          '8',
          '6',
          '8',
        ],
      ),
      academicYear: 2026,
      sourceUrl: 'https://example.com/schedule_2026.pdf',
    );

    expect(terms, hasLength(4));
    expect(terms[0].name, '第1ターム');
    expect(terms[0].start, DateTime(2026, 4, 8));
    expect(terms[0].end, DateTime(2026, 6, 8));
  });

  test('termsFromExtractedText reads no-class notes from official text', () {
    final terms = GakujoAcademicCalendarPdfParser.termsFromExtractedText(
      const GakujoPdfText(
        text: '''
第１ターム 4月8日～6月8日
第２ターム 6月10日～8月5日
第３ターム 10月2日～12月1日
第４ターム 12月3日～2月12日
12/27～1/6 冬期休業
1/15,18大学入学共通
テスト準備・復元のため休講
''',
        actualTexts: [],
      ),
      academicYear: 2026,
      sourceUrl: 'https://example.com/schedule_2026.pdf',
    );

    final fourth = terms.singleWhere((term) => term.name == '第4ターム');
    expect(fourth.noClassDates, contains(DateTime(2026, 12, 28)));
    expect(fourth.noClassDates, contains(DateTime(2027, 1, 6)));
    expect(fourth.noClassDates, contains(DateTime(2027, 1, 15)));
    expect(fourth.noClassDates, contains(DateTime(2027, 1, 18)));
  });

  test('winter vacation includes Saturday and Sunday no-class dates', () {
    final terms = GakujoAcademicCalendarPdfParser.termsFromExtractedText(
      const GakujoPdfText(
        text: '''
第１ターム 4月8日～6月8日
第２ターム 6月10日～8月5日
第３ターム 10月2日～12月1日
第４ターム 12月3日～2月12日
12/27～1/6 冬期休業
''',
        actualTexts: [],
      ),
      academicYear: 2026,
      sourceUrl: 'https://example.com/schedule_2026.pdf',
    );

    final fourth = terms.singleWhere((term) => term.name == '第4ターム');
    expect(fourth.noClassDates, contains(DateTime(2027, 1, 2)));
    expect(fourth.noClassDates, contains(DateTime(2027, 1, 3)));
  });

  test('holiday ranges include their final civil day across DST changes', () {
    final terms = GakujoAcademicCalendarPdfParser.termsFromExtractedText(
      const GakujoPdfText(
        text: '''
第１ターム 4月8日～6月8日
第２ターム 6月10日～8月5日
第３ターム 10月2日～12月1日
第４ターム 12月3日～3月31日
3/1～3/31 春期休業
''',
        actualTexts: [],
      ),
      academicYear: 2026,
      sourceUrl: 'https://example.com/schedule_2026.pdf',
    );

    final fourth = terms.singleWhere((term) => term.name == '第4ターム');
    expect(fourth.noClassDates, contains(DateTime(2027, 3, 31)));
  });

  test('mergeWithBuiltInDetails preserves embedded detailed no-class days', () {
    final merged = GakujoAcademicCalendar.mergeWithBuiltInDetails(
      GakujoAcademicTerm(
        academicYear: 2026,
        name: '第2ターム',
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 8, 5),
        sourceUrl: 'https://example.com/schedule_2026.pdf',
        noClassDates: [DateTime(2026, 6, 15)],
      ),
    );

    expect(merged.noClassDates, contains(DateTime(2026, 6, 15)));
    expect(merged.noClassDates, contains(DateTime(2026, 7, 30)));
    expect(merged.noClassDates, contains(DateTime(2026, 8, 5)));
  });
}

class _ReportView implements GakujoWebViewController {
  const _ReportView(this.response);
  final String response;

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async =>
      script.startsWith('window.__mbgPlannerFetch?.cancel(') ? null : response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<GakujoAcademicTerm> _parsePdf(Uint8List bytes, {int academicYear = 2026}) {
  return GakujoAcademicCalendarPdfParser.termsFromPdfBytes(
    bytes,
    academicYear: academicYear,
    sourceUrl: 'https://www.niigata-u.ac.jp/schedule.pdf',
  );
}

CosStream _compressed(List<int> bytes) {
  final compressed = Uint8List.fromList(zlib.encode(bytes));
  return CosStream(
    CosDictionary({
      'Filter': const CosName('FlateDecode'),
      'Length': CosInteger(compressed.length),
    }),
    compressed,
  );
}

String _pageContent(List<String> lines) {
  return [
    for (final (index, line) in lines.indexed)
      'BT 1 0 0 1 36 ${700 - index * 24} Tm '
          '${RegExp(r'[0-9]+|[^0-9]+').allMatches(line).map((match) {
        final run = match.group(0)!;
        return int.tryParse(run) == null
            ? '/CID 11 Tf <${run.codeUnits.map(_hex).join()}> Tj'
            : '/Roman 11 Tf ($run) Tj';
      }).join(' ')} ET',
  ].join('\n');
}

String _hex(int code) => code.toRadixString(16).padLeft(4, '0');

Uint8List _calendarPdf(List<String> content, {List<CosObject> extra = const []}) {
  final builder = CosDocumentBuilder();
  final cmapLines = <String>{
    for (final page in content)
      for (final match in RegExp(r'<([0-9a-f]+)> Tj').allMatches(page))
        for (final unit in RegExp(r'.{4}').allMatches(match.group(1)!))
          '<${unit.group(0)}> <${unit.group(0)}>',
  };
  final cmap = builder.add(_compressed(ascii.encode(
    '${cmapLines.length} beginbfchar\n${cmapLines.join('\n')}\nendbfchar',
  )));
  final cid = builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type0'),
    'BaseFont': const CosName('FixtureCID'),
    'Encoding': const CosName('Identity-H'),
    'ToUnicode': cmap,
    'DescendantFonts': CosArray([
      CosDictionary({
        'Type': const CosName('Font'),
        'Subtype': const CosName('CIDFontType2'),
        'DW': const CosInteger(1000),
      }),
    ]),
  }));
  final roman = builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  }));
  final pages = CosDictionary({
    'Type': const CosName('Pages'),
    'Count': CosInteger(content.length),
  });
  final parent = builder.add(pages);
  pages['Kids'] = CosArray([
    for (final page in content)
      builder.add(CosDictionary({
        'Type': const CosName('Page'),
        'Parent': parent,
        'MediaBox': CosArray(const [
          CosInteger(0), CosInteger(0), CosInteger(595), CosInteger(842),
        ]),
        'Resources': CosDictionary({
          'Font': CosDictionary({'CID': cid, 'Roman': roman}),
        }),
        'Contents': builder.add(_compressed(ascii.encode(page))),
      })),
  ]);
  for (final object in extra) {
    builder.add(object);
  }
  final root = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': parent,
  }));
  return builder.build(root: root);
}
