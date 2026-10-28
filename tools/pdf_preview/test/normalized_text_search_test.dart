import 'package:flutter_test/flutter_test.dart';
import 'package:mbg_pdf_preview/normalized_text_search.dart';

void main() {
  String normalize(String value) => value
      .replaceAll('\ufedf', 'ل')
      .replaceAll('\ufecc', 'ع')
      .replaceAll('\ufe91', 'ب')
      .replaceAll('\ufbfe', 'ی')
      .replaceAll('\ufe94', 'ة')
      .replaceAll('\ufb01', 'fi')
      .replaceAll('e\u0301', 'é');

  test('maps compatibility and language variants to original PDF ranges', () {
    final text = '😀 اﻟﻌرﺑﯾﺔ';
    final matches = normalizedTextMatches(
      text,
      'العربية',
      normalize: normalize,
      caseInsensitive: true,
      maxMatches: 10,
    );
    expect(matches, [(start: 3, end: text.length)]);
    expect(text.substring(matches.single.start, matches.single.end), 'اﻟﻌرﺑﯾﺔ');
  });

  test(
    'matches reversed RTL text, composed accents and expanded ligatures',
    () {
      final rtl = normalizedTextMatches(
        'םולש',
        'שלום',
        normalize: normalize,
        caseInsensitive: true,
        maxMatches: 10,
      );
      expect(rtl, [(start: 0, end: 4)]);
      final matches = normalizedTextMatches(
        'A ﬁle e\u0301',
        'FILE',
        normalize: normalize,
        caseInsensitive: true,
        maxMatches: 10,
      );
      expect(matches, [(start: 2, end: 5)]);
      expect(
        normalizedTextMatches(
          'e\u0301',
          'é',
          normalize: normalize,
          caseInsensitive: true,
          maxMatches: 10,
        ),
        [(start: 0, end: 2)],
      );
    },
  );

  test('caps matches and preserves case-sensitive searches', () {
    expect(
      normalizedTextMatches(
        'a a a',
        'a',
        normalize: normalize,
        caseInsensitive: true,
        maxMatches: 2,
      ).length,
      2,
    );
    expect(
      normalizedTextMatches(
        'ABC',
        'abc',
        normalize: normalize,
        caseInsensitive: false,
        maxMatches: 2,
      ),
      isEmpty,
    );
  });

  test('bounds memory even when Unicode normalization expands characters', () {
    expect(
      () => normalizedTextMatches(
        'ﬁﬁﬁ',
        'f',
        normalize: normalize,
        caseInsensitive: true,
        maxMatches: 10,
        maxUnits: 5,
      ),
      throwsA(isA<NormalizedTextLimit>()),
    );
  });
}
