import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_preview_script.dart';

void main() {
  test('preview cancellation and page changes keep work bounded', () async {
    final directory = await Directory.systemTemp.createTemp('preview-lifecycle-');
    try {
      final script = File('${directory.path}/preview.js');
      await script.writeAsString(GakujoUploadPreviewScript.build());
      final result = await Process.run('node', [
        'test/upload_preview_lifecycle.mjs',
        script.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
