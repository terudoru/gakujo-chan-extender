import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('download capture keeps repeated fields and the clicked course', () async {
    final result = await Process.run('node', [
      'test/support/download_correctness_source_test.mts',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
