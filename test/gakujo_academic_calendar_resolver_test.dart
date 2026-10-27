import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:morebettergakujo_flutter/src/gakujo_academic_calendar.dart';
import 'package:morebettergakujo_flutter/src/gakujo_academic_calendar_resolver.dart';
import 'package:test/test.dart';

void main() {
  test('calendar PDF rejects oversized operand sequences', () {
    expect(
      () => GakujoAcademicCalendarPdfParser.textLinesFromContentStream(
        '${'1 ' * 4097}Tj', const {},
      ),
      throwsFormatException,
    );
    expect(
      GakujoAcademicCalendarPdfParser.textLinesFromContentStream(
        'BT 1 0 0 1 10 20 Tm (Hello) Tj ET', const {},
      ),
      ['Hello'],
    );
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
      () => GakujoAcademicCalendarPdfParser.extractText(
        Uint8List(GakujoAcademicCalendarResolver.maxResponseBytes + 1),
      ),
      throwsFormatException,
    );
    final content = ascii.encode('beginbfrange\n<0000> <FFFFF> <0001>\nendbfrange');
    final bytes = Uint8List.fromList([
      ...ascii.encode('1 0 obj << /Filter /FlateDecode >>\nstream\n'),
      ...zlib.encode(content),
      ...ascii.encode('\nendstream\nendobj'),
    ]);
    expect(() => GakujoAcademicCalendarPdfParser.extractText(bytes), throwsFormatException);
  });

  test('stops a compressed stream exceeding the PDF expansion budget', () {
    final compressed = zlib.encode(Uint8List(65 * 1024 * 1024));
    final bytes = Uint8List.fromList([
      ...ascii.encode('1 0 obj << /Filter /FlateDecode >>\nstream\n'),
      ...compressed,
      ...ascii.encode('\nendstream\nendobj'),
    ]);
    expect(() => GakujoAcademicCalendarPdfParser.extractText(bytes), throwsFormatException);
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
