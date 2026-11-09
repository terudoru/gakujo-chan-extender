import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/widgets/app_data_sections.dart';

const labels = ['バックアップ作成', 'ファイルから読み込み'];

Widget section({
  required Future<void> Function() create,
  required Future<void> Function() import,
}) =>
    MaterialApp(
        home: Scaffold(
      body: AppBackupSection(
        onCreateBackup: create,
        onImportSettingsFromFile: import,
      ),
    ));

void main() {
  for (final label in labels) {
    testWidgets('$label runs once and blocks related backup actions',
        (tester) async {
      final pending = Completer<void>();
      final calls = <String>[];
      Future<void> run(String action) {
        calls.add(action);
        return pending.future;
      }
      await tester.pumpWidget(section(
        create: () => run(labels[0]),
        import: () => run(labels[1]),
      ));
      final button = find.widgetWithText(OutlinedButton, label);
      final pressed = tester.widget<OutlinedButton>(button).onPressed!;
      pressed();
      pressed();
      await tester.pump();
      expect(calls, [label]);
      for (final action in labels) {
        expect(
            tester.widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, action)).onPressed,
            isNull);
      }
      expect(find.textContaining('処理しています'), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    });

    testWidgets('$label failures are reported and can be retried',
        (tester) async {
      var attempts = 0;
      Future<void> run() async {
        if (++attempts == 1) {
          throw PlatformException(code: 'unavailable');
        }
      }
      await tester.pumpWidget(section(create: run, import: run));
      final button = find.widgetWithText(OutlinedButton, label);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('完了できませんでした'), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(attempts, 2);
    });

    testWidgets('$label late failures do not update disposed UI',
        (tester) async {
      final pending = Completer<void>();
      await tester.pumpWidget(section(
        create: () => pending.future,
        import: () => pending.future,
      ));
      await tester.tap(find.widgetWithText(OutlinedButton, label));
      await tester.pumpWidget(const SizedBox.shrink());
      pending.completeError(PlatformException(code: 'unavailable'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
