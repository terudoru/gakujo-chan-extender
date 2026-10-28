import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closing the preview terminates the PDF worker', () async {
    final result = await Process.run('node', [
      'test/pdf_preview_worker_cleanup.mjs',
      'assets/pdf_preview/web/assets/packages/pdfrx/assets/pdfium_client.js',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
