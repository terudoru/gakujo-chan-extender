import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'gakujo_academic_calendar.dart';
import 'gakujo_academic_calendar_pdf_limits.dart';

typedef GakujoCalendarHtmlFetcher = Future<String> Function(Uri uri);
typedef GakujoCalendarBytesFetcher = Future<Uint8List> Function(Uri uri);

class GakujoAcademicCalendarResolver {
  const GakujoAcademicCalendarResolver({
    this.fetchHtml,
    this.fetchBytes,
  });

  final GakujoCalendarHtmlFetcher? fetchHtml;
  final GakujoCalendarBytesFetcher? fetchBytes;
  static const maxResponseBytes = 16 * 1024 * 1024;

  static bool _isOfficialUrl(Uri uri) {
    final origin = Uri.parse(GakujoAcademicCalendar.calendarPageUrl);
    return uri.scheme == 'https' && uri.host == origin.host &&
        (!uri.hasPort || uri.port == 443) && uri.userInfo.isEmpty;
  }

  Future<List<GakujoAcademicTerm>> fetchTermsForAcademicYear(
    int academicYear,
  ) async {
    final html = await (fetchHtml ?? _defaultFetchHtml)(
      Uri.parse(GakujoAcademicCalendar.calendarPageUrl),
    );
    final pdfUrl = findPdfUrlForAcademicYear(html, academicYear);
    if (pdfUrl == null) {
      return const [];
    }
    final bytes = await (fetchBytes ?? _defaultFetchBytes)(pdfUrl);
    return GakujoAcademicCalendarPdfParser.termsFromPdfBytes(
      bytes,
      academicYear: academicYear,
      sourceUrl: pdfUrl.toString(),
    );
  }

  static Uri? findPdfUrlForAcademicYear(String html, int academicYear) {
    final linkPattern = RegExp(
      r'''<a\s+[^>]*href=["']([^"']+\.pdf(?:\?[^"']*)?)["'][^>]*>(.*?)</a>''',
      caseSensitive: false,
      dotAll: true,
    );
    final year = academicYear.toString();
    final reiwaYear = academicYear - 2018;
    final eraPattern = RegExp('令和\\s*0*$reiwaYear\\s*年度');
    final academicYearPattern = RegExp(
      r'令和\s*\d+\s*年度|\d{4}\s*年度|年度\s*[（(]\s*\d{4}\s*[）)]',
    );
    final westernYearPattern = RegExp(
      '$year\\s*年度|年度\\s*[（(]\\s*$year\\s*[）)]',
    );
    Uri? best;
    var bestScore = 0;
    for (final match in linkPattern.allMatches(html)) {
      final href = match.group(1) ?? '';
      final label = _normalizeDigits(_stripTags(match.group(2) ?? ''));
      if (academicYearPattern.hasMatch(label) &&
          !eraPattern.hasMatch(label) &&
          !westernYearPattern.hasMatch(label)) {
        continue;
      }
      final uri = Uri.tryParse(href);
      if (uri == null) {
        continue;
      }
      // Upload directories such as /uploads/2025/08/ carry the publication
      // date, not the academic year, so only the file name is trusted.
      final fileName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      final nearbyStart = match.start - 80 < 0 ? 0 : match.start - 80;
      final nearbyEnd =
          match.end + 80 > html.length ? html.length : match.end + 80;
      final nearby = _stripTags(
        '${html.substring(nearbyStart, match.start)} '
        '${html.substring(match.end, nearbyEnd)}',
      );
      final score = label.contains(year) || eraPattern.hasMatch(label)
          ? 3
          : fileName.contains(year)
              ? 2
              : nearby.contains(year)
                  ? 1
                  : 0;
      final resolved = Uri.parse(GakujoAcademicCalendar.calendarPageUrl).resolveUri(uri);
      if (!_isOfficialUrl(resolved)) continue;
      if (score > bestScore) {
        bestScore = score;
        best = resolved;
      }
    }
    return best;
  }

  static String _normalizeDigits(String value) {
    return value.replaceAllMapped(
      RegExp(r'[０-９]'),
      (match) => String.fromCharCode(match.group(0)!.codeUnitAt(0) - 0xfee0),
    );
  }

