import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/app_data_sections.dart';

Widget section(
        {required Future<void> Function() import,
        Future<void> Function()? importFromFile,
        Future<void> Function()? export}) =>
    MaterialApp(
        home: Scaffold(
      body: AppMaintenanceSection(
        onCheckUpdates: () async {},
        onCreateBackup: () async {},
        onCreateErrorReport: () async {},
        onExportSettings: export ?? () async {},
        onImportSettings: import,
        onImportSettingsFromFile: importFromFile ?? () async {},
        onCheckDownloadDestination: () async {},
        onCopyDiagnostics: () async {},
      ),
    ));

void main() {
  for (final importLabel in ['設定を読み込み', 'ファイルから読み込み']) {
    testWidgets('$importLabel runs once and blocks related backup actions',
        (tester) async {
      final pending = Completer<void>();
      var clipboardImports = 0;
      var fileImports = 0;
      await tester.pumpWidget(section(
        import: () {
          clipboardImports++;
          return pending.future;
        },
        importFromFile: () {
          fileImports++;
          return pending.future;
        },
      ));
      final button = find.widgetWithText(OutlinedButton, importLabel);
      final pressed = tester.widget<OutlinedButton>(button).onPressed!;
      pressed();
      pressed();
      await tester.pump();
      expect(clipboardImports, importLabel == '設定を読み込み' ? 1 : 0);
      expect(fileImports, importLabel == 'ファイルから読み込み' ? 1 : 0);
      for (final label in [
        '設定を読み込み',
        'ファイルから読み込み',
        '設定をコピー',
        'バックアップ作成',
      ]) {
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
  }

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
