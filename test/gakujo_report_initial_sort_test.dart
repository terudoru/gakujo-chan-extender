import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/generated/report_sorter.g.dart';

void main() {
  final orders = <GakujoReportInitialSort, List<String>>{
    GakujoReportInitialSort.deadline: ['b', 'a', 'c'],
    GakujoReportInitialSort.original: ['c', 'a', 'b'],
    GakujoReportInitialSort.title: ['a', 'b', 'c'],
    GakujoReportInitialSort.courseNumber: ['c', 'b', 'a'],
  };
  for (final sort in GakujoReportInitialSort.values) {
    test('Dart injection and DOM initial order: ${sort.name}', () async {
      final script = gakujoPageScriptBuilders(
        GakujoAppSettings(reportInitialSort: sort),
      )['report']!();
      expect(script, contains(jsonEncode({'initialSort': sort.name})));
      final next = sort == GakujoReportInitialSort.courseNumber
          ? GakujoReportInitialSort.deadline
          : GakujoReportInitialSort.courseNumber;
      await _checkDom(
        script,
        orders[sort]!,
        gakujoPageScriptBuilders(
          GakujoAppSettings(reportInitialSort: next),
        )['report']!(),
        orders[next]!,
      );
    });
  }
  test(
    'DOM unknown initial order falls back to existing deadline sort',
    () async {
      await _checkDom(
        gakujoReportSorterJs({'initialSort': 'future-value'}),
        orders[GakujoReportInitialSort.deadline]!,
        gakujoReportSorterJs({'initialSort': 'original'}),
        orders[GakujoReportInitialSort.original]!,
      );
    },
  );
}

Future<void> _checkDom(
  String script,
  List<String> expected,
  String reconfigureScript,
  List<String> reconfiguredExpected,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'report-initial-sort-',
  );
  try {
    final fixture = File.fromUri(directory.uri.resolve('fixture.json'));
    await fixture.writeAsString(
      jsonEncode({
        'script': script,
        'expected': expected,
        'reconfigureScript': reconfigureScript,
        'reconfiguredExpected': reconfiguredExpected,
      }),
    );
    final result = await Process.run('node', [
      'test/support/report_sorter_initial_sort_harness.cts',
      fixture.path,
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  } finally {
    await directory.delete(recursive: true);
  }
}
