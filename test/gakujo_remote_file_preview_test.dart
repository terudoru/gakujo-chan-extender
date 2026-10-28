import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_preview_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';

void main() {
  testWidgets('attachment dialog offers preview, download and cancellation', (
    tester,
  ) async {
    GakujoDownloadAction? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showGakujoDownloadActionDialog(
                  context,
                  'test.pdf',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('test.pdf'), findsOneWidget);
    await tester.tap(find.text('プレビュー'));
    await tester.pumpAndSettle();
    expect(selected, GakujoDownloadAction.preview);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ダウンロード'));
    await tester.pumpAndSettle();
    expect(selected, GakujoDownloadAction.save);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

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
