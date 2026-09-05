import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/app_data_sections.dart';

Widget section(
        {required Future<void> Function() import,
        Future<void> Function()? export}) =>
    MaterialApp(
        home: Scaffold(
      body: AppMaintenanceSection(
        onCheckUpdates: () async {},
        onCreateBackup: () async {},
        onCreateErrorReport: () async {},
        onExportSettings: export ?? () async {},
        onImportSettings: import,
        onCheckDownloadDestination: () async {},
        onCopyDiagnostics: () async {},
      ),
    ));

void main() {
  testWidgets('one import runs while related backup actions are disabled',
      (tester) async {
    final pending = Completer<void>();
    var imports = 0;
    await tester.pumpWidget(section(import: () {
      imports++;
      return pending.future;
    }));
    final button = find.widgetWithText(OutlinedButton, '設定を読み込み');
    final pressed = tester.widget<OutlinedButton>(button).onPressed!;
    pressed();
    pressed();
    await tester.pump();
    expect(imports, 1);
    for (final label in ['設定を読み込み', '設定をコピー', 'バックアップ作成']) {
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, label))
              .onPressed,
          isNull);
    }
    expect(find.textContaining('処理しています'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
  });

  testWidgets('clipboard failures are reported and the action can be retried',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(section(import: () async {
      if (++attempts == 1) {
        throw PlatformException(code: 'clipboard_unavailable');
      }
    }));
    final button = find.widgetWithText(OutlinedButton, '設定を読み込み');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('完了できませんでした'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('late failures after closing settings do not update disposed UI',
      (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(section(import: () => pending.future));
    await tester.tap(find.widgetWithText(OutlinedButton, '設定を読み込み'));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(PlatformException(code: 'clipboard_unavailable'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
