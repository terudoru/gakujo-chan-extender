import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

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
    Uri? best;
    var bestScore = 0;
    for (final match in linkPattern.allMatches(html)) {
      final href = match.group(1) ?? '';
      final label = _normalizeDigits(_stripTags(match.group(2) ?? ''));
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

  static GakujoPdfText extractText(Uint8List bytes) {
    if (bytes.length > GakujoAcademicCalendarResolver.maxResponseBytes) {
      throw const FormatException('Calendar PDF exceeds size limit');
    }
    final streams = _decodedStreams(bytes);
    final cmap = _parseToUnicodeMap(streams);
    final lines = <String>[];
    for (final stream in streams) {
      final text = latin1.decode(stream, allowInvalid: true);
      if (!text.contains('Tj') && !text.contains('TJ')) {
        continue;
      }
      lines.addAll(textLinesFromContentStream(text, cmap));
    }
    final raw = BytesBuilder(copy: false)..add(bytes);
    for (final stream in streams) {
      raw.add(stream);
    }
    return GakujoPdfText(
      text: lines.join('\n'),
      actualTexts: _actualTexts(raw.takeBytes()),
    );
  }

  /// Reassembles the text runs of one content stream into lines.
  ///
  /// Runs that share a baseline are joined with a space, so a date drawn as
  /// separate runs (e.g. `(4)Tj <6708>Tj (8)Tj ...` mixing a WinAnsi font for
  /// digits and a CID font for kanji) stays on one line.
  @visibleForTesting
  static List<String> textLinesFromContentStream(
    String content,
    Map<int, String> cmap,
  ) {
    final lines = <String>[];
    final current = <String>[];
    double? currentY;
    var lineMatrix = <double>[1, 0, 0, 1, 0, 0];
    var leading = 0.0;
    final operands = <Object>[];
    List<Object>? array;
    const maxContentTokens = 250000;
    const maxPendingOperands = 4096;
    var tokenCount = 0;

    void breakLine() {
      if (current.isNotEmpty) {
        lines.add(current.join(' '));
        current.clear();
      }
      currentY = null;
    }

    void show(String value) {
      final y = lineMatrix[5];
      final previousY = currentY;
      if (previousY != null && (y - previousY).abs() > 0.5) {
        breakLine();
      }
      currentY = y;
      if (value.trim().isNotEmpty) {
        current.add(value);
      }
    }

    void moveText(double tx, double ty) {
      lineMatrix = [
        lineMatrix[0],
        lineMatrix[1],
        lineMatrix[2],
        lineMatrix[3],
        lineMatrix[4] + tx * lineMatrix[0] + ty * lineMatrix[2],
        lineMatrix[5] + tx * lineMatrix[1] + ty * lineMatrix[3],
      ];
    }

    String decodeOperand(Object operand) {
      if (operand is _PdfStringToken) {
        return operand.decode(cmap);
      }
      if (operand is List<Object>) {
        return operand
            .whereType<_PdfStringToken>()
            .map((token) => token.decode(cmap))
            .join();
      }
      return '';
    }

    double? number(int fromEnd) {
      final index = operands.length - fromEnd;
      if (index < 0) {
        return null;
      }
      final value = operands[index];
      return value is double ? value : null;
    }

    void operate(String operator) {
      switch (operator) {
        case 'BT':
          lineMatrix = <double>[1, 0, 0, 1, 0, 0];
        case 'Tm':
          final values = [for (var i = 6; i >= 1; i -= 1) number(i)];
          if (values.every((value) => value != null)) {
            lineMatrix = values.cast<double>();
          }
        case 'Td':
        case 'TD':
          final tx = number(2);
          final ty = number(1);
          if (tx != null && ty != null) {
            if (operator == 'TD') {
              leading = -ty;
            }
            moveText(tx, ty);
          }
        case 'TL':
          leading = number(1) ?? leading;
        case 'T*':
          moveText(0, -leading);
        case 'Tj':
        case 'TJ':
          if (operands.isNotEmpty) {
            show(decodeOperand(operands.last));
          }
        case "'":
        case '"':
          moveText(0, -leading);
          if (operands.isNotEmpty) {
            show(decodeOperand(operands.last));
          }
      }
      operands.clear();
    }

    final length = content.length;
    var index = 0;
    bool isWhitespace(int code) =>
        code == 0x20 ||
        code == 0x0a ||
        code == 0x0d ||
        code == 0x09 ||
        code == 0x0c ||
        code == 0x00;
    bool isDelimiter(int code) =>
        isWhitespace(code) || '()<>[]{}/%'.codeUnits.contains(code);

    void push(Object value) {
      final open = array;
      if (open != null) {
        if (open.length >= maxPendingOperands) {
          throw const FormatException('Calendar PDF operand limit exceeded');
        }
        open.add(value);
      } else {
        if (operands.length >= maxPendingOperands) {
          throw const FormatException('Calendar PDF operand limit exceeded');
        }
        operands.add(value);
      }
    }

    while (index < length) {
      final code = content.codeUnitAt(index);
      if (isWhitespace(code)) {
        index += 1;
        continue;
      }
      if (++tokenCount > maxContentTokens) {
        throw const FormatException('Calendar PDF token limit exceeded');
      }
      switch (content[index]) {
        case '%':
          while (index < length &&
              content[index] != '\n' &&
              content[index] != '\r') {
            index += 1;
          }
        case '(':
          final parsed = _readLiteralString(content, index);
          push(_PdfStringToken(parsed.$1, isHex: false));
          index = parsed.$2;
        case '<':
          if (index + 1 < length && content[index + 1] == '<') {
            index += 2;
            break;
          }
          final end = content.indexOf('>', index + 1);
          final hex = content.substring(index + 1, end < 0 ? length : end);
          push(_PdfStringToken(_hexBytes(hex), isHex: true));
          index = end < 0 ? length : end + 1;
        case '>':
          index += 1;
        case '[':
          array = <Object>[];
          index += 1;
        case ']':
          final closed = array;
          array = null;
          if (closed != null) {
            push(closed);
          }
          index += 1;
        case '{':
        case '}':
          index += 1;
        case '/':
          var end = index + 1;
          while (end < length && !isDelimiter(content.codeUnitAt(end))) {
            end += 1;
          }
          push(content.substring(index, end));
          index = end;
        default:
          var end = index + 1;
          while (end < length && !isDelimiter(content.codeUnitAt(end))) {
            end += 1;
          }
          final token = content.substring(index, end);
          index = end;
          final value = double.tryParse(token);
          if (value != null) {
            push(value);
          } else if (token == 'BI') {
            // Skip inline image data, which is binary.
            final imageEnd = RegExp(r'\sEI(?=\s|$)').firstMatch(
              content.substring(index),
            );
            index = imageEnd == null ? length : index + imageEnd.end;
            operands.clear();
          } else {
            operate(token);
          }
      }
    }
    breakLine();
    return lines;
  }

  static (List<int>, int) _readLiteralString(String content, int start) {
    final bytes = <int>[];
    var depth = 0;
    var index = start;
    while (index < content.length) {
      final char = content[index];
      if (char == '\\') {
        index += 1;
        if (index >= content.length) {
          break;
        }
        final escaped = content[index];
        switch (escaped) {
          case 'n':
            bytes.add(0x0a);
          case 'r':
            bytes.add(0x0d);
          case 't':
            bytes.add(0x09);
          case 'b':
            bytes.add(0x08);
          case 'f':
            bytes.add(0x0c);
          case '\r':
            if (index + 1 < content.length && content[index + 1] == '\n') {
              index += 1;
            }
          case '\n':
            break;
          default:
            final octal = RegExp(r'[0-7]{1,3}').matchAsPrefix(content, index);
            if (octal != null) {
              bytes.add(int.parse(octal.group(0)!, radix: 8) & 0xff);
              index = octal.end - 1;
            } else {
              bytes.add(content.codeUnitAt(index) & 0xff);
            }
        }
        index += 1;
        continue;
      }
      if (char == '(') {
        depth += 1;
        if (depth > 1) {
          bytes.add(0x28);
        }
      } else if (char == ')') {
        depth -= 1;
        if (depth == 0) {
          return (bytes, index + 1);
        }
        bytes.add(0x29);
      } else {
        bytes.add(content.codeUnitAt(index) & 0xff);
      }
      index += 1;
    }
    return (bytes, content.length);
  }

  static List<int> _hexBytes(String hex) {
    final compact = hex.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    final padded = compact.length.isOdd ? '${compact}0' : compact;
    return [
      for (var i = 0; i + 1 < padded.length; i += 2)
        int.parse(padded.substring(i, i + 2), radix: 16),
    ];
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
        if (day.weekday != DateTime.saturday &&
            day.weekday != DateTime.sunday) {
          dates.add(day);
        }
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

  static List<Uint8List> _decodedStreams(Uint8List bytes) {
    final streams = <Uint8List>[];
    var totalBytes = 0;
    var scannedStreams = 0;
    final pattern = RegExp(r'stream\r?\n');
    final source = latin1.decode(bytes, allowInvalid: true);
    for (final match in pattern.allMatches(source)) {
      if (++scannedStreams > 1000) throw const _PdfLimitException();
      final start = match.end;
      final end = source.indexOf('endstream', start);
      if (end < 0) {
        continue;
      }
      final headerLimit = match.start > 8192 ? match.start - 8192 : 0;
      final headerSlice = source.substring(headerLimit, match.start);
      final headerStart = headerSlice.lastIndexOf('obj');
      final header = headerStart < 0 ? headerSlice : headerSlice.substring(headerStart);
      final raw = bytes.sublist(start, end);
      final trimmed = _trimLineBreaks(raw);
      if (!header.contains('/FlateDecode')) {
        totalBytes += trimmed.length;
        if (totalBytes > _maxDecodedPdfBytes) throw const _PdfLimitException();
        streams.add(trimmed);
        continue;
      }
      try {
        final sink = _BoundedPdfSink(_maxDecodedPdfBytes - totalBytes);
        final decoder = zlib.decoder.startChunkedConversion(sink);
        for (var offset = 0; offset < trimmed.length; offset += 4096) {
          final end = offset + 4096 < trimmed.length ? offset + 4096 : trimmed.length;
          decoder.add(trimmed.sublist(offset, end));
        }
        decoder.close();
        final decoded = sink.bytes.takeBytes();
        totalBytes += decoded.length;
        streams.add(decoded);
      } on _PdfLimitException {
        rethrow;
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
            if (from > 65535 || to > 0x10ffff || map.length >= 65536) {
              throw const _PdfLimitException();
            }
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
          if (to < from || to - from > 65535 || map.length + to - from + 1 > 65536 ||
              target + to - from > 0x10ffff) {
            throw const _PdfLimitException();
          }
          for (var code = from; code <= to; code += 1) {
            map[code] = String.fromCharCode(target + code - from);
          }
        }
      }
    }
    return map;
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

class _PdfStringToken {
  const _PdfStringToken(this.bytes, {required this.isHex});

  final List<int> bytes;
  final bool isHex;

  String decode(Map<int, String> cmap) {
    bool printable(List<int> values) =>
        values.every((value) => value >= 0x20 && value != 0x7f);
    String? twoByte() {
      if (bytes.length.isOdd || bytes.isEmpty) {
        return null;
      }
      final buffer = StringBuffer();
      var matched = 0;
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        final value = cmap[(bytes[i] << 8) + bytes[i + 1]];
        if (value != null) {
          matched += 1;
          buffer.write(value);
        }
      }
      return matched == 0 ? null : buffer.toString();
    }

    if (!isHex && printable(bytes)) {
      // Simple (WinAnsi) fonts draw ASCII digits and punctuation directly.
      return String.fromCharCodes(bytes);
    }
    final cid = twoByte();
    if (cid != null) {
      return cid;
    }
    return printable(bytes) ? String.fromCharCodes(bytes) : '';
  }
}

const _maxDecodedPdfBytes = 64 * 1024 * 1024;

class _PdfLimitException extends FormatException {
  const _PdfLimitException() : super('Calendar PDF exceeds processing limits');
}

class _BoundedPdfSink extends ByteConversionSink {
  _BoundedPdfSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > limit) throw const _PdfLimitException();
    bytes.add(chunk);
  }

  @override
  void close() {}
}

class GakujoPdfText {
  const GakujoPdfText({
    required this.text,
    required this.actualTexts,
  });

  final String text;
  final List<String> actualTexts;
}
