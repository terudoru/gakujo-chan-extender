import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'draft migration retries cleanup and respects remote deletion',
    () async {
      final result = await Process.run('node', [
        'test/support/report_draft_source_test.mts',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
