import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'gakujo_academic_calendar.dart';

typedef GakujoCalendarHtmlFetcher = Future<String> Function(Uri uri);
typedef GakujoCalendarBytesFetcher = Future<Uint8List> Function(Uri uri);

class GakujoAcademicCalendarResolver {
  const GakujoAcademicCalendarResolver({
    this.fetchHtml,
    this.fetchBytes,
  });

  final GakujoCalendarHtmlFetcher? fetchHtml;
  final GakujoCalendarBytesFetcher? fetchBytes;

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
    for (final match in linkPattern.allMatches(html)) {
      final href = match.group(1) ?? '';
      final label = _stripTags(match.group(2) ?? '');
      final nearbyStart = match.start - 80 < 0 ? 0 : match.start - 80;
      final nearbyEnd =
          match.end + 80 > html.length ? html.length : match.end + 80;
      final nearby = _stripTags(html.substring(nearbyStart, nearbyEnd));
      final haystack = '$href $label $nearby';
      if (!haystack.contains(academicYear.toString())) {
        continue;
      }
      final uri = Uri.tryParse(href);
      if (uri == null) {
        continue;
      }
      return uri.hasScheme
          ? uri
          : Uri.parse(GakujoAcademicCalendar.calendarPageUrl).resolveUri(uri);
    }
    return null;
  }

  static Future<String> _defaultFetchHtml(Uri uri) async {
    final bytes = await _defaultFetchBytes(uri);
    return utf8.decode(bytes);
  }

  static Future<Uint8List> _defaultFetchBytes(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader, 'MoreBetterGakujo');
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Unexpected status ${response.statusCode}',
          uri: uri,
        );
      }
      final chunks = <int>[];
      await for (final chunk in response) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
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
    final extracted = extractText(bytes);
    return termsFromExtractedText(
      extracted,
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
    final noClassDates = _noClassDatesFromText(
      extracted.text,
      academicYear: academicYear,
    );
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
        ),
    ];
  }

  static GakujoPdfText extractText(Uint8List bytes) {
    final streams = _decodedStreams(bytes);
    final cmap = _parseToUnicodeMap(streams);
    final textParts = <String>[];
    for (final stream in streams) {
      final text = latin1.decode(stream, allowInvalid: true);
      if (!text.contains('Tj') && !text.contains('TJ')) {
        continue;
      }
      for (final match in RegExp(r'<([0-9A-Fa-f\s]+)>\s*Tj').allMatches(text)) {
        textParts.add(_decodeHexText(match.group(1) ?? '', cmap));
      }
      for (final match
          in RegExp(r'\[(.*?)\]\s*TJ', dotAll: true).allMatches(text)) {
        final buffer = StringBuffer();
        for (final hex
            in RegExp(r'<([0-9A-Fa-f\s]+)>').allMatches(match.group(1) ?? '')) {
          buffer.write(_decodeHexText(hex.group(1) ?? '', cmap));
        }
        if (buffer.isNotEmpty) {
          textParts.add(buffer.toString());
        }
      }
    }
    final raw = bytes.toList() + streams.expand((stream) => stream).toList();
    return GakujoPdfText(
      text: textParts.join('\n'),
      actualTexts: _actualTexts(Uint8List.fromList(raw)),
    );
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
      r'第([1-4１-４])ターム\s*([0-9０-９]{1,2})月([0-9０-９]{1,2})日\s*～\s*([0-9０-９]{1,2})月([0-9０-９]{1,2})日',
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
      r'([0-9０-９]{1,2})/([0-9０-９]{1,2})\s*開学記念日',
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
      r'([0-9０-９]{1,2})/([0-9０-９]{1,2})～([0-9０-９]{1,2})/([0-9０-９]{1,2})\s*(?:夏期|冬期|春期)休業',
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
          day = day.add(const Duration(days: 1))) {
        if (day.weekday != DateTime.saturday &&
            day.weekday != DateTime.sunday) {
          dates.add(day);
        }
      }
    }
    for (final match in RegExp(
      r'([0-9０-９]{1,2})/([0-9０-９]{1,2})(?:,([0-9０-９]{1,2}))?大学入学共通[\s\S]{0,40}?休講',
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

  static List<Uint8List> _decodedStreams(Uint8List bytes) {
    final streams = <Uint8List>[];
    final pattern = RegExp(r'stream\r?\n');
    final source = latin1.decode(bytes, allowInvalid: true);
    for (final match in pattern.allMatches(source)) {
      final start = match.end;
      final end = source.indexOf('endstream', start);
      if (end < 0) {
        continue;
      }
      final headerStart = source.lastIndexOf('obj', match.start);
      final header = source.substring(
        headerStart < 0 ? 0 : headerStart,
        match.start,
      );
      final raw = bytes.sublist(start, end);
      final trimmed = _trimLineBreaks(raw);
      if (!header.contains('/FlateDecode')) {
        streams.add(trimmed);
        continue;
      }
      try {
        streams.add(Uint8List.fromList(zlib.decode(trimmed)));
      } on Object {
        // Ignore malformed compressed streams.
      }
    }
    return streams;
  }

  static Map<int, String> _parseToUnicodeMap(List<Uint8List> streams) {
    final map = <int, String>{};
    for (final stream in streams) {
      final text = latin1.decode(stream, allowInvalid: true);
      if (!text.contains('beginbfchar') && !text.contains('beginbfrange')) {
        continue;
      }
      for (final block in RegExp(
        r'beginbfchar(.*?)endbfchar',
        dotAll: true,
      ).allMatches(text)) {
        for (final pair in RegExp(
          r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
        ).allMatches(block.group(1) ?? '')) {
          final from = int.tryParse(pair.group(1) ?? '', radix: 16);
          final to = int.tryParse(pair.group(2) ?? '', radix: 16);
          if (from != null && to != null) {
            map[from] = String.fromCharCode(to);
          }
        }
      }
      for (final block in RegExp(
        r'beginbfrange(.*?)endbfrange',
        dotAll: true,
      ).allMatches(text)) {
        for (final range in RegExp(
          r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
        ).allMatches(block.group(1) ?? '')) {
          final from = int.tryParse(range.group(1) ?? '', radix: 16);
          final to = int.tryParse(range.group(2) ?? '', radix: 16);
          final target = int.tryParse(range.group(3) ?? '', radix: 16);
          if (from == null || to == null || target == null) {
            continue;
          }
          for (var code = from; code <= to; code += 1) {
            map[code] = String.fromCharCode(target + code - from);
          }
        }
      }
    }
    return map;
  }

  static String _decodeHexText(String hex, Map<int, String> cmap) {
    final compact = hex.replaceAll(RegExp(r'\s+'), '');
    if (compact.length.isOdd) {
      return '';
    }
    final bytes = <int>[];
    for (var i = 0; i < compact.length; i += 2) {
      final value = int.tryParse(compact.substring(i, i + 2), radix: 16);
      if (value == null) {
        return '';
      }
      bytes.add(value);
    }
    final buffer = StringBuffer();
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final code = (bytes[i] << 8) + bytes[i + 1];
      buffer.write(cmap[code] ?? '');
    }
    return buffer.toString();
  }

  static List<String> _actualTexts(Uint8List bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final values = <String>[];
    for (final match in RegExp(
      r'/ActualText\((.*?)\)',
      dotAll: true,
    ).allMatches(text)) {
      values.add(_decodePdfLiteral(match.group(1) ?? '').trim());
    }
    return values.where((value) => value.isNotEmpty).toList();
  }

  static String _decodePdfLiteral(String raw) {
    return raw
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', '\\');
  }

  static Uint8List _trimLineBreaks(Uint8List bytes) {
    var start = 0;
    var end = bytes.length;
    while (start < end && (bytes[start] == 0x0a || bytes[start] == 0x0d)) {
      start += 1;
    }
    while (end > start && (bytes[end - 1] == 0x0a || bytes[end - 1] == 0x0d)) {
      end -= 1;
    }
    return bytes.sublist(start, end);
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
