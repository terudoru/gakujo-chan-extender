import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_preview_script.dart';

void main() {
  test(
    'submitted file preview button preserves the original download link',
    () async {
      final dir = await Directory.systemTemp.createTemp('submitted-preview-');
      try {
        final script = File('${dir.path}/preview.js');
        await script.writeAsString(GakujoUploadPreviewScript.build());
        final result = await Process.run('node', [
          'test/submitted_download_capture.mjs',
          script.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
