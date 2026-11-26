import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('checks image headers before decoding for supported formats', () async {
    final result = await Process.run('node', [
      'test/support/gakujo_image_bounds_harness.mts',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });
}
