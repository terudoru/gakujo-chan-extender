// Adapted from pdfrx 2.10.1, Copyright (c) 2018 Takashi Kawasaki.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'normalized_text_search.dart';
import 'unicode_normalization.dart';

/// Helper class to interactively search text in a PDF document.
///
/// To be notified when the search status change, use [addListener].
class BoundedPdfTextSearcher extends Listenable {
  /// Creates a new instance of [PdfTextSearcher].
  BoundedPdfTextSearcher(this._controller) {
    _registerForDocumentChanges();
  }

  final PdfViewerController _controller;

  /// The [PdfViewerController] to use.
  PdfViewerController? get controller =>
      _controller.isReady ? _controller : null;

  Timer? _searchTextTimer; // timer to start search
  int _searchSession = 0; // current search session
  List<PdfPageTextRange> _matches = const [];
  List<int> _matchesPageStartIndices = const [];
  _SearchCondition? _lastSearchCondition;
  int? _currentIndex;
  PdfPageTextRange? _currentMatch;
  int? _searchingPageNumber;
  int? _totalPageCount;
  bool _isSearching = false;
  bool limited = false;
  static const int maxSearchCharacters = 500000;
  static const int maxMatches = 5000;
  final _cachedText = <int, PdfPageText>{};
  StreamSubscription<PdfDocumentEvent>? _documentEventSubscription;

  /// The current match index in [matches] if available.
  int? get currentIndex => _currentIndex;

  /// Get the current matches.
  List<PdfPageTextRange> get matches => _matches;

  /// Whether there are any matches or not (so far).
  bool get hasMatches => _currentIndex != null && matches.isNotEmpty;

  /// Whether the search task is currently running or not
  bool get isSearching => _isSearching;

  /// The page currently being searched.
  int? get searchingPageNumber => _searchingPageNumber;

  int? get totalPageCount => _totalPageCount;

  double? get searchProgress {
    if (_totalPageCount == null || _searchingPageNumber == null) return null;
    return _searchingPageNumber! / _totalPageCount!;
  }

  Pattern? get pattern => _lastSearchCondition?.pattern;

  int get searchSession => _searchSession;

  final List<VoidCallback> _listeners = [];

