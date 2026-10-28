import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mac trackpad momentum navigates once per gesture', () async {
    final directory = await Directory.systemTemp.createTemp('macos-swipe-');
    try {
      final binary = '${directory.path}/swipe-test';
      final compile = await Process.run('xcrun', [
        'swiftc',
        'macos/Runner/MacosHistorySwipeTracker.swift',
        'test/macos_history_swipe_test.swift',
        '-o',
        binary,
      ]);
      expect(compile.exitCode, 0,
          reason: '${compile.stdout}\n${compile.stderr}');
      final result = await Process.run(binary, []);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isMacOS);
}
