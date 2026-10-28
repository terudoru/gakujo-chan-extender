import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_preview_script.dart';

void main() {
  test(
    'remote preview validates requests and handles bounded responses',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'remote-preview-',
      );
      try {
        final script = File('${directory.path}/preview.js');
        await script.writeAsString(GakujoUploadPreviewScript.build());
        final result = await Process.run('node', [
          'test/remote_file_preview.mjs',
          script.path,
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
