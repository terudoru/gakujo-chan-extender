import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mbg_pdf_preview/bounded_text_searcher.dart';
import 'package:pdfrx/pdfrx.dart';

class _Page extends Fake implements PdfPage {
  _Page(this.pageNumber);
  @override
  final int pageNumber;
}

class _Document extends Fake implements PdfDocument {
  _Document(int count) : pages = List.generate(count, (i) => _Page(i + 1));
  @override
  final List<PdfPage> pages;
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
}

class _Controller extends PdfViewerController {
  _Controller(this.testDocument);
  final PdfDocument testDocument;
  @override
  bool get isReady => true;
  @override
  PdfDocument get document => testDocument;
  @override
  void invalidate() {}
  @override
  FutureOr<T?> useDocument<T>(FutureOr<T> Function(PdfDocument) task,
      {bool ensureLoaded = true, Completer? cancelLoading}) => task(testDocument);
}

class _Searcher extends BoundedPdfTextSearcher {
  _Searcher(super.controller, this.texts);
  final List<String> texts;
  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async => PdfPageText(
    pageNumber: pageNumber,
    fullText: texts[pageNumber - 1],
    charRects: const [],
    fragments: const [],
  );
}

Future<void> _search(_Searcher searcher, String query) async {
  final done = Completer<void>();
  void listener() {
    if (!searcher.isSearching && !done.isCompleted) done.complete();
  }
  searcher.addListener(listener);
  searcher.startTextSearch(query, searchImmediately: true, goToFirstMatch: false);
  await done.future.timeout(const Duration(seconds: 10));
  searcher.removeListener(listener);
}

void main() {
  test('normal multi-page search and match limit', () async {
    final searcher = _Searcher(_Controller(_Document(2)), ['Hello hello', 'hello world']);
    await _search(searcher, 'hello');
    expect(searcher.matches.length, 3);
    expect(searcher.limited, false);
    searcher.dispose();

    final many = _Searcher(_Controller(_Document(1)), ['a' * 6000]);
    await _search(many, 'a');
    expect(many.matches.length, 5000);
    expect(many.limited, true);
    many.dispose();
  });

  test('search stops after its aggregate text budget', () async {
    final searcher = _Searcher(_Controller(_Document(6)), List.filled(6, 'x' * 100000));
    await _search(searcher, 'z');
    expect(searcher.matches, isEmpty);
    expect(searcher.limited, true);
    searcher.dispose();
  });
}
