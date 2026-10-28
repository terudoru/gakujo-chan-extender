import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_preview_script.dart';

void main() {
  for (final compactAndroid in [true, false]) {
    test(
      'preview lifecycle stays bounded (Android layout: $compactAndroid)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'preview-lifecycle-',
        );
        try {
          final script = File('${directory.path}/preview.js');
          await script.writeAsString(
            GakujoUploadPreviewScript.build(compactAndroid: compactAndroid),
          );
          final result = await Process.run('node', [
            'test/upload_preview_lifecycle.mjs',
            script.path,
            compactAndroid ? 'android' : 'desktop',
          ]);
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );
  }
}
