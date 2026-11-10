import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TextPreview extends StatefulWidget {
  const TextPreview({super.key, required this.title, required this.text, this.note, required this.onMessage});
  final String title;
  final String text;
  final String? note;
  final ValueChanged<String> onMessage;

  @override
  State<TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<TextPreview> {
  static const _matchLimit = 10000;
  late final List<String> _lines = widget.text.split('\n');
  late final int _longestLine = _lines.fold<int>(0, (n, line) => math.max(n, line.length));
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _heights = <int, double>{};
  final _matches = <({int line, int start, int end})>[];
  final _byLine = <int, List<int>>{};
  int _current = 0, _generation = 0;
  bool _searchOpen = false, _wrap = true, _mono = false, _limited = false;
  bool _noteDismissed = false;
  double _fontSize = 16, _width = 0;

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _find(String query) async {
    final generation = ++_generation;
    setState(() { _matches.clear(); _byLine.clear(); _current = 0; _limited = false; });
    final matches = <({int line, int start, int end})>[];
    final byLine = <int, List<int>>{};
    var work = 0;
    var limited = false;
    if (query.isNotEmpty) {
      for (var line = 0; line < _lines.length; line++) {
        var from = 0;
        while (from <= _lines[line].length - query.length) {
          final found = _lines[line].indexOf(query, from);
          if (found < 0) break;
          if (matches.length == _matchLimit) { limited = true; break; }
          (byLine[line] ??= []).add(matches.length);
          matches.add((line: line, start: found, end: found + query.length));
          from = found + query.length;
          if (++work % 500 == 0) {
            await Future<void>.delayed(Duration.zero);
            if (!mounted || generation != _generation) return;
          }
        }
        if (limited) break;
        work += _lines[line].length + 1;
        if (work >= 32000) {
          work = 0;
          await Future<void>.delayed(Duration.zero);
          if (!mounted || generation != _generation) return;
        }
      }
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _matches..clear()..addAll(matches);
      _byLine..clear()..addAll(byLine);
      _current = 0;
      _limited = limited;
    });
    if (matches.isNotEmpty) unawaited(_scrollToCurrent());
  }

  TextStyle get _style => TextStyle(fontSize: _fontSize, fontFamily: _mono ? 'monospace' : null, height: 1.4);

  double _height(int index) => _heights.putIfAbsent(index, () {
    final painter = TextPainter(
      text: TextSpan(text: _lines[index].isEmpty ? ' ' : _lines[index], style: DefaultTextStyle.of(context).style.merge(_style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: _width);
    final height = painter.height;
    painter.dispose();
    return height;
  });

  Future<void> _scrollToCurrent() async {
    if (_matches.isEmpty || !_scroll.hasClients || _width <= 0) return;
    final target = _matches[_current].line;
    final generation = _generation;
    var offset = 0.0;
    for (var i = 0; i < target; i++) {
      offset += _height(i);
      if (i % 500 == 499) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted || generation != _generation || !_scroll.hasClients ||
            _matches.isEmpty || _matches[_current].line != target) return;
      }
    }
    if (_scroll.hasClients) _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  void _move(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _current = (_current + delta + _matches.length) % _matches.length);
    unawaited(_scrollToCurrent());
  }

  InlineSpan _lineSpan(int line) {
    final text = _lines[line];
    final indices = _byLine[line];
    if (indices == null) return TextSpan(text: text.isEmpty ? ' ' : text);
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final index in indices) {
      final match = _matches[index];
      spans.add(TextSpan(text: text.substring(offset, match.start)));
      spans.add(TextSpan(text: text.substring(match.start, match.end),
        style: TextStyle(backgroundColor: index == _current ? Colors.orange : Colors.yellow)));
      offset = match.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    void resize(double change) => setState(() { _fontSize = (_fontSize + change).clamp(10, 32); _heights.clear(); });
    void option(String value) => setState(() {
      if (value == 'wrap') _wrap = !_wrap;
      if (value == 'mono') _mono = !_mono;
      _heights.clear();
    });
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => widget.onMessage('mbg-preview-close')},
      child: Focus(autofocus: true, child: Scaffold(
        appBar: AppBar(
          toolbarHeight: narrow ? 48 : null,
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: '検索', onPressed: () => setState(() => _searchOpen = !_searchOpen), icon: const Icon(Icons.search)),
            IconButton(tooltip: '縮小', onPressed: () => resize(-2), icon: const Icon(Icons.text_decrease)),
            IconButton(tooltip: '拡大', onPressed: () => resize(2), icon: const Icon(Icons.text_increase)),
            PopupMenuButton<String>(tooltip: 'その他', onSelected: option, itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'wrap', checked: _wrap, child: const Text('折り返し')),
              CheckedPopupMenuItem(value: 'mono', checked: _mono, child: const Text('等幅')),
            ]),
            IconButton(tooltip: '閉じる', onPressed: () => widget.onMessage('mbg-preview-close'), icon: const Icon(Icons.close)),
          ],
          bottom: _searchOpen ? PreferredSize(preferredSize: const Size.fromHeight(52), child: Row(children: [
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: TextField(
              controller: _search, autofocus: true, onChanged: _find,
              decoration: const InputDecoration(hintText: '検索', isDense: true),
            ))),
            Text('${_matches.isEmpty ? 0 : _current + 1} / ${_matches.length}${_limited ? '+' : ''}'),
            IconButton(tooltip: '前の検索結果', onPressed: () => _move(-1), icon: const Icon(Icons.keyboard_arrow_up)),
            IconButton(tooltip: '次の検索結果', onPressed: () => _move(1), icon: const Icon(Icons.keyboard_arrow_down)),
          ])) : null,
        ),
        body: Column(children: [
          if (widget.note != null && widget.note!.isNotEmpty && !_noteDismissed)
            MaterialBanner(content: Text(widget.note!), actions: [TextButton(onPressed: () => setState(() => _noteDismissed = true), child: const Text('閉じる'))]),
          if (_limited) const Text('検索結果は10000件まで表示しています。'),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            final longest = _wrap ? 0 : _longestLine;
            final width = _wrap ? constraints.maxWidth : math.max(constraints.maxWidth, math.min(20000.0, longest * _fontSize * 1.2));
            final contentWidth = math.max(1.0, width - 16);
            if (_width != contentWidth) { _width = contentWidth; _heights.clear(); }
            final list = SizedBox(width: width, child: SelectionArea(child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _lines.length,
              itemExtentBuilder: (index, dimensions) => _height(index),
              itemBuilder: (context, index) => Text.rich(_lineSpan(index), style: _style),
            )));
            return _wrap ? list : SingleChildScrollView(scrollDirection: Axis.horizontal, child: list);
          })),
        ]),
      )),
    );
  }
}
