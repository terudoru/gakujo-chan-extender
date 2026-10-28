import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF outline limits preserve ordinary outlines', () async {
    final result = await Process.run('node', [
      'test/pdf_preview_outline_limits.mjs',
      'assets/pdf_preview/web/assets/packages/pdfrx/assets/pdfium_worker.js',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
  test('PDF text extraction is bounded and releases resources', () async {
    final result = await Process.run('node', [
      'test/pdf_preview_text_limits.mjs',
      'assets/pdf_preview/web/assets/packages/pdfrx/assets/pdfium_worker.js',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
