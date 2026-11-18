import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_compression_libraries.dart';

void main() {
  test('PDF editing preserves existing pages and retries failed library loads', () async {
    final directory = await Directory.systemTemp.createTemp(
      'worksheet-editor-',
    );
    try {
      final script = File('${directory.path}/edit-library.js');
      final injection = GakujoUploadCompressionLibraries.buildInjectionScript(
        'preview-edit',
        [
          'worksheet-worker',
          'window.pdfjsLib = {loaded: true};',
          '{}',
          '{}',
          'if (window.fail) throw new Error("synthetic"); window.PDFLib = {};',
        ],
      );
      await script.writeAsString(
        GakujoUploadCompressionLibraries.acknowledgedInjectionScript(
          'preview-edit',
          injection,
        ),
      );
      final result = await Process.run('node', [
        'test/worksheet_editor.mts',
        script.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
