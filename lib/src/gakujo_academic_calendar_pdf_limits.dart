import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

const _maxDecodedBytes = 64 * 1024 * 1024;
const _maxStreams = 1000;
const _maxMappings = 65536;
const _maxOperands = 1024;
const _limitExceeded = FormatException('Calendar PDF exceeds processing limits');
const _unsupported = FormatException('Unsupported calendar PDF stream');

/// Checks the complete file, including unreferenced streams, before the PDF
/// reader can inflate cross-reference or object streams.
void checkAcademicCalendarPdfLimits(
  Uint8List bytes, {
  required int maxInputBytes,
}) {
  if (bytes.length > maxInputBytes) throw _limitExceeded;
  final parser = CosParser(bytes);
  var decodedBytes = 0;
  var streams = 0;
  var mappings = 0;
  while (parser.peekToken().type != CosTokenType.eof) {
    final token = parser.peekToken();
    if (token.isKeyword('trailer')) {
      parser.nextToken();
      final trailer = parser.parseObject();
      if (trailer is CosDictionary && trailer.containsKey('Encrypt')) {
        throw _unsupported;
      }
      continue;
    }
    if (token.type != CosTokenType.integer ||
        parser.peekToken(1).type != CosTokenType.integer ||
        !parser.peekToken(2).isKeyword('obj')) {
      parser.nextToken();
      continue;
    }
    final object = parser.parseIndirectObject().object;
    if (object is! CosStream) continue;
    if (++streams > _maxStreams) throw _limitExceeded;
    _checkStreamDictionary(object);

    final filter = object.dictionary['Filter'];
    var decoded = object.rawBytes;
    if (filter is CosName) {
      final sink = _BoundedPdfSink(_maxDecodedBytes - decodedBytes);
      final decoder = zlib.decoder.startChunkedConversion(sink);
      const chunkSize = 4096;
      for (var start = 0; start < decoded.length; start += chunkSize) {
        final end = start + chunkSize;
        decoder.add(Uint8List.sublistView(
          decoded,
          start,
          end < decoded.length ? end : decoded.length,
        ));
      }
      decoder.close();
      decoded = sink.bytes.takeBytes();
    }
    decodedBytes += decoded.length;
    if (decodedBytes > _maxDecodedBytes) throw _limitExceeded;
    if (object.dictionary.typeName == 'ObjStm') {
      _checkCompressedObjects(object.dictionary, decoded);
    }
    mappings += _countCMapMappings(decoded, _maxMappings - mappings);
  }
}

void _checkStreamDictionary(CosStream stream) {
  final dict = stream.dictionary;
  final length = dict['Length'];
  final filter = dict['Filter'];
  if (length is! CosInteger ||
      length.value != stream.rawBytes.length ||
      dict.containsKey('Encrypt') ||
      (filter != null && (filter is! CosName || filter.value != 'FlateDecode'))) {
    throw _unsupported;
  }
  final params = dict['DecodeParms'] ?? dict['DP'];
  if (params == null) return;
  // The university's cross-reference streams use fixed-width PNG prediction.
  if (dict.typeName != 'XRef' || params is! CosDictionary) {
    throw _unsupported;
  }
  final predictor = params['Predictor'];
  final columns = params['Columns'];
  if (predictor is! CosInteger ||
      predictor.value != 12 ||
      columns is! CosInteger ||
      columns.value < 1 ||
      columns.value > 16 ||
      params.entries.length != 2) {
    throw _unsupported;
  }
}

void _checkCompressedObjects(CosDictionary dict, Uint8List decoded) {
  final first = dict['First'];
  final count = dict['N'];
  if (first is! CosInteger ||
      count is! CosInteger ||
      first.value < 0 ||
      first.value > decoded.length ||
      count.value < 0 ||
      count.value > first.value ~/ 4) {
    throw _unsupported;
  }
  final header = CosParser(Uint8List.sublistView(decoded, 0, first.value));
  final parser = CosParser(decoded);
  for (var index = 0; index < count.value; index++) {
    header.expectInteger();
    final offset = header.expectInteger();
    if (offset < 0 || offset >= decoded.length - first.value) {
      throw _unsupported;
    }
    parser.seek(first.value + offset);
    if (parser.parseObject() is CosStream) throw _unsupported;
  }
}

// The library eagerly expands ToUnicode ranges. Limit their size before it
// reads them, using its lexer so comments and adjacent hex strings work.
int _countCMapMappings(Uint8List data, int remaining) {
  final source = latin1.decode(data);
  final sections = RegExp(r'beginbf(?:char|range)');
  var count = 0;
  for (final section in sections.allMatches(source)) {
    final isRange = section.group(0) == 'beginbfrange';
    final parser = CosParser(data, offset: section.end);
    while (true) {
      final first = parser.nextToken();
      if (first.type != CosTokenType.hexString) break;
      if (first.bytesValue.length > 2) throw _limitExceeded;
      if (isRange) {
        final last = parser.nextToken();
        if (last.type != CosTokenType.hexString) break;
        if (last.bytesValue.length > 2) throw _limitExceeded;
        final startCode = _codeUnit(first.bytesValue);
        final endCode = _codeUnit(last.bytesValue);
        if (endCode < startCode) throw _limitExceeded;
        count += endCode - startCode + 1;
      } else {
        count++;
      }
      if (count > remaining) throw _limitExceeded;
      parser.parseObject();
    }
  }
  return count;
}

int _codeUnit(Uint8List bytes) {
  return bytes.fold(0, (code, byte) => (code << 8) | byte);
}

void checkAcademicCalendarPdfOperands(Uint8List content) {
  final lexer = CosLexer(content);
  final token = CosTokenBuffer();
  var pending = 0;
  while (lexer.nextToken(token).type != CosTokenType.eof) {
    if (token.type == CosTokenType.keyword) {
      pending = 0;
    } else if (++pending > _maxOperands) {
      throw _limitExceeded;
    }
  }
}

class _BoundedPdfSink extends ByteConversionSink {
  _BoundedPdfSink(this.limit);

  final int limit;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > limit) throw _limitExceeded;
    bytes.add(chunk);
  }

  @override
  void close() {}
}
