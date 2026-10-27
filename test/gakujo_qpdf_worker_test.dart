import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('qpdf worker preserves PDF content and rejects unsafe input', () async {
    final result = await Process.run('node', [
      'test/qpdf_worker_integration.mjs',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