  static Future<String> _defaultFetchHtml(Uri uri) async {
    final bytes = await _defaultFetchBytes(uri);
    return utf8.decode(bytes);
  }

  static Future<Uint8List> _defaultFetchBytes(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      var current = uri;
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (!_isOfficialUrl(current)) throw const FormatException('Untrusted calendar URL');
        final request = await client.getUrl(current).timeout(const Duration(seconds: 8));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'MoreBetterGakujo');
        response = await request.close().timeout(const Duration(seconds: 12));
        if (!response.isRedirect) break;
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || redirects == 5) throw const FormatException('Invalid calendar redirect');
        current = current.resolve(location);
      }
      if (response == null) throw const FormatException('No calendar response');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Unexpected status ${response.statusCode}',
          uri: uri,
        );
      }
      if (response.contentLength > maxResponseBytes) throw const FormatException('Calendar response too large');
      final chunks = BytesBuilder(copy: false);
      final timer = Stopwatch()..start();
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        if (timer.elapsed > const Duration(seconds: 30) || chunks.length + chunk.length > maxResponseBytes) {
          throw const FormatException('Calendar response exceeds limits');
        }
        chunks.add(chunk);
      }
      return chunks.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static String _stripTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class GakujoAcademicCalendarPdfParser {
  const GakujoAcademicCalendarPdfParser._();

  static List<GakujoAcademicTerm> termsFromPdfBytes(
    Uint8List bytes, {
    required int academicYear,
    required String sourceUrl,
  }) {
    checkAcademicCalendarPdfLimits(
      bytes,
      maxInputBytes: GakujoAcademicCalendarResolver.maxResponseBytes,
    );
    final document = PdfDocument.open(bytes);
    final pageTexts = <String>[];
    final matchingPages = <PdfPage>[];
    for (var index = 0; index < document.pageCount; index++) {
      final page = document.page(index);
      checkAcademicCalendarPdfOperands(page.contentBytes());
      final text = PdfTextExtractor.extract(document, index).text;
      if (_pageAcademicYear(text) == academicYear) {
        pageTexts.add(text);
        matchingPages.add(page);
      }
    }
    final text = pageTexts.join('\n');
    final extracted = GakujoPdfText(text: text, actualTexts: const []);
    final terms = termsFromExtractedText(
      extracted,
      academicYear: academicYear,
      sourceUrl: sourceUrl,
    );
    if (terms.isNotEmpty || matchingPages.isEmpty) return terms;

    return termsFromExtractedText(
      GakujoPdfText(
        text: text,
        actualTexts: matchingPages.expand(_pageActualTexts).toList(),
      ),
      academicYear: academicYear,
      sourceUrl: sourceUrl,
    );
  }

  static List<GakujoAcademicTerm> termsFromExtractedText(
    GakujoPdfText extracted, {
    required int academicYear,
    required String sourceUrl,
  }) {
    final ranges = _termRangesFromActualText(
          extracted.actualTexts,
          academicYear: academicYear,
        ) ??
        _termRangesFromPlainText(
          extracted.text,
          academicYear: academicYear,
        );
    if (ranges.length != 4) {
      return const [];
    }
    final classDays = _classDaysFromText(
      extracted.text,
      academicYear: academicYear,
    );
    // A day announced as 授業振替 or 授業開講 holds classes even when it lies
    // inside a stated holiday range (e.g. "12/27～1/6冬期休業、ただし12/27
    // 月曜日授業開講").
    final noClassDates = _noClassDatesFromText(
      extracted.text,
      academicYear: academicYear,
    )
        .where((date) => !classDays.any((swap) => _sameDay(swap.date, date)))
        .toList();
    return [
      for (var i = 1; i <= 4; i += 1)
        GakujoAcademicTerm(
          academicYear: academicYear,
          name: '第$iターム',
          start: ranges[i]!.$1,
          end: ranges[i]!.$2,
          sourceUrl: sourceUrl,
          noClassDates: noClassDates
              .where(
                  (date) => _containsDate(ranges[i]!.$1, ranges[i]!.$2, date))
              .toList(),
          classDaySwaps: classDays
              .where(
                (swap) =>
                    swap.weekday != swap.date.weekday &&
                    _containsDate(ranges[i]!.$1, ranges[i]!.$2, swap.date),
              )
              .toList(),
        ),
    ];
  }

  static List<GakujoClassDaySwap> _classDaysFromText(
    String text, {
    required int academicYear,
  }) {
    const weekdays = {
      '月': DateTime.monday,
      '火': DateTime.tuesday,
      '水': DateTime.wednesday,
      '木': DateTime.thursday,
      '金': DateTime.friday,
      '土': DateTime.saturday,
      '日': DateTime.sunday,
    };
    final swaps = <GakujoClassDaySwap>[];
    for (final match in RegExp(
      r'([0-9０-９]{1,2})\s*/\s*([0-9０-９]{1,2})\s*([月火水木金土日])\s*曜\s*日?\s*授業\s*(?:振替|開講)',
    ).allMatches(text)) {
      final date = _monthDayDate(
        academicYear,
        _number(match.group(1)),
        _number(match.group(2)),
      );
      final weekday = weekdays[match.group(3)];
      if (date == null || weekday == null) {
        continue;
      }
      final swap = GakujoClassDaySwap(date: date, weekday: weekday);
      if (!swaps.contains(swap)) {
        swaps.add(swap);
      }
    }
    return swaps;
  }

  static bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static int? _pageAcademicYear(String text) {
    final heading = RegExp(
      r'^\s*(?:令\s*和\s*(元|[0-9]{1,2})|([0-9]{4}))\s*年\s*度'
      r'(?:\s*[（(]\s*[0-9]{4}\s*[)）])?\s*新\s*潟\s*大\s*学\s*授\s*業\s*暦',
      multiLine: true,
    ).firstMatch(GakujoAcademicCalendarResolver._normalizeDigits(text));
    if (heading == null) return null;
    final reiwa = heading.group(1);
    return reiwa == null
        ? int.parse(heading.group(2)!)
        : 2018 + (reiwa == '元' ? 1 : int.parse(reiwa));
  }

  static Iterable<String> _pageActualTexts(PdfPage page) sync* {
    final cursor = ContentStreamParser.cursor(page.contentBytes());
    String? operator;
    while ((operator = cursor.nextOperator()) != null) {
      if (operator != 'BDC') continue;
      final operands = cursor.takeOperation().operands;
      if (operands.length != 2) continue;
      final properties = operands[1];
      if (properties is! CosDictionary) continue;
      if (properties['ActualText'] case final CosString replacement) {
        yield replacement.text;
      }
    }
  }

  static Map<int, (DateTime, DateTime)>? _termRangesFromActualText(
    List<String> actualTexts, {
    required int academicYear,
  }) {
    final numbers = actualTexts
        .map((text) => int.tryParse(text.trim()))
        .whereType<int>()
        .toList();
    if (numbers.length < 16) {
      return null;
    }
    final termOrder = [2, 3, 4, 1];
    final ranges = <int, (DateTime, DateTime)>{};
    for (var i = 0; i < termOrder.length; i += 1) {
      final offset = i * 4;
      // Months 1-3 belong to the second calendar year of the academic year
      // (April YYYY .. March YYYY+1). Mirror _monthDayDate's mapping so a term
      // that starts in Jan-Mar is not placed a full year too early.
      final startYear = numbers[offset] <= 3 ? academicYear + 1 : academicYear;
      final endYear =
          numbers[offset + 2] <= 3 ? academicYear + 1 : academicYear;
      final start = _validatedDate(
        startYear,
        numbers[offset],
        numbers[offset + 1],
      );
      final end = _validatedDate(
        endYear,
        numbers[offset + 2],
        numbers[offset + 3],
      );
      if (start == null || end == null || end.isBefore(start)) {
        return null;
      }
      ranges[termOrder[i]] = (start, end);
    }
    return ranges;
  }

  static Map<int, (DateTime, DateTime)> _termRangesFromPlainText(
    String text, {
    required int academicYear,
  }) {
    final ranges = <int, (DateTime, DateTime)>{};
    final normalized = text.replaceAll('〜', '～').replaceAll('~', '～');
    final pattern = RegExp(
      r'第\s*([1-4１-４])\s*ターム\s*([0-9０-９]{1,2})\s*月\s*([0-9０-９]{1,2})\s*日\s*～\s*([0-9０-９]{1,2})\s*月\s*([0-9０-９]{1,2})\s*日',
    );
    for (final match in pattern.allMatches(normalized)) {
      final term = _number(match.group(1));
      final startMonth = _number(match.group(2));
      final startDay = _number(match.group(3));
      final endMonth = _number(match.group(4));
      final endDay = _number(match.group(5));
      if (term == null ||
          startMonth == null ||
          startDay == null ||
          endMonth == null ||
          endDay == null) {
        continue;
      }
      final startYear = startMonth <= 3 ? academicYear + 1 : academicYear;
      final endYear = endMonth <= 3 ? academicYear + 1 : academicYear;
      ranges[term] = (
        DateTime(startYear, startMonth, startDay),
        DateTime(endYear, endMonth, endDay),
      );
    }
    return ranges;
  }

  static List<DateTime> _noClassDatesFromText(
    String text, {
    required int academicYear,
  }) {
    final dates = <DateTime>{};
    final normalized =
        text.replaceAll('〜', '～').replaceAll('~', '～').replaceAll('、', ',');
    for (final match in RegExp(
      r'([0-9０-９]{1,2})\s*/\s*([0-9０-９]{1,2})\s*開学記念日',
    ).allMatches(normalized)) {
      final date = _monthDayDate(
        academicYear,
        _number(match.group(1)),
        _number(match.group(2)),
      );
      if (date != null) {
        dates.add(date);
      }
    }
    for (final match in RegExp(
      r'([0-9０-９]{1,2})\s*/\s*([0-9０-９]{1,2})\s*～\s*([0-9０-９]{1,2})\s*/\s*([0-9０-９]{1,2})\s*(?:夏期|冬期|春期)休業',
    ).allMatches(normalized)) {
      final startMonth = _number(match.group(1));
      final startDay = _number(match.group(2));
      final endMonth = _number(match.group(3));
      final endDay = _number(match.group(4));
      final start = _monthDayDate(academicYear, startMonth, startDay);
      var end = _monthDayDate(academicYear, endMonth, endDay);
      if (start == null || end == null) {
        continue;
      }
      if (end.isBefore(start)) {
        end = DateTime(end.year + 1, end.month, end.day);
      }
      for (var day = start;
          !day.isAfter(end);
          day = DateTime(day.year, day.month, day.day + 1)) {
        dates.add(day);
      }
    }
    for (final match in RegExp(
      r'([0-9０-９]{1,2})\s*/\s*([0-9０-９]{1,2})(?:\s*,\s*([0-9０-９]{1,2}))?\s*大学入学共通[\s\S]{0,40}?休講',
    ).allMatches(normalized)) {
      final month = _number(match.group(1));
      final firstDay = _number(match.group(2));
      final secondDay = _number(match.group(3));
      for (final day in [firstDay, secondDay].whereType<int>()) {
        final date = _monthDayDate(academicYear, month, day);
        if (date != null) {
          dates.add(date);
        }
      }
    }
    final sorted = dates.toList()..sort();
    return sorted;
  }

  static bool _containsDate(DateTime start, DateTime end, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static DateTime? _monthDayDate(int academicYear, int? month, int? day) {
    if (month == null || day == null) {
      return null;
    }
    final year = month <= 3 ? academicYear + 1 : academicYear;
    return _validatedDate(year, month, day);
  }

  static DateTime? _validatedDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static int? _number(String? raw) {
    if (raw == null) {
      return null;
    }
    final normalized = raw.replaceAllMapped(
      RegExp(r'[０-９]'),
      (match) => String.fromCharCode(match.group(0)!.codeUnitAt(0) - 0xfee0),
    );
    return int.tryParse(normalized);
  }
}

class GakujoPdfText {
  const GakujoPdfText({
    required this.text,
    required this.actualTexts,
  });

  final String text;
  final List<String> actualTexts;
}
