import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/linux_download_strip.dart';
import 'package:webview_flutter_linux/webview_flutter_linux.dart';

void main() {
  LinuxDownloadProgress progress(int received, int? total) =>
      LinuxDownloadProgress(
        id: '1',
        fileName: '講義資料.pdf',
        bytesReceived: received,
        totalBytes: total,
        status: 'downloading',
      );

  Widget host(LinuxDownloadProgress value, Future<void> Function() cancel) =>
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [LinuxDownloadStrip(progress: value, onCancel: cancel)],
          ),
        ),
      );

  testWidgets(
    'shows filename, percent and disables cancel until it completes',
    (tester) async {
      final cancelled = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        host(progress(250, 1000), () {
          calls++;
          return cancelled.future;
        }),
      );
      expect(find.text('講義資料.pdf — 25%'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.25,
      );
      await tester.tap(find.text('キャンセル'));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      cancelled.complete();
      await tester.pump();
    },
  );

  testWidgets('unknown lengths show KB/MB and update when the size is known', (
    tester,
  ) async {
    await tester.pumpWidget(host(progress(512, null), () async {}));
    expect(find.text('講義資料.pdf — 0.5 KB'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    await tester.pumpWidget(host(progress(1536, null), () async {}));
    expect(find.text('講義資料.pdf — 1.5 KB'), findsOneWidget);
    await tester.pumpWidget(host(progress(1024 * 1024, null), () async {}));
    expect(find.text('講義資料.pdf — 1.0 MB'), findsOneWidget);
    await tester.pumpWidget(host(progress(1258291, null), () async {}));
    expect(find.text('講義資料.pdf — 1.2 MB'), findsOneWidget);
    await tester.pumpWidget(host(progress(1000, 1000), () async {}));
    expect(find.text('講義資料.pdf — 100%'), findsOneWidget);
    expect(progress(1001, 1000).fraction, 1);
  });
}
