import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('page watcher handles mutations, frames, events and disposal', () async {
    final result = await Process.run('node', [
      'test/support/page_watch_test.mts',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