  void notifyListeners() {
    controller?.invalidate();
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Start a new search.
  ///
  /// [pattern] is the text to search for. It can be a [String] or a [RegExp].
  /// If [caseInsensitive] is true, the search will be case insensitive.
  /// If [goToFirstMatch] is true, the viewer will automatically go to the first match.
  /// If [searchImmediately] is true, the search will start immediately,
  /// otherwise it will wait for a short delay not to make the process too heavy.
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
    bool goToFirstMatch = true,
    bool searchImmediately = false,
  }) {
    // Re-issuing the running pattern must not cancel it: search() below would return early for an identical pattern,
    // leaving the matches half collected and isSearching stuck. Only drop a pending search for another pattern.
    _searchTextTimer?.cancel();
    final last = _lastSearchCondition;
    if (last != null &&
        last.caseInsensitive == caseInsensitive &&
        _isIdenticalPattern(last.pattern, pattern)) {
      return;
    }

    void search() {
      // Keep the active search alive until a debounced replacement actually starts.
      _cancelTextSearch();
      final searchSession = _searchSession;
      _lastSearchCondition = _SearchCondition(
        pattern: pattern,
        caseInsensitive: caseInsensitive,
        goToFirstMatch: goToFirstMatch,
      );
      if (pattern.isEmpty) {
        _resetTextSearch();
        return;
      }
      unawaited(_startTextSearchInternal(_lastSearchCondition!, searchSession));
    }

    if (searchImmediately) {
      search();
    } else {
      _searchTextTimer = Timer(const Duration(milliseconds: 500), search);
    }
  }

  /// Reset the current search.
  void resetTextSearch() => _resetTextSearch();

  /// Stop a running search and keep the matches found so far.
  ///
  /// Unlike [resetTextSearch], [matches] and the current match stay; re-issuing the same pattern with
  /// [startTextSearch] then searches the whole document again.
  void stopTextSearch() {
    if (!_isSearching && _searchTextTimer?.isActive != true) return;
    _cancelTextSearch();
    _isSearching = false;
    _lastSearchCondition = null;
    notifyListeners();
  }

  /// Almost identical to [resetTextSearch], but does not notify listeners.
  void dispose() {
    unawaited(_documentEventSubscription?.cancel());
    _listeners.clear();
    _cachedText.clear();
    _resetTextSearch(notify: false);
  }

  void _resetTextSearch({bool notify = true}) {
    _cancelTextSearch();
    _matches = const [];
    _matchesPageStartIndices = const [];
    _searchingPageNumber = null;
    _currentIndex = null;
    _currentMatch = null;
    _isSearching = false;
    _lastSearchCondition = null;
    limited = false;
    if (notify) {
      notifyListeners();
    }
  }

  void _cancelTextSearch() {
    _searchTextTimer?.cancel();
    ++_searchSession;
  }

  Future<void> _startTextSearchInternal(
    _SearchCondition condition,
    int searchSession,
  ) async {
    _isSearching = controller != null;
    await controller?.useDocument((document) async {
      if (searchSession != _searchSession) return;
      final textMatches = <PdfPageTextRange>[];
      final textMatchesPageStartIndex = <int>[];
      var first = true;
      var searchedCharacters = 0;
      limited = false;
      _isSearching = true;
      _matches = const [];
      _matchesPageStartIndices = const [];
      // The previous pattern's position does not index into the new matches.
      _currentIndex = null;
      _currentMatch = null;
      _totalPageCount = document.pages.length;
      notifyListeners();
      for (final page in document.pages) {
        _searchingPageNumber = page.pageNumber;
        if (searchSession != _searchSession) return;
        PdfPageText? pageText;
        try {
          pageText = await loadText(pageNumber: page.pageNumber);
        } catch (_) {
          if (searchSession != _searchSession) return;
          limited = true;
          _isSearching = false;
          notifyListeners();
          return;
        }
        if (searchSession != _searchSession) return;
        if (pageText == null) continue;
        searchedCharacters += pageText.fullText.length;
        if (searchedCharacters > maxSearchCharacters) {
          limited = true;
          _isSearching = false;
          notifyListeners();
          return;
        }
        textMatchesPageStartIndex.add(textMatches.length);
        late final Stream<PdfPageTextRange> matches;
        try {
          matches = condition.pattern is String
              ? Stream.fromIterable(normalizedTextMatches(
                pageText.fullText,
                condition.pattern as String,
                normalize: normalizeSearchText,
                caseInsensitive: condition.caseInsensitive,
                maxMatches: maxMatches - textMatches.length,
              ).map((range) => PdfPageTextRange(
                pageText: pageText!, start: range.start, end: range.end,
              )))
              : pageText.allMatches(condition.pattern,
                  caseInsensitive: condition.caseInsensitive);
        } on NormalizedTextLimit {
          limited = true;
          _isSearching = false;
          notifyListeners();
          return;
        }
        await for (final f in matches) {
          if (searchSession != _searchSession) return;
          textMatches.add(f);
          if (textMatches.length >= maxMatches) {
            limited = true;
            break;
          }
        }
        _matches = List.unmodifiable(textMatches);
        _matchesPageStartIndices = List.unmodifiable(textMatchesPageStartIndex);
        _isSearching = !limited && page.pageNumber < document.pages.length;
        notifyListeners();

        if (_matches.isNotEmpty && first) {
          first = false;
          if (condition.goToFirstMatch) {
            _currentIndex = 0;
            _currentMatch = null;
            unawaited(goToMatchOfIndex(_currentIndex!));
          }
        }
        if (limited) return;
      }
    });
  }

  void _registerForDocumentChanges() {
    unawaited(_documentEventSubscription?.cancel());
    _documentEventSubscription = controller!.document.events.listen((event) {
      if (event is PdfDocumentPageStatusChangedEvent) {
        final changedPages = event.changes.keys.toSet();
        final needRestart = _matches.any(
          (m) => changedPages.contains(m.pageNumber),
        );
        if (needRestart) {
          _restartSearch();
        }
      }
    });
  }

  void _restartSearch() {
    final condition = _lastSearchCondition;
    // Clearing the condition lets startTextSearch run the same pattern again.
    _resetTextSearch();
    _cachedText.clear();
    if (condition != null) {
      startTextSearch(
        condition.pattern,
        caseInsensitive: condition.caseInsensitive,
        goToFirstMatch: condition.goToFirstMatch,
      );
    }
  }

  /// Just a helper function to load the text of a page.
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    final cached = _cachedText[pageNumber];
    if (cached != null) return cached;
    return await controller?.useDocument((document) async {
      final text = await document.pages[pageNumber - 1].loadStructuredText();
      if (_cachedText.length >= 4) _cachedText.remove(_cachedText.keys.first);
      _cachedText[pageNumber] = text;
      return text;
    });
  }

  /// Go to the previous match.
  Future<int> goToPrevMatch() async {
    if (_currentIndex == null) {
      _currentIndex = _matches.length - 1;
      return await goToMatchOfIndex(_currentIndex!);
    }
    if (_currentIndex! > 0) {
      _currentIndex = _currentIndex! - 1;
      return await goToMatchOfIndex(_currentIndex!);
    }
    return -1;
  }

  /// Go to the next match.
  Future<int> goToNextMatch() async {
    if (_currentIndex == null) {
      _currentIndex = 0;
      return await goToMatchOfIndex(_currentIndex!);
    }
    if (_currentIndex! + 1 < _matches.length) {
      _currentIndex = _currentIndex! + 1;
      return await goToMatchOfIndex(_currentIndex!);
    }
    return -1;
  }

  /// Go to the given match.
  Future<void> goToMatch(PdfPageTextRange match) async {
    _currentMatch = match;
    _currentIndex = _matches.indexOf(match);
    await controller?.ensureVisible(
      controller!.calcRectForRectInsidePage(
        pageNumber: match.pageNumber,
        rect: match.bounds,
      ),
      margin: 50,
    );
    controller?.setCurrentPageNumber(match.pageNumber);
    controller?.invalidate();
    notifyListeners();
  }

  /// Get the matches range for the given page number.
  ({int start, int end})? getMatchesRangeForPage(int pageNumber) {
    if (_matchesPageStartIndices.length < pageNumber) return null;
    final start = _matchesPageStartIndices[pageNumber - 1];
    final end = _matchesPageStartIndices.length > pageNumber
        ? _matchesPageStartIndices[pageNumber]
        : _matches.length;
    return (start: start, end: end);
  }

  /// Go to the match of the given index.
  Future<int> goToMatchOfIndex(int index) async {
    if (index < 0 || index >= _matches.length) return -1;
    _currentIndex = index;
    await goToMatch(_matches[index]);
    return index;
  }

  /// Paint callback to highlight the matches.
  ///
  /// Use this with [PdfViewerParams.pagePaintCallbacks] to highlight the matches.
  void pageTextMatchPaintCallback(
    ui.Canvas canvas,
    Rect pageRect,
    PdfPage page,
  ) {
    final range = getMatchesRangeForPage(page.pageNumber);
    if (range == null) return;

    final matchTextColor =
        controller?.params.matchTextColor ?? Colors.yellow.withAlpha(127);
    final activeMatchTextColor =
        controller?.params.activeMatchTextColor ?? Colors.orange.withAlpha(127);

    for (var i = range.start; i < range.end; i++) {
      final m = _matches[i];
      final rect = m.bounds
          .toRect(page: page, scaledPageSize: pageRect.size)
          .translate(pageRect.left, pageRect.top);
      canvas.drawRect(
        rect,
        Paint()
          ..color = m == _currentMatch ? activeMatchTextColor : matchTextColor,
      );
    }
  }

  @override
  VoidCallback addListener(VoidCallback listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
}

extension _PatternExts on Pattern {
  bool get isEmpty {
    switch (this) {
      case final String s:
        return s.isEmpty;
      case final RegExp r:
        return r.pattern.isEmpty;
      default:
        throw UnsupportedError('Pattern type not supported: $this');
    }
  }
}

class _SearchCondition {
  const _SearchCondition({
    required this.pattern,
    required this.caseInsensitive,
    required this.goToFirstMatch,
  });
  final Pattern pattern;
  final bool caseInsensitive;
  final bool goToFirstMatch;
}

bool _isIdenticalPattern(Pattern? a, Pattern? b) {
  if (a is String && b is String) {
    return a == b;
  }
  if (a is RegExp && b is RegExp) {
    return a.pattern == b.pattern &&
        a.isCaseSensitive == b.isCaseSensitive &&
        a.isMultiLine == b.isMultiLine &&
        a.isUnicode == b.isUnicode &&
        a.isDotAll == b.isDotAll;
  }
  if (a == null && b == null) {
    return true;
  }
  return false;
}
