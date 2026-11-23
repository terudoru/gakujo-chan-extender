import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/generated/assignment_attachment.g.dart';

void main() {
  test(
    'desktop file drops select only valid attachments for the target input',
    () async {
      final dir = await Directory.systemTemp.createTemp('mbg-attachment-drop-');
      try {
        final script = File('${dir.path}/attachment.js');
        await script.writeAsString(
          gakujoAssignmentAttachmentJs({
            'scan': false,
            'shared': false,
            'drop': true,
          }),
        );
        final result = await Process.run('node', [
          'test/desktop_attachment_drop.mjs',
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
