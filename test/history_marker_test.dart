import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('history marker tracks dialogs and preview buttons in frames', () async {
    final result = await Process.run('node', ['test/history_marker.mts']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
