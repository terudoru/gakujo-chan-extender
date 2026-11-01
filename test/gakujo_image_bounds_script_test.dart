import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_image_bounds_script.dart';
import 'package:test/test.dart';

void main() {
  test('checks image headers before decoding for supported formats', () async {
    final result = await Process.run('node', [
      'test/support/gakujo_image_bounds_harness.cts',
      GakujoImageBoundsScript.source,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });
}
