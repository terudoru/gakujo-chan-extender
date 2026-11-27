import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'gakujo_academic_calendar_pdf_limits.dart';

const coursePlannerBalancePdfLimit = 2 * 1024 * 1024;
const _reportTitle = '履修科目確認表';
const _dayColumn = '既修得単位(昼間)';
const _nightColumn = '既修得単位(夜間)';
final _units = RegExp(r'^\*?\d{1,4}(?:\.\d{1,2})?$');
final _privateLabel = RegExp(
  r'https?:|[@<>]|学籍番号|在籍番号|学生番号|氏名|メールアドレス|電話番号|\b\d{2}[A-Za-z]\d{4}[A-Za-z]\b|\d{7,}',
  caseSensitive: false,
);

String _normalize(String text) => String.fromCharCodes(
  text.runes.map((code) {
    if (code >= 0xff01 && code <= 0xff5e) return code - 0xfee0;
    return switch (code) {
      0x3000 => 0x20,
      0x2f6c => 0x76ee, // Kangxi radical eye, often used for 目 in PDFs.
      0x2f47 => 0x65e5, // Kangxi radical sun, often used for 日.
      0x2f49 => 0x6708, // Kangxi radical moon, often used for 月.
      _ => code,
    };
  }),
).trim();

typedef _Cell = ({
  String text,
  double left,
  double right,
  double y,
  double height,
});
double _center(_Cell cell) => (cell.left + cell.right) / 2;
String _heading(_Cell cell) => cell.text.replaceAll(RegExp(r'\s+'), '');

List<List<_Cell>> _lines(PdfPageText page) {
  final cells = <_Cell>[
    for (final run in page.runs)
      if (_normalize(run.text).isNotEmpty &&
          run.transform.b.abs() < .01 &&
          run.transform.c.abs() < .01 &&
          run.bounds.width > 0)
        (
          text: _normalize(run.text),
          left: run.bounds.left,
          right: run.bounds.right,
          y: run.transform.f,
          height: run.bounds.height,
        ),
  ]..sort((a, b) => b.y.compareTo(a.y));
  final lines = <List<_Cell>>[];
  for (final cell in cells) {
    if (lines.isEmpty || (lines.last.first.y - cell.y).abs() > 2) lines.add([]);
    lines.last.add(cell);
  }
  return lines.map((line) {
    final joined = <_Cell>[];
    for (final cell in line..sort((a, b) => a.left.compareTo(b.left))) {
      final previous = joined.lastOrNull;
      final gap = previous == null
          ? double.infinity
          : cell.left - previous.right;
      if (previous != null &&
          gap >= -cell.height * .35 &&
          gap <= math.max(1, cell.height * .23)) {
        joined[joined.length - 1] = (
          text: previous.text + cell.text,
          left: previous.left,
          right: math.max(previous.right, cell.right),
          y: previous.y,
          height: math.max(previous.height, cell.height),
        );
      } else {
        joined.add(cell);
      }
    }
    return joined;
  }).toList();
}

typedef _Grid = ({
  double left,
  double right,
  double day,
  double night,
  double step,
});

_Grid? _gridAt(List<List<_Cell>> lines, int index) {
  final sub = lines[index]
      .where((cell) => const {'昼間', '夜間'}.contains(_heading(cell)))
      .toList();
  if (sub.map(_heading).join('/') != '昼間/夜間/昼間/夜間') return null;
  final anchors = sub.map(_center).toList();
  final step = (anchors.last - anchors.first) / 3;
  if (step < 8 ||
      [for (var i = 1; i < 4; i++) anchors[i] - anchors[i - 1]]
          .any((distance) => (distance - step).abs() > step * .22)) {
    return null;
  }
  final header = lines
      .skip(math.max(0, index - 3))
      .take(math.min(3, index) + 1)
      .expand((line) => line)
      .where((cell) => cell.y - sub.first.y < sub.first.height * 3);
  bool group(Set<String> names, int left, int right) => header.any(
    (cell) =>
        names.contains(_heading(cell)) &&
        _center(cell) >= anchors[left] &&
        _center(cell) <= anchors[right],
  );
  if (!group(const {'履修単位', '履修単位数'}, 0, 1) ||
      !group(const {'既修得単位', '既修得単位数'}, 2, 3)) {
    return null;
  }
  final edge = anchors.first - step / 2;
  final labels =
      header
          .where(
            (cell) =>
                const {'区分', '科目区分'}.contains(_heading(cell)) &&
                _center(cell) < edge,
          )
          .toList()
        ..sort((a, b) => b.left.compareTo(a.left));
  if (labels.isEmpty) return null;
  final label = labels.first;
  return (
    left: 2 * _center(label) - edge - label.height,
    right: edge,
    day: anchors[2],
    night: anchors[3],
    step: step,
  );
}

List<String>? _balanceRow(List<_Cell> line, _Grid grid) {
  final label = line
      .where((cell) => cell.left >= grid.left && cell.right < grid.right)
      .map((cell) => cell.text)
      .join('')
      .trim();
  if (label.isEmpty ||
      label.length > 140 ||
      _privateLabel.hasMatch(label) ||
      _units.hasMatch(label)) {
    return null;
  }
  String? column(double x) {
    final found = line
        .where((cell) => (_center(cell) - x).abs() < grid.step * .46)
        .toList();
    if (found.isEmpty) return '';
    if (found.length != 1) return null;
    final value = found.single.text;
    if (const {'-', '—', '―'}.contains(value)) return '';
    return _units.hasMatch(value) ? value : null;
  }

  final day = column(grid.day), night = column(grid.night);
  if (day == null || night == null || (day.isEmpty && night.isEmpty)) {
    return null;
  }
  return [label, day, night];
}

/// Projects only the right-hand earned-credit columns of the official report.
/// Student identifiers, the timetable, and the active enrollment columns stay in memory.
Map<String, dynamic>? readCoursePlannerBalancePdf(Uint8List bytes) {
  if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
    return null;
  }
  checkAcademicCalendarPdfLimits(
    bytes,
    maxInputBytes: coursePlannerBalancePdfLimit,
  );
  final document = PdfDocument.open(bytes);
  if (document.pageCount > 150) return null;
  final rows = <List<String>>[];
  for (var index = 0; index < document.pageCount; index++) {
    checkAcademicCalendarPdfOperands(document.page(index).contentBytes());
    final lines = _lines(PdfTextExtractor.extract(document, index));
    if (index == 0 &&
        !lines
            .take(12)
            .expand((line) => line)
            .any((cell) => _heading(cell) == _reportTitle)) {
      return null;
    }
    _Grid? grid;
    for (final (index, line) in lines.indexed) {
      final found = _gridAt(lines, index);
      if (found != null) {
        grid = found;
        continue;
      }
      if (grid == null) continue;
      if (_balanceRow(line, grid) case final row?) rows.add(row);
    }
  }
  if (rows.isEmpty) return null;
  return {
    'v': 1,
    'kind': 'balances',
    'tables': [
      {
        'heading': _reportTitle,
        'rows': [
          ['科目区分', _dayColumn, _nightColumn],
          ...rows,
        ],
      },
    ],
  };
}
