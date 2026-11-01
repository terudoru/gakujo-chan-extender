import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
  final start = source.indexOf('void CopyWideString(');
  final end = source.indexOf('\nbool ShowDeadlineToast(', start);
  final copy = source.substring(start, end);

  test('native URL policies preserve encoded values and require GET markers',
      () async {
    final result = await Process.run(
      'node',
      ['test/support/windows_url_policy_harness.cts'],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('balloon strings preserve code points at the 64 and 256 unit limits',
      () async {
    final result = await Process.run('node', ['test/support/windows_notification_copy_harness.cts', copy]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('both balloon buffers use the surrogate-safe copy', () {
    expect(
      source,
      contains(
        'CopyWideString(data.szInfoTitle, ARRAYSIZE(data.szInfoTitle), title)',
      ),
    );
    expect(
      source,
      contains('CopyWideString(data.szInfo, ARRAYSIZE(data.szInfo), body)'),
    );
  });
}
